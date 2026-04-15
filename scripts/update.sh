#!/bin/bash

set -euo pipefail

echo "=========================================="
echo "  Updating YOLO EKS Deployment"
echo "=========================================="

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "${SCRIPT_DIR}/.." && pwd)
cd "${REPO_ROOT}"
YOLO_ENV_SILENT=1 source "${SCRIPT_DIR}/setup-env.sh"

echo ""
echo "=== Step 1: Rendering updated manifests ==="
RENDER_DIR=$(mktemp -d)
trap 'rm -rf "${RENDER_DIR}"' EXIT
"${SCRIPT_DIR}/render-manifests.sh" "${RENDER_DIR}"

echo "Applying deployment.yaml..."
kubectl apply -f "${RENDER_DIR}/configmap.yaml"
kubectl apply -f "${RENDER_DIR}/deployment.yaml"

echo "Applying cluster-autoscaler.yaml..."
kubectl apply -f "${RENDER_DIR}/cluster-autoscaler.yaml"

# Restart deployment
echo ""
echo "=== Step 2: Restarting deployment ==="
kubectl rollout restart deployment/yolo-inference -n yolo-inference

# Wait for rollout
echo ""
echo "=== Step 3: Waiting for rollout to complete ==="
kubectl rollout status deployment/yolo-inference -n yolo-inference --timeout=10m

# Show results
echo ""
echo "=== Step 4: Deployment Status ==="
echo ""
echo "Pods distribution across nodes:"
kubectl get pods -n yolo-inference -o wide

echo ""
echo "Nodes status:"
kubectl get nodes -o wide

echo ""
echo "Cluster Autoscaler status:"
kubectl get pods -n kube-system -l app=cluster-autoscaler

echo ""
echo "=========================================="
echo "  ✓ Update Complete!"
echo "=========================================="
echo ""
echo "To check HPA targets, run:"
echo "  kubectl describe hpa yolo-hpa -n yolo-inference"
echo ""
echo "To scale deployment manually:"
echo "  kubectl scale deployment yolo-inference -n yolo-inference --replicas=6"
echo ""
