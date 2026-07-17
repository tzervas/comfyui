# ComfyUI + Ollama Dual-Host AI Stack

<!-- FLEET-BADGES:BEGIN -->
[![CI](https://github.com/tzervas/comfyui/actions/workflows/fleet-ci.yml/badge.svg?branch=main)](https://github.com/tzervas/comfyui/actions/workflows/fleet-ci.yml?query=branch%3Amain)
[![Security](https://github.com/tzervas/comfyui/actions/workflows/fleet-security.yml/badge.svg?branch=main)](https://github.com/tzervas/comfyui/actions/workflows/fleet-security.yml?query=branch%3Amain)
<!-- FLEET-BADGES:END -->

Production-ready containerized AI infrastructure with GPU workers and centralized control plane for LAN-based AI/ML workloads.

## Architecture

**Dual-Host Setup:**
- **Homelab (192.168.1.170)**: Control plane with model registry, nginx proxy, AI frameworks
- **Desktop (192.168.1.99)**: GPU worker with Ollama (LLM inference) and ComfyUI (image generation)

Services auto-register on startup for dynamic service discovery. GPU sharing via Docker or isolated VM with passthrough.

## Quick Start

### On Homelab

```bash
git clone <repo> ~/comfyui && cd ~/comfyui

# Configure environment (see DEPLOYMENT_GUIDE.md for details)
cp .env.homelab.example .env.homelab
# Edit .env.homelab with your tokens and secrets

# Deploy control plane
docker compose -f docker-compose.homelab.yml up -d
```

### On Desktop/GPU Worker

```bash
# Sync or clone project
git clone <repo> ~/comfyui && cd ~/comfyui

# Configure environment
cp .env.desktop.example .env.desktop
# Edit .env.desktop (REGISTRY_URL, secrets, etc.)

# Deploy GPU worker (auto-detects GPU, checks prerequisites)
./tools/deploy-gpu-worker.sh

# Optional: Configure iGPU fallback for seamless desktop use
sudo ./tools/configure-igpu-display.sh
```

### Verify

```bash
# Discover registered GPU workers
curl -s http://192.168.1.170:8081/discover | jq

# Test Ollama inference
curl -X POST http://192.168.1.99:11434/api/generate \
  -d '{"model": "gemma3:1b", "prompt": "Hello", "stream": false}'

# Monitor GPU usage
ssh user@192.168.1.99 "cd ~/comfyui && ./tools/monitor-gpu-sharing.sh"
```

## Features

✅ **Automatic Service Discovery**: Registry-based with health tracking  
✅ **GPU Sharing**: Docker time-slicing + iGPU fallback for desktop  
✅ **Security**: Token auth, basic auth, network isolation, HTTPS  
✅ **Monitoring**: Real-time GPU and container health  
✅ **Management Scripts**: One-command deploy/teardown/health checks  
✅ **Scalable**: Add GPU workers dynamically  
✅ **VM Ready**: Full GPU passthrough guide included  

## Documentation

- **[DEPLOYMENT_GUIDE.md](DEPLOYMENT_GUIDE.md)** - Complete setup walkthrough
- **[docs/desktop-gpu-worker-setup.md](docs/desktop-gpu-worker-setup.md)** - GPU worker configuration
- **[docs/docker-gpu-sharing.md](docs/docker-gpu-sharing.md)** - GPU sharing strategies
- **[docs/vm-gpu-passthrough-setup.md](docs/vm-gpu-passthrough-setup.md)** - VM isolation approach
- **[docs/troubleshooting.md](docs/troubleshooting.md)** - Common issues and fixes

## Components

### Homelab Control Plane
- **model-vault**: Rust-based service registry (Axum + SQLite)
- **nginx**: Reverse proxy with auth and load balancing
- **langchain**: RAG and agentic AI framework
- **langflow**: Visual workflow builder
- **code_executor**: Sandboxed Python execution
- **oauth2-proxy**: User authentication (optional)

### Desktop GPU Worker
- **ollama**: LLM inference with model management
- **comfyui**: Node-based image generation UI

## Prerequisites
- Docker Engine 20.10+ and Docker Compose v2
- NVIDIA GPU + drivers + NVIDIA Container Toolkit (GPU worker)
- 8GB+ RAM (homelab), 16GB+ RAM (desktop)
- Rust 1.70+ (for building model-vault)

- Rust 1.70+ (for building model-vault)

## Management

### Desktop GPU Worker

```bash
# Deploy
./tools/deploy-gpu-worker.sh

# Stop
./tools/teardown-gpu-worker.sh

# Health check
./tools/check-gpu-worker.sh

# Monitor GPU sharing
./tools/monitor-gpu-sharing.sh
```

### Homelab Control Plane

```bash
# Start services
docker compose -f docker-compose.homelab.yml up -d

# Stop services
docker compose -f docker-compose.homelab.yml down

# Check status
docker compose -f docker-compose.homelab.yml ps

# View logs
docker logs model-vault
docker logs nginx
```

### Service Discovery

```bash
# List all registered services
curl -s http://192.168.1.170:8081/discover | jq

# Find Ollama workers
curl -s http://192.168.1.170:8081/discover?service=ollama | jq

# Find ComfyUI instances
curl -s http://192.168.1.170:8081/discover?service=comfyui | jq
```

## Configuration

### Environment Variables

**Homelab (.env.homelab)**:
```bash
NGINX_HTTP_PORT=8081
NGINX_HTTPS_PORT=8444
MODEL_VAULT_TOKEN=<strong-token>
REGISTRY_SECRET=<strong-secret>
HF_TOKEN=<optional-huggingface-token>
```

**Desktop (.env.desktop)**:
```bash
OLLAMA_PORT=11434
COMFYUI_PORT=8188
OLLAMA_MODELS=gemma3:1b,llama3.1:8b,mistral:7b
REGISTRY_URL=http://192.168.1.170:8081
REGISTRY_SECRET=<match-homelab-secret>
MODEL_VAULT_TOKEN=<match-homelab-token>

# GPU resource limits (prevent hogging)
OLLAMA_NUM_PARALLEL=2
OLLAMA_MAX_LOADED_MODELS=2
```

## Accessing Services

| Service | URL | Auth Required |
|---------|-----|---------------|
| Ollama API (direct) | http://192.168.1.99:11434 | No |
| ComfyUI UI (direct) | http://192.168.1.99:8188 | No |
| Registry Discovery | http://192.168.1.170:8081/discover | No |
| Ollama (via proxy) | http://192.168.1.170:8081/ollama/ | Yes (basic auth) |
| ComfyUI (via proxy) | http://192.168.1.170:8081/comfyui/ | Yes (basic auth) |
| LangChain API | http://192.168.1.170:8000 | No |
| LangFlow UI | http://192.168.1.170:7860 | No |

## Examples

### LLM Inference

```bash
# Direct to Ollama
curl -X POST http://192.168.1.99:11434/api/generate \
  -d '{
    "model": "gemma3:1b",
    "prompt": "Explain Docker in one sentence",
    "stream": false
  }' | jq -r '.response'

# Via proxy (requires auth)
curl -u admin:password -X POST http://192.168.1.170:8081/ollama/api/generate \
  -d '{"model": "gemma3:1b", "prompt": "Hello", "stream": false}'
```

### Image Generation

Open ComfyUI in browser:
- Direct: `http://192.168.1.99:8188`
- Via proxy: `http://192.168.1.170:8081/comfyui/` (requires auth)

### Service Discovery

```bash
# Get all available GPU workers
curl -s http://192.168.1.170:8081/discover | jq '.[] | {service: .name, endpoint: .url, gpu: .capabilities.gpu}'
```

## Monitoring

```bash
# GPU usage on desktop
ssh user@192.168.1.99 "docker exec ollama nvidia-smi"

# Container stats
docker stats ollama comfyui --no-stream

# Full health check
./tools/check-gpu-worker.sh

# Real-time GPU monitoring
./tools/monitor-gpu-sharing.sh
```

## Troubleshooting

See [DEPLOYMENT_GUIDE.md](DEPLOYMENT_GUIDE.md#troubleshooting) for detailed troubleshooting steps.

**Common Issues:**
- Services not registering: Check `REGISTRY_URL` and `REGISTRY_SECRET` match between homelab and desktop
- Desktop lag: Configure iGPU fallback or reduce `OLLAMA_NUM_PARALLEL`
- GPU not accessible: Verify NVIDIA Container Toolkit installed
- Port conflicts: Change ports in `.env` files

## Security

**Current Setup:**
- Registry secret authentication
- Nginx basic auth for proxied services
- Network isolation (bridge mode)
- Resource limits

**Production Recommendations:**
- Use strong secrets (not test values)
- Enable HTTPS only (disable HTTP)
- Configure firewall rules
- Enable OAuth2 proxy
- Regular updates and backups

## Architecture Details

### Service Flow

```
User Request
    ↓
Nginx Proxy (homelab:8081)
    ↓
Registry Discovery (/discover)
    ↓
Select GPU Worker (192.168.1.99)
    ↓
Ollama/ComfyUI API
    ↓
GPU Inference
    ↓
Response
```

### GPU Sharing

Docker shares GPU between host and containers via NVIDIA Container Runtime:
- **Time-slicing**: GPU switches between tasks
- **Soft limits**: `OLLAMA_NUM_PARALLEL`, `OLLAMA_MAX_LOADED_MODELS`
- **iGPU fallback**: Configure Xorg to use iGPU for display, dGPU for compute

See [docs/docker-gpu-sharing.md](docs/docker-gpu-sharing.md) for details.

## Contributing

Contributions welcome! Please:
1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Submit a pull request

## License

[Your License Here]

## Support

- Issues: [GitHub Issues]
- Documentation: See `docs/` directory
- Guide: [DEPLOYMENT_GUIDE.md](DEPLOYMENT_GUIDE.md)
- **SSL/TLS Support**: HTTPS access with self-signed certificates.
- **Multi-User Auth**: Basic auth with multiple users and user-specific profiles.
- **Backup & Recovery**: Automated volume backups and restore functionality.
- **Resource Limits**: Configured CPU/memory limits for all services.

## Documentation
- [User Guide](docs/user-guide.md) - Complete usage instructions
- [API Reference](docs/api-reference.md) - Detailed API documentation
- [Troubleshooting](docs/troubleshooting.md) - Common issues and solutions
- CPU-only: Images default to CPU; change `COMFYUI_IMAGE` for GPU.
- SSL: Accept self-signed certificate in browser for HTTPS access.
- Port conflicts: Adjust ports in `.env`.
- Logs: `./manage.sh logs [service]`
- Health: `./manage.sh status` to check status and run health checks.
- RAG Issues: Ensure PDFs are in the ingestion directory; check LangChain logs.
- Code Execution: POST code to /code-executor/ endpoint; limited to Python for security.
- Backup/Restore: Use absolute paths for backup_dir in restore.

## Future Enhancements
- **Model Vault**: Secure Rust-based model management service
  - See `model-vault-context.md` for requirements
  - See `model-vault-integration-plan.md` for integration details
  - Project location: `~/Documents/projects/model-vault`
- GPU support for ComfyUI and Ollama
- Advanced monitoring and alerting
- Multi-user collaboration features
- Model fine-tuning workflows