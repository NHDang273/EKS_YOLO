#!/bin/bash

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "${SCRIPT_DIR}/.." && pwd)
ENV_FILE="${REPO_ROOT}/.env"

if [ ! -f "${ENV_FILE}" ]; then
    echo "ERROR: .env file not found at ${ENV_FILE}"
    exit 1
fi

set -a
source "${ENV_FILE}"
set +a

required_vars=(
    AWS_REGION
    CLUSTER_NAME
    ECR_REPOSITORY
    S3_BUCKET
    S3_MODEL_KEY
    MODEL_PATH
    OUTPUT_PATH
    INFERENCE_DEVICE
    INFERENCE_NODE_INSTANCE_TYPE
    INFERENCE_NODE_MIN_SIZE
    INFERENCE_NODE_MAX_SIZE
    SYSTEM_NODE_INSTANCE_TYPE
    SYSTEM_NODE_MIN_SIZE
    SYSTEM_NODE_MAX_SIZE
    DEPLOYMENT_REPLICAS
    CPU_REQUEST
    CPU_LIMIT
    MEMORY_REQUEST
    MEMORY_LIMIT
)

for var_name in "${required_vars[@]}"; do
    if [ -z "${!var_name:-}" ]; then
        echo "ERROR: ${var_name} is not set in ${ENV_FILE}"
        exit 1
    fi
done

if [ -z "${AWS_ACCOUNT_ID:-}" ]; then
    AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    export AWS_ACCOUNT_ID
fi

if [ -z "${ECR_URL:-}" ]; then
    ECR_URL="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPOSITORY}"
    export ECR_URL
fi

if [ "${YOLO_ENV_SILENT:-0}" != "1" ]; then
    echo "Environment loaded from ${ENV_FILE}"
    echo "AWS_REGION=${AWS_REGION}"
    echo "CLUSTER_NAME=${CLUSTER_NAME}"
    echo "AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID}"
    echo "ECR_REPOSITORY=${ECR_REPOSITORY}"
    echo "ECR_URL=${ECR_URL}"
    echo "S3_BUCKET=${S3_BUCKET}"
fi
