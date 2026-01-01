#!/bin/bash
# Ollama init script: Start Ollama, pull models, then serve
set -e

# Install curl if not present (for healthchecks)
apt-get update && apt-get install -y curl

# Start Ollama serve in background
echo "Starting Ollama serve..."
ollama serve &
OLLAMA_PID=$!

# Wait for Ollama to be ready
echo "Waiting for Ollama API to be ready..."
for i in {1..30}; do
  if curl -s http://localhost:11434/api/tags > /dev/null 2>&1; then
    echo "Ollama API is ready"
    break
  fi
  echo "Waiting... ($i/30)"
  sleep 2
done

# Default models if not specified
DEFAULT_MODELS="tinyllama,nomic-embed-text"
OLLAMA_MODELS=${OLLAMA_MODELS:-$DEFAULT_MODELS}

echo "Pulling Ollama models: $OLLAMA_MODELS"

# Function to download model with security hierarchy
download_model() {
  local model=$1
  
  echo "Checking for $model in local Ollama registry..."
  
  # Primary: Local Ollama (already downloaded models)
  if ollama list | grep -q "$model"; then
    echo "$model already available locally"
    return 0
  fi
  
  # Secondary: Official Ollama registry
  echo "Downloading $model from Ollama registry..."
  if ollama pull "$model"; then
    echo "Successfully downloaded $model from Ollama registry"
    return 0
  fi
  
  # Tertiary: HuggingFace (with authentication and security)
  echo "Ollama registry failed, trying HuggingFace..."
  if [ -n "$HF_TOKEN" ]; then
    export HF_TOKEN="$HF_TOKEN"  # Ensure token is available
    if ollama pull "$model" --registry huggingface; then
      echo "Successfully downloaded $model from HuggingFace"
      return 0
    fi
  fi
  
  echo "Failed to download $model from all sources"
  return 1
}

# Pull each model
IFS=',' read -ra MODELS <<< "$OLLAMA_MODELS"
for model in "${MODELS[@]}"; do
  model=$(echo "$model" | xargs)  # Trim whitespace
  if ! ollama list | grep -q "$model"; then
    echo "Pulling $model..."
    if ! download_model "$model"; then
      echo "Warning: Could not pull $model"
    fi
  else
    echo "$model already available"
  fi
done

echo "Ollama models initialization complete."

# Register with registry
if [ -n "$REGISTRY_URL" ] && [ -n "$REGISTRY_SECRET" ]; then
  echo "Registering Ollama service with registry..."
  CURL_MTLS_ARGS=()
  if [ -n "$REGISTRY_MTLS_CA" ] && [ -f "$REGISTRY_MTLS_CA" ]; then
    CURL_MTLS_ARGS+=(--cacert "$REGISTRY_MTLS_CA")
  fi
  if [ -n "$REGISTRY_MTLS_CERT" ] && [ -n "$REGISTRY_MTLS_KEY" ] && [ -f "$REGISTRY_MTLS_CERT" ] && [ -f "$REGISTRY_MTLS_KEY" ]; then
    CURL_MTLS_ARGS+=(--cert "$REGISTRY_MTLS_CERT" --key "$REGISTRY_MTLS_KEY")
  fi

  ADVERTISE_HOST=${ADVERTISE_HOST:-192.168.1.99}
  ADVERTISE_SCHEME=${ADVERTISE_SCHEME:-http}

  curl "${CURL_MTLS_ARGS[@]}" -X POST "$REGISTRY_URL/register" \
    -H "Content-Type: application/json" \
    -H "X-Registry-Secret: $REGISTRY_SECRET" \
    -d "{\"service\": \"ollama\", \"endpoint\": \"${ADVERTISE_SCHEME}://${ADVERTISE_HOST}:$OLLAMA_PORT\", \"capabilities\": {\"gpu\": true, \"vram_gb\": 24, \"models_loaded\": [\"$OLLAMA_MODELS\"]}}" || echo "Registration failed"
fi

# Stop the background Ollama
kill $OLLAMA_PID
sleep 2

# Now serve in foreground
exec ollama serve