#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  tools/tests/validate-cli.sh -f COMPOSE_FILE --env-file ENV

Runs CLI-level validation by exec'ing into containers:
- ollama: list models, (optional) quick generate
- comfyui: verify custom_nodes/workflows directories exist
EOF
}

COMPOSE_FILE=""
ENV_FILE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    -f|--compose-file)
      COMPOSE_FILE=$2
      shift 2
      ;;
    --env-file)
      ENV_FILE=$2
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown arg: $1" >&2
      usage
      exit 2
      ;;
  esac
done

if [[ -z "$COMPOSE_FILE" || -z "$ENV_FILE" ]]; then
  usage
  exit 2
fi

if [[ ! -f "$COMPOSE_FILE" ]]; then
  echo "compose file not found: $COMPOSE_FILE" >&2
  exit 2
fi

if [[ ! -f "$ENV_FILE" ]]; then
  echo "env file not found: $ENV_FILE" >&2
  exit 2
fi

set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a

pass() { echo "PASS: $*"; }
warn() { echo "WARN: $*" >&2; }

DC=(docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE")

"${DC[@]}" ps >/dev/null

# Ollama
if "${DC[@]}" exec -T ollama ollama list | grep -q "NAME"; then
  pass "ollama cli list works"
else
  warn "ollama list did not return expected output"
fi

# Optional: quick generate if at least one model exists
MODEL=$(${DC[@]} exec -T ollama ollama list | awk 'NR==2{print $1}' | tr -d '\r' || true)
if [[ -n "$MODEL" && "$MODEL" != "NAME" ]]; then
  if ${DC[@]} exec -T ollama ollama run "$MODEL" "hello" >/dev/null 2>&1; then
    pass "ollama cli run works (model=$MODEL)"
  else
    warn "ollama run failed (model=$MODEL)"
  fi
else
  warn "no ollama model found for cli run test"
fi

# ComfyUI paths (best-effort; image layout can differ)
if ${DC[@]} exec -T comfyui sh -lc 'test -d /workspace/ComfyUI/custom_nodes || test -d /opt/ComfyUI/custom_nodes'; then
  pass "comfyui custom_nodes directory exists"
else
  warn "comfyui custom_nodes directory not found"
fi

if ${DC[@]} exec -T comfyui sh -lc 'test -d /opt/ComfyUI/user/default/workflows'; then
  pass "comfyui default workflows dir exists"
else
  warn "comfyui default workflows dir not found"
fi

# Code executor
if ${DC[@]} exec -T code_executor curl -fsS http://localhost:5000/health >/dev/null; then
  pass "code executor /health OK"
else
  warn "code executor /health failed"
fi

echo "CLI validation complete"
