# Deployment Guide

This guide is for the first successful environment bring-up.

## Files Used In This Flow

- [`.env.example`](/Users/nguyenhaidang/Workspace/EKS_YOLO/.env.example:1): source template for `.env`
- [scripts/render-manifests.sh](/Users/nguyenhaidang/Workspace/EKS_YOLO/scripts/render-manifests.sh): renders cluster and workload templates
- [k8s/cluster-config.yaml](/Users/nguyenhaidang/Workspace/EKS_YOLO/k8s/cluster-config.yaml): cluster template consumed by `eksctl`
- [scripts/deploy.sh](/Users/nguyenhaidang/Workspace/EKS_YOLO/scripts/deploy.sh): creates EFS if needed and deploys workload

## Prerequisites

- `aws`, `kubectl`, `eksctl`, and `helm` are installed and available on `PATH`
- the active AWS identity has permission to create and manage EKS, IAM, EFS, and related networking resources
- the YOLO model is already uploaded to S3
- `.env` has been reviewed and updated for the target environment

Recommended checks:

```bash
aws sts get-caller-identity
kubectl version --client
eksctl version
helm version
```

## Environment Review

Copy the template if needed:

```bash
cp .env.example .env
```

Review at least:

- `AWS_REGION`
- `CLUSTER_NAME`
- `ECR_REPOSITORY`
- `S3_BUCKET`
- `S3_MODEL_KEY`
- `INFERENCE_NODE_INSTANCE_TYPE`
- `SYSTEM_NODE_INSTANCE_TYPE`
- `DEPLOYMENT_REPLICAS`
- `CPU_REQUEST`
- `CPU_LIMIT`
- `MEMORY_REQUEST`
- `MEMORY_LIMIT`

Storage behavior:

- leave `EFS_ID` empty if the first deploy should create EFS
- set `EFS_ID` if you want to reuse an existing EFS file system

## Create the Cluster

Render the cluster config and create the cluster:

```bash
RENDER_DIR=$(mktemp -d)
./scripts/render-manifests.sh "$RENDER_DIR"
eksctl create cluster -f "$RENDER_DIR/cluster-config.yaml"
```

Result:

- EKS cluster
- OIDC-enabled IAM integration
- `yolo-sa`
- system and inference node groups

Verify cluster bootstrap:

```bash
kubectl get nodes
kubectl get serviceaccount yolo-sa -n yolo-inference
```

## Deploy the Workload

Run:

```bash
./scripts/deploy.sh
```

High level:

- verify cluster access
- create or reuse EFS
- install required addons
- render manifests
- apply workload resources

If a new EFS file system is created, persist the printed `EFS_ID` into `.env` for future deployments.

## Validate the Deployment

Run:

```bash
kubectl get pods -n yolo-inference -w
kubectl get hpa yolo-hpa -n yolo-inference
kubectl get svc yolo-service -n yolo-inference
kubectl get pods -n kube-system | grep -E 'metrics-server|efs|cluster-autoscaler'
```

Then test the API:

```bash
LB_URL=$(kubectl get svc yolo-service -n yolo-inference -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
curl "http://$LB_URL/health"
```

## Updating an Existing Environment

Use:

```bash
./scripts/update.sh
```

This is the normal day-2 path for applying rendered config changes and restarting the deployment.

## Common Failure Modes

### Missing service account

```bash
kubectl get serviceaccount yolo-sa -n yolo-inference
```

If missing, fix the cluster creation path instead of trying to patch workload IAM manually.

### Model download failure

```bash
kubectl logs -n yolo-inference <pod-name> -c model-downloader
kubectl describe sa yolo-sa -n yolo-inference
```

Validate the bucket, object key, and IRSA permissions.

### EFS mount failure

```bash
kubectl get pvc -n yolo-inference
kubectl describe sc efs-sc
kubectl get pods -n kube-system | grep efs
```

Validate that `EFS_ID` exists in the same AWS region as the cluster.
