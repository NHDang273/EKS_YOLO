# Stress Test

Test auto-scaling của YOLO API.

## Cách dùng

### 1. Tự động lấy LoadBalancer URL:
```bash
python test.py --images test-images --concurrent 10 --total 100
```

### 2. Hoặc chỉ định URL thủ công:
```bash
python test.py --url http://abc123.elb.amazonaws.com --images test-images --concurrent 10 --total 100
```

### 3. Test theo thời gian:
```bash
# Test trong 5 phút
python test.py --images test-images --concurrent 10 --duration 300
```

## Tham số

- `--url`: API URL (không cần nếu kubectl đã config)
- `--images`: Thư mục chứa ảnh test (mặc định: test-images)
- `--concurrent`: Số request đồng thời (mặc định: 5)
- `--total`: Tổng số request
- `--duration`: Thời gian test (giây)

## Lấy LoadBalancer URL thủ công

```bash
# Hostname
kubectl get svc yolo-service -n yolo-inference -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'

# Hoặc IP
kubectl get svc yolo-service -n yolo-inference -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
```

## Ví dụ

```bash
# Test nhanh
python test.py --concurrent 5 --total 50

# Test stress cao
python test.py --concurrent 20 --total 500

# Test liên tục 10 phút
python test.py --concurrent 10 --duration 600
```
Bước 1: Test nhẹ trước (5 concurrent, 20 requests)
```
cd stress-test

python test.py --url http://a11fb22be55d1404dbcb55968c2fe89c-4358812860332e95.elb.ap-southeast-1.amazonaws.com --concurrent 5 --total 20
```

Bước 2: Test stress để trigger auto-scaling
```
# Tăng mạnh: 20 concurrent requests trong 3 phút
python test.py --url http://a11fb22be55d1404dbcb55968c2fe89c-4358812860332e95.elb.ap-southeast-1.amazonaws.com --concurrent 20 --duration 180
```