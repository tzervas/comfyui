#!/bin/bash

set -euo pipefail

# Generates (on homelab) the CA/server certs + a gpu-worker client cert,
# then copies only the needed bundle (ca.pem + gpu-worker client cert/key)
# into the GPU worker project's ./ssl so docker-compose.desktop.yml can mount it.
#
# Assumptions:
# - You can SSH to both homelab and gpu worker
# - homelab repo path matches deploy script default: /data/projects/comfyui
# - gpu worker repo path: /data/projects/comfyui-worker (default)

HOMELAB_USER=${HOMELAB_USER:-kang}
HOMELAB_HOST=${HOMELAB_HOST:-192.168.1.170}
HOMELAB_SSH=${HOMELAB_SSH:-"${HOMELAB_USER}@${HOMELAB_HOST}"}
HOMELAB_PROJECT_DIR=${HOMELAB_PROJECT_DIR:-/data/projects/comfyui}

WORKER_USER=${WORKER_USER:-kang}
WORKER_HOST=${WORKER_HOST:-192.168.1.99}
WORKER_SSH=${WORKER_SSH:-"${WORKER_USER}@${WORKER_HOST}"}
WORKER_PROJECT_DIR=${WORKER_PROJECT_DIR:-/data/projects/comfyui-worker}

# Safer-than-off: accept and pin new host keys on first connect.
SSH_OPTS=${SSH_OPTS:-"-o StrictHostKeyChecking=accept-new"}

STACK_FQDN=${STACK_FQDN:-ai.homelab.lan}
STACK_IP=${STACK_IP:-192.168.1.170}
MTLS_CLIENT_NAME=${MTLS_CLIENT_NAME:-gpu-worker}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || { echo "Missing required command: $1" >&2; exit 1; }
}

require_cmd ssh
require_cmd scp
require_cmd mktemp

TMPDIR_LOCAL=$(mktemp -d)
trap 'rm -rf "$TMPDIR_LOCAL"' EXIT

echo "[mtls] Homelab: $HOMELAB_SSH ($HOMELAB_PROJECT_DIR)"
echo "[mtls] Worker:  $WORKER_SSH ($WORKER_PROJECT_DIR)"

# Ensure both dirs exist (may require sudo on /data)
ssh $SSH_OPTS "$HOMELAB_SSH" "bash -lc '
  set -euo pipefail
  if mkdir -p "'$HOMELAB_PROJECT_DIR'" 2>/dev/null; then exit 0; fi
  command -v sudo >/dev/null 2>&1 || exit 1
  sudo -n mkdir -p "'$HOMELAB_PROJECT_DIR'"
  sudo -n chown -R "'$HOMELAB_USER':'$HOMELAB_USER'" "'$HOMELAB_PROJECT_DIR'" || true
'"
ssh $SSH_OPTS "$WORKER_SSH" "bash -lc '
  set -euo pipefail
  if mkdir -p "'$WORKER_PROJECT_DIR/ssl/clients'" 2>/dev/null; then exit 0; fi
  command -v sudo >/dev/null 2>&1 || exit 1
  sudo -n mkdir -p "'$WORKER_PROJECT_DIR/ssl/clients'"
  sudo -n chown -R "'$WORKER_USER':'$WORKER_USER'" "'$WORKER_PROJECT_DIR'" || true
'"

# Generate on homelab (CA/server/client)
echo "[mtls] Generating certs on homelab..."
ssh $SSH_OPTS "$HOMELAB_SSH" "cd '$HOMELAB_PROJECT_DIR' && \
  STACK_FQDN='$STACK_FQDN' STACK_IP='$STACK_IP' MTLS_CLIENT_NAME='$MTLS_CLIENT_NAME' \
  ./tools/generate-mtls-pki.sh"

# Pull only what we need to local temp
echo "[mtls] Downloading bundle from homelab to local temp..."
scp $SSH_OPTS "$HOMELAB_SSH:$HOMELAB_PROJECT_DIR/ssl/ca.pem" "$TMPDIR_LOCAL/ca.pem"
scp $SSH_OPTS "$HOMELAB_SSH:$HOMELAB_PROJECT_DIR/ssl/clients/${MTLS_CLIENT_NAME}.pem" "$TMPDIR_LOCAL/${MTLS_CLIENT_NAME}.pem"
scp $SSH_OPTS "$HOMELAB_SSH:$HOMELAB_PROJECT_DIR/ssl/clients/${MTLS_CLIENT_NAME}-key.pem" "$TMPDIR_LOCAL/${MTLS_CLIENT_NAME}-key.pem"

# Upload to worker into its repo ssl/
echo "[mtls] Uploading bundle to worker repo ssl/..."
scp $SSH_OPTS "$TMPDIR_LOCAL/ca.pem" "$WORKER_SSH:$WORKER_PROJECT_DIR/ssl/ca.pem"
scp $SSH_OPTS "$TMPDIR_LOCAL/${MTLS_CLIENT_NAME}.pem" "$WORKER_SSH:$WORKER_PROJECT_DIR/ssl/clients/${MTLS_CLIENT_NAME}.pem"
scp $SSH_OPTS "$TMPDIR_LOCAL/${MTLS_CLIENT_NAME}-key.pem" "$WORKER_SSH:$WORKER_PROJECT_DIR/ssl/clients/${MTLS_CLIENT_NAME}-key.pem"

echo "[mtls] Done. Next: set MTLS_VERIFY=optional|on in homelab .env.homelab and redeploy nginx."