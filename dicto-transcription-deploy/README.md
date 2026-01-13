# Dicto Transcription Multi-GPU Deployment

This folder contains the configuration for deploying Speaches with load balancing across multiple GPUs.

## Prerequisites

- Docker with NVIDIA GPU support
- 8 NVIDIA GPUs (compatible with CUDA 12.9.1)
- Audio file named `audio.wav` in the root directory to verify model loading

## Quick Start

From the repository root directory:

```bash
# 1. Build the Docker image
docker compose build --build-arg BASE_IMAGE=nvidia/cuda:12.9.1-cudnn-runtime-ubuntu24.04

# 2. Start the multi-GPU deployment
docker compose -f dicto-transcription-deploy/compose.loadbalancer.yaml up -d

# 3. Load models on all GPUs (requires audio.wav in root directory)
bash dicto-transcription-deploy/load-models.sh TLAIM/whisper-dicto
```

Or use the all-in-one deployment script:

```bash
bash dicto-transcription-deploy/deploy.sh TLAIM/whisper-dicto
```

## Configuration

### Environment Variables

Create a `.env` file in this folder (`dicto-transcription-deploy/.env`) with:

```
HF_TOKEN=your_huggingface_token_here
HTTPS_PROXY=your_https_proxy
```

The token is required to access private Hugging Face models. While the proxy is optional, it can be very helpful behind restrictive firewalls, since Hugging Face relies on multiple redirects that are often difficult to whitelist.

### Adjusting GPU Count

The default setup uses 8 GPUs (0-7). To use fewer GPUs:

1. Edit `compose.loadbalancer.yaml` - remove unwanted `speaches-gpu-X` services
2. Edit `nginx.conf` - remove corresponding backend server entries

## Usage

### Testing

```bash
curl http://localhost:8000/v1/audio/transcriptions \
  -F "file=@audio.wav" \
  -F "model=TLAIM/whisper-dicto"
```

### Monitor
```bash
# View all logs
docker compose -f dicto-transcription-deploy/compose.loadbalancer.yaml logs -f

# View specific container
docker logs -f speaches-gpu-0

# Check nginx load balancer
docker logs -f speaches-loadbalancer
```

### Stop
```bash
docker compose -f dicto-transcription-deploy/compose.loadbalancer.yaml down
```

## Architecture

- **Load Balancer**: Nginx (port 8000) using least-connection algorithm
- **Workers**: 8 Speaches containers, each bound to a specific GPU
- **Cache**: Shared HuggingFace model cache across all workers (**Volume**: speaches_hf-hub-cache)
- **Network**: Bridge network (`speaches-network`) for internal communication
