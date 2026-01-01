#!/usr/bin/env bash
set -euo pipefail

DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=tools/tests/lib_http.sh
source "$DIR/lib_http.sh"

usage() {
  cat <<'EOF'
Usage:
  tools/tests/validate-stack.sh [--env-file PATH] [--base-url URL]

Environment (overrides):
  STACK_FQDN, NGINX_SSL_PORT
  BASIC_AUTH_USER, BASIC_AUTH_PASS
  CURL_INSECURE=1 (default) or 0

  REGISTRY_SECRET
  MTLS_VERIFY=off|optional|on
  REGISTRY_MTLS_CA, REGISTRY_MTLS_CERT, REGISTRY_MTLS_KEY

  OLLAMA_TEST_MODEL (optional)
  OLLAMA_VISION_TEST_MODEL (optional)
EOF
}

ENV_FILE=""
BASE_URL=""

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
SSO_ENABLED=${SSO_ENABLED:-0}
KEYCLOAK_ENABLED=${KEYCLOAK_ENABLED:-0}

CURL_TLS_ARGS=()
if [[ "$CURL_INSECURE" == "1" ]]; then
  CURL_TLS_ARGS+=( -k )
fi

AUTH=(-u "${BASIC_AUTH_USER}:${BASIC_AUTH_PASS}")

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*" >&2; exit 1; }
warn() { echo "WARN: $*" >&2; }

if [[ "$SSO_ENABLED" == "1" ]]; then
  # Minimal SSO smoke checks:
  # - Root should redirect to oauth2 start
  # - oauth2-proxy should respond to /oauth2/ping
  status=$(http_get "${BASE_URL}/" "${CURL_TLS_ARGS[@]}" 2>&1 >/dev/null | tail -n 1 || true)
  if [[ "$status" == "302" || "$status" == "301" ]]; then
    pass "SSO redirect active at /"
  else
    warn "Expected redirect at / with SSO enabled (got $status)"
  fi

  ping_body=$(http_get "${BASE_URL}/oauth2/ping" "${CURL_TLS_ARGS[@]}" 2>"/tmp/status.$$" || true)
  ping_status=$(tail -n 1 "/tmp/status.$$" | tr -d '\r' || true)
  rm -f "/tmp/status.$$"
  if [[ "$ping_status" == "200" ]]; then
    pass "oauth2-proxy /oauth2/ping OK"
  else
    warn "oauth2-proxy /oauth2/ping not validated (status=${ping_status}). Body: $(echo "$ping_body" | head -c 200)"
  fi

  if [[ "$KEYCLOAK_ENABLED" == "1" ]]; then
    kc_body=$(http_get "${BASE_URL}/keycloak/" "${CURL_TLS_ARGS[@]}" 2>"/tmp/status.$$" || true)
    kc_status=$(tail -n 1 "/tmp/status.$$" | tr -d '\r' || true)
    rm -f "/tmp/status.$$"
    if [[ "$kc_status" == "200" || "$kc_status" == "302" ]]; then
      pass "Keycloak reachable at /keycloak/"
    else
      warn "Keycloak not validated at /keycloak/ (status=${kc_status}). Body: $(echo "$kc_body" | head -c 200)"
    fi
  fi

fi

expect_status() {
  local want=$1
  local got=$2
  if [[ "$got" != "$want" ]]; then
    fail "expected HTTP $want, got $got"
  fi
}

# --- Basic Auth gate checks ---
if [[ "$SSO_ENABLED" == "1" ]]; then
  warn "Skipping service probes because SSO is enabled (basic-auth probes not applicable)."
else
status=$(http_get "${BASE_URL}/ollama/api/tags" "${CURL_TLS_ARGS[@]}" 2>&1 >/dev/null | tail -n 1 || true)
# http_get prints status to stderr; capture via redirect above
# If the endpoint is protected, we expect 401 without credentials.
if [[ "$status" == "401" ]]; then
  pass "Ollama basic-auth enforced"
else
  warn "Ollama endpoint did not return 401 without auth (got $status)"
fi

body=$(http_get "${BASE_URL}/ollama/api/tags" "${CURL_TLS_ARGS[@]}" "${AUTH[@]}" 2>"/tmp/status.$$" )
status=$(tail -n 1 "/tmp/status.$$" | tr -d '\r' || true)
rm -f "/tmp/status.$$"
expect_status 200 "$status"
echo "$body" | grep -q '"models"' || fail "Ollama /api/tags response missing models"
pass "Ollama /api/tags OK"

# --- Ollama generate ---
OLLAMA_TEST_MODEL=${OLLAMA_TEST_MODEL:-}
if [[ -z "$OLLAMA_TEST_MODEL" ]]; then
  # Try to pick the first model name from /api/tags without jq
  OLLAMA_TEST_MODEL=$(echo "$body" | sed -n 's/.*"name"[[:space:]]*:[[:space:]]*"\([^"]\+\)".*/\1/p' | head -n 1 || true)
fi

if [[ -n "$OLLAMA_TEST_MODEL" ]]; then
  gen_body=$(http_post_json "${BASE_URL}/ollama/api/generate" "{\"model\":\"${OLLAMA_TEST_MODEL}\",\"prompt\":\"Say hello in one sentence.\",\"stream\":false}" "${CURL_TLS_ARGS[@]}" "${AUTH[@]}" 2>"/tmp/status.$$" || true)
  gen_status=$(tail -n 1 "/tmp/status.$$" | tr -d '\r' || true)
  rm -f "/tmp/status.$$"
  if [[ "$gen_status" == "200" ]] && echo "$gen_body" | grep -q '"response"'; then
    pass "Ollama /api/generate OK (model=${OLLAMA_TEST_MODEL})"
  else
    warn "Ollama /api/generate not validated (model=${OLLAMA_TEST_MODEL}, status=${gen_status}). This is often just 'model not pulled yet'."
  fi
else
  warn "No Ollama model detected; skipping /api/generate"
fi

# --- Ollama multimodal (vision) probe (optional) ---
# Tiny 1x1 PNG
IMG_B64="iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAOq0n1kAAAAASUVORK5CYII="
OLLAMA_VISION_TEST_MODEL=${OLLAMA_VISION_TEST_MODEL:-}
if [[ -n "$OLLAMA_VISION_TEST_MODEL" ]]; then
  chat_body=$(http_post_json "${BASE_URL}/ollama/api/chat" "{\"model\":\"${OLLAMA_VISION_TEST_MODEL}\",\"messages\":[{\"role\":\"user\",\"content\":\"Describe this image in one short phrase.\",\"images\":[\"${IMG_B64}\"]}],\"stream\":false}" "${CURL_TLS_ARGS[@]}" "${AUTH[@]}" 2>"/tmp/status.$$" || true)
  chat_status=$(tail -n 1 "/tmp/status.$$" | tr -d '\r' || true)
  rm -f "/tmp/status.$$"
  if [[ "$chat_status" == "200" ]] && echo "$chat_body" | grep -q '"message"'; then
    pass "Ollama vision /api/chat OK (model=${OLLAMA_VISION_TEST_MODEL})"
  else
    warn "Ollama vision probe failed (model=${OLLAMA_VISION_TEST_MODEL}, status=${chat_status}). If the model is not vision-capable or not pulled yet, this is expected."
  fi
else
  warn "OLLAMA_VISION_TEST_MODEL not set; skipping vision probe"
fi

# --- ComfyUI ---
comfy_body=$(http_get "${BASE_URL}/comfyui/" "${CURL_TLS_ARGS[@]}" "${AUTH[@]}" 2>"/tmp/status.$$" )
comfy_status=$(tail -n 1 "/tmp/status.$$" | tr -d '\r' || true)
rm -f "/tmp/status.$$"
expect_status 200 "$comfy_status"
echo "$comfy_body" | grep -qi "ComfyUI" || warn "ComfyUI HTML did not contain 'ComfyUI' (UI may have changed)"
pass "ComfyUI UI reachable"

# Try a lightweight API endpoint; treat 404 as non-fatal.
obj_body=$(http_get "${BASE_URL}/comfyui/object_info" "${CURL_TLS_ARGS[@]}" "${AUTH[@]}" 2>"/tmp/status.$$" || true)
obj_status=$(tail -n 1 "/tmp/status.$$" | tr -d '\r' || true)
rm -f "/tmp/status.$$"
if [[ "$obj_status" == "200" ]]; then
  echo "$obj_body" | grep -q '"' || true
  pass "ComfyUI /object_info reachable"
else
  warn "ComfyUI /object_info not reachable (status=${obj_status}); skipping custom-node introspection"
fi

# --- LangChain ---
lc_body=$(http_get "${BASE_URL}/langchain/docs" "${CURL_TLS_ARGS[@]}" "${AUTH[@]}" 2>"/tmp/status.$$" )
lc_status=$(tail -n 1 "/tmp/status.$$" | tr -d '\r' || true)
rm -f "/tmp/status.$$"
expect_status 200 "$lc_status"
echo "$lc_body" | grep -q "FastAPI" || warn "LangChain docs did not contain 'FastAPI'"
pass "LangChain docs reachable"

# Multi-agent endpoint probe
agent_body=$(http_post_json "${BASE_URL}/langchain/agent/run" "{\"prompt\":\"Compute 19*23 and explain briefly.\",\"allow_code_execution\":true}" "${CURL_TLS_ARGS[@]}" "${AUTH[@]}" 2>"/tmp/status.$$" || true)
agent_status=$(tail -n 1 "/tmp/status.$$" | tr -d '\r' || true)
rm -f "/tmp/status.$$"
if [[ "$agent_status" == "200" ]] && echo "$agent_body" | grep -q '"answer"'; then
  pass "LangChain multi-agent flow OK"
else
  warn "LangChain multi-agent flow not validated (status=${agent_status})"
fi

# --- LangFlow ---
lf_body=$(http_get "${BASE_URL}/langflow/" "${CURL_TLS_ARGS[@]}" "${AUTH[@]}" 2>"/tmp/status.$$" || true)
lf_status=$(tail -n 1 "/tmp/status.$$" | tr -d '\r' || true)
rm -f "/tmp/status.$$"
if [[ "$lf_status" == "200" ]]; then
  pass "LangFlow reachable"
else
  warn "LangFlow not validated (status=${lf_status})"
fi

# --- Code executor ---
ce_health=$(http_get "${BASE_URL}/code-executor/health" "${CURL_TLS_ARGS[@]}" "${AUTH[@]}" 2>"/tmp/status.$$" || true)
ce_status=$(tail -n 1 "/tmp/status.$$" | tr -d '\r' || true)
rm -f "/tmp/status.$$"
if [[ "$ce_status" == "200" ]] && echo "$ce_health" | grep -q "ok"; then
  pass "Code executor health OK"
else
  warn "Code executor health not validated (status=${ce_status})"
fi

ce_run=$(http_post_text "${BASE_URL}/code-executor/" $'print("hello")\n' "${CURL_TLS_ARGS[@]}" "${AUTH[@]}" 2>"/tmp/status.$$" || true)
ce_run_status=$(tail -n 1 "/tmp/status.$$" | tr -d '\r' || true)
rm -f "/tmp/status.$$"
if [[ "$ce_run_status" == "200" ]] && echo "$ce_run" | grep -q "hello"; then
  pass "Code executor run OK"
else
  warn "Code executor run not validated (status=${ce_run_status}). Response: $(echo "$ce_run" | head -c 200)"
fi

# --- Model Vault health (behind basic auth) ---
mv_health=$(http_get "${BASE_URL}/model-vault/health" "${CURL_TLS_ARGS[@]}" "${AUTH[@]}" 2>"/tmp/status.$$" || true)
mv_status=$(tail -n 1 "/tmp/status.$$" | tr -d '\r' || true)
rm -f "/tmp/status.$$"
if [[ "$mv_status" == "200" ]] && echo "$mv_health" | grep -q "ok"; then
  pass "Model Vault /health OK"
else
  warn "Model Vault /health not validated (status=${mv_status})"
fi
fi

# --- Registry endpoints (secret + optional mTLS) ---
REGISTRY_SECRET=${REGISTRY_SECRET:-}
MTLS_VERIFY=${MTLS_VERIFY:-off}

REGISTRY_TLS_ARGS=("${CURL_TLS_ARGS[@]}")
if [[ "$MTLS_VERIFY" != "off" ]]; then
  # If you want a strict check, provide client certs.
  if [[ -n "${REGISTRY_MTLS_CA:-}" ]]; then
    REGISTRY_TLS_ARGS+=( --cacert "$REGISTRY_MTLS_CA" )
  fi
  if [[ -n "${REGISTRY_MTLS_CERT:-}" && -n "${REGISTRY_MTLS_KEY:-}" ]]; then
    REGISTRY_TLS_ARGS+=( --cert "$REGISTRY_MTLS_CERT" --key "$REGISTRY_MTLS_KEY" )
  fi
fi

if [[ -n "$REGISTRY_SECRET" ]]; then
  # Missing secret should be rejected by model-vault.
  disc_body=$(http_get "${BASE_URL}/discover" "${REGISTRY_TLS_ARGS[@]}" 2>"/tmp/status.$$" || true)
  disc_status=$(tail -n 1 "/tmp/status.$$" | tr -d '\r' || true)
  rm -f "/tmp/status.$$"

  if [[ "$disc_status" == "401" || "$disc_status" == "403" ]]; then
    pass "Registry /discover rejects missing secret"
  else
    warn "Registry /discover did not reject missing secret (status=${disc_status})"
  fi

  disc2_body=$(http_get "${BASE_URL}/discover" -H "X-Registry-Secret: ${REGISTRY_SECRET}" "${REGISTRY_TLS_ARGS[@]}" 2>"/tmp/status.$$" || true)
  disc2_status=$(tail -n 1 "/tmp/status.$$" | tr -d '\r' || true)
  rm -f "/tmp/status.$$"

  if [[ "$disc2_status" == "200" ]]; then
    pass "Registry /discover accepts secret"
  else
    warn "Registry /discover with secret not validated (status=${disc2_status})"
  fi
else
  warn "REGISTRY_SECRET not set; skipping /discover secret validation"
fi

echo "All validation probes completed for ${BASE_URL}"
