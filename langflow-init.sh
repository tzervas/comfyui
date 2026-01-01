#!/bin/bash
# LangFlow init script: Set up default flows and configurations
set -e

echo "Setting up LangFlow defaults..."

# Create data directory if not exists
mkdir -p /app/data/langflow

# Copy default flows if not present
if [ ! -f "/app/data/langflow/sample_rag_flow.json" ]; then
  echo "Installing sample RAG flow..."
  cat > /app/data/langflow/sample_rag_flow.json << 'EOF'
{
  "flow": {
    "data": {
      "nodes": [],
      "edges": []
    },
    "description": "Sample RAG Flow for LangFlow",
    "name": "Sample RAG Flow"
  }
}
EOF
fi

echo "LangFlow defaults ready."