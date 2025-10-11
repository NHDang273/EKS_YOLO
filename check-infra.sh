#!/bin/bash

# Check Infrastructure Status Script
# Verifies all required AWS resources for YOLO EKS deployment

set -e

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}=== Checking Infrastructure Status ===${NC}\n"

# Check environment variables
echo -e "${YELLOW}Environment Variables:${NC}"
if [ -z "$AWS_REGION" ]; then
    echo -e "${RED}✗ AWS_REGION not set${NC}"
    exit 1
else
    echo -e "${GREEN}✓ AWS_REGION: ${AWS_REGION}${NC}"
fi

if [ -z "$CLUSTER_NAME" ]; then
    echo -e "${RED}✗ CLUSTER_NAME not set${NC}"
    exit 1
else
    echo -e "${GREEN}✓ CLUSTER_NAME: ${CLUSTER_NAME}${NC}"
fi

if [ -z "$AWS_ACCOUNT_ID" ]; then
    AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
fi
echo -e "${GREEN}✓ AWS_ACCOUNT_ID: ${AWS_ACCOUNT_ID}${NC}"

if [ -z "$ECR_REPO" ]; then
    echo -e "${RED}✗ ECR_REPO not set${NC}"
    exit 1
else
    echo -e "${GREEN}✓ ECR_REPO: ${ECR_REPO}${NC}"
fi

if [ -z "$S3_WEIGHTS_BUCKET" ]; then
    echo -e "${RED}✗ S3_WEIGHTS_BUCKET not set${NC}"
    exit 1
else
    echo -e "${GREEN}✓ S3_WEIGHTS_BUCKET: ${S3_WEIGHTS_BUCKET}${NC}"
fi

if [ -z "$S3_OUTPUT_BUCKET" ]; then
    echo -e "${YELLOW}! S3_OUTPUT_BUCKET not set (optional)${NC}"
else
    echo -e "${GREEN}✓ S3_OUTPUT_BUCKET: ${S3_OUTPUT_BUCKET}${NC}"
fi

# Check EKS Cluster
echo -e "\n${YELLOW}EKS Cluster:${NC}"
if aws eks describe-cluster --name ${CLUSTER_NAME} --region ${AWS_REGION} >/dev/null 2>&1; then
    CLUSTER_STATUS=$(aws eks describe-cluster --name ${CLUSTER_NAME} --region ${AWS_REGION} --query 'cluster.status' --output text)
    CLUSTER_ENDPOINT=$(aws eks describe-cluster --name ${CLUSTER_NAME} --region ${AWS_REGION} --query 'cluster.endpoint' --output text)
    echo -e "${GREEN}✓ Cluster exists: ${CLUSTER_NAME}${NC}"
    echo -e "  Status: ${CLUSTER_STATUS}"
    echo -e "  Endpoint: ${CLUSTER_ENDPOINT}"

    # Check node groups
    NODE_GROUPS=$(aws eks list-nodegroups --cluster-name ${CLUSTER_NAME} --region ${AWS_REGION} --query 'nodegroups' --output text)
    if [ ! -z "$NODE_GROUPS" ]; then
        echo -e "${GREEN}✓ Node groups: ${NODE_GROUPS}${NC}"
    else
        echo -e "${RED}✗ No node groups found${NC}"
    fi
else
    echo -e "${RED}✗ Cluster not found: ${CLUSTER_NAME}${NC}"
fi

# Check ECR Repository
echo -e "\n${YELLOW}ECR Repository:${NC}"
if aws ecr describe-repositories --repository-names ${ECR_REPO} --region ${AWS_REGION} >/dev/null 2>&1; then
    ECR_URI="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPO}"
    echo -e "${GREEN}✓ Repository exists: ${ECR_REPO}${NC}"
    echo -e "  URI: ${ECR_URI}"

    # Check images
    IMAGE_COUNT=$(aws ecr list-images --repository-name ${ECR_REPO} --region ${AWS_REGION} --query 'length(imageIds)' --output text)
    echo -e "  Images: ${IMAGE_COUNT}"
else
    echo -e "${RED}✗ Repository not found: ${ECR_REPO}${NC}"
fi

# Check S3 Buckets
echo -e "\n${YELLOW}S3 Buckets:${NC}"
if aws s3 ls s3://${S3_WEIGHTS_BUCKET} --region ${AWS_REGION} >/dev/null 2>&1; then
    echo -e "${GREEN}✓ Weights bucket exists: ${S3_WEIGHTS_BUCKET}${NC}"

    # Check for models
    MODEL_COUNT=$(aws s3 ls s3://${S3_WEIGHTS_BUCKET}/models/ --region ${AWS_REGION} 2>/dev/null | wc -l)
    echo -e "  Models in bucket: ${MODEL_COUNT}"
else
    echo -e "${RED}✗ Weights bucket not found: ${S3_WEIGHTS_BUCKET}${NC}"
fi

if [ ! -z "$S3_OUTPUT_BUCKET" ]; then
    if aws s3 ls s3://${S3_OUTPUT_BUCKET} --region ${AWS_REGION} >/dev/null 2>&1; then
        echo -e "${GREEN}✓ Output bucket exists: ${S3_OUTPUT_BUCKET}${NC}"
    else
        echo -e "${RED}✗ Output bucket not found: ${S3_OUTPUT_BUCKET}${NC}"
    fi
fi

# Check EFS
echo -e "\n${YELLOW}EFS File Systems:${NC}"
EFS_ID=$(aws efs describe-file-systems --region ${AWS_REGION} --query "FileSystems[?Tags[?Key=='Name' && Value=='yolo-efs']].FileSystemId" --output text 2>/dev/null)
if [ ! -z "$EFS_ID" ]; then
    EFS_STATE=$(aws efs describe-file-systems --file-system-id ${EFS_ID} --region ${AWS_REGION} --query 'FileSystems[0].LifeCycleState' --output text)
    echo -e "${GREEN}✓ EFS exists: ${EFS_ID}${NC}"
    echo -e "  State: ${EFS_STATE}"

    # Check mount targets
    MOUNT_COUNT=$(aws efs describe-mount-targets --file-system-id ${EFS_ID} --region ${AWS_REGION} --query 'length(MountTargets)' --output text)
    echo -e "  Mount targets: ${MOUNT_COUNT}"
else
    echo -e "${YELLOW}! No EFS found with tag 'yolo-efs'${NC}"
fi

# Check Kubernetes connection
echo -e "\n${YELLOW}Kubernetes Connection:${NC}"
if kubectl cluster-info >/dev/null 2>&1; then
    echo -e "${GREEN}✓ kubectl can connect to cluster${NC}"
    CURRENT_CONTEXT=$(kubectl config current-context)
    echo -e "  Context: ${CURRENT_CONTEXT}"

    # Check namespace
    if kubectl get namespace yolo-inference >/dev/null 2>&1; then
        echo -e "${GREEN}✓ Namespace 'yolo-inference' exists${NC}"

        # Check pods
        POD_COUNT=$(kubectl get pods -n yolo-inference --no-headers 2>/dev/null | wc -l)
        RUNNING_PODS=$(kubectl get pods -n yolo-inference --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l)
        echo -e "  Pods: ${RUNNING_PODS}/${POD_COUNT} running"

        # Check service
        if kubectl get svc yolo-service -n yolo-inference >/dev/null 2>&1; then
            LB_URL=$(kubectl get svc yolo-service -n yolo-inference -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null)
            echo -e "${GREEN}✓ Service 'yolo-service' exists${NC}"
            if [ ! -z "$LB_URL" ]; then
                echo -e "  LoadBalancer: ${LB_URL}"
            else
                echo -e "${YELLOW}  LoadBalancer: pending...${NC}"
            fi
        else
            echo -e "${YELLOW}! Service 'yolo-service' not found${NC}"
        fi
    else
        echo -e "${YELLOW}! Namespace 'yolo-inference' not found${NC}"
    fi
else
    echo -e "${RED}✗ Cannot connect to Kubernetes cluster${NC}"
    echo -e "  Run: aws eks update-kubeconfig --name ${CLUSTER_NAME} --region ${AWS_REGION}"
fi

# Check required Kubernetes addons
echo -e "\n${YELLOW}Kubernetes Addons:${NC}"
if kubectl get pods -n kube-system -l app=efs-csi-controller >/dev/null 2>&1; then
    echo -e "${GREEN}✓ EFS CSI Driver installed${NC}"
else
    echo -e "${RED}✗ EFS CSI Driver not found${NC}"
fi

if kubectl get pods -n kube-system -l name=nvidia-device-plugin-ds >/dev/null 2>&1; then
    echo -e "${GREEN}✓ NVIDIA Device Plugin installed${NC}"
else
    echo -e "${YELLOW}! NVIDIA Device Plugin not found${NC}"
fi

if kubectl get deployment metrics-server -n kube-system >/dev/null 2>&1; then
    echo -e "${GREEN}✓ Metrics Server installed${NC}"
else
    echo -e "${YELLOW}! Metrics Server not found${NC}"
fi

# Summary
echo -e "\n${GREEN}=== Summary ===${NC}"
echo -e "Export these for GitHub Secrets:"
echo -e "${GREEN}AWS_REGION:${NC} ${AWS_REGION}"
echo -e "${GREEN}AWS_ACCOUNT_ID:${NC} ${AWS_ACCOUNT_ID}"
echo -e "${GREEN}ECR_REPOSITORY:${NC} ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPO}"
echo -e "${GREEN}S3_MODEL_BUCKET:${NC} ${S3_WEIGHTS_BUCKET}"
echo -e "${GREEN}EKS_CLUSTER_NAME:${NC} ${CLUSTER_NAME}"

echo -e "\n${YELLOW}Check complete!${NC}"
