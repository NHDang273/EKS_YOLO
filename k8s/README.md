# Kubernetes Manifests

This directory contains all Kubernetes manifests for YOLO inference deployment.

## Files Overview

### Core Deployment
- **deployment.yaml** - Main YOLO inference deployment (GPU sharing enabled)
- **service.yaml** - LoadBalancer service exposing port 80
- **namespace.yaml** - Creates `yolo-inference` namespace
- **configmap.yaml** - Environment variables (S3 bucket, model path, etc.)
- **serviceaccount.yaml** - Service account with IAM role annotation

### Storage
- **pvc.yaml** - PersistentVolumeClaims for EFS (models + output)
- **storageclass.yaml** - EFS CSI StorageClass with Access Points

### Auto-Scaling
- **hpa.yaml** - Horizontal Pod Autoscaler (CPU/Memory based)
- **cluster-autoscaler.yaml** - Cluster Autoscaler for GPU nodes

### Cluster Setup
- **cluster-config.yaml** - eksctl cluster configuration (GPU + CPU nodes)

### IAM (for IRSA)
- **iam-policy.json** - S3 read policy
- **iam-trust-policy.json** - OIDC trust policy template

## Deployment Order

### 1. One-time cluster setup
```bash
eksctl create cluster -f cluster-config.yaml
```

### 2. Deploy infrastructure (run from scripts/)
```bash
./deploy.sh  # Applies manifests in correct order
```

Manual order:
```bash
kubectl apply -f namespace.yaml
kubectl apply -f storageclass.yaml
kubectl apply -f pvc.yaml
kubectl apply -f serviceaccount.yaml
kubectl apply -f configmap.yaml
kubectl apply -f deployment.yaml
kubectl apply -f service.yaml
kubectl apply -f hpa.yaml
kubectl apply -f cluster-autoscaler.yaml
```

## Configuration

### Update S3 Bucket
Edit `configmap.yaml`:
```yaml
data:
  S3_BUCKET: "your-bucket-name"
  S3_MODEL_KEY: "models/best.pt"
```

### Update Cluster Name
Edit `cluster-autoscaler.yaml`:
```yaml
--node-group-auto-discovery=asg:tag=k8s.io/cluster-autoscaler/yolo-inference-cluster
```

### Scale Pods
Edit `deployment.yaml`:
```yaml
spec:
  replicas: 2  # Change this
```

Or use kubectl:
```bash
kubectl scale deployment yolo-inference -n yolo-inference --replicas=4
```

### Adjust HPA Thresholds
Edit `hpa.yaml`:
```yaml
metrics:
- type: Resource
  resource:
    name: cpu
    target:
      averageUtilization: 70  # Adjust this (default: 70%)
```

## Notes

- **GPU Sharing**: Deployment doesn't request `nvidia.com/gpu` explicitly, allowing multiple pods per GPU node
- **Init Container**: Downloads model from S3 to EFS on first pod start
- **Storage**: EFS provides shared ReadWriteMany storage for all pods
- **IRSA**: Service account uses IAM role (no AWS credentials needed in pods)
- **Security**: Pods run as non-root user (UID 1000)

## Troubleshooting

See main README.md troubleshooting section.
