# Desktop GPU Worker Setup (akula-prime)

## Overview
The desktop GPU worker provides bare-minimum containerized GPU services (Ollama + ComfyUI) that automatically register with the homelab control plane when online. This enables secure, controllable GPU access for AI R&D workloads.

## Architecture

### Current: Docker Container Deployment
- **Services**: Ollama (LLM inference), ComfyUI (image generation)
- **Restart Policy**: `unless-stopped` for easy control
- **Registration**: Automatic on startup via init scripts
- **Security**: Registry secret authentication, network isolation
- **GPU Access**: Direct NVIDIA GPU passthrough via Docker

### Future: Hardened VM with GPU Passthrough
- **Host**: akula-prime falls back to iGPU when VM is running
- **VM**: Hardened VM with dedicated GPU passthrough
- **Isolation**: Enhanced security through virtualization layer
- **Management**: KVM/QEMU with GPU passthrough configuration

## Quick Start

### GPU Sharing Configuration (Important!)

**Docker shares GPU between host and containers by default** - no exclusive lock like VMs.

For best desktop experience while serving GPU workloads, configure iGPU for display:

```bash
# On akula-prime (run as root)
sudo ./tools/configure-igpu-display.sh
```

This configures Xorg to use iGPU for desktop display, leaving dGPU fully available for containers. Result:
- ✅ Smooth desktop performance (iGPU handles display)
- ✅ Full dGPU power for AI workloads (no contention)
- ✅ Seamless operation (no manual switching)

**Don't have iGPU?** The compose file includes resource limits to prevent GPU hogging. See [docs/docker-gpu-sharing.md](docker-gpu-sharing.md) for details.

### Deploy GPU Worker Stack
```bash
# On akula-prime (192.168.1.99)
cd /path/to/comfyui
docker compose -f docker-compose.desktop.yml up -d
```

### Stop GPU Worker Stack
```bash
docker compose -f docker-compose.desktop.yml down
```

### Check Status
```bash
docker compose -f docker-compose.desktop.yml ps
docker logs ollama
docker logs comfyui
```

## Service Registration

Services automatically register with homelab (192.168.1.170:8080) on startup:

**Ollama Registration:**
```json
{
  "service": "ollama",
  "endpoint": "http://192.168.1.99:11434",
  "capabilities": {
    "gpu": true,
    "vram_gb": 24,
    "models_loaded": ["<model list>"]
  }
}
```

**ComfyUI Registration:**
```json
{
  "service": "comfyui",
  "endpoint": "http://192.168.1.99:8188",
  "capabilities": {
    "gpu": true,
    "vram_gb": 24
  }
}
```

## Security Features

### Network Security
- Services only exposed on necessary ports
- Registry communication via secret token (`REGISTRY_SECRET`)
- CORS configured for controlled access

### Authentication
- Registry secret required for service registration
- Model vault token for model access (`MODEL_VAULT_TOKEN`)
- HuggingFace token for gated models (`HF_TOKEN`)

### Resource Limits
- CPU: 2-4 cores per service
- Memory: 4-8GB per service
- GPU: Shared across both services

## Environment Variables

Required variables in `.env.desktop`:
```bash
# Registry Configuration
REGISTRY_URL=https://homelab.lan:8443
REGISTRY_SECRET=<your-secret>

# Worker advertised endpoint (what homelab will call back to)
ADVERTISE_HOST=192.168.1.99
ADVERTISE_SCHEME=http

# Optional mTLS client settings for registry access
# These paths are mounted from ./ssl in docker-compose.desktop.yml
REGISTRY_MTLS_CA=/etc/ssl/registry/ca.pem
REGISTRY_MTLS_CERT=/etc/ssl/registry/clients/gpu-worker.pem
REGISTRY_MTLS_KEY=/etc/ssl/registry/clients/gpu-worker-key.pem

# Model Vault
MODEL_VAULT_URL=http://192.168.1.170:8080
MODEL_VAULT_TOKEN=<your-token>

# HuggingFace (optional)
HF_TOKEN=<your-hf-token>

# Service Ports
OLLAMA_PORT=11434
COMFYUI_PORT=8188

# Models (comma-separated)
OLLAMA_MODELS=gemma3:1b,llama3.1:8b,mistral:7b
```

## VM Setup (Future Enhancement)

### Prerequisites
- KVM/QEMU installed on akula-prime
- IOMMU enabled in BIOS
- GPU in separate IOMMU group

### GPU Passthrough Steps
1. **Identify GPU PCI ID:**
   ```bash
   lspci -nn | grep -i nvidia
   ```

2. **Bind GPU to VFIO:**
   ```bash
   # Add to /etc/modprobe.d/vfio.conf
   options vfio-pci ids=<pci-id>
   
   # Rebuild initramfs
   update-initramfs -u
   ```

3. **Create VM with GPU:**
   ```bash
   # Example libvirt XML snippet
   <hostdev mode='subsystem' type='pci' managed='yes'>
     <source>
       <address domain='0x0000' bus='0x01' slot='0x00' function='0x0'/>
     </source>
   </hostdev>
   ```

4. **Configure Host Display:**
   - BIOS: Set primary display to iGPU
   - Or use dynamic switching via scripts

5. **Deploy Docker in VM:**
   - Install Docker in VM
   - Copy docker-compose.desktop.yml
   - Set up GPU drivers in VM
   - Deploy stack normally

### Benefits of VM Approach
- **Isolation**: Complete separation from host system
- **Security**: Hardened VM with minimal attack surface
- **Flexibility**: Easy snapshots, backups, migrations
- **Resource Management**: Better control over GPU allocation
- **Multi-tenancy**: Can run multiple isolated workers

### Considerations
- Performance overhead (~5-10% for GPU workloads)
- More complex setup and maintenance
- Requires dedicated GPU or dynamic switching
- Host display management when GPU passed through

## Troubleshooting

### Desktop Lagging While Containers Running

**Cause**: Containers using too much GPU, impacting desktop performance.

**Solutions**:

1. **Best: Configure iGPU for display** (if available)
   ```bash
   sudo ./tools/configure-igpu-display.sh
   ```

2. **Alternative: Reduce container GPU usage**
   ```bash
   # Edit .env.desktop
   OLLAMA_NUM_PARALLEL=1          # Reduce concurrent requests
   OLLAMA_MAX_LOADED_MODELS=1     # Load fewer models
   
   # Redeploy
   docker compose -f docker-compose.desktop.yml down
   docker compose -f docker-compose.desktop.yml up -d
   ```

3. **Monitor GPU usage**
   ```bash
   ./tools/monitor-gpu-sharing.sh
   ```

See [docs/docker-gpu-sharing.md](docker-gpu-sharing.md) for detailed GPU sharing configuration.

### Services Not Registering
```bash
# Check registry connectivity
curl http://192.168.1.170:8080/discover

# Check container logs
docker logs ollama 2>&1 | grep -i "register"
docker logs comfyui 2>&1 | grep -i "register"

# Verify environment variables
docker exec ollama env | grep REGISTRY
```

### GPU Not Accessible
```bash
# Check GPU visibility
docker exec ollama nvidia-smi

# Verify GPU deployment in compose file
docker inspect ollama | grep -A 10 DeviceRequests
```

### Port Conflicts
```bash
# Check what's using ports
sudo netstat -tlnp | grep -E "11434|8188"

# Change ports in .env.desktop
OLLAMA_PORT=11435
COMFYUI_PORT=8189
```

## Management Scripts

### Quick Deploy
```bash
#!/bin/bash
# deploy-gpu-worker.sh
cd /path/to/comfyui
docker compose -f docker-compose.desktop.yml up -d
echo "GPU worker deployed. Check status with: docker compose -f docker-compose.desktop.yml ps"
```

### Quick Teardown
```bash
#!/bin/bash
# teardown-gpu-worker.sh
cd /path/to/comfyui
docker compose -f docker-compose.desktop.yml down
echo "GPU worker stopped. Volumes preserved."
```

### Health Check
```bash
#!/bin/bash
# check-gpu-worker.sh
echo "=== GPU Worker Status ==="
docker compose -f docker-compose.desktop.yml ps
echo ""
echo "=== Registry Discovery ==="
curl -s http://192.168.1.170:8080/discover | jq
echo ""
echo "=== GPU Status ==="
docker exec ollama nvidia-smi --query-gpu=name,utilization.gpu,memory.used,memory.total --format=csv
```

## Network Diagram

```
┌─────────────────────────────────────────┐
│ Homelab Control Plane (192.168.1.170)  │
│  ┌──────────────┐  ┌─────────────────┐ │
│  │ Model Vault  │  │ Nginx Proxy     │ │
│  │ (Registry)   │◄─┤ /register       │ │
│  │ :8080        │  │ /discover       │ │
│  └──────────────┘  └─────────────────┘ │
└─────────────┬───────────────────────────┘
              │ LAN (192.168.1.0/24)
              │
┌─────────────▼───────────────────────────┐
│ Desktop GPU Worker (192.168.1.99)       │
│  ┌──────────────┐  ┌─────────────────┐ │
│  │ Ollama       │  │ ComfyUI         │ │
│  │ :11434       │  │ :8188           │ │
│  │ (24GB VRAM)  │  │ (GPU Enabled)   │ │
│  └──────────────┘  └─────────────────┘ │
│         │ Auto-register on startup      │
│         └───────────────────────────────┤
│  ┌─────────────────────────────────────┐│
│  │ NVIDIA GPU (Shared)                 ││
│  └─────────────────────────────────────┘│
└─────────────────────────────────────────┘
```

## Maintenance

### Model Updates
```bash
# Pull new models
docker exec ollama ollama pull llama3.2:3b

# Verify models
docker exec ollama ollama list
```

### Log Rotation
```bash
# Configure in /etc/docker/daemon.json
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}
```

### Backup Volumes
```bash
# Backup Ollama models
docker run --rm -v ollama_data:/data -v $(pwd):/backup ubuntu tar czf /backup/ollama-backup.tar.gz /data

# Backup ComfyUI outputs
docker run --rm -v comfyui_outputs:/data -v $(pwd):/backup ubuntu tar czf /backup/comfyui-backup.tar.gz /data
```

## Integration with Homelab

The GPU worker integrates with homelab services:
- **Discovery**: Homelab queries `/discover?service=ollama` to find available workers
- **Load Balancing**: Nginx routes requests based on GPU availability
- **Failover**: Multiple workers can register for redundancy
- **Monitoring**: Homelab tracks worker health via registry heartbeats

## References
- [Docker GPU Support](https://docs.docker.com/config/containers/resource_constraints/#gpu)
- [NVIDIA Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/install-guide.html)
- [KVM GPU Passthrough](https://wiki.archlinux.org/title/PCI_passthrough_via_OVMF)
- [VFIO Configuration](https://wiki.debian.org/VGAPassthrough)
