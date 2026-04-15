#!/bin/bash

set -euo pipefail

echo "=========================================="
echo "  YOLO EKS Infrastructure Deployment"
echo "=========================================="

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "${SCRIPT_DIR}/.." && pwd)
cd "${REPO_ROOT}"
YOLO_ENV_SILENT=1 source "${SCRIPT_DIR}/setup-env.sh"

echo ""
echo "Environment:"
echo "  AWS Region: $AWS_REGION"
echo "  Cluster: $CLUSTER_NAME"
echo "  Account ID: $AWS_ACCOUNT_ID"
echo "  ECR: $ECR_URL"
echo "  S3 Bucket: $S3_BUCKET"

# Verify cluster
echo ""
echo "=== Step 1: Verifying EKS Cluster ==="
kubectl get nodes || {
    echo "ERROR: kubectl not configured"
    echo "Run: aws eks update-kubeconfig --name $CLUSTER_NAME --region $AWS_REGION"
    exit 1
}

echo ""
echo "=== Step 2: Verifying IRSA-managed Service Account ==="

kubectl get serviceaccount yolo-sa -n yolo-inference >/dev/null 2>&1 || {
    echo "ERROR: ServiceAccount yolo-sa not found in namespace yolo-inference"
    echo "Create the cluster using the rendered eksctl config first."
    exit 1
}

echo "✓ ServiceAccount exists: yolo-sa"

echo ""
echo "=== Step 3: Creating EFS File System ==="
if [ -n "${EFS_ID:-}" ]; then
    echo "Using existing EFS: ${EFS_ID}"
else
    VPC_ID=$(aws eks describe-cluster --name "${CLUSTER_NAME}" --region "${AWS_REGION}" --query 'cluster.resourcesVpcConfig.vpcId' --output text)
    echo "VPC: $VPC_ID"

    EFS_ID=$(aws efs create-file-system \
        --creation-token "yolo-efs-$(date +%s)" \
        --performance-mode generalPurpose \
        --encrypted \
        --tags Key=Name,Value=yolo-efs \
        --region "${AWS_REGION}" \
        --query 'FileSystemId' \
        --output text)
    export EFS_ID

    echo "Created EFS: ${EFS_ID}"
    echo "Persist this value in .env as EFS_ID to reuse the same file system on later deploys."

    sleep 30

    CLUSTER_SG=$(aws eks describe-cluster --name "${CLUSTER_NAME}" --region "${AWS_REGION}" --query 'cluster.resourcesVpcConfig.clusterSecurityGroupId' --output text)
    SUBNET_IDS=$(aws eks describe-cluster --name "${CLUSTER_NAME}" --region "${AWS_REGION}" --query 'cluster.resourcesVpcConfig.subnetIds' --output text)

    echo "Creating EFS mount targets..."
    for subnet in $SUBNET_IDS; do
        aws efs create-mount-target \
            --file-system-id "${EFS_ID}" \
            --subnet-id "${subnet}" \
            --security-groups "${CLUSTER_SG}" \
            --region "${AWS_REGION}" 2>/dev/null || true
    done
    echo "✓ EFS created"
fi

echo ""
echo "=== Step 4: Installing Kubernetes Addons ==="

helm repo add aws-efs-csi-driver https://kubernetes-sigs.github.io/aws-efs-csi-driver/ 2>/dev/null || true
helm repo update

echo "Installing EFS CSI Driver..."
helm upgrade --install aws-efs-csi-driver aws-efs-csi-driver/aws-efs-csi-driver \
    --namespace kube-system \
    --create-namespace \
    --set image.repository=602401143452.dkr.ecr.${AWS_REGION}.amazonaws.com/eks/aws-efs-csi-driver

echo "Installing Metrics Server..."
# Remove old Metrics Server if exists to avoid conflicts
echo "Checking for existing Metrics Server..."
if kubectl get deployment metrics-server -n kube-system &>/dev/null; then
    echo "Removing old Metrics Server deployment..."
    kubectl delete deployment metrics-server -n kube-system
    kubectl delete apiservice v1beta1.metrics.k8s.io 2>/dev/null || true
    sleep 5
fi

kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

sleep 20
echo "✓ Addons installed"

echo ""
echo "=== Step 5: Rendering Kubernetes Manifests ==="
RENDER_DIR=$(mktemp -d)
trap 'rm -rf "${RENDER_DIR}"' EXIT
export EFS_ID
"${SCRIPT_DIR}/render-manifests.sh" "${RENDER_DIR}"
echo "✓ Rendered manifests: ${RENDER_DIR}"

echo ""
echo "=== Step 6: Deploying to EKS ==="

kubectl apply -f k8s/namespace.yaml
kubectl apply -f "${RENDER_DIR}/storageclass.yaml"
kubectl apply -f k8s/pvc.yaml
kubectl apply -f "${RENDER_DIR}/configmap.yaml"
kubectl apply -f "${RENDER_DIR}/deployment.yaml"
kubectl apply -f k8s/service.yaml
kubectl apply -f k8s/hpa.yaml
kubectl apply -f "${RENDER_DIR}/cluster-autoscaler.yaml"

echo "✓ Infrastructure deployed"

echo ""
echo "=========================================="
echo "  ✓ Infrastructure Setup Complete!"
echo "=========================================="
echo ""
echo "NEXT STEPS:"
echo ""
echo "1. Trigger GitHub Actions to build & deploy:"
echo "   - Go to: https://github.com/YOUR_USERNAME/YOUR_REPO/actions"
echo "   - Click 'Build and Deploy to EKS'"
echo "   - Click 'Run workflow' → Run on 'main'"
echo ""
echo "2. Monitor deployment:"
echo "   kubectl get pods -n yolo-inference -w"
echo ""
echo "3. Get LoadBalancer URL:"
echo "   kubectl get svc yolo-service -n yolo-inference"
echo ""
echo "4. Test API:"
echo "   LB_URL=\$(kubectl get svc yolo-service -n yolo-inference -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')"
echo "   curl http://\$LB_URL/health | jq '.'"
echo ""
echo "=========================================="
