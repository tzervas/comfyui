#!/bin/bash
# Health check script for GPU worker services
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo "🏥 GPU Worker Health Check"
echo "=========================="
echo ""

cd "$PROJECT_ROOT"

# Check if services are running
echo "📊 Service Status:"
echo "-------------------"
if docker compose -f docker-compose.desktop.yml ps | grep -q "Up"; then
    docker compose -f docker-compose.desktop.yml ps
    echo ""
else
    echo -e "${RED}❌ No services running${NC}"
    echo ""
    echo "Start services with: ./tools/deploy-gpu-worker.sh"
    exit 1
fi

# Check Ollama health
echo "🦙 Ollama Health:"
echo "----------------"
if docker exec ollama curl -sf http://localhost:11434/api/tags > /dev/null 2>&1; then
    echo -e "${GREEN}✅ Ollama API responding${NC}"
    MODEL_COUNT=$(docker exec ollama ollama list | tail -n +2 | wc -l)
    echo "   Models loaded: $MODEL_COUNT"
else
    echo -e "${RED}❌ Ollama API not responding${NC}"
fi
echo ""

# Check ComfyUI health
echo "🎨 ComfyUI Health:"
echo "-----------------"
if docker exec comfyui curl -sf http://localhost:18188 > /dev/null 2>&1; then
    echo -e "${GREEN}✅ ComfyUI responding${NC}"
else
    echo -e "${YELLOW}⚠️  ComfyUI not responding${NC}"
fi
echo ""

# Check GPU
echo "🎮 GPU Status:"
echo "-------------"
if docker exec ollama nvidia-smi &> /dev/null; then
    docker exec ollama nvidia-smi --query-gpu=name,utilization.gpu,memory.used,memory.total --format=csv,noheader | \
    while IFS=',' read -r name util mem_used mem_total; do
        echo -e "${GREEN}✅ GPU: $name${NC}"
        echo "   Utilization: $util"
        echo "   Memory: $mem_used / $mem_total"
    done
else
    echo -e "${RED}❌ GPU not accessible${NC}"
fi
echo ""

# Check registry registration
echo "📡 Registry Status:"
echo "------------------"
REGISTRY_URL=$(grep "^REGISTRY_URL=" "$PROJECT_ROOT/.env.desktop" 2>/dev/null | cut -d'=' -f2 || echo "")
if [[ -n "$REGISTRY_URL" ]]; then
    if curl -sf "$REGISTRY_URL/discover?service=ollama" > /dev/null 2>&1; then
        OLLAMA_NODES=$(curl -sf "$REGISTRY_URL/discover?service=ollama" | grep -o '"id"' | wc -l)
        echo -e "${GREEN}✅ Registry reachable${NC}"
        echo "   Registered Ollama nodes: $OLLAMA_NODES"
    else
        echo -e "${YELLOW}⚠️  Registry not reachable at $REGISTRY_URL${NC}"
    fi
    
    if curl -sf "$REGISTRY_URL/discover?service=comfyui" > /dev/null 2>&1; then
        COMFYUI_NODES=$(curl -sf "$REGISTRY_URL/discover?service=comfyui" | grep -o '"id"' | wc -l)
        echo "   Registered ComfyUI nodes: $COMFYUI_NODES"
    fi
else
    echo -e "${YELLOW}⚠️  REGISTRY_URL not configured${NC}"
fi
echo ""

# Resource usage
echo "💻 Resource Usage:"
echo "-----------------"
echo "Ollama:"
docker stats ollama --no-stream --format "   CPU: {{.CPUPerc}}\tMemory: {{.MemUsage}}"
echo ""
echo "ComfyUI:"
docker stats comfyui --no-stream --format "   CPU: {{.CPUPerc}}\tMemory: {{.MemUsage}}"
echo ""

# Recent errors
echo "🔍 Recent Errors:"
echo "----------------"
OLLAMA_ERRORS=$(docker logs ollama --since 10m 2>&1 | grep -i "error\|fail\|exception" | tail -3)
if [[ -n "$OLLAMA_ERRORS" ]]; then
    echo -e "${YELLOW}Ollama:${NC}"
    echo "$OLLAMA_ERRORS"
else
    echo -e "${GREEN}✅ No recent Ollama errors${NC}"
fi

COMFYUI_ERRORS=$(docker logs comfyui --since 10m 2>&1 | grep -i "error\|fail\|exception" | tail -3)
if [[ -n "$COMFYUI_ERRORS" ]]; then
    echo -e "${YELLOW}ComfyUI:${NC}"
    echo "$COMFYUI_ERRORS"
else
    echo -e "${GREEN}✅ No recent ComfyUI errors${NC}"
fi
echo ""

echo "✅ Health check complete!"
