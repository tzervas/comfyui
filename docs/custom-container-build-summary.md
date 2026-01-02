# Custom Container Build Summary

**Branch:** `feature/custom-containers`  
**Date:** 2026-01-02  
**Phase:** 1 (Ollama + ComfyUI validation)

## Version Pins

| Component | Version/Tag | Source |
|-----------|-------------|--------|
| **OpenWebUI** | `git-ccd3295-cuda126` | ghcr.io/open-webui/open-webui |
| **Pipelines** | `git-039f9c5-cuda` | ghcr.io/open-webui/pipelines |
| **ComfyUI** | `v0.7.0` | Self-built from official release |
| **Ollama** | `0.5.8` | ollama/ollama |
| **LoLLMs** | `<Phase 2>` | Deferred until after validation |

## 12-Core Resource Budget

**Total Allocation: ~11.5 cores (0.5 core headroom)**

| Service | CPU Limit | CPU Reserve | Memory Limit | GPU | Notes |
|---------|-----------|-------------|--------------|-----|-------|
| **Ollama** | 4.0 | 2.0 | 8GB | ✓ | LLM inference primary |
| **ComfyUI** | 3.0 | 2.0 | 6GB | ✓ | Media generation |
| **OpenWebUI** | 1.5 | 0.5 | 2GB | - | Frontend UI |
| **Pipelines** | 1.0 | 0.5 | 1GB | - | Middleware |
| **LangChain** | 2.0 | 1.0 | 2GB | - | RAG backend |
| **LangFlow** | 2.0 | 1.0 | 2GB | - | Visual workflows |
| **Model Vault** | 1.0 | 0.5 | 1GB | - | Registry |
| **nginx** | 0.5 | 0.25 | 256MB | - | Reverse proxy |
| **Keycloak** | 2.0 | 1.0 | 2GB | - | SSO (profile: sso) |
| **Keycloak DB** | 1.0 | 0.5 | 1GB | - | SSO (profile: sso) |
| **oauth2-proxy** | 0.5 | 0.25 | 256MB | - | SSO (profile: sso) |
| **code_executor** | 0.5 | - | 512MB | - | Sandboxed exec |

**GPU Sharing:** Single NVIDIA GPU shared between Ollama + ComfyUI via NVIDIA driver time-slicing.

## Dockerfile.comfyui Details

**Base Image:** `nvidia/cuda:12.6.3-cudnn-runtime-ubuntu22.04`

**Key Components:**
- Python 3.11
- PyTorch 2.4.1 with CUDA 12.6 support
- Official ComfyUI v0.7.0 (git tag)
- ComfyUI-Manager for custom nodes
- SQLAlchemy + alembic (v0.7.0 new DB layer)
- transformers>=4.50.3, safetensors>=0.4.2

**Paths:**
- Install: `/opt/ComfyUI`
- Models: `/opt/ComfyUI/models/*`
- Output: `/opt/ComfyUI/output`
- Input: `/opt/ComfyUI/input`
- User profiles: `/opt/ComfyUI/user_profiles`

**Port:** `18188`

**User:** `comfyui` (UID 1000)

## Build Commands

```bash
# Build ComfyUI container
docker compose -f docker-compose.single-node-gpu.yml build comfyui

# Pull pinned OpenWebUI/Pipelines tags
docker pull ghcr.io/open-webui/open-webui:git-ccd3295-cuda126
docker pull ghcr.io/open-webui/pipelines:git-039f9c5-cuda

# Bring up full stack
docker compose -f docker-compose.single-node-gpu.yml up -d

# Monitor resource usage
docker stats --no-stream
```

## Validation Checklist

- [ ] ComfyUI container builds successfully
- [ ] OpenWebUI/Pipelines pull without errors
- [ ] Stack starts all services healthy
- [ ] Ollama models load (gemma3:1b, deepseek-r1:1.5b)
- [ ] ComfyUI accessible at http://localhost:8080/comfyui/
- [ ] Pipelines `/filter/inlet` test succeeds
- [ ] End-to-end media generation: POST → ComfyUI /prompt → /view URL → nginx 200 OK
- [ ] Resource limits respected (docker stats shows <12 cores)
- [ ] GPU memory stable (nvidia-smi shows no OOM)

## Phase 2 (Post-Validation)

**LoLLMs Integration:**
- Pin to main-branch commit SHA (latest stable)
- Create `Dockerfile.lollms` (Python 3.11-slim base)
- Add to compose with 2 CPU / 4GB limits
- Wire oauth2-proxy auth in nginx
- Enable GPU sharing via MPS/time-slicing
- Validate three-way GPU contention

## Notes

- **ComfyUI v0.7.0 changes:** New SQLite DB layer replaces old JSON workflow storage; ComfyUI-Manager compatibility confirmed.
- **PyTorch 2.4+ requirement:** Per v0.7.0 release notes; CUDA 12.6 recommended for stability.
- **No oauth2-proxy for ComfyUI/Ollama:** Auth handled at nginx layer via Basic Auth; ai-dock portal disabled (`WEB_ENABLE_AUTH=false`).
- **LoLLMs deferred:** Focus on stable Ollama+ComfyUI baseline before adding third GPU consumer.
- **12-core fit:** If host heavily used, reduce Ollama to 3 CPU first, then LangFlow/LangChain as needed.
