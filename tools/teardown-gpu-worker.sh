#!/bin/bash
# Quick teardown script for GPU worker on akula-prime
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "🛑 Tearing Down GPU Worker Stack..."
echo "==================================="

# Check for compose file
if [[ ! -f "$PROJECT_ROOT/docker-compose.desktop.yml" ]]; then
    echo "❌ Error: docker-compose.desktop.yml not found"
    exit 1
fi

# Show current status
cd "$PROJECT_ROOT"
echo ""
echo "📊 Current Status:"
docker compose -f docker-compose.desktop.yml ps

# Confirm teardown
echo ""
read -p "⚠️  Stop all GPU worker services? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Cancelled."
    exit 0
fi

# Stop services
echo ""
echo "🛑 Stopping services..."
docker compose -f docker-compose.desktop.yml down

echo ""
echo "✅ GPU Worker stopped successfully!"
echo ""
echo "💾 Note: Volumes are preserved. Models and outputs remain intact."
echo ""
echo "🗑️  To remove volumes as well, run:"
echo "   docker compose -f docker-compose.desktop.yml down -v"
echo ""
echo "🚀 To redeploy, run:"
echo "   ./tools/deploy-gpu-worker.sh"
