#!/bin/bash

# Check if Ollama API is responding
if ! curl -f --max-time 10 http://localhost:11434/api/tags > /dev/null; then
  exit 1
fi

# Basic CLI sanity (does not require any models to be pulled).
if ! ollama list >/dev/null 2>&1; then
  exit 1
fi

# Optional strict model check.
# Enable with: OLLAMA_HEALTHCHECK_STRICT_MODELS=1
OLLAMA_HEALTHCHECK_STRICT_MODELS=${OLLAMA_HEALTHCHECK_STRICT_MODELS:-0}
if [ "$OLLAMA_HEALTHCHECK_STRICT_MODELS" = "1" ] && [ -n "${OLLAMA_MODELS:-}" ]; then
  list_out=$(ollama list 2>/dev/null || true)
  IFS=',' read -ra EXPECTED_MODELS <<< "$OLLAMA_MODELS"
  for model in "${EXPECTED_MODELS[@]}"; do
    model=$(echo "$model" | xargs)
    if ! echo "$list_out" | grep -q "$model"; then
      echo "Expected model $model not found"
      exit 1
    fi
  done
fi

exit 0