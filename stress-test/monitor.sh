#!/bin/bash

# Monitor Auto-Scaling in Real-time
# Run this in parallel with stress test

echo "=========================================="
echo "  Monitoring YOLO EKS Auto-Scaling"
echo "=========================================="

while true; do
    clear
    echo "Time: $(date '+%Y-%m-%d %H:%M:%S')"
    echo ""

    echo "=== Pods Status ==="
    kubectl get pods -n yolo-inference -o wide --no-headers | \
        awk '{printf "%-40s %-10s %-15s %-40s\n", $1, $3, $6, $7}'

    echo ""
    echo "=== Pods per Node ==="
    kubectl get pods -n yolo-inference -o wide --no-headers | \
        awk '{print $7}' | sort | uniq -c | \
        awk '{printf "  %s: %d pods\n", $2, $1}'

    echo ""
    echo "=== HPA Status ==="
    kubectl get hpa yolo-hpa -n yolo-inference --no-headers | \
        awk '{printf "  Current: %s/%s replicas\n  CPU: %s\n  Memory: %s\n", $7, $8, $3, $5}'

    echo ""
    echo "=== Nodes Status ==="
    kubectl get nodes --no-headers | \
        awk '{printf "%-50s %-10s %-10s\n", $1, $2, $3}'

    echo ""
    echo "=== GPU Nodes Count ==="
    GPU_NODES=$(kubectl get nodes -l node.kubernetes.io/instance-type=g4dn.xlarge --no-headers | wc -l)
    CPU_NODES=$(kubectl get nodes -l node.kubernetes.io/instance-type=t3.medium --no-headers | wc -l)
    echo "  GPU nodes (g4dn.xlarge): $GPU_NODES"
    echo "  CPU nodes (t3.medium): $CPU_NODES"

    echo ""
    echo "=== Cluster Autoscaler Logs (last 3 lines) ==="
    kubectl logs -n kube-system -l app=cluster-autoscaler --tail=3 2>/dev/null | \
        grep -E "scale|node" || echo "  No recent scaling events"

    echo ""
    echo "=========================================="
    echo "Press Ctrl+C to stop monitoring"

    sleep 5
done
