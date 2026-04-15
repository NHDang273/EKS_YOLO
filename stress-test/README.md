# Stress Test Guide

Use this directory to validate request distribution, HPA behavior, and basic service stability.

## Before You Start

Run from this directory:

```bash
cd stress-test
```

Confirm the service is reachable:

```bash
kubectl get svc yolo-service -n yolo-inference
```

## Basic Usage

### Auto-discover the LoadBalancer URL

```bash
python test.py --images test-images --concurrent 10 --total 100
```

### Provide the URL manually

```bash
python test.py --url http://abc123.elb.amazonaws.com --images test-images --concurrent 10 --total 100
```

### Run for a fixed duration

```bash
python test.py --images test-images --concurrent 10 --duration 300
```

## Arguments

- `--url`: API base URL. Optional if `kubectl` points at the correct cluster.
- `--images`: directory containing test images. Default is `test-images`.
- `--concurrent`: number of concurrent requests. Default is `5`.
- `--total`: total request count.
- `--duration`: test duration in seconds.

## Recommended Test Sequence

### 1. Smoke test

```bash
python test.py --concurrent 5 --total 20
```

Expected outcome:

- requests succeed consistently
- response payloads contain pod names
- no pod restarts occur

### 2. Distribution test

```bash
python test.py --concurrent 10 --total 100
```

Expected outcome:

- requests are spread across multiple pods when replicas are available
- latency remains stable enough for the target workload

### 3. Scaling test

```bash
python test.py --concurrent 20 --duration 180
```

Expected outcome:

- HPA metrics move upward
- pod replicas increase when thresholds are crossed
- cluster autoscaler adds capacity if scheduling requires it

## Observe the System While Testing

In separate terminals:

```bash
kubectl get pods -n yolo-inference -w
kubectl get hpa yolo-hpa -n yolo-inference -w
kubectl get nodes -o wide
kubectl logs -n yolo-inference -l app=yolo-inference --tail=50
```

## Manual Service Endpoint Lookup

```bash
kubectl get svc yolo-service -n yolo-inference -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
```

## Interpreting Results

Watch for:

- failed requests or non-200 responses
- repeated pod restarts
- long cold-start delays after scale-out
- HPA stuck with no metrics
- pending pods caused by insufficient node capacity

If scaling does not happen, inspect:

```bash
kubectl describe hpa yolo-hpa -n yolo-inference
kubectl get pods -n kube-system | grep metrics-server
kubectl logs -n kube-system -l app=cluster-autoscaler --tail=100
```
