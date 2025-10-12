#!/bin/bash

# Update Deployment Script
# Run this after pulling new code from GitHub

set -e

echo "=========================================="
echo "  Updating YOLO EKS Deployment"
echo "=========================================="

cd ~/desktop/Auto_Scale_GPU_EKS

# Pull latest code
echo ""
echo "=== Step 1: Pulling latest code from GitHub ==="
git pull origin main

# Apply updated manifests
echo ""
echo "=== Step 2: Applying updated Kubernetes manifests ==="

echo "Applying deployment.yaml (GPU sharing config)..."
kubectl apply -f k8s/deployment.yaml

echo "Applying cluster-autoscaler.yaml..."
kubectl apply -f k8s/cluster-autoscaler.yaml

echo "Applying configmap.yaml..."
kubectl apply -f k8s/configmap.yaml

# Restart deployment
echo ""
echo "=== Step 3: Restarting deployment ==="
kubectl rollout restart deployment/yolo-inference -n yolo-inference

# Wait for rollout
echo ""
echo "=== Step 4: Waiting for rollout to complete ==="
kubectl rollout status deployment/yolo-inference -n yolo-inference --timeout=10m

# Show results
echo ""
echo "=== Step 5: Deployment Status ==="
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
echo "To check GPU sharing, run:"
echo "  kubectl describe nodes | grep -A 10 'nvidia.com/gpu'"
echo ""
echo "To scale deployment:"
echo "  kubectl scale deployment yolo-inference -n yolo-inference --replicas=6"
echo ""
