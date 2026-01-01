#!/bin/bash

set -euo pipefail

# Rotate MODEL_VAULT_TOKEN and REGISTRY_SECRET without losing volumes.
# - Updates local env files (homelab + desktop + single-node) if present
# - Optionally updates remote homelab env and triggers redeploy
#
# Usage (local only):
#   ./tools/rotate-secrets.sh
#
# Usage (also update homelab + redeploy):
#   REMOTE_SSH=kang@192.168.1.170 REMOTE_PROJECT_DIR=/data/projects/comfyui ./tools/rotate-secrets.sh --remote

ENV_FILES=(.env.homelab .env.desktop .env.single-node-gpu)

REMOTE=false
if [ "${1:-}" = "--remote" ]; then
  REMOTE=true
fi

if ! command -v openssl >/dev/null 2>&1; then
  echo "openssl is required" >&2
  exit 1
fi

MODEL_VAULT_TOKEN=$(openssl rand -hex 32)
REGISTRY_SECRET=$(openssl rand -hex 32)

update_file() {
  local f="$1"
  [ -f "$f" ] || return 0

  if grep -q '^MODEL_VAULT_TOKEN=' "$f"; then
    sed -i "s|^MODEL_VAULT_TOKEN=.*|MODEL_VAULT_TOKEN=$MODEL_VAULT_TOKEN|" "$f"
  else
    echo "MODEL_VAULT_TOKEN=$MODEL_VAULT_TOKEN" >> "$f"
  fi

  if grep -q '^REGISTRY_SECRET=' "$f"; then
    sed -i "s|^REGISTRY_SECRET=.*|REGISTRY_SECRET=$REGISTRY_SECRET|" "$f"
  else
    echo "REGISTRY_SECRET=$REGISTRY_SECRET" >> "$f"
  fi

  echo "[rotate] Updated $f"
}

for f in "${ENV_FILES[@]}"; do
  update_file "$f"
done

echo "[rotate] New MODEL_VAULT_TOKEN and REGISTRY_SECRET generated."

echo "[rotate] NOTE: This does not delete volumes; existing models remain intact."

if [ "$REMOTE" = true ]; then
  REMOTE_SSH=${REMOTE_SSH:-kang@192.168.1.170}
  REMOTE_PROJECT_DIR=${REMOTE_PROJECT_DIR:-/data/projects/comfyui}
  SSH_OPTS=${SSH_OPTS:-"-o StrictHostKeyChecking=accept-new"}
  REMOTE_SUDO=${REMOTE_SUDO:-auto}

  echo "[rotate] Pushing updated .env.homelab to remote and redeploying..."
  scp $SSH_OPTS .env.homelab "$REMOTE_SSH:$REMOTE_PROJECT_DIR/.env.homelab"

  # Determine whether docker requires sudo on the remote.
  DOCKER_PREFIX="docker"
  if [ "$REMOTE_SUDO" = "1" ]; then
    DOCKER_PREFIX="sudo -n docker"
  elif [ "$REMOTE_SUDO" = "auto" ]; then
    if ssh $SSH_OPTS "$REMOTE_SSH" "docker info >/dev/null 2>&1"; then
      DOCKER_PREFIX="docker"
    elif ssh $SSH_OPTS "$REMOTE_SSH" "command -v sudo >/dev/null 2>&1 && sudo -n docker info >/dev/null 2>&1"; then
      DOCKER_PREFIX="sudo -n docker"
    fi
  fi

  ssh $SSH_OPTS "$REMOTE_SSH" "bash -lc 'cd "'$REMOTE_PROJECT_DIR'" && "'$DOCKER_PREFIX'" compose -f docker-compose.homelab.yml --env-file .env.homelab up -d --build'"

  echo "[rotate] Remote redeploy done."
fi
