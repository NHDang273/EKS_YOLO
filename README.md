# YOLO Inference on Amazon EKS with Auto-Scaling

Production-ready YOLOv8 object detection service on Amazon EKS with GPU auto-scaling.

## 🚀 Features

- ⚡ **GPU-accelerated inference** - NVIDIA T4 (g4dn.xlarge)
- 📈 **Auto-scaling** - HPA + Cluster Autoscaler
- 🐳 **Containerized** - Docker + ECR
- 🔄 **CI/CD** - GitHub Actions
- 💾 **Shared storage** - EFS for models
- 🔐 **Secure** - IAM Roles for Service Accounts (IRSA)

## 📁 Project Structure

```
yolo_eks/
├── main.py                      # FastAPI application
├── Dockerfile                   # Container definition
├── requirements.txt
├── README.md                    # This file
│
├── k8s/                         # Kubernetes manifests
│   ├── cluster-config.yaml      # EKS cluster setup
│   ├── deployment.yaml          # YOLO deployment
│   ├── service.yaml             # LoadBalancer
│   ├── hpa.yaml                 # Horizontal Pod Autoscaler
│   ├── cluster-autoscaler.yaml  # Cluster Autoscaler
│   ├── configmap.yaml
│   ├── serviceaccount.yaml
│   ├── pvc.yaml
│   ├── storageclass.yaml
│   └── iam-*.json
│
├── scripts/                     # Setup & deployment scripts
│   ├── 1-setup-cluster.sh       # Create EKS cluster
│   ├── 2-setup-iam.sh           # Setup IAM roles
│   ├── 3-setup-github.sh        # GitHub Actions access
│   ├── 4-deploy.sh              # Deploy infrastructure
│   └── 5-update.sh              # Update deployment
│
├── stress-test/                 # Load testing
│   ├── test.py                  # Stress test script
│   ├── monitor.sh               # Monitor auto-scaling
│   └── test-images/             # Place test images here
│
└── .github/workflows/
    └── deploy.yml               # CI/CD pipeline
```

---

## 🏗️ Architecture

```
GitHub → ECR → EKS Cluster
                ├── GPU Nodes (g4dn.xlarge)
                │   ├── Pod 1 ──┐
                │   ├── Pod 2 ──┼── Share GPU
                │   └── Pod N ──┘
                ├── LoadBalancer Service
                ├── EFS (Model Storage)
                └── S3 (Model Source)
```

### Auto-Scaling Flow:
1. **Low load** → 1 GPU node, 2 pods
2. **Medium load** → HPA scales to 4-5 pods on same node (~30s)
3. **High load** → Node full → Cluster Autoscaler adds GPU node (~3-5 min)
4. **Scale down** → After 5 min idle → Remove pods → Remove nodes

---

## 🚀 Quick Start

### Prerequisites
- AWS Account with EKS permissions
- `kubectl`, `eksctl`, `aws-cli`, `helm` installed
- Docker installed

### 1️⃣ Create EKS Cluster

```bash
# Create cluster (takes ~15-20 min)
eksctl create cluster -f k8s/cluster-config.yaml

# Verify
kubectl get nodes
```

### 2️⃣ Setup IAM Permissions

```bash
cd scripts
./2-setup-iam.sh
```

This creates:
- OIDC provider for EKS
- IAM role with S3 read access
- Attaches role to service account

### 3️⃣ Setup GitHub Actions

```bash
./3-setup-github.sh
```

Add these secrets to GitHub:
- `AWS_ACCESS_KEY_ID`
- `AWS_SECRET_ACCESS_KEY`
- `AWS_REGION=ap-southeast-1`
- `ECR_REPOSITORY=yolo-test`
- `EKS_CLUSTER_NAME=yolo-inference-cluster`
- `S3_MODEL_BUCKET=s3-eks-dang`

### 4️⃣ Deploy Infrastructure

```bash
./4-deploy.sh
```

Creates:
- EFS file system
- Namespace, PVC, ConfigMap
- Deployment, Service, HPA
- Cluster Autoscaler

### 5️⃣ Get Service URL

```bash
kubectl get svc yolo-service -n yolo-inference

# Output:
# NAME           TYPE           CLUSTER-IP      EXTERNAL-IP                        PORT(S)
# yolo-service   LoadBalancer   10.100.x.x      a1f82be55d1484dbc95968c2fe8e-...   80:30655/TCP
```

---

## 🔄 Update Deployment

After pulling new code:

```bash
git pull origin main
cd scripts
./5-update.sh
```

---

## 🧪 Stress Test & Monitor

### Prepare Test Images

```bash
# Copy your test images
cp /path/to/images/*.jpg stress-test/test-images/
```

### Run Load Test

```bash
cd stress-test

# Terminal 1: Monitor auto-scaling
./monitor.sh

# Terminal 2: Run stress test
LB_URL=$(kubectl get svc yolo-service -n yolo-inference -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

python test.py \
  --url "http://$LB_URL" \
  --images test-images \
  --concurrent 15 \
  --total 150
```

### Expected Output

```
📊 Results:
   Total: 150 requests
   ✅ Success: 148 (98.7%)
   ⏱️  Avg time: 1.23s

🎯 Pod distribution:
   pod-1: 37 requests (25%)
   pod-2: 38 requests (25.3%)
   pod-3: 36 requests (24%)
   pod-4: 37 requests (24.7%)
```

---

## 📡 API Usage

### Health Check
```bash
curl http://$LB_URL/health
```

### Predict
```bash
curl -X POST \
  -F "file=@test.jpg" \
  http://$LB_URL/predict
```

Response:
```json
{
  "success": true,
  "detections": [
    {"class": "person", "confidence": 0.92, "bbox": [...]},
    {"class": "car", "confidence": 0.87, "bbox": [...]}
  ],
  "pod_name": "yolo-inference-xxx-yyy",
  "inference_time": 0.045
}
```

---

## 🐛 Troubleshooting

### Pods not starting
```bash
kubectl describe pod <pod-name> -n yolo-inference
kubectl logs <pod-name> -n yolo-inference -c model-downloader  # Init container
kubectl logs <pod-name> -n yolo-inference -c yolo-inference     # Main container
```

### S3 Access Denied (403)
```bash
# Check IAM role
kubectl describe sa yolo-sa -n yolo-inference

# Verify policy
aws iam list-attached-role-policies --role-name yolo-eks-pod-role

# Attach S3 read policy
aws iam attach-role-policy \
  --role-name yolo-eks-pod-role \
  --policy-arn arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess
```

### Auto-scaling not working
```bash
# Check HPA
kubectl get hpa -n yolo-inference
kubectl describe hpa yolo-hpa -n yolo-inference

# Check metrics-server
kubectl get pods -n kube-system | grep metrics-server

# Check Cluster Autoscaler logs
kubectl logs -n kube-system -l app=cluster-autoscaler --tail=50
```

### EFS mount issues
```bash
# Check PVC
kubectl get pvc -n yolo-inference

# Check EFS CSI driver
kubectl get pods -n kube-system | grep efs-csi
```

---

## 🔧 Configuration

### Scale Manually

```bash
# Scale pods
kubectl scale deployment yolo-inference -n yolo-inference --replicas=6

# Scale GPU nodes
eksctl scale nodegroup gpu-nodes \
  --cluster yolo-inference-cluster \
  --region ap-southeast-1 \
  --nodes 2
```

### Update HPA Thresholds

Edit `k8s/hpa.yaml`:
```yaml
metrics:
- type: Resource
  resource:
    name: cpu
    target:
      type: Utilization
      averageUtilization: 70  # Change this
```

Apply:
```bash
kubectl apply -f k8s/hpa.yaml
```

---

## 📊 Monitoring

```bash
# Watch pods
watch kubectl get pods -n yolo-inference -o wide

# Watch HPA
watch kubectl get hpa -n yolo-inference

# Watch nodes
watch kubectl get nodes

# Pod logs
kubectl logs -f -n yolo-inference -l app=yolo-inference

# Autoscaler logs
kubectl logs -f -n kube-system -l app=cluster-autoscaler
```

---

## 🧹 Cleanup & Restart

### Delete Cluster

```bash
# Delete entire cluster (takes ~10-15 min)
eksctl delete cluster --name yolo-inference-cluster --region ap-southeast-1
```

This removes:
- All nodes (GPU + CPU)
- LoadBalancer
- EFS file system
- VPC resources

### Start Fresh - Complete Setup Flow

After deleting, to start from scratch:

#### **Step 1: Create Cluster** (~15-20 min)
```bash
eksctl create cluster -f k8s/cluster-config.yaml
```

#### **Step 2: Setup IAM** (~2 min)
```bash
cd scripts
./setup-iam.sh
```

Creates:
- OIDC provider
- IAM role with S3 access
- Service account binding

#### **Step 3: Deploy Infrastructure** (~5 min)
```bash
./deploy.sh
```

Deploys in order:
1. Namespace → StorageClass → PVC (creates EFS)
2. ServiceAccount → ConfigMap
3. Deployment (init container downloads model from S3)
4. Service (creates LoadBalancer ~2-3 min)
5. HPA + Cluster Autoscaler

#### **Step 4: Get LoadBalancer URL**
```bash
kubectl get svc yolo-service -n yolo-inference -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
```

**Total time: ~35-40 minutes**

### Optional: Delete Other Resources

```bash
# Delete ECR repo
aws ecr delete-repository --repository-name yolo-test --region ap-southeast-1 --force

# Delete S3 bucket (optional)
aws s3 rb s3://s3-eks-dang --force
```

---

## 📝 Notes

- **GPU Sharing**: Pods don't request GPU explicitly, allowing multiple pods per GPU
- **Init Container**: Downloads model from S3 to EFS on first run
- **Storage**: EFS for persistent model storage, S3 as source
- **Security**: Pods run as non-root user, IAM roles via IRSA
- **Cost**: ~$0.50/hour per g4dn.xlarge GPU node

---

## 📚 Additional Resources

- [EKS Documentation](https://docs.aws.amazon.com/eks/)
- [Cluster Autoscaler](https://github.com/kubernetes/autoscaler/tree/master/cluster-autoscaler)
- [NVIDIA Device Plugin](https://github.com/NVIDIA/k8s-device-plugin)
- [YOLOv8 Documentation](https://docs.ultralytics.com/)

---

## 🤝 Contributing

1. Fork repository
2. Create feature branch
3. Make changes
4. Test locally
5. Submit pull request

---

## 📄 License

MIT License
