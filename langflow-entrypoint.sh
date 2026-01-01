#!/bin/bash
set -e

echo "Setting up LangFlow directories..."
mkdir -p /tmp/langflow || true
mkdir -p /app/data/.cache || true
chmod 755 /app/data/.cache || true
chmod 755 /tmp/langflow || true
ls -la /tmp/ | grep langflow || true

echo "Starting LangFlow..."
exec "$@"