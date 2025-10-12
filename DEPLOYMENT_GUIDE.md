# YOLO EKS Deployment Guide

## Prerequisites
- EKS cluster đã được tạo
- kubectl configured
- AWS CLI configured
- Helm installed
- S3 bucket chứa model weights

## Deployment Steps

### Step 1: Setup IAM Permissions (Run ONCE)
```bash
chmod +x setup-iam.sh
./setup-iam.sh
```

**Việc này sẽ:**
- Tạo IAM OIDC provider cho EKS cluster
- Tạo IAM policy cho phép read S3 bucket
- Tạo IAM role `yolo-eks-pod-role` với trust relationship
- Attach policy vào role

**Output:**
```
✓ IAM Setup Complete!
Role ARN: arn:aws:iam::688567276212:role/yolo-eks-pod-role
```

### Step 2: Deploy Infrastructure
```bash
chmod +x deploy.sh
./deploy.sh
```

**Việc này sẽ:**
- Kiểm tra IAM role đã tạo chưa
- Tạo EFS file system + mount targets
- Install Kubernetes addons:
  - EFS CSI Driver
  - NVIDIA Device Plugin
  - Metrics Server
- Update manifests với actual values
- Deploy all K8s resources

### Step 3: Trigger GitHub Actions
1. Go to: https://github.com/YOUR_USERNAME/YOUR_REPO/actions
2. Click "Build and Deploy to EKS"
3. Click "Run workflow" → Run on `main`

**GitHub Actions sẽ:**
- Build Docker image
- Push to ECR
- Trigger rolling update of deployment

### Step 4: Verify Deployment
```bash
# Check pods
kubectl get pods -n yolo-inference -w

# Check logs
kubectl logs -n yolo-inference -l app=yolo-inference

# Get LoadBalancer URL
LB_URL=$(kubectl get svc yolo-service -n yolo-inference -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
echo $LB_URL

# Test health endpoint
curl http://$LB_URL/health | jq '.'
```

## Troubleshooting

### Init Container fails with S3 permission denied
```bash
# Check IAM role
kubectl describe sa yolo-sa -n yolo-inference

# Should see annotation:
# eks.amazonaws.com/role-arn: arn:aws:iam::688567276212:role/yolo-eks-pod-role

# Check pod has correct service account
kubectl get pod <POD_NAME> -n yolo-inference -o yaml | grep serviceAccount
```

### EFS mount fails
```bash
# Check EFS CSI driver
kubectl get pods -n kube-system | grep efs

# Check PVC status
kubectl get pvc -n yolo-inference

# Check StorageClass
kubectl describe sc efs-sc
```

### Pod stuck in Pending
```bash
# Check events
kubectl describe pod <POD_NAME> -n yolo-inference

# Common issues:
# - No GPU nodes available
# - EFS mount timeout
# - Image pull error
```

## Files Structure

```
k8s/
├── iam-policy.json           # S3 read permissions
├── iam-trust-policy.json     # OIDC trust relationship
├── namespace.yaml            # yolo-inference namespace
├── serviceaccount.yaml       # SA with IAM role annotation
├── storageclass.yaml         # EFS storage class
├── pvc.yaml                  # PVCs for models & output
├── configmap.yaml            # Environment configs
├── deployment.yaml           # Main deployment
├── service.yaml              # LoadBalancer service
└── hpa.yaml                  # Horizontal Pod Autoscaler

setup-iam.sh                  # Setup IAM (run once)
deploy.sh                     # Deploy infrastructure
```

## Configuration Details

### IAM Permissions
- **Policy**: `yolo-s3-read-policy`
  - s3:GetObject
  - s3:ListBucket
- **Role**: `yolo-eks-pod-role`
  - Trust: EKS OIDC provider
  - Service Account: `yolo-inference/yolo-sa`

### EFS Configuration
- **Provisioning Mode**: `efs-ap` (Access Points)
- **Base Path**: `/` (root)
- **Directory Permissions**: `700`
- **UID/GID**: `1000:1000`
- **Mount Options**: TLS encryption

### Init Container
- **Image**: `amazon/aws-cli:latest`
- **Purpose**: Download model from S3 to EFS
- **IAM**: Uses ServiceAccount role
- **Logic**:
  1. Check if model exists in EFS
  2. Download from S3 if missing or update
  3. Set permissions (644)

## Clean Up

```bash
# Delete deployment
kubectl delete -f k8s/

# Delete EFS
EFS_ID=$(aws efs describe-file-systems --query 'FileSystems[?Name==`yolo-efs`].FileSystemId' --output text)
aws efs delete-file-system --file-system-id $EFS_ID

# Delete IAM resources
aws iam detach-role-policy --role-name yolo-eks-pod-role --policy-arn $(aws iam list-policies --query 'Policies[?PolicyName==`yolo-s3-read-policy`].Arn' --output text)
aws iam delete-role --role-name yolo-eks-pod-role
aws iam delete-policy --policy-arn $(aws iam list-policies --query 'Policies[?PolicyName==`yolo-s3-read-policy`].Arn' --output text)
```

## Notes

1. **IAM Setup**: Chỉ cần chạy `setup-iam.sh` một lần duy nhất
2. **EFS Access Points**: Tự động tạo bởi CSI driver khi tạo PVC
3. **Model Download**: Init container chạy mỗi khi pod restart
4. **Security**: Pods run as non-root user (UID 1000)
5. **GPU Scheduling**: Pods chỉ schedule trên g4dn.xlarge nodes
