# Custom Container Build Research Summary

**Generated:** January 2, 2026  
**Purpose:** Research for custom container builds for self-hosted AI stack

---

## 1. ComfyUI v0.7.0 Analysis

### Source Information
- **Release:** https://github.com/comfyanonymous/ComfyUI/releases/tag/v0.7.0
- **Tag Date:** ~3 days ago (late December 2025)
- **Commit:** f59f71cf34067d46713f6243312f7f0b360d061f

### Key Dependencies (from requirements.txt v0.7.0)
```
comfyui-frontend-package==1.35.9
comfyui-workflow-templates==0.7.64
comfyui-embedded-docs==0.3.1
torch
torchsde
torchvision
torchaudio
numpy>=1.25.0
einops
transformers>=4.50.3
tokenizers>=0.13.3
sentencepiece
safetensors>=0.4.2
aiohttp>=3.11.8
yarl>=1.18.0
pyyaml
Pillow
scipy
tqdm
psutil
alembic
SQLAlchemy
av>=14.2.0

# Non-essential dependencies:
kornia>=0.7.1
spandrel
pydantic~=2.0
pydantic-settings~=2.0
```

### CUDA/GPU Requirements
- **PyTorch:** 2.4+ required (explicitly stated in v0.7.0 release notes)
- **NVIDIA CUDA:** cu130 recommended for stable, nightly also supported
- **AMD ROCm:** 6.4+ stable, 7.0+ nightly
- **Memory:** Depends on model, 6GB+ VRAM recommended for most tasks

### Official Dockerfile Status
- **No official Dockerfile** in the ComfyUI repository
- Community uses various approaches:
  - ai-dock/comfyui images (currently used in this project)
  - Manual builds from source

### Recommended Dockerfile Approach

```dockerfile
# Dockerfile.comfyui-custom
FROM nvidia/cuda:12.6.3-cudnn-runtime-ubuntu22.04

ARG COMFYUI_VERSION=v0.7.0
ARG PYTHON_VERSION=3.12

# System dependencies
RUN apt-get update && apt-get install -y \
    git curl wget \
    python${PYTHON_VERSION} python${PYTHON_VERSION}-venv python3-pip \
    libgl1-mesa-glx libglib2.0-0 libsm6 libxext6 libxrender-dev \
    ffmpeg \
    && rm -rf /var/lib/apt/lists/*

# Create non-root user
RUN useradd -m -u 1000 comfyui
USER comfyui
WORKDIR /home/comfyui

# Clone ComfyUI at specific version
RUN git clone --depth 1 --branch ${COMFYUI_VERSION} \
    https://github.com/comfyanonymous/ComfyUI.git

WORKDIR /home/comfyui/ComfyUI

# Create venv and install dependencies
RUN python${PYTHON_VERSION} -m venv venv && \
    . venv/bin/activate && \
    pip install --upgrade pip && \
    pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu126 && \
    pip install -r requirements.txt

# Model directories
RUN mkdir -p models/checkpoints models/vae models/loras output input

EXPOSE 8188

# Healthcheck
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD curl -f http://localhost:8188/system_stats || exit 1

# Entrypoint
ENTRYPOINT ["/home/comfyui/ComfyUI/venv/bin/python", "main.py"]
CMD ["--listen", "0.0.0.0", "--port", "8188"]
```

### Resource Limits (Tight Workstation Deployment)
```yaml
cpus: 4.0
mem_limit: 8g
deploy:
  resources:
    reservations:
      devices:
        - driver: nvidia
          count: 1
          capabilities: [gpu]
```

### Integration Points
- **No native OAuth2/Keycloak support** - authentication must be handled at reverse proxy level
- **API Endpoints:** `/prompt`, `/view`, `/history`, `/system_stats`
- Works with existing nginx SSO proxy pattern in this stack

---

## 2. LoLLMs WebUI v14 Analysis

### Source Information
- **Release:** https://github.com/ParisNeo/lollms-webui/releases/tag/v14
- **Codename:** Saïph
- **Release Date:** November 11, 2024
- **Commit:** a904ec0cd0e90bf3b4eeab946e03364463983592

### Key Dependencies (from requirements.txt v14)
```
colorama
numpy==1.26.*
pandas
Pillow>=9.5.0
pyyaml
requests
rich
scipy
tqdm
setuptools
wheel
psutil
pytest
GitPython
ascii-colors>=0.4.2
beautifulsoup4
packaging

fastapi
uvicorn
python-multipart
python-socketio
python-socketio[client]
python-socketio[asyncio_client]

pydantic
selenium
tiktoken

pipmaster>=0.1.7

lollmsvectordb>=1.1.0
freedom-search>=0.1.9
scrapemaster>=0.2.0
freedom_search
lollms_client>=0.7.5

aiofiles
python-multipart
zipfile36
```

### Existing Dockerfile (from v14 branch)
The project has a working Dockerfile:
```dockerfile
FROM python:3.11-slim

WORKDIR /app

RUN apt-get update && apt-get install -y \
    git curl \
    && rm -rf /var/lib/apt/lists/*

# Installs Miniconda (optional, for conda env management)
# Alternative: direct pip install approach

# Clone and install
RUN git clone --depth 1 --recurse-submodules \
    https://github.com/ParisNeo/lollms-webui.git \
    && cd lollms-webui/lollms_core && pip install -e . \
    && cd ../utilities/pipmaster && pip install -e .

WORKDIR /app/lollms-webui
RUN pip install -r requirements.txt

EXPOSE 9600

CMD ["python", "app.py", "--host", "0.0.0.0", "--force-accept-remote-access"]
```

### Recommended Dockerfile Approach (Optimized)

```dockerfile
# Dockerfile.lollms
FROM python:3.11-slim

ARG LOLLMS_VERSION=v14

# System dependencies
RUN apt-get update && apt-get install -y \
    git curl \
    libgl1 libglib2.0-0 libsm6 libxext6 libxrender-dev \
    && rm -rf /var/lib/apt/lists/*

# Create non-root user
RUN useradd -m -u 1000 lollms
WORKDIR /app

# Clone at specific version
RUN git clone --depth 1 --branch ${LOLLMS_VERSION} --recurse-submodules \
    https://github.com/ParisNeo/lollms-webui.git

WORKDIR /app/lollms-webui

# Install dependencies
RUN pip install --no-cache-dir -r requirements.txt && \
    pip install --no-cache-dir -e lollms_core && \
    pip install --no-cache-dir torch --index-url https://download.pytorch.org/whl/cu121

# Create data directories
RUN mkdir -p /app/personal_data && \
    echo "lollms_path: /app/lollms-webui/lollms_core/lollms\nlollms_personal_path: /app/personal_data" > /app/global_paths_cfg.yaml

# Switch to non-root
RUN chown -R lollms:lollms /app
USER lollms

EXPOSE 9600

HEALTHCHECK --interval=30s --timeout=10s --start-period=90s --retries=3 \
    CMD curl -f http://localhost:9600/ || exit 1

CMD ["python", "app.py", "--host", "0.0.0.0", "--force-accept-remote-access"]
```

### Resource Limits (Tight Workstation Deployment)
```yaml
cpus: 2.0
mem_limit: 4g
deploy:
  resources:
    reservations:
      devices:
        - driver: nvidia
          count: 1
          capabilities: [gpu]
```

### ComfyUI Integration Capabilities
- LoLLMs has a **bindings system** that can connect to external services
- Can integrate with Ollama binding (`zoos/bindings_zoo/ollama_ai/`)
- No direct ComfyUI binding in v14, but can be:
  - Added via custom function calls
  - Integrated via API endpoints
  - Connected via the LiteLLM or OpenRouter bindings for routing

### OAuth2/Keycloak Integration Points
- **No native OAuth2/OIDC support** in v14
- LoLLMs has a `client_id` authentication mechanism for API calls
- Uses FastAPI - can potentially add OAuth2 middleware
- **Recommended approach:** Handle auth at nginx/oauth2-proxy level (consistent with stack pattern)

### Security Considerations
- `--force-accept-remote-access` flag disables some validation
- Has `host != localhost` checks for code execution endpoints
- Needs careful config for production exposure

---

## 3. Version Pinning Verification

### OpenWebUI
- **Image:** `ghcr.io/open-webui/open-webui:git-ccd3295-cuda126`
- **Status:** ✅ VERIFIED EXISTS
- **Architectures:** amd64, arm64
- **Digest:** sha256:efcbf76350d4a894c93d96bdfba4122528bb19ce6f12ff56caa33d43790566ed (amd64)

### Pipelines
- **Image:** `ghcr.io/open-webui/pipelines:git-039f9c5-cuda`
- **Status:** ✅ VERIFIED EXISTS
- **Architectures:** amd64, arm64
- **Digest:** sha256:fc4a76abf65e464f51c9e0969ca3856e9fac48b35944d15f80b82b0f62f19108 (amd64)

### Updated versions.lock.yaml
```yaml
docker_images:
  openwebui:
    image: ghcr.io/open-webui/open-webui
    tag: "git-ccd3295-cuda126"
    digest: "sha256:efcbf76350d4a894c93d96bdfba4122528bb19ce6f12ff56caa33d43790566ed"
  pipelines:
    image: ghcr.io/open-webui/pipelines
    tag: "git-039f9c5-cuda"
    digest: "sha256:fc4a76abf65e464f51c9e0969ca3856e9fac48b35944d15f80b82b0f62f19108"
  comfyui:
    # Custom build from Dockerfile.comfyui-custom
    image: local/comfyui
    tag: "v0.7.0"
    build_context: .
    dockerfile: Dockerfile.comfyui-custom
  lollms:
    # Custom build from Dockerfile.lollms
    image: local/lollms
    tag: "v14"
    build_context: .
    dockerfile: Dockerfile.lollms
```

---

## 4. SSO Integration Summary

### Current Stack Pattern
The stack uses:
1. **Keycloak** as IdP (profile: `sso`)
2. **oauth2-proxy** for authentication enforcement
3. **nginx** for reverse proxy with conditional SSO

### Integration for New Services

Both ComfyUI and LoLLMs lack native OAuth2/OIDC support. Use the existing pattern:

```nginx
# nginx.conf.template additions for new services

# LoLLMs behind oauth2-proxy (when SSO_ENABLED=1)
location /lollms/ {
    {{#if SSO_ENABLED}}
    auth_request /oauth2/auth;
    error_page 401 = /oauth2/sign_in;
    auth_request_set $user $upstream_http_x_auth_request_user;
    auth_request_set $email $upstream_http_x_auth_request_email;
    proxy_set_header X-User $user;
    proxy_set_header X-Email $email;
    {{/if}}
    
    proxy_pass http://lollms:9600/;
    proxy_http_version 1.1;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection "upgrade";
    proxy_set_header Host $host;
}
```

### Keycloak Realm Configuration
Add to `config/keycloak/comfyui-realm.json`:
```json
{
  "clients": [
    {
      "clientId": "lollms",
      "enabled": true,
      "publicClient": false,
      "redirectUris": ["https://{{STACK_FQDN}}/lollms/*"],
      "webOrigins": ["https://{{STACK_FQDN}}"]
    }
  ]
}
```

---

## 5. Resource Limit Recommendations (Tight Workstation)

### Total Budget Assumption
- **CPU:** 16 cores available, 12 usable for containers
- **RAM:** 32GB total, 24GB for containers
- **GPU:** Single NVIDIA GPU (8GB+ VRAM)

### Service Allocation

| Service | CPU | Memory | GPU |
|---------|-----|--------|-----|
| OpenWebUI | 2.0 | 3GB | - |
| Pipelines | 1.0 | 1GB | - |
| Ollama | 4.0 | 8GB | shared |
| ComfyUI (custom) | 4.0 | 6GB | shared |
| LoLLMs (custom) | 2.0 | 4GB | shared |
| Keycloak | 1.0 | 1GB | - |
| Keycloak-DB | 0.5 | 512MB | - |
| nginx | 0.25 | 128MB | - |
| oauth2-proxy | 0.25 | 128MB | - |
| **Total** | ~15 | ~24GB | 1 GPU |

### GPU Sharing Strategy
Use NVIDIA MPS or time-slicing for concurrent access:
```yaml
# For each GPU service
deploy:
  resources:
    reservations:
      devices:
        - driver: nvidia
          count: 1
          capabilities: [gpu]
```

---

## 6. Blockers and Concerns

### ComfyUI
1. **No official Dockerfile** - community solutions vary in quality
2. **Large dependency tree** - builds can be slow
3. **Model storage** - needs volume strategy for large model files
4. **VRAM contention** - with Ollama and LoLLMs

### LoLLMs
1. **v14 is from Nov 2024** - 14 months old, main branch has 589 commits since
2. **PyQt5 dependency** - may cause headless container issues (needs `--force-accept-remote-access`)
3. **No native SSO** - requires proxy-level auth
4. **Binding ecosystem** - may need additional setup for Ollama integration

### General
1. **GPU memory pressure** - three GPU services competing
2. **Cold start times** - large model loads can take minutes
3. **Disk space** - combined models can be 50GB+
4. **Network isolation** - ensure services can communicate internally

---

## 7. Recommended Implementation Order

1. **Phase 1: Version Pinning**
   - Update `versions.lock.yaml` with verified digests
   - Update `.env` files with new image tags
   - Test OpenWebUI + Pipelines with pinned versions

2. **Phase 2: ComfyUI Custom Build**
   - Create `Dockerfile.comfyui-custom`
   - Build and test locally
   - Integrate with existing nginx/SSO

3. **Phase 3: LoLLMs Custom Build**
   - Create `Dockerfile.lollms`
   - Configure Ollama binding
   - Add nginx routing + SSO

4. **Phase 4: Integration Testing**
   - Full stack startup
   - SSO flow verification
   - Resource monitoring under load

---

## 8. Files to Create/Modify

### New Files
- `Dockerfile.comfyui-custom` - Custom ComfyUI v0.7.0 build
- `Dockerfile.lollms` - Custom LoLLMs v14 build
- `healthcheck-lollms.sh` - Healthcheck script
- `lollms-init.sh` - Initialization script (optional)

### Modified Files
- `config/versions.lock.yaml` - Add pinned versions
- `docker-compose.single-node-gpu.yml` - Add lollms service
- `nginx.conf.template` - Add lollms routing
- `.env.single-node-gpu` - Add LOLLMS_* variables
- `config/keycloak/comfyui-realm.json` - Add lollms client (if using SSO)
