#!/bin/bash

# Setup Environment Variables
# Run this script to configure your environment for YOLO EKS deployment

export AWS_REGION=ap-southeast-1
export CLUSTER_NAME=yolo-inference-cluster
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
export ECR_REPO=ai-inference
export S3_WEIGHTS_BUCKET=s3-eks-dang
export S3_OUTPUT_BUCKET=s3-eks-dang
export ECR_URL=${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPO}

echo "=== Environment Variables ==="
echo "AWS_REGION: ${AWS_REGION}"
echo "CLUSTER_NAME: ${CLUSTER_NAME}"
echo "AWS_ACCOUNT_ID: ${AWS_ACCOUNT_ID}"
echo "ECR_REPO: ${ECR_REPO}"
echo "S3_WEIGHTS_BUCKET: ${S3_WEIGHTS_BUCKET}"
echo "S3_OUTPUT_BUCKET: ${S3_OUTPUT_BUCKET}"
echo "ECR_URL: ${ECR_URL}"

# Save to ~/.bashrc
cat >> ~/.bashrc <<EOF

# YOLO EKS Environment Variables
export AWS_REGION=ap-southeast-1
export CLUSTER_NAME=yolo-inference-cluster
export AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID}
export ECR_REPO=ai-inference
export S3_WEIGHTS_BUCKET=s3-eks-dang
export S3_OUTPUT_BUCKET=s3-eks-dang
export ECR_URL=${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPO}
EOF

echo ""
echo "✓ Environment variables saved to ~/.bashrc"
echo "Run: source ~/.bashrc"
