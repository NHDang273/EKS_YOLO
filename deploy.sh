#!/bin/bash

# YOLO EKS Deployment Script
# This script deploys infrastructure to EKS (without building Docker image)
# Docker image will be built by GitHub Actions

# Don't exit on error - handle errors gracefully
set +e

echo "=========================================="
echo "  YOLO EKS Infrastructure Deployment"
echo "=========================================="

# Load environment
cd ~/desktop/Auto_Scale_GPU_EKS
source ./setup-env.sh

echo ""
echo "Environment:"
echo "  AWS Region: $AWS_REGION"
echo "  Cluster: $CLUSTER_NAME"
echo "  Account ID: $AWS_ACCOUNT_ID"
echo "  ECR: $ECR_URL"
echo "  S3 Bucket: $S3_WEIGHTS_BUCKET"

# Verify cluster
echo ""
echo "=== Step 1: Verifying EKS Cluster ==="
kubectl get nodes || {
    echo "ERROR: kubectl not configured"
    echo "Run: aws eks update-kubeconfig --name $CLUSTER_NAME --region $AWS_REGION"
    exit 1
}

echo ""
echo "=== Step 2: Checking IAM Role for Service Account ==="

# Check if IAM role exists
ROLE_EXISTS=$(aws iam get-role --role-name yolo-eks-pod-role 2>/dev/null | wc -l)
if [ "$ROLE_EXISTS" -eq "0" ]; then
    echo "⚠️  IAM role not found. Please run ./setup-iam.sh first!"
    exit 1
else
    echo "✓ IAM Role exists: yolo-eks-pod-role"
fi

echo ""
echo "=== Step 3: Creating EFS File System ==="
VPC_ID=$(aws eks describe-cluster --name ${CLUSTER_NAME} --region ${AWS_REGION} --query 'cluster.resourcesVpcConfig.vpcId' --output text)
echo "VPC: $VPC_ID"

EFS_ID=$(aws efs create-file-system \
    --creation-token yolo-efs-$(date +%s) \
    --performance-mode generalPurpose \
    --encrypted \
    --tags Key=Name,Value=yolo-efs \
    --region ${AWS_REGION} \
    --query 'FileSystemId' \
    --output text)

echo "EFS ID: $EFS_ID"
export EFS_ID=$EFS_ID

sleep 30

CLUSTER_SG=$(aws eks describe-cluster --name ${CLUSTER_NAME} --region ${AWS_REGION} --query 'cluster.resourcesVpcConfig.clusterSecurityGroupId' --output text)
SUBNET_IDS=$(aws eks describe-cluster --name ${CLUSTER_NAME} --region ${AWS_REGION} --query 'cluster.resourcesVpcConfig.subnetIds' --output text)

echo "Creating EFS mount targets..."
for subnet in $SUBNET_IDS; do
    aws efs create-mount-target \
        --file-system-id $EFS_ID \
        --subnet-id $subnet \
        --security-groups $CLUSTER_SG \
        --region ${AWS_REGION} 2>/dev/null || true
done
echo "✓ EFS created"

echo ""
echo "=== Step 4: Installing Kubernetes Addons ==="

helm repo add aws-efs-csi-driver https://kubernetes-sigs.github.io/aws-efs-csi-driver/ 2>/dev/null || true
helm repo update

echo "Installing EFS CSI Driver..."
helm install aws-efs-csi-driver aws-efs-csi-driver/aws-efs-csi-driver \
    --namespace kube-system \
    --set image.repository=602401143452.dkr.ecr.${AWS_REGION}.amazonaws.com/eks/aws-efs-csi-driver

echo "Installing NVIDIA Device Plugin..."
kubectl apply -f https://raw.githubusercontent.com/NVIDIA/k8s-device-plugin/v0.14.0/nvidia-device-plugin.yml

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
echo "=== Step 5: Updating Kubernetes Manifests ==="

sed -i "s/fs-XXXXXXXXX/${EFS_ID}/g" k8s/storageclass.yaml
sed -i "s/ACCOUNT_ID/${AWS_ACCOUNT_ID}/g" k8s/serviceaccount.yaml
sed -i "s|ACCOUNT_ID.dkr.ecr.REGION.amazonaws.com|${ECR_URL}|g" k8s/deployment.yaml
sed -i "s/yolo-models-bucket/${S3_WEIGHTS_BUCKET}/g" k8s/configmap.yaml
sed -i "s/us-west-2/${AWS_REGION}/g" k8s/configmap.yaml

echo "✓ Manifests updated"

echo ""
echo "=== Step 6: Deploying to EKS ==="

kubectl apply -f k8s/namespace.yaml
kubectl apply -f k8s/storageclass.yaml
kubectl apply -f k8s/pvc.yaml
kubectl apply -f k8s/serviceaccount.yaml
kubectl apply -f k8s/configmap.yaml
kubectl apply -f k8s/deployment.yaml
kubectl apply -f k8s/service.yaml
kubectl apply -f k8s/hpa.yaml

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