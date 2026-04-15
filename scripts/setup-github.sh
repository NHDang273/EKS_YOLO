#!/bin/bash

# Setup GitHub Actions access to EKS cluster
# Run this after cluster is created

set -e

echo "=========================================="
echo "  Setup GitHub Actions Access to EKS"
echo "=========================================="

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "${SCRIPT_DIR}/.." && pwd)
cd "${REPO_ROOT}"
YOLO_ENV_SILENT=1 source "${SCRIPT_DIR}/setup-env.sh"

echo "Cluster: $CLUSTER_NAME"
echo "Region: $AWS_REGION"

# Update kubeconfig
echo ""
echo "=== Updating kubeconfig ==="
aws eks update-kubeconfig --name $CLUSTER_NAME --region $AWS_REGION

# Get current aws-auth
echo ""
echo "=== Getting current aws-auth ConfigMap ==="
kubectl get configmap aws-auth -n kube-system -o yaml > /tmp/aws-auth-backup.yaml
echo "✓ Backup saved to /tmp/aws-auth-backup.yaml"

# Check if github-actions-user exists
echo ""
echo "=== Checking GitHub Actions IAM user ==="
GITHUB_USER_EXISTS=$(aws iam get-user --user-name github-actions-user 2>/dev/null | wc -l)

if [ "$GITHUB_USER_EXISTS" -eq "0" ]; then
    echo "⚠️  IAM user 'github-actions-user' not found"
    echo ""
    echo "Create user with:"
    echo "  aws iam create-user --user-name github-actions-user"
    echo "  aws iam attach-user-policy --user-name github-actions-user --policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPowerUser"
    echo "  aws iam attach-user-policy --user-name github-actions-user --policy-arn arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess"
    echo "  aws iam create-access-key --user-name github-actions-user"
    echo ""
    read -p "Do you want to create it now? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        aws iam create-user --user-name github-actions-user
        aws iam attach-user-policy --user-name github-actions-user --policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPowerUser
        aws iam attach-user-policy --user-name github-actions-user --policy-arn arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess

        echo ""
        echo "Creating access key..."
        aws iam create-access-key --user-name github-actions-user
        echo ""
        echo "⚠️  Save these credentials to GitHub Secrets!"
        echo ""
    fi
fi

# Add user to aws-auth using eksctl
echo ""
echo "=== Adding GitHub Actions user to aws-auth ==="

eksctl create iamidentitymapping \
  --cluster $CLUSTER_NAME \
  --region $AWS_REGION \
  --arn arn:aws:iam::${AWS_ACCOUNT_ID}:user/github-actions-user \
  --username github-actions \
  --group system:masters \
  --no-duplicate-arns 2>/dev/null || echo "Mapping may already exist"

# Verify
echo ""
echo "=== Verifying aws-auth ConfigMap ==="
kubectl get configmap aws-auth -n kube-system -o yaml

echo ""
echo "=========================================="
echo "  ✓ GitHub Actions Access Setup Complete!"
echo "=========================================="
echo ""
echo "GitHub Secrets should have:"
echo "  AWS_ACCESS_KEY_ID: <from access key above>"
echo "  AWS_SECRET_ACCESS_KEY: <from access key above>"
echo "  AWS_REGION: $AWS_REGION"
echo "  ECR_REPOSITORY: $ECR_REPOSITORY"
echo "  EKS_CLUSTER_NAME: $CLUSTER_NAME"
echo "  S3_MODEL_BUCKET: $S3_BUCKET"
echo ""
