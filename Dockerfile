FROM nvidia/cuda:12.2.0-cudnn8-runtime-ubuntu22.04

ENV DEBIAN_FRONTEND=noninteractive
ENV PYTHONUNBUFFERED=1

WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y \
    python3.10 \
    python3-pip \
    libgl1-mesa-glx \
    libglib2.0-0 \
    && rm -rf /var/lib/apt/lists/*

# Copy and install Python dependencies
COPY requirements.txt .
RUN pip3 install --no-cache-dir -r requirements.txt

# Copy application code
COPY main.py .

# Create directories for EFS mount points and set permissions
# /models will be mounted from EFS (read-only) - for model weights
# /output will be mounted from EFS (read-write) - for shared output
RUN mkdir -p /models /output /tmp && \
    useradd -m -u 1000 appuser && \
    chown -R appuser:appuser /app /output /tmp && \
    chmod 777 /models /output

# Switch to non-root user
USER appuser

# Environment variables (can be overridden by Kubernetes ConfigMap)
ENV MODEL_PATH=/models/best.pt
ENV OUTPUT_PATH=/output

EXPOSE 8000

# Health check
HEALTHCHECK --interval=30s --timeout=5s --start-period=60s --retries=3 \
    CMD python3 -c "import requests; requests.get('http://localhost:8000/health')" || exit 1

CMD ["python3", "main.py"]