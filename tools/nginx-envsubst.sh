#!/bin/sh
set -eu

TEMPLATE_PATH="/etc/nginx/nginx.conf.template"
OUTPUT_PATH="/etc/nginx/nginx.conf"

if [ ! -f "$TEMPLATE_PATH" ]; then
  echo "[nginx-envsubst] Missing template: $TEMPLATE_PATH" >&2
  exit 1
fi

: "${STACK_FQDN:=_}"
: "${MTLS_VERIFY:=off}"
:
: "${SSO_ENABLED:=0}"
: "${OAUTH2_PROXY_UPSTREAM:=oauth2-proxy:4180}"
:
: "${MODEL_VAULT_MODE:=remote}" # remote|local
: "${MODEL_VAULT_REMOTE_BASE_URL:=https://homelab.lan:8443}"
: "${MODEL_VAULT_SSL_VERIFY:=on}" # on|off
: "${MODEL_VAULT_SSL_TRUSTED_CERT:=/etc/ssl/certs/localhost/ca.pem}"

# Defaults for upstreams (Docker DNS)
: "${OLLAMA_UPSTREAM:=ollama:11434}"
: "${COMFYUI_UPSTREAM:=comfyui:18188}"

export STACK_FQDN MTLS_VERIFY OLLAMA_UPSTREAM COMFYUI_UPSTREAM SSO_ENABLED OAUTH2_PROXY_UPSTREAM
export MODEL_VAULT_MODE MODEL_VAULT_REMOTE_BASE_URL MODEL_VAULT_SSL_VERIFY MODEL_VAULT_SSL_TRUSTED_CERT

if [ "$MTLS_VERIFY" = "off" ]; then
  MTLS_CA_DIRECTIVE=""
else
  MTLS_CA_DIRECTIVE='ssl_client_certificate /etc/ssl/certs/localhost/ca.pem;'
fi

export MTLS_CA_DIRECTIVE

# If mTLS is enabled (optional/on), enforce client certs on registry endpoints.
# If mTLS is off, keep registry open to header-based auth only.
if [ "$MTLS_VERIFY" = "off" ]; then
  REGISTRY_MTLS_ENFORCE=""
else
  REGISTRY_MTLS_ENFORCE='if ($ssl_client_verify != SUCCESS) { return 401; }'
fi

export REGISTRY_MTLS_ENFORCE
export REGISTRY_SECRET

# --- Auth gate ---
if [ "$SSO_ENABLED" = "1" ]; then
  AUTH_GATE=$(cat <<'EOF'
auth_request /oauth2/auth;
error_page 401 = @sso_signin;
EOF
)
  SSO_LOCATIONS=$(cat <<EOF
location = /oauth2/auth {
    internal;
    set \$oauth2_upstream ${OAUTH2_PROXY_UPSTREAM};
    proxy_pass http://\$oauth2_upstream/oauth2/auth;
    proxy_set_header Host \$http_host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-Proto \$scheme;
    proxy_set_header X-Forwarded-Host \$http_host;
    proxy_set_header X-Forwarded-Uri \$request_uri;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
}

location /oauth2/ {
    set \$oauth2_upstream ${OAUTH2_PROXY_UPSTREAM};
    proxy_pass http://\$oauth2_upstream;
    proxy_set_header Host \$http_host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-Proto \$scheme;
    proxy_set_header X-Forwarded-Host \$http_host;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
}

location @sso_signin {
    return 302 /oauth2/start?rd=\$scheme://\$http_host\$request_uri;
}
EOF
)
else
  AUTH_GATE=$(cat <<'EOF'
auth_basic "Access Restricted";
auth_basic_user_file /etc/nginx/.htpasswd;
EOF
)
  SSO_LOCATIONS=""
fi

export AUTH_GATE SSO_LOCATIONS

# --- Model Vault proxying (local vs remote) ---
if [ "$MODEL_VAULT_MODE" = "remote" ]; then
  MODEL_VAULT_API_PROXY_PASS="${MODEL_VAULT_REMOTE_BASE_URL}/model-vault/"
  MODEL_VAULT_REGISTER_PROXY_PASS="${MODEL_VAULT_REMOTE_BASE_URL}/register"
  MODEL_VAULT_DISCOVER_PROXY_PASS="${MODEL_VAULT_REMOTE_BASE_URL}/discover"
  MODEL_VAULT_PROXY_SSL=$(cat <<EOF
proxy_ssl_server_name on;
proxy_ssl_verify ${MODEL_VAULT_SSL_VERIFY};
proxy_ssl_trusted_certificate ${MODEL_VAULT_SSL_TRUSTED_CERT};
proxy_ssl_verify_depth 2;
EOF
)
else
  MODEL_VAULT_API_PROXY_PASS="http://model_vault_backend/"
  MODEL_VAULT_REGISTER_PROXY_PASS="http://model_vault_backend/register"
  MODEL_VAULT_DISCOVER_PROXY_PASS="http://model_vault_backend/discover"
  MODEL_VAULT_PROXY_SSL=""
fi

export MODEL_VAULT_API_PROXY_PASS MODEL_VAULT_REGISTER_PROXY_PASS MODEL_VAULT_DISCOVER_PROXY_PASS MODEL_VAULT_PROXY_SSL

envsubst '${STACK_FQDN} ${MTLS_VERIFY} ${OLLAMA_UPSTREAM} ${COMFYUI_UPSTREAM} ${OAUTH2_PROXY_UPSTREAM} ${SSO_LOCATIONS} ${AUTH_GATE} ${MTLS_CA_DIRECTIVE} ${REGISTRY_MTLS_ENFORCE} ${REGISTRY_SECRET} ${MODEL_VAULT_API_PROXY_PASS} ${MODEL_VAULT_REGISTER_PROXY_PASS} ${MODEL_VAULT_DISCOVER_PROXY_PASS} ${MODEL_VAULT_PROXY_SSL}' \
  < "$TEMPLATE_PATH" > "$OUTPUT_PATH"

echo "[nginx-envsubst] Rendered $OUTPUT_PATH (STACK_FQDN=$STACK_FQDN, MTLS_VERIFY=$MTLS_VERIFY, SSO_ENABLED=$SSO_ENABLED, MODEL_VAULT_MODE=$MODEL_VAULT_MODE)"
