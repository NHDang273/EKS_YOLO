# YOLO EKS Deployment Guide

Hướng dẫn deploy YOLO inference application lên AWS EKS với GitHub Actions CI/CD.

## 🏗️ Kiến trúc

```
GitHub Actions → ECR (Docker Image) + S3 (Model Weights)
                        ↓
                   EKS Cluster
                        ↓
          ┌─────────────┴─────────────┐
          ↓                           ↓
    EFS (Models)                Pods (shared data)
          ↑                           ↓
    S3 Model → Init Container    Output → EFS
```

### Components:
- **GitHub Actions**: CI/CD pipeline tự động build và deploy
- **ECR**: Container registry cho Docker images
- **S3**: Storage cho model weights
- **EFS**: Shared file system cho models và outputs giữa các pods
- **EKS**: Kubernetes cluster với GPU nodes

---

## 📋 Prerequisites

### 1. AWS Resources

#### a. Tạo EKS Cluster với GPU nodes
```bash
eksctl create cluster \
  --name yolo-cluster \
  --region us-west-2 \
  --node-type g4dn.xlarge \
  --nodes 2 \
  --nodes-min 1 \
  --nodes-max 5 \
  --with-oidc \
  --ssh-access \
  --ssh-public-key your-key-name \
  --managed
```

#### b. Tạo S3 Bucket
```bash
aws s3 mb s3://yolo-models-bucket --region us-west-2

# Upload model lần đầu
aws s3 cp models/best_Hai_03092025.pt s3://yolo-models-bucket/models/best.pt
```

#### c. Tạo ECR Repository
```bash
aws ecr create-repository \
  --repository-name yolo-inference \
  --region us-west-2
```

#### d. Tạo EFS File System
```bash
# Tạo EFS
aws efs create-file-system \
  --creation-token yolo-efs-$(date +%s) \
  --performance-mode generalPurpose \
  --throughput-mode bursting \
  --encrypted \
  --region us-west-2

# Lấy EFS ID (ví dụ: fs-0123456789abcdef)
EFS_ID=$(aws efs describe-file-systems --query 'FileSystems[0].FileSystemId' --output text)
echo $EFS_ID

# Tạo mount targets trong mỗi subnet của EKS cluster
# Lấy subnet IDs
SUBNET_IDS=$(aws eks describe-cluster --name yolo-cluster --query 'cluster.resourcesVpcConfig.subnetIds' --output text)

# Lấy security group của cluster
CLUSTER_SG=$(aws eks describe-cluster --name yolo-cluster --query 'cluster.resourcesVpcConfig.clusterSecurityGroupId' --output text)

# Tạo mount target cho mỗi subnet
for subnet in $SUBNET_IDS; do
  aws efs create-mount-target \
    --file-system-id $EFS_ID \
    --subnet-id $subnet \
    --security-groups $CLUSTER_SG
done
```

### 2. Install EFS CSI Driver

```bash
# Add Helm repo
helm repo add aws-efs-csi-driver https://kubernetes-sigs.github.io/aws-efs-csi-driver/
helm repo update

# Install driver
helm install aws-efs-csi-driver aws-efs-csi-driver/aws-efs-csi-driver \
  --namespace kube-system \
  --set image.repository=602401143452.dkr.ecr.us-west-2.amazonaws.com/eks/aws-efs-csi-driver \
  --set controller.serviceAccount.create=true
```

### 3. Install NVIDIA Device Plugin

```bash
kubectl create -f https://raw.githubusercontent.com/NVIDIA/k8s-device-plugin/v0.14.0/nvidia-device-plugin.yml
```

### 4. Tạo IAM Role cho Pods (IRSA)

```bash
# Tạo trust policy
cat > trust-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::ACCOUNT_ID:oidc-provider/oidc.eks.REGION.amazonaws.com/id/OIDC_ID"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "oidc.eks.REGION.amazonaws.com/id/OIDC_ID:sub": "system:serviceaccount:yolo-inference:yolo-sa"
        }
      }
    }
  ]
}
EOF

# Tạo IAM role
aws iam create-role \
  --role-name yolo-eks-pod-role \
  --assume-role-policy-document file://trust-policy.json

# Attach policies
cat > pod-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::yolo-models-bucket",
        "arn:aws:s3:::yolo-models-bucket/*"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
        "elasticfilesystem:DescribeFileSystems",
        "elasticfilesystem:ClientMount",
        "elasticfilesystem:ClientWrite"
      ],
      "Resource": "*"
    }
  ]
}
EOF

aws iam put-role-policy \
  --role-name yolo-eks-pod-role \
  --policy-name yolo-pod-policy \
  --policy-document file://pod-policy.json
```

---

## ⚙️ Configuration

### 1. Update Kubernetes Manifests

#### a. Update `k8s/storageclass.yaml`
Thay `fs-XXXXXXXXX` bằng EFS ID thực tế:
```bash
# Lấy EFS ID
aws efs describe-file-systems --query 'FileSystems[0].FileSystemId' --output text

# Edit file
sed -i 's/fs-XXXXXXXXX/fs-YOUR-ACTUAL-ID/g' k8s/storageclass.yaml
```

#### b. Update `k8s/serviceaccount.yaml`
Thay `ACCOUNT_ID` bằng AWS Account ID:
```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
sed -i "s/ACCOUNT_ID/$ACCOUNT_ID/g" k8s/serviceaccount.yaml
```

#### c. Update `k8s/deployment.yaml`
Thay ECR repository URL:
```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REGION="us-west-2"
sed -i "s|ACCOUNT_ID.dkr.ecr.REGION.amazonaws.com|$ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com|g" k8s/deployment.yaml
```

#### d. Update `k8s/configmap.yaml`
Cập nhật S3 bucket name và AWS region nếu cần.

### 2. Configure GitHub Secrets

Vào repository → Settings → Secrets and variables → Actions → New repository secret

Thêm các secrets sau:
- `AWS_ACCESS_KEY_ID`: AWS access key
- `AWS_SECRET_ACCESS_KEY`: AWS secret key
- `AWS_REGION`: `us-west-2` (hoặc region của bạn)
- `ECR_REPOSITORY`: `123456789.dkr.ecr.us-west-2.amazonaws.com/yolo-inference`
- `S3_MODEL_BUCKET`: `yolo-models-bucket`
- `EKS_CLUSTER_NAME`: `yolo-cluster`

---

## 🚀 Deployment

### 1. Deploy Kubernetes Resources

```bash
# Update kubeconfig
aws eks update-kubeconfig --name yolo-cluster --region us-west-2

# Deploy tất cả resources
kubectl apply -f k8s/namespace.yaml
kubectl apply -f k8s/storageclass.yaml
kubectl apply -f k8s/pvc.yaml
kubectl apply -f k8s/serviceaccount.yaml
kubectl apply -f k8s/configmap.yaml
kubectl apply -f k8s/deployment.yaml
kubectl apply -f k8s/service.yaml
kubectl apply -f k8s/hpa.yaml
```

### 2. Verify Deployment

```bash
# Check pods
kubectl get pods -n yolo-inference

# Check logs
kubectl logs -f deployment/yolo-inference -n yolo-inference

# Check service
kubectl get svc -n yolo-inference

# Check PVCs
kubectl get pvc -n yolo-inference
```

### 3. Get LoadBalancer URL

```bash
kubectl get svc yolo-service -n yolo-inference -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
```

---

## 🔄 CI/CD Workflow

Khi push code lên GitHub (branch `main`):

1. **GitHub Actions trigger**
2. **Build Docker image** → Push to ECR
3. **Upload model** → Push to S3
4. **Deploy to EKS** → Update deployment với image mới

### Manual Trigger
Có thể trigger manually qua GitHub UI:
- Actions → Build and Deploy to EKS → Run workflow

---

## 🧪 Testing

### Test API Endpoint

```bash
# Get LoadBalancer URL
LB_URL=$(kubectl get svc yolo-service -n yolo-inference -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

# Health check
curl http://$LB_URL/health

# Test inference
curl -X POST http://$LB_URL/predict \
  -F "file=@test_image.jpg"

# List all outputs (from all pods)
curl http://$LB_URL/outputs
```

### Test Shared EFS Output

```bash
# Exec vào pod thứ nhất
POD1=$(kubectl get pods -n yolo-inference -o jsonpath='{.items[0].metadata.name}')
kubectl exec -it $POD1 -n yolo-inference -- ls -la /output

# Exec vào pod thứ hai
POD2=$(kubectl get pods -n yolo-inference -o jsonpath='{.items[1].metadata.name}')
kubectl exec -it $POD2 -n yolo-inference -- ls -la /output

# Cả hai pods đều thấy cùng một output folder (shared)
```

---

## 📊 Monitoring

### View Logs

```bash
# All pods
kubectl logs -f deployment/yolo-inference -n yolo-inference

# Specific pod
kubectl logs -f <pod-name> -n yolo-inference

# Init container logs
kubectl logs <pod-name> -n yolo-inference -c model-downloader
```

### View Metrics

```bash
# Pod metrics
kubectl top pods -n yolo-inference

# HPA status
kubectl get hpa -n yolo-inference
```

---

## 🔧 Troubleshooting

### Pod không start được

```bash
# Check events
kubectl describe pod <pod-name> -n yolo-inference

# Check logs
kubectl logs <pod-name> -n yolo-inference --previous
```

### EFS mount issues

```bash
# Check PVC status
kubectl get pvc -n yolo-inference

# Check storage class
kubectl describe sc efs-sc

# Verify EFS mount targets
aws efs describe-mount-targets --file-system-id fs-XXXXX
```

### GPU không available

```bash
# Check NVIDIA plugin
kubectl get pods -n kube-system | grep nvidia

# Check node labels
kubectl get nodes -o json | jq '.items[].status.allocatable'
```

### Model không download được

```bash
# Check init container logs
kubectl logs <pod-name> -n yolo-inference -c model-downloader

# Verify IAM role
kubectl describe sa yolo-sa -n yolo-inference

# Check S3 bucket
aws s3 ls s3://yolo-models-bucket/models/
```

---

## 🧹 Cleanup

```bash
# Delete Kubernetes resources
kubectl delete namespace yolo-inference

# Delete EFS
aws efs delete-file-system --file-system-id fs-XXXXX

# Delete EKS cluster
eksctl delete cluster --name yolo-cluster --region us-west-2

# Delete S3 bucket
aws s3 rb s3://yolo-models-bucket --force

# Delete ECR repository
aws ecr delete-repository --repository-name yolo-inference --force
```

---

## 📝 Notes

1. **EFS Performance**: Sử dụng Provisioned Throughput nếu cần performance cao hơn
2. **GPU Costs**: g4dn.xlarge ~$0.526/hour, nhớ monitor và scale down khi không dùng
3. **Model Updates**: Mỗi lần push code mới, model cũng được sync từ S3
4. **Shared Output**: Tất cả pods đều ghi vào cùng EFS `/output`, có thể thấy results từ các pods khác
5. **Security**: Pods chạy với non-root user (UID 1000)

---

## 🔗 Useful Commands

```bash
# Port forward để test local
kubectl port-forward svc/yolo-service 8000:80 -n yolo-inference

# Scale deployment
kubectl scale deployment yolo-inference --replicas=5 -n yolo-inference

# Update image
kubectl set image deployment/yolo-inference yolo-inference=NEW_IMAGE -n yolo-inference

# Rollback deployment
kubectl rollout undo deployment/yolo-inference -n yolo-inference

# Restart pods
kubectl rollout restart deployment/yolo-inference -n yolo-inference
```
