#!/bin/bash
# Quick deployment script for GPU worker on akula-prime
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "🚀 Deploying GPU Worker Stack..."
echo "================================"

# Check if we're on the right host
HOSTNAME=$(hostname)
if [[ "$HOSTNAME" != "akula-prime" ]]; then
    echo "⚠️  Warning: This script is intended for akula-prime"
    echo "   Current hostname: $HOSTNAME"
    read -p "Continue anyway? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# Check for required files
if [[ ! -f "$PROJECT_ROOT/.env.desktop" ]]; then
    echo "❌ Error: .env.desktop not found"
    echo "   Please create it with required variables:"
    echo "   - REGISTRY_URL"
    echo "   - REGISTRY_SECRET"
    echo "   - MODEL_VAULT_TOKEN"
    exit 1
fi

if [[ ! -f "$PROJECT_ROOT/docker-compose.desktop.yml" ]]; then
    echo "❌ Error: docker-compose.desktop.yml not found"
    exit 1
fi

# Check Docker
if ! command -v docker &> /dev/null; then
    echo "❌ Error: Docker is not installed"
    exit 1
fi

if ! docker compose version &> /dev/null; then
    echo "❌ Error: Docker Compose is not available"
    exit 1
fi

# Check GPU
if ! command -v nvidia-smi &> /dev/null; then
    echo "⚠️  Warning: nvidia-smi not found. GPU may not be available."
    read -p "Continue anyway? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
else
    echo "✅ GPU detected:"
    nvidia-smi --query-gpu=name,memory.total --format=csv,noheader
fi

# Load environment
export $(grep -v '^#' "$PROJECT_ROOT/.env.desktop" | xargs)

# Deploy stack
cd "$PROJECT_ROOT"
echo ""
echo "📦 Pulling latest images..."
docker compose -f docker-compose.desktop.yml pull

echo ""
echo "🏗️  Building custom images..."
docker compose -f docker-compose.desktop.yml build

echo ""
echo "🚀 Starting services..."
docker compose -f docker-compose.desktop.yml up -d

echo ""
echo "⏳ Waiting for services to initialize..."
sleep 5

echo ""
echo "📊 Service Status:"
docker compose -f docker-compose.desktop.yml ps

echo ""
echo "⏳ Waiting for services to be healthy..."
ids=$(docker compose -f docker-compose.desktop.yml ps -q)
deadline=$((SECONDS+240))
while [ $SECONDS -lt $deadline ]; do
    all_ok=1
    for id in $ids; do
        status=$(docker inspect -f '{{.State.Status}}' "$id" 2>/dev/null || echo unknown)
        health=$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "$id" 2>/dev/null || echo unknown)
        if [ "$status" != "running" ]; then
            all_ok=0
        fi
        if [ "$health" != "none" ] && [ "$health" != "healthy" ]; then
            all_ok=0
        fi
    done
    if [ $all_ok -eq 1 ]; then
        echo "✅ Services are running/healthy"
        break
    fi
    echo "⏳ Waiting..."
    sleep 5
done

echo ""
echo "✅ GPU Worker deployed successfully!"
echo ""
echo "🔍 Check logs with:"
echo "   docker logs ollama -f"
echo "   docker logs comfyui -f"
echo ""
echo "🛑 Stop services with:"
echo "   docker compose -f docker-compose.desktop.yml down"
echo ""
echo "🔄 Services will automatically restart unless explicitly stopped"
