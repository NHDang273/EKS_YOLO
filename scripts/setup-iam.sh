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

# Check if cluster exists
echo ""
echo "=== Checking EKS Cluster ==="
CLUSTER_STATUS=$(aws eks describe-cluster --name ${CLUSTER_NAME} --region ${AWS_REGION} --query 'cluster.status' --output text 2>/dev/null || echo "NOT_FOUND")

if [ "$CLUSTER_STATUS" == "NOT_FOUND" ]; then
    echo "ERROR: Cluster '${CLUSTER_NAME}' not found in region ${AWS_REGION}"
    echo ""
    echo "Please check:"
    echo "  1. Cluster name is correct"
    echo "  2. Region is correct"
    echo "  3. AWS credentials are valid"
    echo ""
    echo "List clusters:"
    aws eks list-clusters --region ${AWS_REGION}
    exit 1
fi

if [ "$CLUSTER_STATUS" != "ACTIVE" ]; then
    echo "ERROR: Cluster status is ${CLUSTER_STATUS}, expected ACTIVE"
    exit 1
fi

echo "✓ Cluster is ACTIVE"

# Get OIDC provider
echo ""
echo "=== Setting up OIDC Provider ==="
OIDC_PROVIDER=$(aws eks describe-cluster --name ${CLUSTER_NAME} --region ${AWS_REGION} --query "cluster.identity.oidc.issuer" --output text)
OIDC_PROVIDER_URL=$(echo $OIDC_PROVIDER | sed -e "s/^https:\/\///")
OIDC_ID=$(echo $OIDC_PROVIDER_URL | rev | cut -d'/' -f1 | rev)

echo "OIDC Provider URL: $OIDC_PROVIDER_URL"
echo "OIDC ID: $OIDC_ID"

# Check if OIDC provider is associated with IAM
OIDC_EXISTS=$(aws iam list-open-id-connect-providers --region ${AWS_REGION} 2>/dev/null | grep -c $OIDC_ID || echo "0")

if [ "$OIDC_EXISTS" == "0" ]; then
    echo "Creating IAM OIDC identity provider..."

    # Check if eksctl is available
    if command -v eksctl &> /dev/null; then
        eksctl utils associate-iam-oidc-provider \
            --cluster $CLUSTER_NAME \
            --region $AWS_REGION \
            --approve
    else
        # Use AWS CLI directly
        echo "eksctl not found, using AWS CLI..."
        THUMBPRINT=$(echo | openssl s_client -servername oidc.eks.${AWS_REGION}.amazonaws.com -showcerts -connect oidc.eks.${AWS_REGION}.amazonaws.com:443 2>&- | openssl x509 -fingerprint -sha1 -noout | cut -d'=' -f2 | tr -d ':' | tr '[:upper:]' '[:lower:]')

        aws iam create-open-id-connect-provider \
            --url $OIDC_PROVIDER \
            --client-id-list sts.amazonaws.com \
            --thumbprint-list $THUMBPRINT \
            --region ${AWS_REGION}
    fi

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
