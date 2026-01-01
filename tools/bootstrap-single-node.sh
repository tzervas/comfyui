#!/usr/bin/env bash
set -euo pipefail

# Bootstraps and deploys the single-node all-in-one stack on this host.
# - Generates/updates secrets in .env.single-node-gpu
# - Generates TLS certs for STACK_FQDN (+ optional STACK_IP SAN)
# - Generates a fresh .htpasswd with random passwords
# - Brings down any conflicting compose stacks (desktop/homelab) if requested
# - Deploys docker-compose.single-node-gpu.yml
# - Runs validation harness

ENV_FILE=${ENV_FILE:-.env.single-node-gpu}
COMPOSE_FILE=${COMPOSE_FILE:-docker-compose.single-node-gpu.yml}
STACK_FQDN=${STACK_FQDN:-akula-prime.lan}
STACK_IP=${STACK_IP:-192.168.1.99}

STOP_CONFLICTING=${STOP_CONFLICTING:-1}

if [[ ! -f "$ENV_FILE" ]]; then
  echo "env file not found: $ENV_FILE" >&2
  exit 2
fi
if [[ ! -f "$COMPOSE_FILE" ]]; then
  echo "compose file not found: $COMPOSE_FILE" >&2
  exit 2
fi

# Load current env values
set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a

upsert_env() {
  local key=$1
  local value=$2
  if grep -qE "^${key}=" "$ENV_FILE"; then
    sed -i -E "s|^${key}=.*|${key}=${value}|" "$ENV_FILE"
  else
    echo "${key}=${value}" >> "$ENV_FILE"
  fi
}

if ! grep -qE '^MODEL_VAULT_MODE=' "$ENV_FILE"; then
  upsert_env MODEL_VAULT_MODE "remote"
fi
if ! grep -qE '^MODEL_VAULT_REMOTE_BASE_URL=' "$ENV_FILE"; then
  upsert_env MODEL_VAULT_REMOTE_BASE_URL "https://homelab.lan:8443"
fi

# Secure-by-default: enable SSO + Keycloak unless explicitly disabled.
if ! grep -qE '^SSO_ENABLED=' "$ENV_FILE"; then
  upsert_env SSO_ENABLED "1"
fi
if ! grep -qE '^KEYCLOAK_ENABLED=' "$ENV_FILE"; then
  upsert_env KEYCLOAK_ENABLED "1"
fi

# Optional baseline allowlist for SSO
SSO_ALLOWED_EMAILS=${SSO_ALLOWED_EMAILS:-}
OAUTH2_PROXY_CFG_PATH="config/oauth2-proxy/oauth2-proxy.cfg"
OAUTH2_PROXY_EMAILS_PATH="config/oauth2-proxy/allowed_emails.txt"

mkdir -p "config/oauth2-proxy"

if [[ -n "$SSO_ALLOWED_EMAILS" ]]; then
  echo "[sso] Writing baseline allowlist to ${OAUTH2_PROXY_EMAILS_PATH}"
  : > "$OAUTH2_PROXY_EMAILS_PATH"
  IFS=',' read -ra EMAILS <<< "$SSO_ALLOWED_EMAILS"
  for e in "${EMAILS[@]}"; do
    e=$(echo "$e" | xargs)
    [[ -n "$e" ]] && echo "$e" >> "$OAUTH2_PROXY_EMAILS_PATH"
  done

  echo "[sso] Enabling authenticated_emails_file in ${OAUTH2_PROXY_CFG_PATH}"
  cat > "$OAUTH2_PROXY_CFG_PATH" <<'EOF'
# OAuth2 Proxy config (TOML-like).
# Provider/client credentials are supplied via env vars in docker-compose.

proxy_prefix = "/oauth2"
upstreams = ["file:///dev/null"]
reverse_proxy = true
set_xauthrequest = true
skip_provider_button = true

# Healthcheck endpoint exposed through nginx at /oauth2/ping
ping_path = "/oauth2/ping"

# Baseline allowlist (one email per line)
authenticated_emails_file = "/etc/oauth2-proxy/allowed_emails.txt"

# Still allow any domain, but the allowlist above restricts actual users.
email_domains = ["*"]
EOF
else
  # Ensure files exist in a sane default (open login mode).
  if [[ ! -f "$OAUTH2_PROXY_EMAILS_PATH" ]]; then
    cat > "$OAUTH2_PROXY_EMAILS_PATH" <<'EOF'
# One email per line. When enabled, only these users may access.
# Example:
# admin@example.com
EOF
  fi
  if [[ ! -f "$OAUTH2_PROXY_CFG_PATH" ]]; then
    cat > "$OAUTH2_PROXY_CFG_PATH" <<'EOF'
# OAuth2 Proxy config (TOML-like).
# Provider/client secrets are supplied via env vars in docker-compose.

proxy_prefix = "/oauth2"
upstreams = ["file:///dev/null"]
reverse_proxy = true
set_xauthrequest = true
skip_provider_button = true

# Healthcheck endpoint exposed through nginx at /oauth2/ping
ping_path = "/oauth2/ping"

# Open login mode (IdP controls who can authenticate).
email_domains = ["*"]
EOF
  fi
fi

# Ensure FQDN is correct
upsert_env STACK_FQDN "$STACK_FQDN"

# Generate secrets (always rotate for a clean bootstrap)
MODEL_VAULT_TOKEN=$(openssl rand -hex 32)
REGISTRY_SECRET=$(openssl rand -hex 32)

# oauth2-proxy cookie secret (urlsafe base64)
OAUTH2_PROXY_COOKIE_SECRET=$(openssl rand -base64 32 | tr -d '\n' | tr '+/' '-_')

upsert_env MODEL_VAULT_TOKEN "$MODEL_VAULT_TOKEN"
upsert_env REGISTRY_SECRET "$REGISTRY_SECRET"
upsert_env OAUTH2_PROXY_COOKIE_SECRET "$OAUTH2_PROXY_COOKIE_SECRET"

# If not set, compute a sane default redirect URL for oauth2-proxy
NGINX_SSL_PORT=${NGINX_SSL_PORT:-8443}
if ! grep -qE '^OAUTH2_PROXY_REDIRECT_URL=' "$ENV_FILE"; then
  upsert_env OAUTH2_PROXY_REDIRECT_URL "https://${STACK_FQDN}:${NGINX_SSL_PORT}/oauth2/callback"
fi

# --- Optional self-hosted IdP: Keycloak ---
KEYCLOAK_ENABLED=${KEYCLOAK_ENABLED:-0}
SSO_EMAIL_DOMAIN=${SSO_EMAIL_DOMAIN:-local.lan}

if [[ "$KEYCLOAK_ENABLED" == "1" ]]; then
  # Ensure SSO is enabled when running a local IdP
  upsert_env SSO_ENABLED "1"

  # Keycloak bootstrap admin (for admin console)
  KEYCLOAK_BOOTSTRAP_ADMIN_USERNAME=${KEYCLOAK_BOOTSTRAP_ADMIN_USERNAME:-kcadmin}
  KEYCLOAK_BOOTSTRAP_ADMIN_PASSWORD=${KEYCLOAK_BOOTSTRAP_ADMIN_PASSWORD:-$(openssl rand -base64 18 | tr -d '\n' | tr -d '=')}
  upsert_env KEYCLOAK_BOOTSTRAP_ADMIN_USERNAME "$KEYCLOAK_BOOTSTRAP_ADMIN_USERNAME"
  upsert_env KEYCLOAK_BOOTSTRAP_ADMIN_PASSWORD "$KEYCLOAK_BOOTSTRAP_ADMIN_PASSWORD"

  # oauth2-proxy OIDC client
  OAUTH2_PROXY_CLIENT_ID=${OAUTH2_PROXY_CLIENT_ID:-comfyui-ingress}
  OAUTH2_PROXY_CLIENT_SECRET=${OAUTH2_PROXY_CLIENT_SECRET:-$(openssl rand -base64 32 | tr -d '\n' | tr '+/' '-_')}
  upsert_env OAUTH2_PROXY_CLIENT_ID "$OAUTH2_PROXY_CLIENT_ID"
  upsert_env OAUTH2_PROXY_CLIENT_SECRET "$OAUTH2_PROXY_CLIENT_SECRET"

  # Issuer URL for the imported realm behind nginx
  upsert_env OIDC_ISSUER_URL "https://${STACK_FQDN}:${NGINX_SSL_PORT}/keycloak/realms/comfyui"

  # Baseline realm users
  SSO_ADMIN_PASS=${SSO_ADMIN_PASS:-$(openssl rand -base64 18 | tr -d '\n' | tr -d '=')}
  SSO_USER1_PASS=${SSO_USER1_PASS:-$(openssl rand -base64 18 | tr -d '\n' | tr -d '=')}
  SSO_USER2_PASS=${SSO_USER2_PASS:-$(openssl rand -base64 18 | tr -d '\n' | tr -d '=')}
  upsert_env SSO_EMAIL_DOMAIN "$SSO_EMAIL_DOMAIN"
  upsert_env SSO_ADMIN_PASS "$SSO_ADMIN_PASS"
  upsert_env SSO_USER1_PASS "$SSO_USER1_PASS"
  upsert_env SSO_USER2_PASS "$SSO_USER2_PASS"

  # Default allowlist to baseline users unless user overrides
  if ! grep -qE '^SSO_ALLOWED_EMAILS=' "$ENV_FILE"; then
    upsert_env SSO_ALLOWED_EMAILS "admin@${SSO_EMAIL_DOMAIN},user1@${SSO_EMAIL_DOMAIN},user2@${SSO_EMAIL_DOMAIN}"
    SSO_ALLOWED_EMAILS="admin@${SSO_EMAIL_DOMAIN},user1@${SSO_EMAIL_DOMAIN},user2@${SSO_EMAIL_DOMAIN}"
  fi

  # Render realm import with injected secrets/passwords
  TEMPLATE="config/keycloak/realm-comfyui.json.template"
  OUT="config/keycloak/realm-comfyui.json"
  if [[ ! -f "$TEMPLATE" ]]; then
    echo "Missing Keycloak realm template: $TEMPLATE" >&2
    exit 2
  fi
  sed \
    -e "s/__OAUTH2_PROXY_CLIENT_SECRET__/${OAUTH2_PROXY_CLIENT_SECRET}/g" \
    -e "s/__STACK_FQDN__/${STACK_FQDN}/g" \
    -e "s/__NGINX_SSL_PORT__/${NGINX_SSL_PORT}/g" \
    -e "s/__SSO_EMAIL_DOMAIN__/${SSO_EMAIL_DOMAIN}/g" \
    -e "s/__SSO_ADMIN_PASS__/${SSO_ADMIN_PASS}/g" \
    -e "s/__SSO_USER1_PASS__/${SSO_USER1_PASS}/g" \
    -e "s/__SSO_USER2_PASS__/${SSO_USER2_PASS}/g" \
    "$TEMPLATE" > "$OUT"
  chmod 600 "$OUT" || true
fi

# Generate basic auth users
ADMIN_PASS=$(openssl rand -base64 18 | tr -d '\n' | tr -d '=')
USER1_PASS=$(openssl rand -base64 18 | tr -d '\n' | tr -d '=')
USER2_PASS=$(openssl rand -base64 18 | tr -d '\n' | tr -d '=')

ADMIN_HASH=$(openssl passwd -apr1 "${ADMIN_PASS}")
USER1_HASH=$(openssl passwd -apr1 "${USER1_PASS}")
USER2_HASH=$(openssl passwd -apr1 "${USER2_PASS}")

cat > .htpasswd <<EOF
admin:${ADMIN_HASH}
user1:${USER1_HASH}
user2:${USER2_HASH}
EOF
# Must be readable by nginx worker processes inside the container.
chmod 644 .htpasswd

# Generate TLS certs
STACK_FQDN="$STACK_FQDN" STACK_IP="$STACK_IP" ./tools/generate-mtls-pki.sh

if [[ "$STOP_CONFLICTING" == "1" ]]; then
  # Best-effort shutdown of other stacks that commonly use conflicting container_name values.
  if [[ -f docker-compose.desktop.yml && -f .env.desktop ]]; then
    docker compose -f docker-compose.desktop.yml --env-file .env.desktop down || true
  fi
  if [[ -f docker-compose.homelab.yml && -f .env.homelab ]]; then
    docker compose -f docker-compose.homelab.yml --env-file .env.homelab down || true
  fi
fi

# Deploy

MODEL_VAULT_MODE=${MODEL_VAULT_MODE:-remote}
SSO_ENABLED=${SSO_ENABLED:-0}

KEYCLOAK_ENABLED=${KEYCLOAK_ENABLED:-0}

PROFILES=()
if [[ "$MODEL_VAULT_MODE" == "local" ]]; then
  PROFILES+=(--profile local-vault)
fi
if [[ "$SSO_ENABLED" == "1" ]]; then
  PROFILES+=(--profile sso)
fi

if [[ "$KEYCLOAK_ENABLED" == "1" ]]; then
  PROFILES+=(--profile keycloak)
fi

docker compose "${PROFILES[@]}" -f "$COMPOSE_FILE" --env-file "$ENV_FILE" up -d --build

# Nginx resolves upstreams at startup; restart to ensure it loads the latest
# config + service discovery state.
docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" restart nginx || true

# Wait for health
SERVICES=(ollama comfyui langchain langflow code_executor nginx)
if [[ "$MODEL_VAULT_MODE" == "local" ]]; then
  SERVICES=(model-vault "${SERVICES[@]}")
fi
if [[ "$SSO_ENABLED" == "1" ]]; then
  SERVICES=(oauth2-proxy "${SERVICES[@]}")
fi
if [[ "$KEYCLOAK_ENABLED" == "1" ]]; then
  SERVICES=(keycloak-db keycloak "${SERVICES[@]}")
fi

for s in "${SERVICES[@]}"; do
  echo "[wait] $s"
  for _ in $(seq 1 90); do
    status=$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$s" 2>/dev/null || true)
    if [[ "$status" == "healthy" || "$status" == "running" ]]; then
      break
    fi
    sleep 2
  done
  status=$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$s" 2>/dev/null || true)
  echo "[wait] $s => $status"
  if [[ "$status" != "healthy" && "$status" != "running" ]]; then
    echo "[wait] $s did not become healthy/running" >&2
    docker logs --tail 200 "$s" >&2 || true
    exit 1
  fi
done

# Validate through ingress
if [[ "$SSO_ENABLED" == "1" ]]; then
  echo "[validate] SSO is enabled; skipping basic-auth validation harness."
else
  BASIC_AUTH_USER=admin BASIC_AUTH_PASS="$ADMIN_PASS" ./tools/tests/validate-stack.sh --env-file "$ENV_FILE"
fi

cat <<EOF

=== ACCESS ===
Base URL: https://${STACK_FQDN}:${NGINX_SSL_PORT:-8443}
ComfyUI:  https://${STACK_FQDN}:${NGINX_SSL_PORT:-8443}/comfyui/
Ollama:   https://${STACK_FQDN}:${NGINX_SSL_PORT:-8443}/ollama/
LangChain https://${STACK_FQDN}:${NGINX_SSL_PORT:-8443}/langchain/docs
LangFlow: https://${STACK_FQDN}:${NGINX_SSL_PORT:-8443}/langflow/
CodeExec: https://${STACK_FQDN}:${NGINX_SSL_PORT:-8443}/code-executor/

=== BASIC AUTH ===
admin / ${ADMIN_PASS}
user1 / ${USER1_PASS}
user2 / ${USER2_PASS}

=== SSO (oauth2-proxy) ===
SSO_ENABLED=${SSO_ENABLED:-0}
OIDC_ISSUER_URL=${OIDC_ISSUER_URL:-}
OAUTH2_PROXY_CLIENT_ID=${OAUTH2_PROXY_CLIENT_ID:-}
OAUTH2_PROXY_CLIENT_SECRET=${OAUTH2_PROXY_CLIENT_SECRET:-}
OAUTH2_PROXY_REDIRECT_URL=${OAUTH2_PROXY_REDIRECT_URL:-}

=== KEYCLOAK (self-hosted IdP) ===
KEYCLOAK_ENABLED=${KEYCLOAK_ENABLED:-0}
KEYCLOAK_BOOTSTRAP_ADMIN_USERNAME=${KEYCLOAK_BOOTSTRAP_ADMIN_USERNAME:-}
KEYCLOAK_BOOTSTRAP_ADMIN_PASSWORD=${KEYCLOAK_BOOTSTRAP_ADMIN_PASSWORD:-}
Keycloak URL: https://${STACK_FQDN}:${NGINX_SSL_PORT:-8443}/keycloak/
Realm users: admin/user1/user2 (see SSO_*_PASS in env file)

=== MODEL-VAULT / REGISTRY ===
MODEL_VAULT_TOKEN=${MODEL_VAULT_TOKEN}
REGISTRY_SECRET=${REGISTRY_SECRET}
EOF
