# 🚀 YOLO EKS Deployment - Complete Guide

Deploy YOLO Inference Application lên AWS EKS với GitHub Actions CI/CD.

---

## 📋 Table of Contents

1. [Overview](#overview)
2. [Prerequisites](#prerequisites)
3. [Deployment Steps](#deployment-steps)
4. [After Deployment](#after-deployment)
5. [Troubleshooting](#troubleshooting)

---

## Overview

### Architecture

```
Windows Local → GitHub → GitHub Actions → ECR + S3
                                          ↓
                                     EKS Cluster
                                          ↓
                              ┌───────────┴───────────┐
                              ↓                       ↓
                         EFS (Models)           Pods (shared)
                              ↑                       ↓
                    S3 Model → Init Container   Output → EFS
```

### Components
- **GitHub Actions**: CI/CD pipeline
- **ECR**: Docker container registry
- **S3**: Model weights storage
- **EFS**: Shared file system (models + outputs)
- **EKS**: Kubernetes cluster (GPU nodes: g4dn.xlarge)

### S3 Structure
```
s3://ai-weights-{ACCOUNT_ID}/
└── models/
    └── best.pt    ← Model file
```

---

## Prerequisites

### Local Machine (Windows)
- [ ] Git installed
- [ ] AWS CLI installed and configured (`aws configure`)
- [ ] GitHub account
- [ ] Model file: `models/best_Hai_03092025.pt`

### AWS Account
- [ ] AWS Account with admin access
- [ ] IAM User credentials (Access Key + Secret Key)

---

## Deployment Steps

## STEP 1: Push Code to GitHub

### 1.1. Create GitHub Repository

1. Go to: https://github.com/new
2. Repository name: **yolo-eks-deployment**
3. Visibility: **Private**
4. Click **Create repository**

### 1.2. Push Code

```bash
# Open Git Bash or PowerShell
cd h:\RESEARCH\EKS\yolo_eks

git init
git add .
git commit -m "Initial commit: YOLO EKS deployment"

# Replace YOUR_USERNAME
git remote add origin https://github.com/YOUR_USERNAME/yolo-eks-deployment.git

git branch -M main
git push -u origin main
```

---

## STEP 2: Upload Model to S3

### 2.1. Configure AWS CLI

```bash
aws configure
# AWS Access Key ID: <your-key>
# AWS Secret Access Key: <your-secret>
# Default region: ap-southeast-1
# Default output: json
```

### 2.2. Upload Model

```bash
# PowerShell
$ACCOUNT_ID = aws sts get-caller-identity --query Account --output text
$S3_BUCKET = "ai-weights-$ACCOUNT_ID"

# Create bucket
aws s3 mb s3://$S3_BUCKET --region ap-southeast-1

# Upload model (~145MB, will take a few minutes)
aws s3 cp "h:\RESEARCH\EKS\yolo_eks\models\best_Hai_03092025.pt" "s3://$S3_BUCKET/models/best.pt" --region ap-southeast-1

# Verify
aws s3 ls s3://$S3_BUCKET/models/ --human-readable
```

**Expected output:**
```
2025-10-11 10:30:45  145.2 MiB best.pt
```

---

## STEP 3: Configure GitHub Secrets

✅ **You've already done this!** Your secrets:

- `AWS_ACCESS_KEY_ID` ✓
- `AWS_SECRET_ACCESS_KEY` ✓
- `AWS_REGION` = `ap-southeast-1` ✓
- `ECR_REPOSITORY` = `{ACCOUNT_ID}.dkr.ecr.ap-southeast-1.amazonaws.com/ai-inference` ✓
- `S3_MODEL_BUCKET` = `ai-weights-{ACCOUNT_ID}` ✓
- `EKS_CLUSTER_NAME` = `ai-inference-prod` ✓

---

## STEP 4: Create EC2 Bastion

### 4.1. Create IAM Role

**IAM Console → Roles → Create role:**
- Trusted entity: EC2
- Permissions: `AdministratorAccess`
- Role name: `yolo-eks-bastion-role`

### 4.2. Launch EC2

**EC2 Console → Launch Instance:**
- Name: `yolo-eks-bastion`
- AMI: **Amazon Linux 2023**
- Instance type: **t3.medium**
- Key pair: Create new → `yolo-eks-key` (download .pem file)
- Network: Default VPC, Enable public IP
- Security group: Allow SSH (port 22)
- Storage: 30 GB
- **IAM role**: `yolo-eks-bastion-role` ⚠️ **IMPORTANT**

### 4.3. SSH to EC2

```bash
# Git Bash
chmod 400 yolo-eks-key.pem
ssh -i yolo-eks-key.pem ec2-user@<EC2_PUBLIC_IP>
```

---

## STEP 5: Setup EC2 Environment

### 5.1. Install Tools

```bash
# Update system
sudo yum update -y

# Install Docker
sudo yum install docker -y
sudo systemctl start docker
sudo systemctl enable docker
sudo usermod -aG docker ec2-user

# Install kubectl
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

# Install eksctl
curl --silent --location "https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_$(uname -s)_amd64.tar.gz" | tar xz -C /tmp
sudo mv /tmp/eksctl /usr/local/bin

# Install Helm
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# Install jq & git
sudo yum install jq git -y

# Logout and login again
exit
```

### 5.2. Clone Repository

```bash
# SSH back in
ssh -i yolo-eks-key.pem ec2-user@<EC2_PUBLIC_IP>

# Clone repo (replace YOUR_USERNAME)
git clone https://github.com/YOUR_USERNAME/yolo-eks-deployment.git
cd yolo-eks-deployment

# Setup environment
source setup-env.sh

# Verify
echo $AWS_ACCOUNT_ID
echo $S3_WEIGHTS_BUCKET
echo $ECR_URL
```

---

## STEP 6: Create AWS Infrastructure

### 6.1. Create ECR Repository

```bash
aws ecr create-repository \
  --repository-name ${ECR_REPO} \
  --region ${AWS_REGION} \
  --image-scanning-configuration scanOnPush=true
```

### 6.2. Create EKS Cluster (15-20 minutes ☕)

```bash
# Create cluster
eksctl create cluster -f cluster-config.yaml

# This will take 15-20 minutes...
# You can monitor in another terminal:
# watch -n 30 'eksctl get cluster --name ai-inference-prod --region ap-southeast-1'
```

### 6.3. Update kubeconfig

```bash
aws eks update-kubeconfig --name ${CLUSTER_NAME} --region ${AWS_REGION}

# Verify
kubectl get nodes

# Should see 4 nodes: 2 GPU + 2 CPU
```

### 6.4. Create EFS

```bash
# Get VPC ID
VPC_ID=$(aws eks describe-cluster --name ${CLUSTER_NAME} --region ${AWS_REGION} --query 'cluster.resourcesVpcConfig.vpcId' --output text)

# Create EFS
EFS_ID=$(aws efs create-file-system \
  --creation-token yolo-efs-$(date +%s) \
  --performance-mode generalPurpose \
  --encrypted \
  --tags Key=Name,Value=yolo-efs \
  --region ${AWS_REGION} \
  --query 'FileSystemId' \
  --output text)

echo "EFS ID: $EFS_ID"
echo "export EFS_ID=$EFS_ID" >> ~/.bashrc
source ~/.bashrc

# Wait for EFS to be available
sleep 30

# Get cluster security group and subnets
CLUSTER_SG=$(aws eks describe-cluster --name ${CLUSTER_NAME} --region ${AWS_REGION} --query 'cluster.resourcesVpcConfig.clusterSecurityGroupId' --output text)
SUBNET_IDS=$(aws eks describe-cluster --name ${CLUSTER_NAME} --region ${AWS_REGION} --query 'cluster.resourcesVpcConfig.subnetIds' --output text)

# Create mount targets
for subnet in $SUBNET_IDS; do
  aws efs create-mount-target \
    --file-system-id $EFS_ID \
    --subnet-id $subnet \
    --security-groups $CLUSTER_SG \
    --region ${AWS_REGION} 2>/dev/null || echo "Mount target may exist"
done

echo "✓ EFS created: $EFS_ID"
```

### 6.5. Install Kubernetes Addons

```bash
# EFS CSI Driver
helm repo add aws-efs-csi-driver https://kubernetes-sigs.github.io/aws-efs-csi-driver/
helm repo update
helm install aws-efs-csi-driver aws-efs-csi-driver/aws-efs-csi-driver \
  --namespace kube-system \
  --set image.repository=602401143452.dkr.ecr.${AWS_REGION}.amazonaws.com/eks/aws-efs-csi-driver

# NVIDIA Device Plugin (for GPU)
kubectl apply -f https://raw.githubusercontent.com/NVIDIA/k8s-device-plugin/v0.14.0/nvidia-device-plugin.yml

# Metrics Server (for HPA)
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

# Verify
kubectl get pods -n kube-system | grep -E "efs|nvidia|metrics"
```

---

## STEP 7: Update Kubernetes Manifests

```bash
cd ~/yolo-eks-deployment

# Update with actual values
sed -i "s/fs-XXXXXXXXX/${EFS_ID}/g" k8s/storageclass.yaml
sed -i "s/ACCOUNT_ID/${AWS_ACCOUNT_ID}/g" k8s/serviceaccount.yaml
sed -i "s|ACCOUNT_ID.dkr.ecr.REGION.amazonaws.com|${ECR_URL}|g" k8s/deployment.yaml
sed -i "s/yolo-models-bucket/${S3_WEIGHTS_BUCKET}/g" k8s/configmap.yaml
sed -i "s/us-west-2/${AWS_REGION}/g" k8s/configmap.yaml

# Verify changes
echo "=== Verifying updates ==="
grep fileSystemId k8s/storageclass.yaml
grep role-arn k8s/serviceaccount.yaml
grep "image:" k8s/deployment.yaml | head -1
grep S3_BUCKET k8s/configmap.yaml
```

---

## STEP 8: Build and Push Docker Image

```bash
cd ~/yolo-eks-deployment

# Login to ECR
aws ecr get-login-password --region ${AWS_REGION} | docker login --username AWS --password-stdin ${ECR_URL}

# Build image
docker build -t ${ECR_URL}:v1.0.0 .

# Tag as latest
docker tag ${ECR_URL}:v1.0.0 ${ECR_URL}:latest

# Push to ECR
docker push ${ECR_URL}:v1.0.0
docker push ${ECR_URL}:latest

# Verify
aws ecr list-images --repository-name ${ECR_REPO} --region ${AWS_REGION}
```

---

## STEP 9: Deploy to EKS

```bash
cd ~/yolo-eks-deployment

# Apply all Kubernetes resources
kubectl apply -f k8s/namespace.yaml
kubectl apply -f k8s/storageclass.yaml
kubectl apply -f k8s/pvc.yaml
kubectl apply -f k8s/serviceaccount.yaml
kubectl apply -f k8s/configmap.yaml
kubectl apply -f k8s/deployment.yaml
kubectl apply -f k8s/service.yaml
kubectl apply -f k8s/hpa.yaml

# Watch pods starting (Ctrl+C to exit)
kubectl get pods -n yolo-inference -w
```

**Expected output:**
```
NAME                              READY   STATUS              RESTARTS   AGE
yolo-inference-xxx                0/1     Init:0/1            0          30s
yolo-inference-xxx                0/1     PodInitializing     0          2m
yolo-inference-xxx                1/1     Running             0          3m
yolo-inference-yyy                1/1     Running             0          3m
yolo-inference-zzz                1/1     Running             0          3m
```

---

## STEP 10: Get LoadBalancer URL

```bash
# Wait 3-5 minutes for LoadBalancer provisioning
kubectl get svc yolo-service -n yolo-inference

# Get URL
LB_URL=$(kubectl get svc yolo-service -n yolo-inference -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
echo "LoadBalancer URL: http://$LB_URL"

# Save to environment
echo "export LB_URL=$LB_URL" >> ~/.bashrc
source ~/.bashrc
```

---

## STEP 11: Test API

### Health Check

```bash
curl http://$LB_URL/health | jq '.'
```

**Expected:**
```json
{
  "status": "healthy",
  "model_path": "/models/best.pt",
  "pod_name": "yolo-inference-xxx-yyy",
  "output_path": "/output"
}
```

### Test Inference

```bash
# Download test image
curl -o test.jpg https://ultralytics.com/images/bus.jpg

# Run inference
curl -X POST http://$LB_URL/predict -F "file=@test.jpg" | jq '.'
```

**Expected:**
```json
{
  "success": true,
  "detections": [...],
  "count": 5,
  "pod_name": "yolo-inference-xxx",
  "output_file": "/output/result_xxx.json"
}
```

### List Shared Outputs

```bash
curl http://$LB_URL/outputs | jq '.'
```

Shows outputs from ALL pods (shared via EFS).

---

## After Deployment

### GitHub Actions is Now Active! 🎉

**Every time you push code to `main` branch:**
1. GitHub Actions automatically builds Docker image
2. Pushes to ECR
3. Deploys to EKS cluster
4. Verifies model exists in S3

### Test CI/CD Pipeline

**From Windows local:**

```bash
cd h:\RESEARCH\EKS\yolo_eks

# Make a change
echo '
@app.get("/version")
async def version():
    return {"version": "1.0.1", "pod": POD_NAME}
' >> main.py

# Commit and push
git add main.py
git commit -m "Add version endpoint"
git push origin main
```

**Monitor on GitHub:**
1. Go to repository → Actions tab
2. Watch workflow running (~5-10 minutes)

**Verify on EC2:**
```bash
# Check deployment
kubectl rollout status deployment/yolo-inference -n yolo-inference

# Test new endpoint
curl http://$LB_URL/version | jq '.'
```

---

## Monitoring

### View Pods

```bash
# All pods
kubectl get pods -n yolo-inference

# Pod details
kubectl describe pod <pod-name> -n yolo-inference

# Logs
kubectl logs -f deployment/yolo-inference -n yolo-inference

# Logs from specific pod
kubectl logs -f <pod-name> -n yolo-inference

# Init container logs
kubectl logs <pod-name> -n yolo-inference -c model-downloader
```

### View Metrics

```bash
# Pod resource usage
kubectl top pods -n yolo-inference

# Node resource usage
kubectl top nodes

# HPA status
kubectl get hpa -n yolo-inference
```

### Check Shared EFS

```bash
# Get a pod
POD=$(kubectl get pods -n yolo-inference -o jsonpath='{.items[0].metadata.name}')

# Exec into pod
kubectl exec -it $POD -n yolo-inference -- bash

# Inside pod:
ls -lh /models/     # Model weights
ls -lh /output/     # Shared outputs
exit
```

---

## Scaling

### Manual Scale

```bash
# Scale to 5 replicas
kubectl scale deployment yolo-inference --replicas=5 -n yolo-inference

# Watch scaling
kubectl get pods -n yolo-inference -w
```

### Auto Scaling (HPA)

Already configured to auto-scale based on:
- **CPU**: 70% threshold
- **Memory**: 80% threshold
- **Min replicas**: 2
- **Max replicas**: 10

```bash
# Check HPA
kubectl get hpa -n yolo-inference

# Should show:
# NAME             REFERENCE                   TARGETS         MINPODS   MAXPODS   REPLICAS
# yolo-hpa         Deployment/yolo-inference   30%/70%         2         10        3
```

---

## Update Model

### When you have a new model:

**1. Upload to S3 (from Windows):**
```bash
aws s3 cp "models\new_model.pt" "s3://$S3_BUCKET/models/best.pt" --region ap-southeast-1
```

**2. Restart pods (from EC2):**
```bash
kubectl rollout restart deployment/yolo-inference -n yolo-inference

# Watch restart
kubectl get pods -n yolo-inference -w
```

Pods will download the new model from S3 during init.

---

## Troubleshooting

### Pods not starting

```bash
# Check events
kubectl describe pod <pod-name> -n yolo-inference

# Check init container logs
kubectl logs <pod-name> -n yolo-inference -c model-downloader

# Check main container logs
kubectl logs <pod-name> -n yolo-inference
```

### LoadBalancer pending

```bash
# Check service
kubectl describe svc yolo-service -n yolo-inference

# Wait 5 minutes, then check again
kubectl get svc yolo-service -n yolo-inference
```

### Model download failed

```bash
# Verify model in S3
aws s3 ls s3://$S3_WEIGHTS_BUCKET/models/

# Check IAM permissions
kubectl describe sa yolo-sa -n yolo-inference

# Check init container logs
kubectl logs <pod-name> -n yolo-inference -c model-downloader
```

### EFS mount issues

```bash
# Check PVC status
kubectl get pvc -n yolo-inference

# Check storage class
kubectl describe sc efs-sc

# Verify EFS mount targets
aws efs describe-mount-targets --file-system-id $EFS_ID --region $AWS_REGION
```

### GPU not available

```bash
# Check NVIDIA plugin
kubectl get pods -n kube-system -l name=nvidia-device-plugin-ds

# Check node GPU allocation
kubectl get nodes -o json | jq '.items[].status.allocatable."nvidia.com/gpu"'

# Describe node
kubectl describe node <gpu-node-name>
```

---

## Cleanup

### Delete Application Only

```bash
kubectl delete namespace yolo-inference
```

### Delete Entire Infrastructure

```bash
# Delete EKS cluster
eksctl delete cluster --name ai-inference-prod --region ap-southeast-1

# Delete S3 bucket
aws s3 rb s3://$S3_WEIGHTS_BUCKET --force --region ap-southeast-1

# Delete ECR repository
aws ecr delete-repository --repository-name $ECR_REPO --force --region ap-southeast-1

# Delete EFS (get mount targets first)
for mt in $(aws efs describe-mount-targets --file-system-id $EFS_ID --region ap-southeast-1 --query 'MountTargets[].MountTargetId' --output text); do
  aws efs delete-mount-target --mount-target-id $mt --region ap-southeast-1
done
sleep 30
aws efs delete-file-system --file-system-id $EFS_ID --region ap-southeast-1

# Terminate EC2 instance (AWS Console)
```

---

## Cost Estimate

**Monthly cost (ap-southeast-1):**
- EKS Cluster: ~$73/month
- 2x g4dn.xlarge (GPU): ~$310/month (24/7)
- 2x t3.medium (CPU): ~$60/month
- t3.medium (EC2 bastion): ~$30/month
- EFS: ~$5/month
- S3: ~$1/month
- **Total: ~$480/month**

**Cost optimization:**
- Stop EC2 bastion when not needed
- Scale down EKS nodes during off-hours
- Use Spot Instances for non-production
- Delete cluster when not actively developing

---

## Useful Commands

```bash
# Port forward to test locally
kubectl port-forward svc/yolo-service 8000:80 -n yolo-inference
curl http://localhost:8000/health

# Update deployment image
kubectl set image deployment/yolo-inference yolo-inference=$ECR_URL:new-tag -n yolo-inference

# Rollback deployment
kubectl rollout undo deployment/yolo-inference -n yolo-inference

# View deployment history
kubectl rollout history deployment/yolo-inference -n yolo-inference

# Restart deployment
kubectl rollout restart deployment/yolo-inference -n yolo-inference

# Get all resources
kubectl get all -n yolo-inference

# Delete stuck pod
kubectl delete pod <pod-name> -n yolo-inference --force --grace-period=0
```

---

## Summary

✅ **What You Have Now:**
- EKS Cluster with GPU nodes
- Auto-scaling YOLO inference API
- Shared model storage via EFS
- Shared output storage between pods
- CI/CD pipeline via GitHub Actions
- LoadBalancer with public endpoint

✅ **Workflow:**
1. Push code → GitHub
2. GitHub Actions → Build & Deploy automatically
3. Pods download model from S3 → EFS
4. All pods share model and outputs via EFS

🎉 **Your YOLO API is LIVE!**

```bash
# Quick check
curl http://$LB_URL/health
```

---

**Last Updated**: 2025-10-11
**Region**: ap-southeast-1
**Cluster**: ai-inference-prod
