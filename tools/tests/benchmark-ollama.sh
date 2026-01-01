#!/usr/bin/env bash
set -euo pipefail

DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=tools/tests/lib_http.sh
source "$DIR/lib_http.sh"

usage() {
  cat <<'EOF'
Usage:
  tools/tests/benchmark-ollama.sh [--env-file PATH] [--base-url URL] [--iterations N] [--model NAME] [--prompt TEXT]

Benchmarks Ollama via ingress (recommended), measuring request latency.

Notes:
- This is a lightweight benchmark; it does not attempt to control GPU clocks, batching, or warmup beyond a single warmup call.
- If the model isn't pulled, Ollama may return a non-200 response.

Defaults:
  iterations: 10
  prompt: "Write one sentence about GPUs."
EOF
}

ENV_FILE=""
BASE_URL=""
ITERATIONS=10
MODEL=""
PROMPT='Write one sentence about GPUs.'

while [[ $# -gt 0 ]]; do
  case "$1" in
    --env-file)
      ENV_FILE=$2
      shift 2
      ;;
    --base-url)
      BASE_URL=$2
      shift 2
      ;;
    --iterations)
      ITERATIONS=$2
      shift 2
      ;;
    --model)
      MODEL=$2
      shift 2
      ;;
    --prompt)
      PROMPT=$2
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

if [[ -n "$ENV_FILE" ]]; then
  if [[ ! -f "$ENV_FILE" ]]; then
    echo "env file not found: $ENV_FILE" >&2
    exit 2
  fi
  set -a
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  set +a
fi

STACK_FQDN=${STACK_FQDN:-localhost}
NGINX_SSL_PORT=${NGINX_SSL_PORT:-8443}

if [[ -z "$BASE_URL" ]]; then
  BASE_URL="https://${STACK_FQDN}:${NGINX_SSL_PORT}"
fi

BASIC_AUTH_USER=${BASIC_AUTH_USER:-admin}
BASIC_AUTH_PASS=${BASIC_AUTH_PASS:-admin}
CURL_INSECURE=${CURL_INSECURE:-1}

CURL_TLS_ARGS=()
if [[ "$CURL_INSECURE" == "1" ]]; then
  CURL_TLS_ARGS+=( -k )
fi

AUTH=(-u "${BASIC_AUTH_USER}:${BASIC_AUTH_PASS}")

# Detect model if not provided
if [[ -z "$MODEL" ]]; then
  tags=$(http_get "${BASE_URL}/ollama/api/tags" "${CURL_TLS_ARGS[@]}" "${AUTH[@]}" 2>/tmp/status.$$ || true)
  status=$(tail -n 1 /tmp/status.$$ | tr -d '\r' || true)
  rm -f /tmp/status.$$
  if [[ "$status" != "200" ]]; then
    echo "WARN: /api/tags returned status=${status}; cannot auto-detect model" >&2
  else
    MODEL=$(echo "$tags" | sed -n 's/.*"name"[[:space:]]*:[[:space:]]*"\([^"]\+\)".*/\1/p' | head -n 1 || true)
  fi
fi

if [[ -z "$MODEL" ]]; then
  echo "FAIL: no model specified and none detected from /api/tags" >&2
  exit 1
fi

echo "Benchmarking Ollama via ${BASE_URL}"
echo "Model: ${MODEL}"
echo "Iterations: ${ITERATIONS}"

# Warmup (best-effort)
http_post_json "${BASE_URL}/ollama/api/generate" "{\"model\":\"${MODEL}\",\"prompt\":\"warmup\",\"stream\":false}" "${CURL_TLS_ARGS[@]}" "${AUTH[@]}" >/dev/null 2>/tmp/status.$$ || true
rm -f /tmp/status.$$

# Collect timings (ms)
# Uses curl -w timing for accuracy; falls back to http_post_json path if needed.
if command -v curl >/dev/null 2>&1; then
  total=0
  ok=0
  for i in $(seq 1 "$ITERATIONS"); do
    ms=$(curl -sS -o /dev/null -w '%{time_total}' -k -u "${BASIC_AUTH_USER}:${BASIC_AUTH_PASS}" \
      -H 'Content-Type: application/json' \
      --data "{\"model\":\"${MODEL}\",\"prompt\":\"${PROMPT//\"/\\\"}\",\"stream\":false}" \
      "${BASE_URL}/ollama/api/generate" || echo "")

    if [[ -z "$ms" ]]; then
      echo "iter ${i}: error" >&2
      continue
    fi

    # seconds -> ms (integer)
    ms_int=$(awk -v s="$ms" 'BEGIN{printf "%d", (s*1000)}')
    echo "iter ${i}: ${ms_int} ms"
    total=$((total + ms_int))
    ok=$((ok + 1))
  done

  if [[ "$ok" -gt 0 ]]; then
    avg=$((total / ok))
    echo "OK: ${ok}/${ITERATIONS} successful"
    echo "AVG: ${avg} ms"
  else
    echo "FAIL: no successful iterations" >&2
    exit 1
  fi
else
  echo "WARN: curl not found; cannot benchmark precisely" >&2
  exit 2
fi
