# 🚀 Deployment Guide - Local to EKS via EC2

Hướng dẫn deploy từ máy Windows local → GitHub → EC2 → EKS

---

## 📋 Workflow Overview

```
Windows Local → GitHub → EC2 (Bastion) → EKS Cluster
     |              |           |              |
   Code          Remote      Setup &       Production
  Editor         Repo       Deploy         Workload
```

---

## PART 1: Push Code từ Local lên GitHub

### Step 1.1: Prepare Local Repository

```bash
# Mở Git Bash hoặc PowerShell
cd h:\RESEARCH\EKS\yolo_eks

# Check git status
git status

# Add all files
git add .

# Commit
git commit -m "Initial commit: YOLO EKS deployment setup"
```

### Step 1.2: Create GitHub Repository

1. Vào https://github.com/new
2. **Repository name**: `yolo-eks-deployment`
3. **Visibility**: Private (recommended)
4. **KHÔNG tích** "Initialize with README"
5. Click **Create repository**

### Step 1.3: Push to GitHub

```bash
# Add remote (thay YOUR_USERNAME)
git remote add origin https://github.com/YOUR_USERNAME/yolo-eks-deployment.git

# Check remote
git remote -v

# Push
git branch -M main
git push -u origin main
```

**✅ Verify:** Vào GitHub repository, check files đã có chưa.

**⚠️ Note:** File `models/best_Hai_03092025.pt` sẽ KHÔNG được push (trong `.gitignore`). Model sẽ upload lên S3 từ EC2.

---

## PART 2: Setup EC2 Instance (Bastion Server)

### Step 2.1: Launch EC2 Instance

**AWS Console → EC2 → Launch Instance:**

1. **Name**: `yolo-eks-bastion`

2. **AMI**: Amazon Linux 2023 AMI (Free tier)

3. **Instance type**: `t3.medium` (2 vCPU, 4GB RAM)
   - Cần RAM đủ để build Docker image

4. **Key pair**:
   - Create new key pair: `yolo-eks-key`
   - Type: RSA
   - Format: `.pem` (for SSH) hoặc `.ppk` (for PuTTY)
   - **Download và save** key pair

5. **Network settings**:
   - VPC: Default VPC
   - Subnet: Any public subnet
   - Auto-assign Public IP: **Enable**
   - Security group: Create new
     - Name: `yolo-eks-bastion-sg`
     - Rules:
       - SSH (22): Your IP only
       - HTTPS (443): Anywhere (for git, docker, aws)

6. **Storage**: 30 GB gp3

7. **Advanced details → IAM instance profile**:
   - **Important**: Create/Attach IAM role với permissions:
     - `AmazonEKSClusterPolicy`
     - `AmazonEKSWorkerNodePolicy`
     - `AmazonEC2ContainerRegistryFullAccess`
     - `AmazonS3FullAccess`
     - `AmazonElasticFileSystemFullAccess`
     - (Hoặc dùng `AdministratorAccess` cho đơn giản - testing only)

8. Click **Launch instance**

### Step 2.2: Create IAM Role for EC2 (Nếu chưa có)

**IAM Console → Roles → Create role:**

1. **Trusted entity**: AWS service → EC2
2. **Permissions policies**:
   - `AmazonEKSClusterPolicy`
   - `AmazonEKSWorkerNodePolicy`
   - `AmazonEC2ContainerRegistryFullAccess`
   - `AmazonS3FullAccess`
   - `AmazonElasticFileSystemFullAccess`
   - `IAMFullAccess` (để tạo service accounts)
3. **Role name**: `yolo-eks-bastion-role`
4. Create role

**Attach role to EC2:**
- EC2 Console → Instance → Actions → Security → Modify IAM role
- Select `yolo-eks-bastion-role`
- Update IAM role

### Step 2.3: Connect to EC2

**Option 1: SSH (Linux/Mac/Git Bash)**
```bash
# Set permissions for key
chmod 400 yolo-eks-key.pem

# SSH to EC2
ssh -i yolo-eks-key.pem ec2-user@<EC2-PUBLIC-IP>
```

**Option 2: PuTTY (Windows)**
1. Convert `.pem` to `.ppk` using PuTTYgen
2. Open PuTTY
3. Host: `ec2-user@<EC2-PUBLIC-IP>`
4. Auth: Browse → Select `.ppk` file
5. Connect

**Option 3: EC2 Instance Connect (Browser)**
1. EC2 Console → Select instance
2. Click **Connect** → **EC2 Instance Connect**
3. Click **Connect**

---

## PART 3: Setup EC2 Environment

### Step 3.1: Install Required Tools

```bash
# Update system
sudo yum update -y

# Install Git
sudo yum install git -y
git --version

# Install Docker
sudo yum install docker -y
sudo systemctl start docker
sudo systemctl enable docker
sudo usermod -aG docker ec2-user

# Logout and login again for docker group
exit
# SSH lại vào EC2

# Verify Docker
docker --version
docker ps

# Install kubectl
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
kubectl version --client

# Install eksctl
curl --silent --location "https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_$(uname -s)_amd64.tar.gz" | tar xz -C /tmp
sudo mv /tmp/eksctl /usr/local/bin
eksctl version

# Install Helm
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
helm version

# Install AWS CLI (should be pre-installed on Amazon Linux 2023)
aws --version

# Install jq (JSON processor)
sudo yum install jq -y
```

### Step 3.2: Configure AWS CLI

```bash
# Check if IAM role is attached (should return role name)
aws sts get-caller-identity

# Should see output like:
# {
#     "UserId": "AIDAXXXXXXXXXX:i-xxxxxxxxxx",
#     "Account": "123456789012",
#     "Arn": "arn:aws:sts::123456789012:assumed-role/yolo-eks-bastion-role/i-xxxxxxxxxx"
# }

# Set default region
aws configure set default.region ap-southeast-1

# Verify
aws configure list
```

### Step 3.3: Clone Repository from GitHub

```bash
# Clone repository
git clone https://github.com/YOUR_USERNAME/yolo-eks-deployment.git

# Navigate to project
cd yolo-eks-deployment

# Check files
ls -la
```

---

## PART 4: Upload Model Weights to S3

### Step 4.1: Upload Model từ Local → S3

**Trên máy Windows local:**

```bash
# Install AWS CLI (nếu chưa có): https://aws.amazon.com/cli/

# Configure AWS CLI
aws configure
# AWS Access Key ID: <your-key>
# AWS Secret Access Key: <your-secret>
# Default region: ap-southeast-1

# Set bucket name
$S3_BUCKET = "ai-weights-$(aws sts get-caller-identity --query Account --output text)"

# Create bucket
aws s3 mb s3://$S3_BUCKET --region ap-southeast-1

# Upload model
aws s3 cp "h:\RESEARCH\EKS\yolo_eks\models\best_Hai_03092025.pt" "s3://$S3_BUCKET/models/best.pt" --region ap-southeast-1

# Verify
aws s3 ls "s3://$S3_BUCKET/models/" --human-readable
```

**Hoặc dùng AWS Console:**
1. S3 Console → Create bucket: `ai-weights-<account-id>`
2. Upload file `models/best_Hai_03092025.pt` → Rename to `best.pt`
3. Path: `s3://ai-weights-<account-id>/models/best.pt`

---

## PART 5: Setup Environment Variables trên EC2

```bash
# Setup environment
cd ~/yolo-eks-deployment
source setup-env.sh

# Verify
echo "AWS_REGION: $AWS_REGION"
echo "CLUSTER_NAME: $CLUSTER_NAME"
echo "AWS_ACCOUNT_ID: $AWS_ACCOUNT_ID"
echo "ECR_REPO: $ECR_REPO"
echo "S3_WEIGHTS_BUCKET: $S3_WEIGHTS_BUCKET"
echo "ECR_URL: $ECR_URL"
```

**Expected output:**
```
AWS_REGION: ap-southeast-1
CLUSTER_NAME: ai-inference-prod
AWS_ACCOUNT_ID: 123456789012
ECR_REPO: ai-inference
S3_WEIGHTS_BUCKET: ai-weights-123456789012
ECR_URL: 123456789012.dkr.ecr.ap-southeast-1.amazonaws.com/ai-inference
```

---

## PART 6: Create AWS Infrastructure

### Step 6.1: Create S3 & ECR

```bash
# Create S3 bucket (if not created from local)
aws s3 mb s3://${S3_WEIGHTS_BUCKET} --region ${AWS_REGION}

# Create ECR repository
aws ecr create-repository \
  --repository-name ${ECR_REPO} \
  --region ${AWS_REGION} \
  --image-scanning-configuration scanOnPush=true

# Verify
aws s3 ls | grep ai-weights
aws ecr describe-repositories --region ${AWS_REGION}
```

### Step 6.2: Create EKS Cluster (15-20 phút)

```bash
# Create cluster
eksctl create cluster -f cluster-config.yaml

# This will take 15-20 minutes...
# Go grab a coffee ☕
```

**Monitor progress:**
```bash
# In another terminal tab
watch -n 10 'aws eks describe-cluster --name ai-inference-prod --region ap-southeast-1 --query cluster.status'
```

### Step 6.3: Update kubeconfig

```bash
# Update kubectl config
aws eks update-kubeconfig --name ${CLUSTER_NAME} --region ${AWS_REGION}

# Verify connection
kubectl cluster-info
kubectl get nodes

# Should see 2 GPU nodes + 2 CPU nodes
```

### Step 6.4: Create EFS

```bash
# Get VPC ID
VPC_ID=$(aws eks describe-cluster --name ${CLUSTER_NAME} --region ${AWS_REGION} --query 'cluster.resourcesVpcConfig.vpcId' --output text)
echo "VPC ID: $VPC_ID"

# Create EFS
EFS_ID=$(aws efs create-file-system \
  --creation-token yolo-efs-$(date +%s) \
  --performance-mode generalPurpose \
  --throughput-mode bursting \
  --encrypted \
  --tags Key=Name,Value=yolo-efs \
  --region ${AWS_REGION} \
  --query 'FileSystemId' \
  --output text)

echo "EFS ID: $EFS_ID"
echo "export EFS_ID=$EFS_ID" >> ~/.bashrc
source ~/.bashrc

# Wait for EFS
sleep 30

# Get cluster security group
CLUSTER_SG=$(aws eks describe-cluster --name ${CLUSTER_NAME} --region ${AWS_REGION} --query 'cluster.resourcesVpcConfig.clusterSecurityGroupId' --output text)

# Get subnets
SUBNET_IDS=$(aws eks describe-cluster --name ${CLUSTER_NAME} --region ${AWS_REGION} --query 'cluster.resourcesVpcConfig.subnetIds' --output text)

# Create mount targets
for subnet in $SUBNET_IDS; do
  aws efs create-mount-target \
    --file-system-id $EFS_ID \
    --subnet-id $subnet \
    --security-groups $CLUSTER_SG \
    --region ${AWS_REGION} 2>/dev/null || echo "Mount target exists"
done

echo "✓ EFS created: $EFS_ID"
```

### Step 6.5: Install Kubernetes Addons

```bash
# EFS CSI Driver
helm repo add aws-efs-csi-driver https://kubernetes-sigs.github.io/aws-efs-csi-driver/
helm repo update
helm install aws-efs-csi-driver aws-efs-csi-driver/aws-efs-csi-driver \
  --namespace kube-system \
  --set image.repository=602401143452.dkr.ecr.${AWS_REGION}.amazonaws.com/eks/aws-efs-csi-driver

# NVIDIA Device Plugin
kubectl apply -f https://raw.githubusercontent.com/NVIDIA/k8s-device-plugin/v0.14.0/nvidia-device-plugin.yml

# Metrics Server
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

# Verify
kubectl get pods -n kube-system | grep -E "efs|nvidia|metrics"
```

---

## PART 7: Update Kubernetes Manifests

```bash
cd ~/yolo-eks-deployment

# Update StorageClass with EFS ID
sed -i "s/fs-XXXXXXXXX/${EFS_ID}/g" k8s/storageclass.yaml

# Update ServiceAccount with Account ID
sed -i "s/ACCOUNT_ID/${AWS_ACCOUNT_ID}/g" k8s/serviceaccount.yaml

# Update Deployment with ECR URL
sed -i "s|ACCOUNT_ID.dkr.ecr.REGION.amazonaws.com|${ECR_URL}|g" k8s/deployment.yaml

# Update ConfigMap with S3 bucket
sed -i "s/yolo-models-bucket/${S3_WEIGHTS_BUCKET}/g" k8s/configmap.yaml
sed -i "s/us-west-2/${AWS_REGION}/g" k8s/configmap.yaml

# Verify changes
echo "=== Verifying updates ==="
cat k8s/storageclass.yaml | grep fileSystemId
cat k8s/serviceaccount.yaml | grep role-arn
cat k8s/deployment.yaml | grep "image:"
cat k8s/configmap.yaml | grep S3_BUCKET
```

---

## PART 8: Build and Push Docker Image

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

## PART 9: Deploy to EKS

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

**Expected flow:**
```
NAME                              READY   STATUS            RESTARTS   AGE
yolo-inference-xxx                0/1     Init:0/1          0          10s
yolo-inference-xxx                0/1     PodInitializing   0          2m
yolo-inference-xxx                1/1     Running           0          3m
```

---

## PART 10: Verify Deployment

### Step 10.1: Check Infrastructure

```bash
cd ~/yolo-eks-deployment
./check-infra.sh
```

### Step 10.2: Get LoadBalancer URL

```bash
# Get service
kubectl get svc yolo-service -n yolo-inference

# Get LoadBalancer URL (wait ~3-5 minutes)
LB_URL=$(kubectl get svc yolo-service -n yolo-inference -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
echo "LoadBalancer URL: http://$LB_URL"

# Save to environment
echo "export LB_URL=$LB_URL" >> ~/.bashrc
source ~/.bashrc
```

### Step 10.3: Test API

```bash
# Health check
curl http://$LB_URL/health | jq '.'

# Expected:
{
  "status": "healthy",
  "model_path": "/models/best.pt",
  "pod_name": "yolo-inference-xxx",
  "output_path": "/output"
}

# Download test image
curl -o test.jpg https://ultralytics.com/images/bus.jpg

# Test inference
curl -X POST http://$LB_URL/predict -F "file=@test.jpg" | jq '.'

# List outputs
curl http://$LB_URL/outputs | jq '.'
```

---

## PART 11: Configure GitHub Actions (CI/CD)

### Step 11.1: Get GitHub Secrets Values

```bash
# On EC2, print all secrets
echo "=== GitHub Secrets ==="
echo "AWS_ACCESS_KEY_ID: <from IAM user>"
echo "AWS_SECRET_ACCESS_KEY: <from IAM user>"
echo "AWS_REGION: $AWS_REGION"
echo "ECR_REPOSITORY: $ECR_URL"
echo "S3_MODEL_BUCKET: $S3_WEIGHTS_BUCKET"
echo "EKS_CLUSTER_NAME: $CLUSTER_NAME"
```

**⚠️ Important:** EC2 sử dụng IAM Role, nhưng GitHub Actions cần IAM User credentials.

### Step 11.2: Create IAM User for GitHub Actions

**AWS Console → IAM → Users → Create user:**

1. **User name**: `github-actions-yolo-eks`
2. **Permissions**: Attach policies:
   - `AmazonEC2ContainerRegistryFullAccess`
   - `AmazonS3FullAccess`
   - `AmazonEKSFullAccess`
3. Create user
4. **Security credentials** → **Create access key**
5. Use case: Application running outside AWS
6. **Download credentials** (CSV file)

### Step 11.3: Add Secrets to GitHub

1. GitHub Repository → **Settings** → **Secrets and variables** → **Actions**
2. Click **New repository secret**
3. Add 6 secrets:

| Name | Value |
|------|-------|
| `AWS_ACCESS_KEY_ID` | From IAM user CSV |
| `AWS_SECRET_ACCESS_KEY` | From IAM user CSV |
| `AWS_REGION` | `ap-southeast-1` |
| `ECR_REPOSITORY` | `<account-id>.dkr.ecr.ap-southeast-1.amazonaws.com/ai-inference` |
| `S3_MODEL_BUCKET` | `ai-weights-<account-id>` |
| `EKS_CLUSTER_NAME` | `ai-inference-prod` |

### Step 11.4: Test CI/CD

**On local machine:**

```bash
# Make a change
cd h:\RESEARCH\EKS\yolo_eks

# Add version endpoint
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

**Monitor:**
1. GitHub → Actions tab
2. Watch "Build and Deploy to EKS" workflow
3. Wait ~5-10 minutes

**Verify on EC2:**
```bash
# Check deployment
kubectl rollout status deployment/yolo-inference -n yolo-inference

# Test new endpoint
curl http://$LB_URL/version | jq '.'
```

---

## 🎉 DEPLOYMENT COMPLETE!

### ✅ What's Running:

- ✅ **EKS Cluster**: `ai-inference-prod` in `ap-southeast-1`
- ✅ **Nodes**: 2x g4dn.xlarge (GPU) + 2x t3.medium (CPU)
- ✅ **Pods**: 3 replicas with auto-scaling
- ✅ **LoadBalancer**: Public endpoint
- ✅ **CI/CD**: Auto-deploy on git push

### 🔗 Important URLs:

```bash
# Print summary
echo "=== DEPLOYMENT SUMMARY ==="
echo "LoadBalancer: http://$LB_URL"
echo "Health: http://$LB_URL/health"
echo "ECR: $ECR_URL"
echo "S3: s3://$S3_WEIGHTS_BUCKET"
echo "EFS: $EFS_ID"
```

### 📊 Monitoring Commands:

```bash
# On EC2:
kubectl get pods -n yolo-inference
kubectl logs -f deployment/yolo-inference -n yolo-inference
kubectl top pods -n yolo-inference
kubectl get hpa -n yolo-inference
```

### 🧹 Cleanup (When done):

```bash
# Delete namespace
kubectl delete namespace yolo-inference

# Delete cluster
eksctl delete cluster --name ai-inference-prod --region ap-southeast-1

# Delete S3, ECR
aws s3 rb s3://$S3_WEIGHTS_BUCKET --force
aws ecr delete-repository --repository-name $ECR_REPO --force

# Terminate EC2
# AWS Console → EC2 → Terminate instance
```

---

## 💰 Cost Estimate:

- **EKS**: $73/month
- **2x g4dn.xlarge**: $310/month (24/7)
- **2x t3.medium**: $60/month
- **t3.medium EC2**: $30/month
- **EFS**: $5/month
- **S3**: $1/month
- **Total**: ~$480/month

**Save costs:**
- Stop EC2 khi không dùng
- Scale down EKS nodes off-hours
- Use Spot instances

---

**🚀 YOUR YOLO API IS LIVE!**
