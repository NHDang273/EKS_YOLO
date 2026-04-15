#!/bin/bash

set -euo pipefail

if [ $# -ne 1 ]; then
    echo "Usage: $0 <output-dir>"
    exit 1
fi

OUTPUT_DIR=$1
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "${SCRIPT_DIR}/.." && pwd)

mkdir -p "${OUTPUT_DIR}"

if ! command -v envsubst >/dev/null 2>&1; then
    echo "ERROR: envsubst is required"
    exit 1
fi

YOLO_ENV_SILENT=1 source "${SCRIPT_DIR}/setup-env.sh"

render_template() {
    local input_file=$1
    local output_file=$2
    envsubst < "${input_file}" > "${output_file}"
}

render_template "${REPO_ROOT}/k8s/cluster-config.yaml" "${OUTPUT_DIR}/cluster-config.yaml"
render_template "${REPO_ROOT}/k8s/cluster-autoscaler.yaml" "${OUTPUT_DIR}/cluster-autoscaler.yaml"
render_template "${REPO_ROOT}/k8s/configmap.yaml" "${OUTPUT_DIR}/configmap.yaml"
render_template "${REPO_ROOT}/k8s/deployment.yaml" "${OUTPUT_DIR}/deployment.yaml"

if [ -n "${EFS_ID:-}" ]; then
    render_template "${REPO_ROOT}/k8s/storageclass.yaml" "${OUTPUT_DIR}/storageclass.yaml"
fi
