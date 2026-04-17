# Kịch bản Demo: YOLO Inference Auto-Scaling trên AWS EKS

## Mục tiêu

Chứng minh một hệ thống AI inference production-ready có khả năng:
- Nhận diện đối tượng trong ảnh thời gian thực
- Tự động scale pods khi tải tăng (HPA)
- Tự động thêm EC2 node khi không đủ tài nguyên (Cluster Autoscaler)
- Chia sẻ model và output giữa tất cả pods qua EFS

---

## Kiến trúc tổng quan (1 phút)

```
[Client gửi ảnh]
        |
        v
  AWS Network LB          ← entry point duy nhất
        |
   ┌────┴────┐
   v         v
 Pod 1     Pod 2          ← ban đầu chỉ có 2 pods
   |         |
   └────┬────┘
        v
   EFS Shared Storage
   ├── /models/best.pt    ← model dùng chung, download 1 lần từ S3
   └── /output/           ← kết quả từ tất cả pods ghi vào đây
```

**Điểm nhấn khi giới thiệu:**
> "Toàn bộ hệ thống tự vận hành — không cần can thiệp thủ công khi tải tăng hay giảm."

---

## Cảnh 1: Hệ thống đang chạy bình thường (2 phút)

### Mở 3 terminal song song

**Terminal 1 — Trạng thái pods:**
```bash
watch -n 3 kubectl get pods -n yolo-inference -o wide
```

**Terminal 2 — Trạng thái HPA:**
```bash
watch -n 5 kubectl get hpa yolo-hpa -n yolo-inference
```

**Terminal 3 — Trạng thái nodes:**
```bash
watch -n 10 kubectl get nodes -o wide
```

### Gọi API thủ công để demo chức năng

```bash
LB_URL=$(kubectl get svc yolo-service -n yolo-inference \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

# Health check
curl http://$LB_URL/health | python3 -m json.tool
```

**Kết quả mong đợi — nói với người xem:**
```json
{
  "status": "healthy",
  "pod_name": "yolo-inference-xxx-aaa",
  "model_path": "/models/best.pt",
  "inference_device": "cpu"
}
```

> "Hệ thống đang healthy, model đã được load sẵn trên mỗi pod."

---

## Cảnh 2: Thực hiện inference (2 phút)

```bash
# Gửi 1 ảnh để xem kết quả detection
curl -X POST \
  -F "file=@stress-test/test-images/sample.jpg" \
  http://$LB_URL/predict | python3 -m json.tool
```

**Kết quả mong đợi:**
```json
{
  "success": true,
  "count": 3,
  "pod_name": "yolo-inference-xxx-aaa",
  "detections": [
    { "class": "person", "confidence": 0.91, "bbox": [120, 45, 380, 520] },
    { "class": "car",    "confidence": 0.87, "bbox": [10,  200, 150, 310] },
    { "class": "dog",    "confidence": 0.73, "bbox": [400, 300, 550, 480] }
  ]
}
```

> "Model nhận diện được 3 đối tượng. Kết quả còn được lưu vào EFS để tất cả pods đều truy cập được."

```bash
# Xem file kết quả trên EFS shared storage
curl http://$LB_URL/outputs | python3 -m json.tool
```

---

## Cảnh 3: Trigger Auto-Scaling — Đây là phần chính (5 phút)

### Bắt đầu bắn load

```bash
cd stress-test
python3 test.py \
  --url http://$LB_URL \
  --concurrent 20 \
  --duration 180
```

### Những gì người xem sẽ thấy

**Giai đoạn 1 — CPU tăng (~1 phút đầu):**
```
# Terminal 2 (HPA):
NAME       REFERENCE                     TARGETS        MINPODS   MAXPODS   REPLICAS
yolo-hpa   Deployment/yolo-inference     45%/70%        2         10        2

# CPU tăng dần...
yolo-hpa   Deployment/yolo-inference     82%/70%        2         10        2   ← vượt ngưỡng!
```

> "CPU đã vượt 70% — HPA bắt đầu quyết định scale up."

**Giai đoạn 2 — Pods mới được tạo (~2-3 phút):**
```
# Terminal 1 (Pods):
NAME                          READY   STATUS              NODE
yolo-inference-xxx-aaa        1/1     Running             ip-10-0-1-100
yolo-inference-xxx-bbb        1/1     Running             ip-10-0-2-200
yolo-inference-xxx-ccc        0/1     Pending             <none>          ← pod mới
yolo-inference-xxx-ddd        0/1     ContainerCreating   ip-10-0-1-100   ← pod mới
```

> "HPA đã tạo thêm pods. Một số đang Pending vì node chưa đủ tài nguyên."

**Giai đoạn 3 — Cluster Autoscaler thêm node mới (~3-5 phút):**
```
# Terminal 3 (Nodes):
NAME            STATUS   ROLES    INSTANCE-TYPE
ip-10-0-1-100   Ready    worker   t3.large
ip-10-0-2-200   Ready    worker   t3.large
ip-10-0-3-300   Ready    worker   t3.large    ← node mới được provision!
```

> "Cluster Autoscaler phát hiện pods đang Pending, tự động provision thêm EC2 node mới."

**Giai đoạn 4 — Hệ thống ổn định:**
```
yolo-hpa   Deployment/yolo-inference     65%/70%   2   10   6   ← 6 pods đang chạy
```

---

## Cảnh 4: Kết quả stress test (2 phút)

Stress test kết thúc, đọc kết quả:

```
==================================================
📊 RESULTS
==================================================
Total time:     180.0s
Total requests: 1840
✅ Success:     1835 (99.7%)
❌ Failed:      5
Throughput:     10.2 req/s

⏱️  Response times:
  Min: 0.45s
  Max: 3.21s
  Avg: 1.87s

🎯 Pod distribution:
  yolo-inference-xxx-aaa: 312 (17.0%)
  yolo-inference-xxx-bbb: 308 (16.8%)
  yolo-inference-xxx-ccc: 305 (16.6%)
  yolo-inference-xxx-ddd: 298 (16.2%)
  yolo-inference-xxx-eee: 310 (16.9%)
  yolo-inference-xxx-fff: 302 (16.5%)
```

**Điểm nhấn:**
> "99.7% success rate. Load được phân bổ đều — ~17% mỗi pod. Hệ thống tự xử lý hoàn toàn, không cần can thiệp."

---

## Cảnh 5: Scale down tự động (tùy chọn — nếu còn thời gian)

Sau khi stress test dừng, chờ ~5 phút:

```bash
# HPA scale down
yolo-hpa   Deployment/yolo-inference   12%/70%   2   10   3   ← giảm dần
yolo-hpa   Deployment/yolo-inference   8%/70%    2   10   2   ← về min replicas

# Node dư cũng được xóa sau ~10 phút
```

> "Khi không còn tải, hệ thống tự scale down — tiết kiệm chi phí, không cần tắt thủ công."

---

## Tổng kết cho người xem (1 phút)

| Tính năng | Giá trị |
|-----------|---------|
| YOLO inference qua REST API | Upload ảnh → nhận kết quả detection ngay |
| Shared model storage (EFS) | Download model 1 lần, tất cả pods dùng chung |
| HPA | Tự scale 2 → 10 pods theo CPU/Memory |
| Cluster Autoscaler | Tự thêm/bớt EC2 node theo nhu cầu |
| Shared output (EFS) | Kết quả từ mọi pod đều truy cập được |
| Zero downtime | Scale up/down không ảnh hưởng requests đang chạy |
