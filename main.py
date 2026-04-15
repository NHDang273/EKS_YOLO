from fastapi import FastAPI, File, UploadFile
from fastapi.responses import JSONResponse
import uvicorn
from ultralytics import YOLO
import numpy as np
from PIL import Image
import io
import os
from datetime import datetime
import json
from dotenv import load_dotenv

# Load environment variables from .env file (for local development)
load_dotenv()

# Khởi tạo FastAPI app
app = FastAPI(title="YOLO Inference API")

# Load YOLO model from environment variable or default path
MODEL_PATH = os.getenv('MODEL_PATH', '/models/best.pt')
OUTPUT_PATH = os.getenv('OUTPUT_PATH', '/output')
POD_NAME = os.getenv('POD_NAME', 'local')
INFERENCE_DEVICE = os.getenv('INFERENCE_DEVICE', 'cpu')

# Create output directory if it doesn't exist
os.makedirs(OUTPUT_PATH, exist_ok=True)

print(f"Loading YOLO model from: {MODEL_PATH}")
model = YOLO(MODEL_PATH)

# Set device from environment. Default is CPU for EKS deployment.
model.to(INFERENCE_DEVICE)
print(f"Model loaded successfully on {INFERENCE_DEVICE}. Pod: {POD_NAME}")

@app.get("/health")
async def health():
    """Health check endpoint for Kubernetes probes"""
    return {
        "status": "healthy",
        "model_path": MODEL_PATH,
        "pod_name": POD_NAME,
        "output_path": OUTPUT_PATH,
        "inference_device": INFERENCE_DEVICE
    }

@app.get("/")
async def root():
    return {
        "message": "YOLO Inference API is running",
        "pod": POD_NAME,
        "model": MODEL_PATH,
        "inference_device": INFERENCE_DEVICE
    }

@app.post("/predict")
async def predict(file: UploadFile = File(...)):
    try:
        # Đọc ảnh từ upload
        contents = await file.read()
        image = Image.open(io.BytesIO(contents))

        # Convert PIL Image to numpy array
        img_array = np.array(image)

        # Inference
        results = model(img_array)

        # Xử lý kết quả
        detections = []
        for result in results:
            boxes = result.boxes
            for box in boxes:
                detection = {
                    "class": result.names[int(box.cls[0])],
                    "confidence": float(box.conf[0]),
                    "bbox": box.xyxy[0].tolist()  # [x1, y1, x2, y2]
                }
                detections.append(detection)

        # Save result to shared EFS output folder
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S_%f")
        result_data = {
            "timestamp": timestamp,
            "pod_name": POD_NAME,
            "filename": file.filename,
            "detections": detections,
            "count": len(detections)
        }

        # Save to shared EFS volume - all pods can read this
        output_file = os.path.join(OUTPUT_PATH, f"result_{POD_NAME}_{timestamp}.json")
        with open(output_file, 'w') as f:
            json.dump(result_data, f, indent=2)

        print(f"Saved result to shared EFS: {output_file}")

        return JSONResponse(content={
            "success": True,
            "detections": detections,
            "count": len(detections),
            "pod_name": POD_NAME,
            "output_file": output_file
        })

    except Exception as e:
        return JSONResponse(
            status_code=500,
            content={
                "success": False,
                "error": str(e),
                "pod_name": POD_NAME
            }
        )

@app.get("/outputs")
async def list_outputs():
    """List all output files from shared EFS (from all pods)"""
    try:
        files = []
        if os.path.exists(OUTPUT_PATH):
            for filename in os.listdir(OUTPUT_PATH):
                if filename.endswith('.json'):
                    filepath = os.path.join(OUTPUT_PATH, filename)
                    file_stat = os.stat(filepath)
                    files.append({
                        "filename": filename,
                        "size": file_stat.st_size,
                        "modified": datetime.fromtimestamp(file_stat.st_mtime).isoformat()
                    })

        return JSONResponse(content={
            "success": True,
            "total_files": len(files),
            "files": sorted(files, key=lambda x: x['modified'], reverse=True),
            "pod_name": POD_NAME
        })
    except Exception as e:
        return JSONResponse(
            status_code=500,
            content={
                "success": False,
                "error": str(e),
                "pod_name": POD_NAME
            }
        )

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8000)
