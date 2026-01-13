#!/bin/bash
set -e

MODEL="${1:-TLAIM/whisper-dicto}"

echo "=== Loading Speaches models on all GPUs ==="
echo "Model: $MODEL"
echo ""

# Check if audio file exists
if [ ! -f "audio.wav" ]; then
    echo "Error: audio.wav not found in current directory."
    echo "Please provide a test audio file named 'audio.wav' to verify model loading."
    exit 1
fi

# Detect speaches GPU containers
CONTAINERS=$(docker ps --filter "name=speaches-gpu-" --format "{{.Names}}" | sort)
if [ -z "$CONTAINERS" ]; then
    echo "Error: No running speaches-gpu-* containers found"
    echo "Make sure to start the services first with: export COMPOSE_FILE=compose.loadbalancer.yaml && docker compose up -d"
    exit 1
fi

NUM_GPUS=$(echo "$CONTAINERS" | wc -l)
echo "Detected $NUM_GPUS running speaches-gpu container(s):"
echo "$CONTAINERS" | sed 's/^/  - /'
echo ""
echo "Note: First load may take several minutes as the model is downloaded and loaded into GPU memory."
echo ""

# Copy audio file once into nginx container
echo "Copying audio.wav to loadbalancer container..."
if ! docker cp audio.wav speaches-loadbalancer:/tmp/audio.wav 2>&1; then
    echo "Error: Could not copy audio file to loadbalancer container"
    exit 1
fi

# Function to load model on GPU and verify with test transcription
load_model_on_gpu() {
    local container_name=$1

    echo "Loading model on ${container_name}..."

    # Step 1: Load the model into GPU memory
    echo "  Loading model ${MODEL} into GPU memory..."
    load_response=$(docker exec speaches-loadbalancer sh -c "
        curl -s -w '\nHTTP_CODE:%{http_code}' \
             -X POST \
             http://${container_name}:8000/v1/models/${MODEL}
    " 2>&1)

    load_http_code=$(echo "$load_response" | grep "HTTP_CODE:" | cut -d: -f2)

    if [ "$load_http_code" != "200" ]; then
        echo "✗ ${container_name} model load failed (HTTP $load_http_code)"
        load_response_body=$(echo "$load_response" | grep -v "HTTP_CODE:")
        echo "  Response: ${load_response_body:0:200}"
        return 1
    fi

    echo "  Model loaded into GPU memory successfully"

    # Step 2: Verify model with test transcription
    echo "  Verifying model with test transcription..."
    response=$(docker exec speaches-loadbalancer sh -c "
        curl -s -w '\nHTTP_CODE:%{http_code}' \
             http://${container_name}:8000/v1/audio/transcriptions \
             -F 'file=@/tmp/audio.wav' \
             -F 'model=${MODEL}'
    " 2>&1)

    http_code=$(echo "$response" | grep "HTTP_CODE:" | cut -d: -f2)
    response_body=$(echo "$response" | grep -v "HTTP_CODE:")

    if [ "$http_code" = "200" ]; then
        echo "✓ ${container_name} model loaded and verified successfully"
    else
        echo "✗ ${container_name} verification failed (HTTP $http_code)"
        echo "  Response: ${response_body:0:200}"
    fi
}

# Load models on all GPUs sequentially
# All containers share the same HuggingFace cache, so parallel loading
# could cause conflicts if the model needs to be downloaded first
echo "$CONTAINERS" | while read -r container; do
    load_model_on_gpu "$container"
done

echo ""
echo "=== Model loading complete ==="
echo "All models are now loaded on GPUs and ready for requests."
echo ""
echo "Test with: curl http://localhost:8000/v1/audio/transcriptions -F 'file=@audio.wav' -F 'model=${MODEL}'"
