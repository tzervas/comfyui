#!/bin/bash
# Monitor GPU sharing between host and containers
# Shows real-time GPU utilization breakdown

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Check if nvidia-smi is available
if ! command -v nvidia-smi &> /dev/null; then
    echo "❌ nvidia-smi not found. Is NVIDIA driver installed?"
    exit 1
fi

echo "🎮 GPU Sharing Monitor"
echo "Press Ctrl+C to exit"
echo ""

while true; do
    clear
    echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}          GPU Sharing Monitor (akula-prime)          ${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
    echo ""
    
    # Overall GPU stats
    echo -e "${GREEN}📊 Overall GPU Usage:${NC}"
    nvidia-smi --query-gpu=name,utilization.gpu,utilization.memory,memory.used,memory.total,temperature.gpu,power.draw --format=csv,noheader | \
    while IFS=',' read -r name gpu_util mem_util mem_used mem_total temp power; do
        echo "   GPU: $name"
        echo "   Compute: $gpu_util | Memory Util: $mem_util"
        echo "   VRAM: $mem_used / $mem_total"
        echo "   Temp: $temp | Power: $power"
    done
    echo ""
    
    # Process breakdown
    echo -e "${YELLOW}🔍 Process Breakdown:${NC}"
    echo "   PID    | Type   | GPU Util | Mem (MiB) | Process Name"
    echo "   -------|--------|----------|-----------|-------------"
    
    # Get processes using GPU
    nvidia-smi --query-compute-apps=pid,process_name,used_memory --format=csv,noheader 2>/dev/null | \
    while IFS=',' read -r pid pname mem; do
        # Identify if process is from container or host
        if docker ps --quiet | xargs -I {} docker top {} -o pid,comm 2>/dev/null | grep -q "^$pid"; then
            ptype="${GREEN}[CONT]${NC}"
        else
            ptype="${BLUE}[HOST]${NC}"
        fi
        
        # Get GPU utilization for this process (approximate from pmon)
        gpu_util=$(nvidia-smi pmon -c 1 | grep "^$pid" | awk '{print $5}' || echo "N/A")
        
        printf "   %-6s | %b | %-8s | %-9s | %s\n" "$pid" "$ptype" "$gpu_util%" "$mem" "$pname"
    done
    echo ""
    
    # Container stats
    echo -e "${GREEN}🐳 Container GPU Usage:${NC}"
    if docker ps --filter "name=ollama" --filter "name=comfyui" --format "{{.Names}}" | grep -q .; then
        for container in $(docker ps --filter "name=ollama" --filter "name=comfyui" --format "{{.Names}}"); do
            if docker ps --filter "name=$container" --format "{{.Names}}" | grep -q .; then
                # Get PIDs for container processes using GPU
                container_pids=$(docker top $container -o pid 2>/dev/null | tail -n +2)
                gpu_mem=0
                
                # Sum GPU memory for all container processes
                for pid in $container_pids; do
                    pid_mem=$(nvidia-smi --query-compute-apps=pid,used_memory --format=csv,noheader 2>/dev/null | grep "^$pid" | awk -F',' '{print $2}' | grep -oE '[0-9]+' || echo "0")
                    gpu_mem=$((gpu_mem + pid_mem))
                done
                
                if [ $gpu_mem -gt 0 ]; then
                    printf "   %-15s: %d MiB\n" "$container" "$gpu_mem"
                else
                    printf "   %-15s: ${YELLOW}Idle${NC}\n" "$container"
                fi
            fi
        done
    else
        echo "   ${YELLOW}No GPU containers running${NC}"
    fi
    echo ""
    
    # Host display hint
    echo -e "${BLUE}💻 Desktop Display:${NC}"
    # Check if iGPU is being used for display
    if glxinfo 2>/dev/null | grep -qi "intel"; then
        echo -e "   ${GREEN}✅ Using iGPU (Intel) - Optimal setup${NC}"
        echo "   dGPU fully available for containers"
    elif glxinfo 2>/dev/null | grep -qi "nvidia"; then
        echo -e "   ${YELLOW}⚠️  Using dGPU (NVIDIA) for display${NC}"
        echo "   Desktop and containers sharing GPU"
        echo "   Consider switching to iGPU for display"
    else
        echo "   ${YELLOW}⚠️  Unable to detect display GPU${NC}"
    fi
    echo ""
    
    # Performance hints
    echo -e "${BLUE}💡 Performance Tips:${NC}"
    total_mem=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader | grep -oE '[0-9]+')
    used_mem=$(nvidia-smi --query-gpu=memory.used --format=csv,noheader | grep -oE '[0-9]+')
    mem_pct=$((used_mem * 100 / total_mem))
    
    if [ $mem_pct -gt 90 ]; then
        echo -e "   ${RED}🔴 High VRAM usage ($mem_pct%)${NC}"
        echo "   - Consider stopping containers if desktop lags"
        echo "   - Or reduce OLLAMA_MAX_LOADED_MODELS"
    elif [ $mem_pct -gt 70 ]; then
        echo -e "   ${YELLOW}🟡 Moderate VRAM usage ($mem_pct%)${NC}"
        echo "   - Monitor for desktop performance issues"
    else
        echo -e "   ${GREEN}🟢 Healthy VRAM usage ($mem_pct%)${NC}"
    fi
    echo ""
    
    echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
    echo "Refreshing in 3 seconds... (Ctrl+C to exit)"
    sleep 3
done
