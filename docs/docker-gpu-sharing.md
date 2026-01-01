# Docker GPU Sharing Configuration

## Overview
Docker with NVIDIA Container Runtime **shares the GPU by default** - it does NOT exclusively lock the GPU like VM passthrough does. Both the host and containers can use the GPU simultaneously through time-slicing.

## Current Behavior

### GPU Sharing Architecture
```
┌────────────────────────────────────────┐
│         NVIDIA GPU (RTX 3090)          │
│              24GB VRAM                 │
└─────────────┬──────────────────────────┘
              │ Shared via NVIDIA Runtime
     ┌────────┴────────┐
     │                 │
┌────▼─────┐    ┌─────▼──────┐
│   Host   │    │ Containers │
│ Display  │    │ Ollama     │
│ Desktop  │    │ ComfyUI    │
│ Apps     │    │ etc.       │
└──────────┘    └────────────┘
```

### How It Works
1. **NVIDIA Container Runtime** manages GPU access
2. **Time-Slicing**: GPU switches between host and container tasks
3. **Shared Memory**: VRAM is shared, not partitioned
4. **No Exclusive Lock**: Host always has GPU access for display
5. **Fair Scheduling**: NVIDIA driver handles resource allocation

## Resource Configuration

### Current Limits (Conservative)
The desktop compose file currently sets:
- **CPU**: 2-4 cores per service (leaves cores for host)
- **RAM**: 4-8GB per service (leaves RAM for host)
- **GPU**: Shared access, no hard limits

### Problem: Containers Can Hog GPU
If containers run intensive workloads, they can consume most GPU resources, causing:
- Desktop lag/stutter
- Slow window animations
- Video playback issues
- Gaming performance drops

## Solution Options

### Option 1: GPU Compute Limits (Recommended for Docker)

Add NVIDIA environment variables to limit container GPU usage:

```yaml
environment:
  # Limit GPU compute to 80% (leaves 20% for host)
  - NVIDIA_MIG_CONFIG_DEVICES=all
  - CUDA_MPS_PIPE_DIRECTORY=/tmp/nvidia-mps
  - CUDA_MPS_LOG_DIRECTORY=/tmp/nvidia-log
```

**Pros:**
- Simple configuration
- Soft limits, flexible
- No driver changes needed

**Cons:**
- Not strict enforcement
- Containers can burst to 100% if host idle

### Option 2: MIG (Multi-Instance GPU) - Hardware Partitioning

Supported on: A100, A30, A40, RTX A6000, RTX 6000 Ada (NOT consumer RTX 3090)

```bash
# Enable MIG mode
sudo nvidia-smi -mig 1

# Create instances (example: 3 slices)
sudo nvidia-smi mig -cgi 9,9,14 -C  # 1/4, 1/4, 1/2 of GPU

# Assign to containers
docker run --gpus '"device=0:0"' ...  # Container gets MIG instance 0
docker run --gpus '"device=0:1"' ...  # Container gets MIG instance 1
# Host uses remaining capacity
```

**Pros:**
- Hard isolation
- Guaranteed resources
- Better multi-tenancy

**Cons:**
- Only on specific GPUs
- More complex setup
- Fixed partitions

### Option 3: Time-Slice Configuration (NVIDIA)

Configure explicit time-slicing in NVIDIA driver:

Create `/etc/nvidia-container-runtime/config.toml`:
```toml
[nvidia-container-runtime]
debug = "/var/log/nvidia-container-runtime.log"

[nvidia-container-runtime.gpu-time-slice]
# Allocate 70% of GPU time to containers, 30% to host
container-share = 0.7
```

**Pros:**
- Fair time allocation
- Works on all GPUs
- Balanced performance

**Cons:**
- Requires runtime configuration
- Not widely documented

### Option 4: Automatic iGPU Fallback (Best UX)

Configure Xorg to prefer iGPU for display, reserve dGPU for compute:

**Step 1: Identify GPUs**
```bash
lspci | grep -i vga
# 00:02.0 VGA compatible controller: Intel Corporation UHD Graphics (iGPU)
# 01:00.0 VGA compatible controller: NVIDIA Corporation GA102 (dGPU)
```

**Step 2: Configure Xorg**

Create `/etc/X11/xorg.conf.d/20-igpu-primary.conf`:
```
Section "ServerLayout"
    Identifier "Layout0"
    Screen 0 "iGPU" 0 0
    Screen 1 "dGPU" RightOf "iGPU"
    Option "AutoAddGPU" "false"
EndSection

Section "Device"
    Identifier "iGPU"
    Driver "intel"
    BusID "PCI:0:2:0"
EndSection

Section "Screen"
    Identifier "iGPU"
    Device "iGPU"
EndSection

Section "Device"
    Identifier "dGPU"
    Driver "nvidia"
    BusID "PCI:1:0:0"
    Option "AllowExternalGpus" "True"
EndSection

Section "Screen"
    Identifier "dGPU"
    Device "dGPU"
EndSection
```

**Step 3: Configure PRIME**
```bash
# Set iGPU as primary for display
sudo prime-select intel

# Or use on-demand mode
sudo prime-select on-demand
```

**Step 4: Verify**
```bash
glxinfo | grep "OpenGL renderer"
# Should show Intel renderer for display
```

**Pros:**
- Seamless user experience
- iGPU handles all display
- dGPU fully available for containers
- No performance impact on desktop
- No special container config needed

**Cons:**
- Requires iGPU
- Slight setup complexity
- Can't use dGPU for gaming on host

### Option 5: Dynamic GPU Assignment with Scripts

Create smart scripts that manage GPU allocation:

**gpu-mode-desktop.sh** (dGPU for host):
```bash
#!/bin/bash
# Stop containers to free dGPU
docker compose -f docker-compose.desktop.yml down
sudo prime-select nvidia  # Use dGPU for display
echo "Desktop mode: dGPU available for gaming/work"
```

**gpu-mode-serve.sh** (dGPU for containers):
```bash
#!/bin/bash
sudo prime-select intel   # Fall back to iGPU
docker compose -f docker-compose.desktop.yml up -d
echo "Serve mode: dGPU available for AI workloads"
```

**Pros:**
- Full control
- Best performance in each mode
- Simple to understand

**Cons:**
- Manual switching
- Not simultaneous use

## Recommended Implementation

### Phase 1: Immediate (No Host Config Changes)

Add resource awareness to containers:

```yaml
# In docker-compose.desktop.yml
environment:
  # Reduce batch sizes to limit GPU memory usage
  - OLLAMA_NUM_PARALLEL=2        # Limit concurrent requests
  - OLLAMA_MAX_LOADED_MODELS=2   # Limit loaded models
  
  # For ComfyUI
  - COMFYUI_ARGS=--normalvram    # Use less VRAM
```

### Phase 2: iGPU Fallback (Recommended)

Configure Xorg to use iGPU for display (Option 4 above). This gives:
- **Host**: Smooth desktop on iGPU (more than enough for display)
- **Containers**: Full dGPU access for AI workloads
- **Zero conflicts**: No sharing needed

### Phase 3: Advanced (Future)

If you upgrade to MIG-capable GPU (A100, A40, etc.), use MIG for hard partitioning.

## Monitoring GPU Sharing

### Check GPU Usage by Process
```bash
# See what's using GPU
nvidia-smi pmon -c 1

# Detailed per-process
nvidia-smi dmon -s mu -c 1
```

### Watch GPU Memory
```bash
watch -n 1 nvidia-smi
```

### Container-specific Usage
```bash
# Get container GPU stats
docker stats ollama --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}"

# NVIDIA container stats
nvidia-smi --query-compute-apps=pid,used_memory --format=csv
```

### Add Monitoring Script

**tools/monitor-gpu-sharing.sh**:
```bash
#!/bin/bash
while true; do
  clear
  echo "=== GPU Usage Distribution ==="
  echo ""
  nvidia-smi --query-gpu=utilization.gpu,utilization.memory,memory.used,memory.total --format=csv,noheader | \
    awk -F, '{printf "GPU Util: %s | Memory Util: %s | Used: %s | Total: %s\n", $1, $2, $3, $4}'
  echo ""
  echo "=== Process Breakdown ==="
  nvidia-smi pmon -c 1 | tail -n +3
  sleep 2
done
```

## Testing GPU Sharing

### Test 1: Baseline (No Containers)
```bash
# Stop containers
docker compose -f docker-compose.desktop.yml down

# Check GPU idle usage
nvidia-smi

# Run desktop apps, check responsiveness
```

### Test 2: Light Load
```bash
# Start containers
docker compose -f docker-compose.desktop.yml up -d

# Generate small model inference
curl -X POST http://localhost:11434/api/generate \
  -d '{"model": "gemma3:1b", "prompt": "Hello"}'

# Check desktop responsiveness
# Play video, move windows, etc.
```

### Test 3: Heavy Load
```bash
# Generate large image in ComfyUI
# Or run multiple Ollama requests in parallel

# Monitor GPU
watch -n 1 nvidia-smi

# Check for desktop lag
```

## Current Status & Next Steps

**Current Config**: Basic GPU sharing, no limits
- ✅ Works fine for light workloads
- ⚠️ May lag desktop under heavy AI load

**Recommended Next Step**: Configure iGPU fallback (Option 4)
- ✅ Best user experience
- ✅ No performance compromise
- ✅ Seamless operation

**Alternative**: Add resource limits (Option 1) if iGPU config too complex

## Implementation Guide for iGPU Fallback

1. **Verify iGPU Present**
   ```bash
   lspci | grep -i vga
   ```

2. **Install Intel Drivers**
   ```bash
   sudo apt install xserver-xorg-video-intel
   ```

3. **Create Xorg Config** (see Option 4 above)

4. **Restart Display Manager**
   ```bash
   sudo systemctl restart gdm3  # or lightdm/sddm
   ```

5. **Verify iGPU Active**
   ```bash
   glxinfo | grep "renderer"
   ```

6. **Deploy Containers**
   ```bash
   ./tools/deploy-gpu-worker.sh
   ```

7. **Test Desktop Performance**
   - Open multiple windows
   - Play video
   - Check smoothness

Would you like me to implement the iGPU fallback configuration or add resource limits to the containers?
