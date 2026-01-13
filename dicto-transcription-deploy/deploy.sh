#!/bin/bash
set -e

MODEL="${1:-TLAIM/whisper-dicto}"

echo "=== Deploying Speaches Multi-GPU Setup ==="
echo "Model: $MODEL"
echo ""

# Step 1: Build the image
echo "Step 1: Building Docker image with CUDA 12.9.1..."
docker compose build --build-arg BASE_IMAGE=nvidia/cuda:12.9.1-cudnn-runtime-ubuntu24.04

# Step 2: Start services
echo ""
echo "Step 2: Starting services with load balancer..."
docker compose -f dicto-transcription-deploy/compose.loadbalancer.yaml up -d

# Step 3: Wait for services to be healthy
echo ""
echo "Step 3: Waiting for services to become healthy..."
sleep 5

# Check if all containers are running
CONTAINERS=$(docker ps --filter "name=speaches-gpu-" --format "{{.Names}}" | wc -l)
echo "Running containers: $CONTAINERS"

if [ "$CONTAINERS" -eq 0 ]; then
    echo "Error: No speaches containers are running"
    exit 1
fi

# Step 4: Load models on GPUs
echo ""
echo "Step 4: Loading models on all GPUs..."
if [ -f "audio.wav" ]; then
    bash dicto-transcription-deploy/load-models.sh "$MODEL"
else
    echo "Warning: audio.wav not found. Skipping model loading."
    echo "You can run 'bash dicto-transcription-deploy/load-models.sh $MODEL' later once you have a test audio file."
fi

echo ""
echo "=== Deployment complete ==="
echo ""
echo "Load balancer is running at: http://localhost:8000"
echo "Test with: curl http://localhost:8000/v1/audio/transcriptions -F 'file=@audio.wav' -F 'model=$MODEL'"
echo ""
echo "To view logs: docker compose -f dicto-transcription-deploy/compose.loadbalancer.yaml logs -f"
echo "To stop: docker compose -f dicto-transcription-deploy/compose.loadbalancer.yaml down"
