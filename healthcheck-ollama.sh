#!/bin/bash

# Check if Ollama API is responding
if ! curl -f --max-time 10 http://localhost:11434/api/tags > /dev/null; then
  exit 1
fi

# Check if models are available
if ! ollama list | grep -q NAME; then
  exit 1
fi

# If OLLAMA_MODELS is set, verify those models are present
if [ -n "$OLLAMA_MODELS" ]; then
  IFS=',' read -ra EXPECTED_MODELS <<< "$OLLAMA_MODELS"
  for model in "${EXPECTED_MODELS[@]}"; do
    model=$(echo "$model" | xargs)
    if ! ollama list | grep -q "$model"; then
      echo "Expected model $model not found"
      exit 1
    fi
  done
fi

exit 0