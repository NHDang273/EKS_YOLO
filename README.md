# YOLO Inference on AWS EKS

Deploy YOLO inference application lên AWS EKS với GitHub Actions CI/CD pipeline.

## 🏗️ Kiến trúc

```
GitHub → GitHub Actions → ECR (Docker Image) + S3 (Model)
                              ↓
                         EKS Cluster
                              ↓
                    ┌─────────┴─────────┐
                    ↓                   ↓
               EFS (Models)        Pods (shared data)
                    ↑                   ↓
          S3 Model → Init Container downloads
```

### Components:
- **GitHub Actions**: CI/CD pipeline tự động build và deploy
- **ECR**: Container registry cho Docker images
- **S3**: Storage cho model weights
- **EFS**: Shared file system cho models và outputs giữa các pods
- **EKS**: Kubernetes cluster với GPU nodes (g4dn.xlarge)

---

## 🚀 Quick Start

### 1. Setup Environment

```bash
# Run setup script
source setup-env.sh

# Verify environment
echo $AWS_REGION
echo $CLUSTER_NAME
echo $ECR_URL
```

**Environment Variables:**
- `AWS_REGION`: ap-southeast-1
- `CLUSTER_NAME`: ai-inference-prod
- `ECR_REPO`: ai-inference
- `S3_WEIGHTS_BUCKET`: ai-weights-{ACCOUNT_ID}
- `S3_OUTPUT_BUCKET`: ai-outputs-{ACCOUNT_ID}

### 2. Check Infrastructure

```bash
# Run infrastructure check
./check-infra.sh
```

Script sẽ kiểm tra:
- ✓ EKS Cluster status
- ✓ ECR Repository
- ✓ S3 Buckets
- ✓ EFS File System
- ✓ Kubernetes connection
- ✓ Required addons (EFS CSI, NVIDIA plugin, Metrics server)

### 3. Deploy Application

**Application được deploy tự động qua GitHub Actions khi push code.**

Workflow sẽ:
1. Build Docker image → Push to ECR
2. Upload model weights → Push to S3
3. Update Kubernetes deployment

---

## 📁 Project Structure

```
yolo_eks/
├── .github/workflows/
│   └── deploy.yml              # GitHub Actions CI/CD
├── k8s/
│   ├── namespace.yaml          # Namespace
│   ├── serviceaccount.yaml     # Service Account với IRSA
│   ├── storageclass.yaml       # EFS Storage Class
│   ├── pvc.yaml                # PVCs cho models và output
│   ├── configmap.yaml          # Configuration
│   ├── deployment.yaml         # Deployment với init container
│   ├── service.yaml            # LoadBalancer Service
│   └── hpa.yaml                # Horizontal Pod Autoscaler
├── cluster-config.yaml         # EKS cluster configuration
├── setup-env.sh                # Setup environment variables
├── check-infra.sh              # Check infrastructure status
├── main.py                     # FastAPI application
├── Dockerfile                  # Container image definition
├── requirements.txt            # Python dependencies
└── README.md                   # This file
```

---

## 🔧 Configuration

### Update Kubernetes Manifests

Trước khi deploy, cần update các placeholders:

#### 1. StorageClass ([k8s/storageclass.yaml](k8s/storageclass.yaml))
```bash
# Get EFS ID
EFS_ID=$(aws efs describe-file-systems --region $AWS_REGION --query "FileSystems[0].FileSystemId" --output text)

# Update file
sed -i "s/fs-XXXXXXXXX/${EFS_ID}/g" k8s/storageclass.yaml
```

#### 2. ServiceAccount ([k8s/serviceaccount.yaml](k8s/serviceaccount.yaml))
```bash
# Update with your AWS Account ID
sed -i "s/ACCOUNT_ID/${AWS_ACCOUNT_ID}/g" k8s/serviceaccount.yaml
```

#### 3. Deployment ([k8s/deployment.yaml](k8s/deployment.yaml))
```bash
# Update ECR URL
sed -i "s|ACCOUNT_ID.dkr.ecr.REGION.amazonaws.com|${ECR_URL}|g" k8s/deployment.yaml
```

#### 4. ConfigMap ([k8s/configmap.yaml](k8s/configmap.yaml))
```bash
# Update S3 bucket and region
sed -i "s/yolo-models-bucket/${S3_WEIGHTS_BUCKET}/g" k8s/configmap.yaml
sed -i "s/us-west-2/${AWS_REGION}/g" k8s/configmap.yaml
```

### GitHub Secrets

Thêm các secrets vào GitHub repository (Settings → Secrets and variables → Actions):

```bash
AWS_ACCESS_KEY_ID=<your-access-key>
AWS_SECRET_ACCESS_KEY=<your-secret-key>
AWS_REGION=ap-southeast-1
ECR_REPOSITORY=<account-id>.dkr.ecr.ap-southeast-1.amazonaws.com/ai-inference
S3_MODEL_BUCKET=ai-weights-<account-id>
EKS_CLUSTER_NAME=ai-inference-prod
```

---

## 📦 Deployment Flow

### GitHub Actions Workflow

Khi push code lên branch `main`:

1. **Build & Push Docker Image**
   ```
   Docker build → Tag → Push to ECR
   ```

2. **Upload Model Weights**
   ```
   models/best_Hai_03092025.pt → S3 bucket
   ```

3. **Deploy to EKS**
   ```
   Update deployment → Rolling update pods
   ```

### Init Container Flow

Mỗi pod khi start:

1. **Init Container** chạy trước main container
2. Download model từ S3 → EFS `/models`
3. Main container start, đọc model từ EFS (read-only)
4. Results được ghi vào EFS `/output` (shared giữa các pods)

---

## 🧪 Testing

### Get LoadBalancer URL

```bash
LB_URL=$(kubectl get svc yolo-service -n yolo-inference -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
echo $LB_URL
```

### API Endpoints

#### 1. Health Check
```bash
curl http://$LB_URL/health
```

Response:
```json
{
  "status": "healthy",
  "model_path": "/models/best.pt",
  "pod_name": "yolo-inference-xxx",
  "output_path": "/output"
}
```

#### 2. Inference
```bash
curl -X POST http://$LB_URL/predict \
  -F "file=@test_image.jpg"
```

Response:
```json
{
  "success": true,
  "detections": [...],
  "count": 5,
  "pod_name": "yolo-inference-xxx",
  "output_file": "/output/result_xxx.json"
}
```

#### 3. List All Outputs (Shared)
```bash
curl http://$LB_URL/outputs
```

Response - shows outputs from ALL pods (shared EFS):
```json
{
  "success": true,
  "total_files": 150,
  "files": [
    {
      "filename": "result_pod1_20251011_123456.json",
      "size": 2048,
      "modified": "2025-10-11T12:34:56"
    }
  ],
  "pod_name": "yolo-inference-yyy"
}
```

---

## 📊 Monitoring

### View Pods Status

```bash
# Watch pods
kubectl get pods -n yolo-inference -w

# Pod details
kubectl describe pod <pod-name> -n yolo-inference

# Check GPU allocation
kubectl get nodes -o json | jq '.items[].status.allocatable'
```

### View Logs

```bash
# All pods logs
kubectl logs -f deployment/yolo-inference -n yolo-inference

# Specific pod
kubectl logs -f <pod-name> -n yolo-inference

# Init container logs
kubectl logs <pod-name> -n yolo-inference -c model-downloader
```

### View Metrics

```bash
# Pod metrics (CPU, Memory)
kubectl top pods -n yolo-inference

# Node metrics
kubectl top nodes

# HPA status
kubectl get hpa -n yolo-inference
```

### Check Shared EFS

```bash
# Exec into pod
POD=$(kubectl get pods -n yolo-inference -o jsonpath='{.items[0].metadata.name}')
kubectl exec -it $POD -n yolo-inference -- bash

# Inside pod
ls -la /models      # Model weights (read-only)
ls -la /output      # Shared outputs (read-write)
```

---

## 🔄 Scaling

### Manual Scaling

```bash
# Scale to 5 replicas
kubectl scale deployment yolo-inference --replicas=5 -n yolo-inference
```

### Auto Scaling (HPA)

HPA automatically scales based on CPU/Memory:

```yaml
minReplicas: 2
maxReplicas: 10
targetCPU: 70%
targetMemory: 80%
```

Check HPA:
```bash
kubectl get hpa -n yolo-inference
```

---

## 🛠️ Troubleshooting

### Pods không start

```bash
# Check events
kubectl describe pod <pod-name> -n yolo-inference

# Check logs
kubectl logs <pod-name> -n yolo-inference
```

### EFS mount issues

```bash
# Check PVC status
kubectl get pvc -n yolo-inference

# Check storage class
kubectl describe sc efs-sc

# Verify EFS mount targets
aws efs describe-mount-targets --file-system-id $EFS_ID
```

### Model không download được

```bash
# Check init container logs
kubectl logs <pod-name> -n yolo-inference -c model-downloader

# Verify S3 bucket
aws s3 ls s3://$S3_WEIGHTS_BUCKET/models/

# Check IAM permissions
kubectl describe sa yolo-sa -n yolo-inference
```

### GPU không available

```bash
# Check NVIDIA plugin
kubectl get pods -n kube-system -l name=nvidia-device-plugin-ds

# Check node labels
kubectl get nodes --show-labels | grep gpu
```

---

## 🧹 Cleanup

### Delete Application Only

```bash
kubectl delete namespace yolo-inference
```

### Delete Entire Cluster

```bash
eksctl delete cluster --name ai-inference-prod --region ap-southeast-1
```

### Delete S3 & ECR

```bash
# Delete S3 buckets
aws s3 rb s3://$S3_WEIGHTS_BUCKET --force
aws s3 rb s3://$S3_OUTPUT_BUCKET --force

# Delete ECR repo
aws ecr delete-repository --repository-name $ECR_REPO --force --region $AWS_REGION
```

---

## 📚 Documentation

- [README-DEPLOYMENT.md](README-DEPLOYMENT.md) - Chi tiết deployment
- [cluster-config.yaml](cluster-config.yaml) - EKS cluster configuration
- [k8s/](k8s/) - Kubernetes manifests

---

## 🔗 Useful Commands

```bash
# Port forward to test locally
kubectl port-forward svc/yolo-service 8000:80 -n yolo-inference
curl http://localhost:8000/health

# Update deployment image
kubectl set image deployment/yolo-inference yolo-inference=$ECR_URL:latest -n yolo-inference

# Rollback deployment
kubectl rollout undo deployment/yolo-inference -n yolo-inference

# Restart all pods
kubectl rollout restart deployment/yolo-inference -n yolo-inference

# Check deployment history
kubectl rollout history deployment/yolo-inference -n yolo-inference
```

---

## 💰 Cost Estimate

**Monthly cost** (ap-southeast-1):
- EKS Cluster: ~$73/month
- g4dn.xlarge x2: ~$310/month (24/7)
- t3.medium x2: ~$60/month
- EFS: ~$3-5/month (10GB)
- S3: ~$1/month
- **Total: ~$450/month**

**Cost optimization:**
- Scale down GPU nodes khi không dùng
- Sử dụng Spot Instances
- Schedule pods (chỉ chạy giờ làm việc)

---

## 📝 Notes

- **EFS Performance**: Sử dụng Provisioned Throughput nếu cần hiệu năng cao hơn
- **Security**: Pods chạy với non-root user (UID 1000)
- **Model Updates**: Mỗi lần push code, model cũng được sync từ S3
- **Shared Output**: Tất cả pods ghi vào cùng EFS `/output`
- **Init Container**: Đảm bảo model luôn được download trước khi pod start

---

**Version**: 1.0
**Last Updated**: 2025-10-11
**Region**: ap-southeast-1
**Cluster**: ai-inference-prod
