#!/usr/bin/env sh
set -eu

# Deep readiness probe for the ingress container.
# Validates that Nginx is up AND core upstreams are reachable on the Docker network.
#
# Controlled by env:
#   SSO_ENABLED=0|1
#   KEYCLOAK_ENABLED=0|1
#   MODEL_VAULT_MODE=remote|local

SSO_ENABLED=${SSO_ENABLED:-0}
KEYCLOAK_ENABLED=${KEYCLOAK_ENABLED:-0}
MODEL_VAULT_MODE=${MODEL_VAULT_MODE:-remote}
PROBE_OLLAMA=${PROBE_OLLAMA:-1}
PROBE_COMFYUI=${PROBE_COMFYUI:-1}

OLLAMA_UPSTREAM=${OLLAMA_UPSTREAM:-}
COMFYUI_UPSTREAM=${COMFYUI_UPSTREAM:-}

# Busybox wget is present in nginx:alpine.
wget_ok() {
  url=$1
  wget -q -T 5 -O - "$url" >/dev/null 2>&1
}

wget_body_contains() {
  url=$1
  needle=$2
  wget -q -T 8 -O - "$url" 2>/dev/null | grep -q "$needle"
}

# Nginx liveness (no auth)
wget_ok "http://localhost/healthz" || exit 1

# Core upstreams (optional)
if [ "$PROBE_OLLAMA" = "1" ] && [ -n "$OLLAMA_UPSTREAM" ]; then
  wget_body_contains "http://${OLLAMA_UPSTREAM}/api/tags" "models" || exit 1
fi

if [ "$PROBE_COMFYUI" = "1" ] && [ -n "$COMFYUI_UPSTREAM" ]; then
  # ComfyUI HTML should load.
  # (Some images may not include the exact string; keep this check loose.)
  wget_ok "http://${COMFYUI_UPSTREAM}/" || exit 1
fi

# Optional local model-vault
if [ "$MODEL_VAULT_MODE" = "local" ]; then
  wget_body_contains "http://model-vault:8080/health" "ok" || exit 1
fi

# Optional SSO components
if [ "$SSO_ENABLED" = "1" ]; then
  # The oauth2-proxy container exposes /oauth2/ping when ping_path is set.
  wget_ok "http://oauth2-proxy:4180/oauth2/ping" || exit 1
fi

if [ "$KEYCLOAK_ENABLED" = "1" ]; then
  # Keycloak served under relative path /keycloak.
  wget_ok "http://keycloak:8080/keycloak/" || exit 1
  wget_ok "http://keycloak:8080/keycloak/realms/comfyui" || exit 1
fi

exit 0
