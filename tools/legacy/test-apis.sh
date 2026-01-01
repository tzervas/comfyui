#!/bin/bash

# API Testing Suite for ComfyUI/Ollama Stack
# Usage: ./test-apis.sh [service] (optional: test specific service, else all)

set -e

BASE_URL="http://localhost"
OLLAMA_PORT=11434
COMFYUI_PORT=8188
LANGCHAIN_PORT=8000
LANGFLOW_PORT=7860
CODE_EXECUTOR_PORT=5000

LOG_DIR="./test-logs"
mkdir -p $LOG_DIR

log() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a $LOG_DIR/test-$(date +%Y%m%d-%H%M%S).log
}

test_ollama() {
  log "Testing Ollama API..."
  # Test tags
  if curl -s -f $BASE_URL:$OLLAMA_PORT/api/tags | jq -e '.models' > /dev/null; then
    log "Ollama /api/tags: PASS"
  else
    log "Ollama /api/tags: FAIL"
    docker compose logs ollama > $LOG_DIR/ollama-fail.log
    return 1
  fi

  # Test generate (simple prompt)
  response=$(curl -s -X POST $BASE_URL:$OLLAMA_PORT/api/generate -H "Content-Type: application/json" -d '{"model":"tinyllama","prompt":"Hello","stream":false}')
  if echo "$response" | jq -e '.response' > /dev/null; then
    log "Ollama /api/generate: PASS"
  else
    log "Ollama /api/generate: FAIL - Response: $response"
    docker compose logs ollama > $LOG_DIR/ollama-generate-fail.log
    return 1
  fi
}

test_comfyui() {
  log "Testing ComfyUI..."
  # Test web interface
  if curl -s -f $BASE_URL:$COMFYUI_PORT/ | grep -q "ComfyUI"; then
    log "ComfyUI web interface: PASS"
  else
    log "ComfyUI web interface: FAIL"
    docker compose logs comfyui > $LOG_DIR/comfyui-fail.log
    return 1
  fi

  # Note: Deep workflow testing would require uploading a workflow JSON, but for now, basic check
}

test_langchain() {
  log "Testing LangChain API..."
  # Test generate endpoint
  response=$(curl -s -X POST $BASE_URL:$LANGCHAIN_PORT/generate -H "Content-Type: application/json" -d '{"prompt":"What is AI?"}')
  if echo "$response" | jq -e '.response' > /dev/null; then
    log "LangChain /generate: PASS"
  else
    log "LangChain /generate: FAIL - Response: $response"
    docker compose logs langchain > $LOG_DIR/langchain-fail.log
    return 1
  fi
}

test_langflow() {
  log "Testing LangFlow..."
  # Test health or basic endpoint
  if curl -s -f $BASE_URL:$LANGFLOW_PORT/health || curl -s -f $BASE_URL:$LANGFLOW_PORT/; then
    log "LangFlow interface: PASS"
  else
    log "LangFlow interface: FAIL"
    docker compose logs langflow > $LOG_DIR/langflow-fail.log
    return 1
  fi
}

test_code_executor() {
  log "Testing Code Executor..."
  # Test GET (simple HTTP server)
  if curl -s -f $BASE_URL:$CODE_EXECUTOR_PORT/ | grep -q "Directory listing"; then
    log "Code Executor GET: PASS"
  else
    log "Code Executor GET: FAIL"
    docker compose logs code_executor > $LOG_DIR/code-executor-fail.log
    return 1
  fi

  # Note: POST code execution not implemented in simple server
}

test_load() {
  log "Running load tests..."
  # Install apache2-utils if not present
  if ! command -v ab &> /dev/null; then
    log "apache2-utils not found, installing..."
    sudo apt-get update && sudo apt-get install -y apache2-utils
  fi

  # Load test Ollama
  log "Load testing Ollama API..."
  ab -n 10 -c 2 -T "application/json" -p /dev/stdin $BASE_URL:$OLLAMA_PORT/api/generate <<< '{"model":"tinyllama","prompt":"Hello","stream":false}' > $LOG_DIR/load-ollama.log 2>&1
  if grep -q "Failed requests: 0" $LOG_DIR/load-ollama.log; then
    log "Ollama load test: PASS"
  else
    log "Ollama load test: FAIL"
  fi

  # Load test LangChain
  log "Load testing LangChain API..."
  ab -n 5 -c 1 -T "application/json" -p /dev/stdin $BASE_URL:$LANGCHAIN_PORT/generate <<< '{"prompt":"Hello"}' > $LOG_DIR/load-langchain.log 2>&1
  if grep -q "Failed requests: 0" $LOG_DIR/load-langchain.log; then
    log "LangChain load test: PASS"
  else
    log "LangChain load test: FAIL"
  fi
}

case "$1" in
  ollama)
    test_ollama
    ;;
  comfyui)
    test_comfyui
    ;;
  langchain)
    test_langchain
    ;;
  langflow)
    test_langflow
    ;;
  code-executor)
    test_code_executor
    ;;
  load)
    test_load
    ;;
  all|"")
    test_ollama
    test_comfyui
    test_langchain
    test_langflow
    test_code_executor
    test_load
    log "All tests completed. Logs in $LOG_DIR"
    ;;
  *)
    echo "Usage: $0 [ollama|comfyui|langchain|langflow|code-executor|load|all]"
    exit 1
    ;;
esac