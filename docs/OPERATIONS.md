# Operations Runbook

This document is the day-2 operating guide for the YOLO inference service running on EKS.

## Main Files

- [scripts/update.sh](/Users/nguyenhaidang/Workspace/EKS_YOLO/scripts/update.sh): normal rollout path
- [scripts/deploy.sh](/Users/nguyenhaidang/Workspace/EKS_YOLO/scripts/deploy.sh): full deploy path
- [k8s/hpa.yaml](/Users/nguyenhaidang/Workspace/EKS_YOLO/k8s/hpa.yaml): autoscaling thresholds
- [k8s/deployment.yaml](/Users/nguyenhaidang/Workspace/EKS_YOLO/k8s/deployment.yaml): pod spec and resource requests
- [main.py](/Users/nguyenhaidang/Workspace/EKS_YOLO/main.py): app endpoints and runtime behavior

## Standard Commands

### Check cluster and workload state

```bash
kubectl get nodes -o wide
kubectl get pods -n yolo-inference -o wide
kubectl get hpa yolo-hpa -n yolo-inference
kubectl get svc yolo-service -n yolo-inference
kubectl get pods -n kube-system | grep -E 'metrics-server|efs|cluster-autoscaler'
```

### Get service endpoint

```bash
kubectl get svc yolo-service -n yolo-inference -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
```

### Check rollout status

```bash
kubectl rollout status deployment/yolo-inference -n yolo-inference --timeout=10m
```

## Deployment Lifecycle

### First deployment

```bash
RENDER_DIR=$(mktemp -d)
./scripts/render-manifests.sh "$RENDER_DIR"
eksctl create cluster -f "$RENDER_DIR/cluster-config.yaml"
./scripts/deploy.sh
```

### Normal update

```bash
./scripts/update.sh
```

Use this for updated image tags, `.env` changes, and normal manifest changes.

## Post-Deploy Validation

Run these checks after every deployment:

```bash
kubectl get pods -n yolo-inference
kubectl describe hpa yolo-hpa -n yolo-inference
kubectl get pvc -n yolo-inference
kubectl logs -n yolo-inference -l app=yolo-inference --tail=50
```

Application checks:

```bash
LB_URL=$(kubectl get svc yolo-service -n yolo-inference -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
curl "http://$LB_URL/health"
curl -X POST -F "file=@test.jpg" "http://$LB_URL/predict"
```

Success criteria:

- all workload pods reach `Running` and `Ready`
- HPA reports current metrics
- EFS-backed PVCs are `Bound`
- `/health` returns `healthy`
- `/predict` returns a successful inference response

## Incident Triage

### Pod does not start

```bash
kubectl describe pod <pod-name> -n yolo-inference
kubectl logs <pod-name> -n yolo-inference -c model-downloader
kubectl logs <pod-name> -n yolo-inference -c yolo-inference
```

Likely causes:

- bad S3 bucket or model key
- EFS mount failure
- CPU or memory requests too large for available nodes
- image pull failure

### HPA does not scale

```bash
kubectl describe hpa yolo-hpa -n yolo-inference
kubectl get apiservice | grep metrics
kubectl get pods -n kube-system | grep metrics-server
```

Likely causes:

- metrics-server not healthy
- traffic too low to cross CPU or memory thresholds
- pod resource requests or limits do not reflect real workload behavior

### Pending pods

```bash
kubectl get pods -n yolo-inference
kubectl describe pod <pod-name> -n yolo-inference
kubectl get nodes -o wide
kubectl logs -n kube-system -l app=cluster-autoscaler --tail=100
```

Likely causes:

- autoscaler has not yet added capacity
- node groups are undersized
- scheduling constraints no longer match available instance types

## Rollback Strategy

Rollback is operational rather than release-managed.

Options:

1. revert the image or config change in source control
2. run `./scripts/update.sh` again
3. if needed, use `kubectl rollout undo deployment/yolo-inference -n yolo-inference`

Before relying on `rollout undo`, confirm the Deployment revision history exists for the change you want to back out.

## Data and Storage

Operational expectations:

- model weights are expected at `/models/best.pt`
- inference result files are written to `/output`
- output files accumulate on EFS unless an external cleanup process is added

Production recommendation:

- define a retention and cleanup policy for `/output`
- monitor EFS growth and throughput
- treat `EFS_ID` as persistent infrastructure, not an ephemeral deploy artifact

## Security Baseline

- workload uses IRSA through `yolo-sa`
- container runs as non-root
- capabilities are dropped
- still missing: auth, TLS policy, and tighter CI/CD permissions

## Hardening Backlog

High-value production improvements:

- replace ad hoc GitHub IAM user access with a role-based CI/CD pattern
- add observability: metrics, dashboards, and alerts
- pin remote addon versions and remove unbounded `latest` dependencies
- add image versioning and release-based rollback
- add lifecycle management for output artifacts
