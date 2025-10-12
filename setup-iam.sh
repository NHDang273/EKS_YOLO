#!/bin/bash

# Setup IAM permissions for EKS cluster
# Run this ONCE before deploying

set -e

echo "=========================================="
echo "  Setting up IAM for EKS"
echo "=========================================="

# Load environment
cd ~/desktop/Auto_Scale_GPU_EKS
source ./setup-env.sh

echo "Cluster: $CLUSTER_NAME"
echo "Region: $AWS_REGION"
echo "Account: $AWS_ACCOUNT_ID"

# Check if OIDC provider exists
echo ""
echo "=== Checking OIDC Provider ==="
OIDC_PROVIDER=$(aws eks describe-cluster --name ${CLUSTER_NAME} --region ${AWS_REGION} --query "cluster.identity.oidc.issuer" --output text 2>/dev/null || echo "")

if [ -z "$OIDC_PROVIDER" ]; then
    echo "ERROR: Cluster not found or no OIDC provider"
    exit 1
fi

OIDC_PROVIDER_URL=$(echo $OIDC_PROVIDER | sed -e "s/^https:\/\///")
OIDC_ID=$(echo $OIDC_PROVIDER_URL | rev | cut -d'/' -f1 | rev)

echo "OIDC Provider: $OIDC_PROVIDER_URL"
echo "OIDC ID: $OIDC_ID"

# Check if OIDC provider is associated with IAM
OIDC_EXISTS=$(aws iam list-open-id-connect-providers | grep $OIDC_ID | wc -l)

if [ "$OIDC_EXISTS" -eq "0" ]; then
    echo "Creating IAM OIDC identity provider..."
    eksctl utils associate-iam-oidc-provider \
        --cluster $CLUSTER_NAME \
        --region $AWS_REGION \
        --approve
    echo "✓ OIDC provider created"
else
    echo "✓ OIDC provider already exists"
fi

echo ""
echo "=== Creating IAM Policy and Role ==="

# Update IAM policy with actual bucket name
sed -i "s/yolo-models-bucket/${S3_WEIGHTS_BUCKET}/g" k8s/iam-policy.json

# Create policy
POLICY_ARN=$(aws iam create-policy \
    --policy-name yolo-s3-read-policy \
    --policy-document file://k8s/iam-policy.json \
    --query 'Policy.Arn' \
    --output text 2>/dev/null || aws iam list-policies --query "Policies[?PolicyName=='yolo-s3-read-policy'].Arn" --output text)

echo "Policy ARN: $POLICY_ARN"

# Update trust policy
cp k8s/iam-trust-policy.json k8s/iam-trust-policy-temp.json
sed -i "s/ACCOUNT_ID/${AWS_ACCOUNT_ID}/g" k8s/iam-trust-policy-temp.json
sed -i "s/OIDC_ID/${OIDC_ID}/g" k8s/iam-trust-policy-temp.json
sed -i "s/REGION/${AWS_REGION}/g" k8s/iam-trust-policy-temp.json

# Create role
ROLE_NAME="yolo-eks-pod-role"
aws iam create-role \
    --role-name $ROLE_NAME \
    --assume-role-policy-document file://k8s/iam-trust-policy-temp.json 2>/dev/null || echo "Role already exists"

# Attach policy
aws iam attach-role-policy \
    --role-name $ROLE_NAME \
    --policy-arn $POLICY_ARN 2>/dev/null || echo "Policy already attached"

rm k8s/iam-trust-policy-temp.json

echo "✓ IAM Role: $ROLE_NAME"
echo "✓ Role ARN: arn:aws:iam::${AWS_ACCOUNT_ID}:role/${ROLE_NAME}"

echo ""
echo "=========================================="
echo "  ✓ IAM Setup Complete!"
echo "=========================================="
echo ""
echo "Role ARN to use in ServiceAccount:"
echo "  arn:aws:iam::${AWS_ACCOUNT_ID}:role/${ROLE_NAME}"
echo ""
echo "Next: Run ./deploy.sh to deploy infrastructure"
