#!/bin/bash
# ComfyUI init script: Install custom nodes for LLM integration
set -e

# Assume ComfyUI is starting, install nodes
echo "Installing ComfyUI custom nodes..."

# Install ComfyUI-Manager if not present
if [ ! -d "/workspace/ComfyUI/custom_nodes/ComfyUI-Manager" ]; then
  echo "Installing ComfyUI-Manager..."
  cd /workspace/ComfyUI/custom_nodes
  git clone https://github.com/ltdrdata/ComfyUI-Manager.git
  pip install -r ComfyUI-Manager/requirements.txt
fi

# Install LLM-Party
if [ ! -d "/workspace/ComfyUI/custom_nodes/comfyui_LLM_party" ]; then
  echo "Installing ComfyUI-LLM-Party..."
  cd /workspace/ComfyUI/custom_nodes
  git clone https://github.com/heshengtao/comfyui_LLM_party.git
  pip install -r comfyui_LLM_party/requirements.txt
fi

# Install Copilot (if available)
if [ ! -d "/workspace/ComfyUI/custom_nodes/ComfyUI-Copilot" ]; then
  echo "Installing ComfyUI-Copilot..."
  cd /workspace/ComfyUI/custom_nodes
  git clone https://github.com/AIDC-AI/ComfyUI-Copilot.git || echo "Copilot repo not found, skipping"
  if [ -f "ComfyUI-Copilot/requirements.txt" ]; then
    pip install -r ComfyUI-Copilot/requirements.txt
  fi
fi

echo "Setting up default ComfyUI workflows..."

# Create workflows directory
mkdir -p /opt/ComfyUI/user/default/workflows

# Install workflow templates (mounted from repo)
if [ -d "/app/assets/workflows" ]; then
  echo "Copying workflow templates from /app/assets/workflows ..."
  cp -n /app/assets/workflows/*.json /opt/ComfyUI/user/default/workflows/ 2>/dev/null || true
fi

# Ensure a default workflow exists
if [ ! -f "/opt/ComfyUI/user/default/workflows/default_workflow.json" ]; then
  echo "No default workflow template found; creating a minimal placeholder."
  cat > /opt/ComfyUI/user/default/workflows/default_workflow.json << 'EOF'
{
  "workflow": {
    "nodes": [],
    "links": [],
    "groups": [],
    "config": {},
    "extra": {},
    "version": 0.4
  },
  "name": "Default Workflow",
  "description": "Starter template. Add nodes in the UI and save a new workflow."
}
EOF
fi

echo "Setting up user profiles..."

# Create user-specific directories
for user in user1 user2; do
  mkdir -p /opt/ComfyUI/user/${user}/workflows
  if [ ! -f "/opt/ComfyUI/user/${user}/workflows/${user}_workflow.json" ]; then
    echo "Installing ${user} workflow..."
    cat > /opt/ComfyUI/user/${user}/workflows/${user}_workflow.json << EOF
{
  "workflow": {
    "nodes": [],
    "links": [],
    "groups": [],
    "config": {},
    "extra": {},
    "version": 0.4
  },
  "name": "${user} Workflow",
  "description": "Custom workflow for ${user}"
}
EOF
  fi
done

echo "ComfyUI custom nodes and workflows ready."

# Register with registry
if [ -n "$REGISTRY_URL" ] && [ -n "$REGISTRY_SECRET" ]; then
  echo "Registering ComfyUI service with registry..."
  CURL_MTLS_ARGS=()
  if [ -n "${REGISTRY_CA:-}" ]; then
    CURL_MTLS_ARGS+=(--cacert "$REGISTRY_CA")
  elif [ -n "${REGISTRY_MTLS_CA:-}" ]; then
    CURL_MTLS_ARGS+=(--cacert "$REGISTRY_MTLS_CA")
  fi
  if [ -n "$REGISTRY_MTLS_CERT" ] && [ -n "$REGISTRY_MTLS_KEY" ]; then
    CURL_MTLS_ARGS+=(--cert "$REGISTRY_MTLS_CERT" --key "$REGISTRY_MTLS_KEY")
  fi

  ADVERTISE_HOST=${ADVERTISE_HOST:-192.168.1.99}
  ADVERTISE_SCHEME=${ADVERTISE_SCHEME:-http}

  curl "${CURL_MTLS_ARGS[@]}" -X POST "$REGISTRY_URL/register" \
    -H "Content-Type: application/json" \
    -H "X-Registry-Secret: $REGISTRY_SECRET" \
    -d "{\"service\": \"comfyui\", \"endpoint\": \"${ADVERTISE_SCHEME}://${ADVERTISE_HOST}:${COMFYUI_PORT:-8188}\", \"capabilities\": {\"gpu\": true, \"vram_gb\": 24}}" || echo "Registration failed"
fi