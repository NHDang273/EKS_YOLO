# YOLO Inference on Amazon EKS

CPU-based YOLO inference service deployed on Amazon EKS with shared EFS storage, HPA, and cluster autoscaler.

## What It Contains

- FastAPI inference service running YOLO on CPU
- EKS cluster and workload manifests rendered from `.env`
- EFS-backed shared storage for model and outputs
- scripts for first deploy, update, and GitHub access setup
- docs for deployment, operations, CI/CD, and load testing

Current gaps:

- no API auth
- no TLS at the app layer
- no metrics or centralized logging stack
- no retention policy for output data

## Architecture

```text
Client
  |
  v
AWS LoadBalancer Service
  |
  v
YOLO FastAPI Pods on EKS
  | \
  |  \__ HPA scales pods on CPU and memory
  |
  +--> EFS /models
  +--> EFS /output

S3 model file
  |
  v
Init container copies model to EFS if missing
```

## Runtime Flow

1. `eksctl` creates the EKS cluster and the `yolo-sa` IAM service account.
2. `scripts/deploy.sh` creates or reuses EFS and installs required cluster addons.
3. The deployment init container downloads the YOLO model from S3 into EFS when `/models/best.pt` is missing.
4. The FastAPI container loads the model from EFS and serves `/health`, `/predict`, and `/outputs`.
5. HPA scales pods on CPU and memory pressure.
6. Cluster Autoscaler expands or shrinks worker capacity based on pending workload.

## Repo Map

### Application

- [main.py](/Users/nguyenhaidang/Workspace/EKS_YOLO/main.py): FastAPI app with `/health`, `/predict`, and `/outputs`
- [Dockerfile](/Users/nguyenhaidang/Workspace/EKS_YOLO/Dockerfile): container image build
- [requirements.txt](/Users/nguyenhaidang/Workspace/EKS_YOLO/requirements.txt): Python dependencies
- [`.env.example`](/Users/nguyenhaidang/Workspace/EKS_YOLO/.env.example:1): environment template copied to `.env`

### Kubernetes

- [k8s/cluster-config.yaml](/Users/nguyenhaidang/Workspace/EKS_YOLO/k8s/cluster-config.yaml): `eksctl` cluster template
- [k8s/cluster-autoscaler.yaml](/Users/nguyenhaidang/Workspace/EKS_YOLO/k8s/cluster-autoscaler.yaml): cluster autoscaler manifest
- [k8s/deployment.yaml](/Users/nguyenhaidang/Workspace/EKS_YOLO/k8s/deployment.yaml): workload deployment and init container
- [k8s/configmap.yaml](/Users/nguyenhaidang/Workspace/EKS_YOLO/k8s/configmap.yaml): runtime env passed into pods
- [k8s/service.yaml](/Users/nguyenhaidang/Workspace/EKS_YOLO/k8s/service.yaml): public LoadBalancer service
- [k8s/hpa.yaml](/Users/nguyenhaidang/Workspace/EKS_YOLO/k8s/hpa.yaml): pod autoscaling policy
- [k8s/storageclass.yaml](/Users/nguyenhaidang/Workspace/EKS_YOLO/k8s/storageclass.yaml): EFS storage class template
- [k8s/pvc.yaml](/Users/nguyenhaidang/Workspace/EKS_YOLO/k8s/pvc.yaml): model and output PVCs
- [k8s/namespace.yaml](/Users/nguyenhaidang/Workspace/EKS_YOLO/k8s/namespace.yaml): `yolo-inference` namespace

### Scripts

- [scripts/setup-env.sh](/Users/nguyenhaidang/Workspace/EKS_YOLO/scripts/setup-env.sh): load and validate `.env`
- [scripts/render-manifests.sh](/Users/nguyenhaidang/Workspace/EKS_YOLO/scripts/render-manifests.sh): render templates into a temp directory
- [scripts/deploy.sh](/Users/nguyenhaidang/Workspace/EKS_YOLO/scripts/deploy.sh): first infra and workload deploy
- [scripts/update.sh](/Users/nguyenhaidang/Workspace/EKS_YOLO/scripts/update.sh): apply updates and restart rollout
- [scripts/setup-github.sh](/Users/nguyenhaidang/Workspace/EKS_YOLO/scripts/setup-github.sh): grant GitHub Actions cluster access

### Docs

- [docs/SETUP_GUIDE.md](/Users/nguyenhaidang/Workspace/EKS_YOLO/docs/SETUP_GUIDE.md): first bring-up
- [docs/OPERATIONS.md](/Users/nguyenhaidang/Workspace/EKS_YOLO/docs/OPERATIONS.md): runbook and day-2 operations
- [docs/GITHUB_SETUP.md](/Users/nguyenhaidang/Workspace/EKS_YOLO/docs/GITHUB_SETUP.md): CI/CD access model
- [stress-test/README.md](/Users/nguyenhaidang/Workspace/EKS_YOLO/stress-test/README.md): load test usage

## Configuration

The single source of truth is [`.env.example`](/Users/nguyenhaidang/Workspace/EKS_YOLO/.env.example:1) copied to `.env`.

Critical variables:

- `AWS_REGION`
- `CLUSTER_NAME`
- `ECR_REPOSITORY`
- `S3_BUCKET`
- `S3_MODEL_KEY`
- `EFS_ID`
- `INFERENCE_NODE_INSTANCE_TYPE`
- `SYSTEM_NODE_INSTANCE_TYPE`
- `DEPLOYMENT_REPLICAS`
- `CPU_REQUEST`
- `CPU_LIMIT`
- `MEMORY_REQUEST`
- `MEMORY_LIMIT`

Notes:

- leave `EFS_ID` empty on the first deploy if the script should create EFS
- persist `EFS_ID` back into `.env` after first deploy
- rendered manifests are written to a temp directory, not back into `k8s/`

## Standard Workflow

### 1. Prepare configuration

```bash
cp .env.example .env
```

Review the environment values before touching AWS resources.

### 2. Render and create the cluster

```bash
RENDER_DIR=$(mktemp -d)
./scripts/render-manifests.sh "$RENDER_DIR"
eksctl create cluster -f "$RENDER_DIR/cluster-config.yaml"
```

### 3. Deploy cluster services and workload

```bash
./scripts/deploy.sh
```

### 4. Verify health

```bash
kubectl get nodes
kubectl get pods -n yolo-inference
kubectl get hpa yolo-hpa -n yolo-inference
kubectl get svc yolo-service -n yolo-inference
```

### 5. Roll forward changes

```bash
./scripts/update.sh
```

Use this path for normal re-deployments.

## API

### Health check

```bash
curl http://<LOADBALANCER_URL>/health
```

### Predict

```bash
curl -X POST \
  -F "file=@test.jpg" \
  http://<LOADBALANCER_URL>/predict
```

### List outputs

```bash
curl http://<LOADBALANCER_URL>/outputs
```

## Production Notes

- config is centralized through `.env`
- IRSA is managed through `eksctl`
- deploy and update flows are scriptable
- hardening still needed around auth, TLS, observability, and data retention
