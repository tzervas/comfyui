# Dual-Host AI Stack Deployment Guide

## Overview
This guide covers the complete deployment of a dual-host AI infrastructure with GPU workers on a desktop (akula-prime) and control plane services on a homelab server.

**Architecture:**
- **Homelab (192.168.1.170)**: Control plane with model registry, nginx proxy, AI frameworks
- **Desktop (192.168.1.99)**: GPU worker with Ollama and ComfyUI

## Prerequisites

### Hardware Requirements
- **Homelab Server**: 
  - 4+ CPU cores
  - 8GB+ RAM
  - Network connectivity
  
- **Desktop (GPU Worker)**:
  - NVIDIA GPU (tested with RTX 5080, 16GB VRAM)
  - 8+ CPU cores
  - 16GB+ RAM
  - Docker with NVIDIA Container Runtime
  - Optional: iGPU for display fallback

### Software Requirements
- Docker Engine 20.10+
- Docker Compose v2
- Git
- rsync (for syncing)
- NVIDIA drivers (on GPU worker)
- NVIDIA Container Toolkit (on GPU worker)

## Initial Setup

### 1. Clone Repository (on both hosts)

```bash
# On homelab
git clone <repo-url> ~/comfyui
cd ~/comfyui

# On desktop (or use rsync from homelab)
git clone <repo-url> ~/comfyui
cd ~/comfyui
```

### 2. Configure Environment Variables

**On Homelab** (`~comfyui/.env.homelab`):
```bash
# Nginx Ports
NGINX_HTTP_PORT=8081
NGINX_HTTPS_PORT=8444

# Authentication (set strong values in production)
MODEL_VAULT_TOKEN=your_secure_model_vault_token_here
REGISTRY_SECRET=your_secure_registry_secret_here

# OAuth2 (optional, for user auth)
OAUTH2_PROXY_CLIENT_ID=your_oauth_client_id
OAUTH2_PROXY_CLIENT_SECRET=your_oauth_client_secret
OAUTH2_PROXY_COOKIE_SECRET=your_cookie_secret

# HuggingFace (optional, for gated models)
HF_TOKEN=your_hf_token
```

**On Desktop** (`~/comfyui/.env.desktop`):
```bash
# Service Ports
OLLAMA_PORT=11434
COMFYUI_PORT=8188

# Ollama Configuration
OLLAMA_ORIGINS=http://192.168.1.170  # Homelab IP
OLLAMA_MODELS=gemma3:1b,deepseek-r1:1.5b,smollm2:1.7b,llama3.1:8b,mistral:7b

# GPU Resource Limits (to prevent hogging)
OLLAMA_NUM_PARALLEL=2
OLLAMA_MAX_LOADED_MODELS=2

# ComfyUI Configuration
COMFYUI_IMAGE=ghcr.io/ai-dock/comfyui:latest
COMFYUI_EXTRA_ARGS=--normalvram

# Registry Configuration (must match homelab)
REGISTRY_URL=http://192.168.1.170:8081
REGISTRY_SECRET=your_secure_registry_secret_here
MODEL_VAULT_TOKEN=your_secure_model_vault_token_here

# HuggingFace (optional)
HF_TOKEN=your_hf_token

# GPU Driver
GPU_DRIVER=nvidia
```

### 3. Generate SSL Certificates (Homelab)

```bash
cd ~/comfyui
mkdir -p ssl
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout ssl/key.pem \
  -out ssl/cert.pem \
  -subj "/CN=homelab.local"
```

### 4. Create Nginx Basic Auth (Homelab)

```bash
# Install htpasswd if not present
sudo apt install apache2-utils

# Create user (replace 'admin' with your username)
htpasswd -c ~/comfyui/.htpasswd admin
```

## Deployment

### Phase 1: Deploy Homelab Control Plane

```bash
# On homelab (192.168.1.170)
cd ~/comfyui

# Start services
docker compose -f docker-compose.homelab.yml up -d

# Wait for services to initialize (30-60 seconds)
sleep 30

# Check status
docker compose -f docker-compose.homelab.yml ps

# Verify model-vault registry
curl -s http://localhost:8081/discover | jq

# Expected output: []  (no services registered yet)
```

**Services Started:**
- `model-vault`: Service registry on port 8080 (internal)
- `nginx`: Reverse proxy on ports 8081 (HTTP) and 8444 (HTTPS)
- `langchain`: AI framework on port 8000
- `code_executor`: Code execution service on port 5000
- `langflow`: Workflow builder on port 7860
- `oauth2-proxy`: Authentication proxy

### Phase 2: Deploy Desktop GPU Worker

#### Option A: Automatic Deployment (Recommended)

```bash
# On desktop (192.168.1.99)
cd ~/comfyui

# Run deployment script
./tools/deploy-gpu-worker.sh
```

#### Option B: Manual Deployment

```bash
# On desktop
cd ~/comfyui

# Build and start services
docker compose -f docker-compose.desktop.yml build
docker compose -f docker-compose.desktop.yml up -d

# Check status
docker compose -f docker-compose.desktop.yml ps

# Verify GPU access
docker exec ollama nvidia-smi
```

**Services Started:**
- `ollama`: LLM inference on port 11434
- `comfyui`: Image generation on port 8188

### Phase 3: Configure iGPU Display Fallback (Optional but Recommended)

If your desktop has integrated GPU, configure it for display to free up dGPU for containers:

```bash
# On desktop (requires sudo)
sudo ./tools/configure-igpu-display.sh

# Follow prompts to restart display manager
# After restart, verify:
glxinfo | grep "OpenGL renderer"
# Should show: Intel (or your iGPU model)
```

**Benefits:**
- Desktop runs smoothly on iGPU
- Full dGPU power for AI workloads
- No performance conflicts

### Phase 4: Register Services (Manual if Auto-Registration Fails)

The init scripts should automatically register services. If they don't:

```bash
# From homelab, manually register ollama
curl -X POST http://localhost:8081/register \
  -H "Content-Type: application/json" \
  -d '{
    "service": "ollama",
    "endpoint": "http://192.168.1.99:11434",
    "capabilities": {
      "gpu": true,
      "models": ["gemma3:1b", "llama3.1:8b"]
    }
  }'

# Manually register comfyui
curl -X POST http://localhost:8081/register \
  -H "Content-Type: application/json" \
  -d '{
    "service": "comfyui",
    "endpoint": "http://192.168.1.99:8188",
    "capabilities": {
      "gpu": true,
      "vram_gb": 16
    }
  }'
```

### Phase 5: Verify Integration

```bash
# Discover registered services
curl -s http://192.168.1.170:8081/discover | jq

# Expected output:
# [
#   {
#     "id": 1,
#     "name": "ollama",
#     "url": "http://192.168.1.99:11434",
#     "capabilities": {...},
#     "status": "active"
#   },
#   {
#     "id": 2,
#     "name": "comfyui",
#     "url": "http://192.168.1.99:8188",
#     "capabilities": {...},
#     "status": "active"
#   }
# ]

# Test ollama inference via desktop
curl -X POST http://192.168.1.99:11434/api/generate \
  -d '{"model": "gemma3:1b", "prompt": "Hello", "stream": false}' | jq -r '.response'

# Check GPU usage on desktop
ssh user@192.168.1.99 "docker exec ollama nvidia-smi"
```

## Usage

### Accessing Services

**From Homelab LAN:**

- **Ollama API**: `http://192.168.1.99:11434`
- **ComfyUI UI**: `http://192.168.1.99:8188`
- **Registry API**: `http://192.168.1.170:8081/discover`
- **Nginx Proxy**: `http://192.168.1.170:8081` (HTTP) or `https://192.168.1.170:8444` (HTTPS)
- **LangChain API**: `http://192.168.1.170:8000`
- **Code Executor**: `http://192.168.1.170:5000`
- **LangFlow UI**: `http://192.168.1.170:7860`

**Via Nginx Proxy (with auth):**

```bash
# Ollama via proxy (requires .htpasswd auth)
curl -u admin:password http://192.168.1.170:8081/ollama/api/tags

# ComfyUI via proxy (requires auth)
# Open in browser: http://192.168.1.170:8081/comfyui/
```

### Discovering Available GPU Workers

```bash
# Find all GPU workers
curl -s http://192.168.1.170:8081/discover?service=ollama | jq

# Filter by capabilities
curl -s http://192.168.1.170:8081/discover | jq '.[] | select(.capabilities.gpu == true)'
```

### Running AI Workloads

**LLM Inference (Ollama):**

```bash
# Simple generation
curl -X POST http://192.168.1.99:11434/api/generate \
  -d '{
    "model": "gemma3:1b",
    "prompt": "Explain quantum computing",
    "stream": false
  }' | jq -r '.response'

# Chat completion
curl -X POST http://192.168.1.99:11434/api/chat \
  -d '{
    "model": "llama3.1:8b",
    "messages": [
      {"role": "user", "content": "What is Docker?"}
    ]
  }'
```

**Image Generation (ComfyUI):**

Open `http://192.168.1.99:8188` in browser and use the web UI.

### Managing GPU Worker

**Start/Stop Services:**

```bash
# On desktop
cd ~/comfyui

# Stop services
./tools/teardown-gpu-worker.sh

# Start services
./tools/deploy-gpu-worker.sh

# Check health
./tools/check-gpu-worker.sh
```

**Monitor GPU Sharing:**

```bash
# On desktop
./tools/monitor-gpu-sharing.sh

# Shows:
# - GPU utilization
# - Memory usage
# - Process breakdown (host vs containers)
# - Performance warnings
```

## Monitoring

### Health Checks

**Homelab Services:**

```bash
# Check all services
docker compose -f docker-compose.homelab.yml ps

# Check specific service logs
docker logs model-vault
docker logs nginx
docker logs langchain

# Check registry health
curl -s http://localhost:8081/discover | jq length
```

**Desktop Services:**

```bash
# Via SSH from homelab
ssh user@192.168.1.99 "docker ps --format 'table {{.Names}}\t{{.Status}}'"

# Check ollama health
ssh user@192.168.1.99 "docker exec ollama curl -s http://localhost:11434/api/tags | jq -r '.models[].name'"

# Check GPU
ssh user@192.168.1.99 "docker exec ollama nvidia-smi"
```

### Performance Monitoring

**GPU Utilization:**

```bash
# Real-time GPU monitoring on desktop
ssh user@192.168.1.99 "watch -n 1 docker exec ollama nvidia-smi"

# Or use monitoring script
ssh user@192.168.1.99 "cd ~/comfyui && ./tools/monitor-gpu-sharing.sh"
```

**Container Resource Usage:**

```bash
# On desktop
docker stats ollama comfyui --no-stream

# On homelab
docker stats model-vault nginx langchain --no-stream
```

## Troubleshooting

### Services Not Registering

**Symptom**: `/discover` returns empty array

**Solutions**:
1. Check environment variables on desktop:
   ```bash
   ssh user@192.168.1.99 "docker exec ollama env | grep REGISTRY"
   ```

2. Verify registry connectivity:
   ```bash
   ssh user@192.168.1.99 "curl -v http://192.168.1.170:8081/discover"
   ```

3. Check init script logs:
   ```bash
   ssh user@192.168.1.99 "docker logs ollama 2>&1 | grep -i register"
   ```

4. Manually register (see Phase 4 above)

### Desktop Lagging While Containers Running

**Symptom**: Desktop UI slow, videos stutter

**Solutions**:

1. **Best**: Configure iGPU display fallback (see Phase 3)

2. **Reduce container GPU usage**:
   Edit `.env.desktop`:
   ```bash
   OLLAMA_NUM_PARALLEL=1
   OLLAMA_MAX_LOADED_MODELS=1
   ```
   Redeploy:
   ```bash
   docker compose -f docker-compose.desktop.yml down
   docker compose -f docker-compose.desktop.yml up -d
   ```

3. **Monitor GPU sharing**:
   ```bash
   ./tools/monitor-gpu-sharing.sh
   ```

### GPU Not Accessible in Containers

**Symptom**: `nvidia-smi` fails in container

**Solutions**:

1. Verify NVIDIA Container Toolkit installed:
   ```bash
   docker run --rm --gpus all nvidia/cuda:11.8.0-base-ubuntu22.04 nvidia-smi
   ```

2. Check Docker daemon config (`/etc/docker/daemon.json`):
   ```json
   {
     "runtimes": {
       "nvidia": {
         "path": "nvidia-container-runtime",
         "runtimeArgs": []
       }
     }
   }
   ```

3. Restart Docker:
   ```bash
   sudo systemctl restart docker
   ```

### Nginx Proxy Not Working

**Symptom**: 404 or connection refused via proxy

**Solutions**:

1. Check nginx config:
   ```bash
   docker exec nginx nginx -t
   ```

2. Verify upstreams reachable:
   ```bash
   docker exec nginx ping -c 1 model-vault
   docker exec nginx curl -s http://model-vault:8080/health
   ```

3. Check nginx logs:
   ```bash
   docker logs nginx
   ```

### Ports Already in Use

**Symptom**: "port is already allocated"

**Solutions**:

1. Find what's using the port:
   ```bash
   sudo netstat -tlnp | grep <port>
   ```

2. Change port in `.env` file and redeploy

3. Or stop conflicting service

### Model Downloads Failing

**Symptom**: Ollama can't pull models

**Solutions**:

1. Check internet connectivity:
   ```bash
   docker exec ollama curl -I https://ollama.com
   ```

2. Set proxy if needed (in `.env.desktop`):
   ```bash
   HTTPS_PROXY=http://proxy.example.com:8080
   ```

3. Try pulling manually:
   ```bash
   docker exec ollama ollama pull gemma3:1b
   ```

4. Check available disk space:
   ```bash
   docker exec ollama df -h /root/.ollama
   ```

## Maintenance

### Updating Services

**Homelab:**

```bash
cd ~/comfyui
git pull
docker compose -f docker-compose.homelab.yml pull
docker compose -f docker-compose.homelab.yml up -d
```

**Desktop:**

```bash
# Sync from homelab
rsync -avz homelab:~/comfyui/ ~/comfyui/

# Or git pull if it's a git repo
git pull

# Rebuild and redeploy
docker compose -f docker-compose.desktop.yml pull
docker compose -f docker-compose.desktop.yml build
docker compose -f docker-compose.desktop.yml up -d
```

### Backup

**Ollama Models:**

```bash
docker run --rm \
  -v comfyui-ollama_ollama_data:/data \
  -v $(pwd):/backup \
  ubuntu tar czf /backup/ollama-models-$(date +%Y%m%d).tar.gz /data
```

**ComfyUI Outputs:**

```bash
docker run --rm \
  -v comfyui-ollama_comfyui_outputs:/data \
  -v $(pwd):/backup \
  ubuntu tar czf /backup/comfyui-outputs-$(date +%Y%m%d).tar.gz /data
```

**Registry Database:**

```bash
docker run --rm \
  -v comfyui-ollama_model_vault_data:/data \
  -v $(pwd):/backup \
  ubuntu tar czf /backup/registry-db-$(date +%Y%m%d).tar.gz /data
```

### Log Rotation

Configure in `/etc/docker/daemon.json`:

```json
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}
```

Then restart Docker:
```bash
sudo systemctl restart docker
```

### Cleaning Up

**Remove Stopped Containers:**

```bash
docker compose -f docker-compose.homelab.yml down
docker compose -f docker-compose.desktop.yml down
```

**Remove Volumes (WARNING: deletes data):**

```bash
docker compose -f docker-compose.homelab.yml down -v
docker compose -f docker-compose.desktop.yml down -v
```

**Remove Unused Images:**

```bash
docker image prune -a
```

## Security Considerations

### Current Configuration
- ✅ Registry secret authentication
- ✅ Basic auth on nginx proxy
- ✅ Resource limits on containers
- ✅ Network isolation (bridge mode)
- ✅ CORS restrictions on Ollama

### Recommendations for Production

1. **Change default secrets** in `.env` files
2. **Enable HTTPS only** (disable HTTP on nginx)
3. **Use firewall rules** to restrict access:
   ```bash
   # On homelab
   sudo ufw allow from 192.168.1.0/24 to any port 8081
   sudo ufw allow from 192.168.1.0/24 to any port 8444
   
   # On desktop
   sudo ufw allow from 192.168.1.170 to any port 11434
   sudo ufw allow from 192.168.1.170 to any port 8188
   ```

4. **Enable OAuth2 proxy** for user authentication
5. **Regular updates** of base images and dependencies
6. **Monitor logs** for suspicious activity
7. **Backup regularly** (see Maintenance section)

## Advanced Configuration

### Adding More GPU Workers

Repeat Phase 2 on additional desktops, using unique IPs. They'll automatically register with the homelab registry.

### Load Balancing

Nginx can be configured to load balance across multiple GPU workers:

```nginx
upstream ollama_backend {
    server 192.168.1.99:11434;
    server 192.168.1.100:11434;  # Additional worker
    server 192.168.1.101:11434;  # Additional worker
    keepalive 32;
}
```

### Custom Models

**Add to Ollama:**

```bash
# On desktop
docker exec ollama ollama pull your-model-name

# Or set in .env.desktop
OLLAMA_MODELS=gemma3:1b,your-model-name
```

**Add to ComfyUI:**

Download models to `comfyui_models` volume or use ComfyUI Manager UI.

## Quick Reference

### Essential Commands

```bash
# Homelab: Start services
docker compose -f docker-compose.homelab.yml up -d

# Homelab: Stop services
docker compose -f docker-compose.homelab.yml down

# Homelab: Check status
docker compose -f docker-compose.homelab.yml ps

# Desktop: Deploy GPU worker
./tools/deploy-gpu-worker.sh

# Desktop: Stop GPU worker
./tools/teardown-gpu-worker.sh

# Desktop: Health check
./tools/check-gpu-worker.sh

# Desktop: Monitor GPU
./tools/monitor-gpu-sharing.sh

# Discover services
curl -s http://192.168.1.170:8081/discover | jq

# Test Ollama
curl -X POST http://192.168.1.99:11434/api/generate \
  -d '{"model": "gemma3:1b", "prompt": "Hello", "stream": false}'
```

### Important Files

- `docker-compose.homelab.yml` - Homelab service definitions
- `docker-compose.desktop.yml` - Desktop GPU worker definitions
- `.env.homelab` - Homelab environment variables
- `.env.desktop` - Desktop environment variables
- `nginx.conf` - Nginx proxy configuration
- `config/model-vault.yaml` - Registry configuration
- `.htpasswd` - Nginx basic auth credentials

### Ports Reference

| Service | Host | Internal | External |
|---------|------|----------|----------|
| Nginx HTTP | Homelab | 80 | 8081 |
| Nginx HTTPS | Homelab | 443 | 8444 |
| Model Vault | Homelab | 8080 | - |
| LangChain | Homelab | 8000 | 8000 |
| Code Executor | Homelab | 5000 | 5000 |
| LangFlow | Homelab | 7860 | 7860 |
| Ollama | Desktop | 11434 | 11434 |
| ComfyUI | Desktop | 18188 | 8188 |

## Support

For issues, questions, or contributions:
- Check [docs/troubleshooting.md](troubleshooting.md)
- Review [docs/docker-gpu-sharing.md](docker-gpu-sharing.md) for GPU config
- See [docs/vm-gpu-passthrough-setup.md](vm-gpu-passthrough-setup.md) for VM approach

## Next Steps

After successful deployment:
1. Explore ComfyUI workflows at `http://192.168.1.99:8188`
2. Test different Ollama models
3. Configure iGPU fallback for better desktop performance
4. Set up automated backups
5. Implement proper authentication (OAuth2)
6. Add monitoring and alerting
7. Scale with additional GPU workers
