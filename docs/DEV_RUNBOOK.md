# Dev Runbook: Chạy Demo YOLO EKS từ EC2 Bastion

## Yêu cầu trước khi bắt đầu

- Đã tạo EC2 Bastion (Amazon Linux 2023, t3.medium, 20GB gp3)
- IAM Role gắn vào EC2 với các quyền: EKS, EC2, S3, ECR, IAM, CloudFormation
- SSH vào được Bastion

---

## Phần 1: Cài tools trên Bastion

```bash
# kubectl
curl -LO "https://dl.k8s.io/release/$(curl -sL https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
chmod +x kubectl && sudo mv kubectl /usr/local/bin/

# eksctl
curl -sLO "https://github.com/eksctl-io/eksctl/releases/latest/download/eksctl_Linux_amd64.tar.gz"
tar -xzf eksctl_Linux_amd64.tar.gz && sudo mv eksctl /usr/local/bin/
rm eksctl_Linux_amd64.tar.gz

# helm
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# docker
sudo yum install -y docker git python3-pip
sudo systemctl start docker && sudo systemctl enable docker
sudo usermod -aG docker $USER
newgrp docker

# verify
aws sts get-caller-identity
kubectl version --client
eksctl version
helm version
docker info | grep "Server Version"
```

---

## Phần 2: Clone repo & cấu hình

```bash
git clone <your-repo-url>
cd EKS_YOLO

cp .env.example .env
```

Mở `.env` và điền các giá trị:

```bash
nano .env
```

Các trường cần điền:

```env
AWS_REGION=ap-southeast-1
CLUSTER_NAME=yolo-inference-cluster
AWS_ACCOUNT_ID=          # lấy bằng lệnh bên dưới
ECR_REPOSITORY=yolo-inference
S3_BUCKET=s3-eks-dang
S3_MODEL_KEY=models/best.pt
EFS_ID=                  # để trống, script tự tạo
```

Lấy Account ID:

```bash
aws sts get-caller-identity --query Account --output text
```

---

## Phần 3: Upload model lên S3

Nếu S3 chưa có model:

```bash
pip3 install ultralytics --quiet

# Download model YOLOv8n (~6MB)
python3 -c "from ultralytics import YOLO; YOLO('yolov8n.pt')"

# Upload lên S3
aws s3 cp ~/.cache/ultralytics/yolov8n.pt s3://s3-eks-dang/models/best.pt

# Verify
aws s3 ls s3://s3-eks-dang/models/
```

---

## Phần 4: Tạo EKS Cluster

> Bước này mất 15-20 phút.

```bash
RENDER_DIR=$(mktemp -d)
./scripts/render-manifests.sh "$RENDER_DIR"
eksctl create cluster -f "$RENDER_DIR/cluster-config.yaml"
```

Sau khi xong, verify:

```bash
kubectl get nodes
kubectl get serviceaccount yolo-sa -n yolo-inference
```

Mong đợi thấy ít nhất 3 nodes (2 system + 1 inference) và serviceaccount `yolo-sa`.

---

## Phần 5: Build & Push Docker image lên ECR

```bash
# Lấy Account ID
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ECR_URL="${ACCOUNT_ID}.dkr.ecr.ap-southeast-1.amazonaws.com/yolo-inference"

# Tạo ECR repository
aws ecr create-repository --repository-name yolo-inference --region ap-southeast-1

# Login ECR
aws ecr get-login-password --region ap-southeast-1 | \
  docker login --username AWS --password-stdin \
  ${ACCOUNT_ID}.dkr.ecr.ap-southeast-1.amazonaws.com

# Build & push
docker build -t yolo-inference .
docker tag yolo-inference:latest ${ECR_URL}:latest
docker push ${ECR_URL}:latest

# Cập nhật ECR_URL vào .env
echo "ECR_URL=${ECR_URL}" >> .env
```

---

## Phần 6: Deploy workload lên EKS

```bash
./scripts/deploy.sh
```

Script sẽ:
1. Tạo EFS file system và mount targets
2. Cài EFS CSI Driver và Metrics Server qua Helm
3. Apply toàn bộ Kubernetes manifests

Sau khi chạy xong, **lưu EFS_ID vào `.env`**:

```bash
# EFS_ID sẽ được in ra trong output của deploy.sh, ví dụ: fs-0abc1234
# Thêm vào .env:
echo "EFS_ID=fs-0abc1234" >> .env
```

---

## Phần 7: Verify deployment

```bash
# Pods đang chạy
kubectl get pods -n yolo-inference -w
# Chờ tất cả STATUS = Running, READY = 1/1

# HPA đã active
kubectl get hpa yolo-hpa -n yolo-inference

# Service có EXTERNAL-IP
kubectl get svc yolo-service -n yolo-inference

# Addons đang chạy
kubectl get pods -n kube-system | grep -E 'metrics-server|efs|cluster-autoscaler'
```

---

## Phần 8: Test API

```bash
# Lấy LoadBalancer URL
LB_URL=$(kubectl get svc yolo-service -n yolo-inference \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

echo "API URL: http://$LB_URL"

# Health check
curl http://$LB_URL/health | python3 -m json.tool

# Predict (cần 1 file ảnh)
curl -X POST \
  -F "file=@stress-test/test-images/sample.jpg" \
  http://$LB_URL/predict | python3 -m json.tool

# List outputs
curl http://$LB_URL/outputs | python3 -m json.tool
```

---

## Phần 9: Chạy stress test để trigger scaling

### Chuẩn bị ảnh test

```bash
cd stress-test
mkdir -p test-images

# Copy ảnh vào hoặc download sample
curl -L "https://ultralytics.com/images/bus.jpg" -o test-images/bus.jpg
curl -L "https://ultralytics.com/images/zidane.jpg" -o test-images/zidane.jpg
```

### Mở 3 terminal song song để quan sát

**Terminal 1:**
```bash
watch -n 3 kubectl get pods -n yolo-inference -o wide
```

**Terminal 2:**
```bash
watch -n 5 kubectl get hpa yolo-hpa -n yolo-inference
```

**Terminal 3:**
```bash
watch -n 10 kubectl get nodes -o wide
```

### Bắn load (Terminal 4)

```bash
cd stress-test

# Smoke test trước (20 requests)
python3 test.py --url http://$LB_URL --concurrent 5 --total 20

# Scaling test — trigger HPA
python3 test.py --url http://$LB_URL --concurrent 20 --duration 180
```

### Những gì cần quan sát

| Thời điểm | Quan sát |
|-----------|----------|
| ~1 phút | CPU trên HPA vượt 70% |
| ~2 phút | Pods mới xuất hiện (Pending → ContainerCreating → Running) |
| ~4 phút | Node mới được provision (Cluster Autoscaler) |
| ~5 phút | Hệ thống ổn định với nhiều pods hơn |
| Sau test | Pods tự giảm về min=2 sau 5 phút |

---

## Phần 10: Dọn dẹp sau demo

```bash
# Xóa workload
kubectl delete namespace yolo-inference

# Xóa cluster (xóa tất cả node groups & VPC)
eksctl delete cluster --name yolo-inference-cluster --region ap-southeast-1

# Xóa EFS (nếu không dùng nữa)
aws efs delete-file-system --file-system-id fs-0abc1234 --region ap-southeast-1

# Xóa ECR images
aws ecr delete-repository --repository-name yolo-inference --force --region ap-southeast-1
```

---

## Troubleshooting nhanh

**Pods không start:**
```bash
kubectl describe pod <pod-name> -n yolo-inference
kubectl logs <pod-name> -n yolo-inference -c model-downloader
```

**HPA không scale:**
```bash
kubectl describe hpa yolo-hpa -n yolo-inference
kubectl get pods -n kube-system | grep metrics-server
```

**EFS không mount:**
```bash
kubectl get pvc -n yolo-inference
kubectl describe sc efs-sc
kubectl get pods -n kube-system | grep efs
```

**Không kết nối được API:**
```bash
# Kiểm tra LB đã có IP chưa (có thể mất 2-3 phút)
kubectl get svc yolo-service -n yolo-inference
```
