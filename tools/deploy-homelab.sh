#!/bin/bash

set -euo pipefail

# Deploy/update the homelab control-plane stack to a stable path on /data.
# This script:
# 1) Creates a remote project directory under /data
# 2) Rsyncs the local repo to the remote directory
# 3) Runs docker compose (homelab) to update containers
# 4) Waits for containers to be running/healthy
#
# Defaults assume:
#   homelab: kang@192.168.1.170
# Remote path:
#   /data/projects/comfyui

REMOTE_USER=${REMOTE_USER:-kang}
REMOTE_HOST=${REMOTE_HOST:-192.168.1.170}
REMOTE_SSH=${REMOTE_SSH:-"${REMOTE_USER}@${REMOTE_HOST}"}

# Safer-than-off: accept and pin new host keys on first connect.
SSH_OPTS=${SSH_OPTS:-"-o StrictHostKeyChecking=accept-new"}

# Some hosts require sudo for Docker access.
# - REMOTE_DOCKER_SUDO=auto|1|0
#   auto: try docker, fallback to sudo -n docker
REMOTE_DOCKER_SUDO=${REMOTE_DOCKER_SUDO:-auto}

REMOTE_BASE_DIR=${REMOTE_BASE_DIR:-/data/projects}
REMOTE_PROJECT_NAME=${REMOTE_PROJECT_NAME:-comfyui}
REMOTE_PROJECT_DIR=${REMOTE_PROJECT_DIR:-"${REMOTE_BASE_DIR}/${REMOTE_PROJECT_NAME}"}

COMPOSE_FILES=${COMPOSE_FILES:-"docker-compose.homelab.yml docker-compose.openwebui.yml"}
ENV_FILE=${ENV_FILE:-.env.homelab}

# Additional flags for `docker compose up`.
# Default includes --force-recreate so bind-mount absolute paths and container env
# are refreshed even if the remote project directory changed.
COMPOSE_UP_FLAGS=${COMPOSE_UP_FLAGS:-"-d --build --force-recreate"}

RSYNC_EXCLUDES=${RSYNC_EXCLUDES:-tools/rsync-excludes.txt}

# Compose profiles to enable (computed from ENV_FILE).
COMPOSE_PROFILE_ARGS=${COMPOSE_PROFILE_ARGS:-""}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing required command: $1" >&2
    exit 1
  }
}

require_cmd ssh
require_cmd rsync

for f in $COMPOSE_FILES; do
  if [ ! -f "$f" ]; then
    echo "Missing compose file: $f" >&2
    exit 1
  fi
done
if [ ! -f "$ENV_FILE" ]; then
  echo "Missing $ENV_FILE in current directory" >&2
  exit 1
fi
if [ ! -f "$RSYNC_EXCLUDES" ]; then
  echo "Missing $RSYNC_EXCLUDES" >&2
  exit 1
fi

if [ -z "$COMPOSE_PROFILE_ARGS" ]; then
  if grep -Eq '^(SSO_ENABLED|KEYCLOAK_ENABLED)=1' "$ENV_FILE"; then
    COMPOSE_PROFILE_ARGS="--profile sso"
  fi
fi

echo "[deploy] Remote: $REMOTE_SSH"
echo "[deploy] Remote dir: $REMOTE_PROJECT_DIR"

detect_remote_docker_prefix() {
  if [ "$REMOTE_DOCKER_SUDO" = "1" ]; then
    echo "sudo -n docker"; return 0
  fi
  if [ "$REMOTE_DOCKER_SUDO" = "0" ]; then
    echo "docker"; return 0
  fi

  if ssh $SSH_OPTS "$REMOTE_SSH" "docker info >/dev/null 2>&1"; then
    echo "docker"; return 0
  fi
  if ssh $SSH_OPTS "$REMOTE_SSH" "command -v sudo >/dev/null 2>&1 && sudo -n docker info >/dev/null 2>&1"; then
    echo "sudo -n docker"; return 0
  fi
  echo "docker"
}

REMOTE_DOCKER_PREFIX=$(detect_remote_docker_prefix)
echo "[deploy] Remote docker prefix: $REMOTE_DOCKER_PREFIX"

# Ensure remote directory exists (on /data). If /data is root-owned, use sudo -n.
ssh $SSH_OPTS "$REMOTE_SSH" "bash -c '
  set -eo pipefail
  REMOTE_PROJECT_DIR=\"'$REMOTE_PROJECT_DIR'\"
  REMOTE_USER=\"'$REMOTE_USER'\"
  if mkdir -p \"\$REMOTE_PROJECT_DIR\" 2>/dev/null; then
    exit 0
  fi
  if command -v sudo >/dev/null 2>&1; then
    sudo -n mkdir -p \"\$REMOTE_PROJECT_DIR\"
    sudo -n chown -R \"\$REMOTE_USER:\$REMOTE_USER\" \"\$REMOTE_PROJECT_DIR\" || true
    exit 0
  fi
  echo \"[deploy] Failed to create remote dir and sudo not available\" >&2
  exit 1
'"

# Sync repo
echo "[deploy] Syncing repo via rsync..."
rsync -az --delete \
  -e "ssh $SSH_OPTS" \
  --exclude-from="$RSYNC_EXCLUDES" \
  ./ "$REMOTE_SSH:$REMOTE_PROJECT_DIR/"

# Build docker compose -f args
COMPOSE_ARGS=""
for f in $COMPOSE_FILES; do
  COMPOSE_ARGS="$COMPOSE_ARGS -f $f"
done

# Check if stack is already deployed (best-effort)
echo "[deploy] Checking existing deployment state..."
ssh $SSH_OPTS "$REMOTE_SSH" "cd '$REMOTE_PROJECT_DIR' && (\
  if [ '$REMOTE_DOCKER_PREFIX' = 'sudo -n docker' ]; then sudo -n docker compose $COMPOSE_ARGS $COMPOSE_PROFILE_ARGS --env-file '$ENV_FILE' ps; else docker compose $COMPOSE_ARGS $COMPOSE_PROFILE_ARGS --env-file '$ENV_FILE' ps; fi \
  || true)"

# Render/validate config on remote
echo "[deploy] Validating compose config on remote..."
ssh $SSH_OPTS "$REMOTE_SSH" "cd '$REMOTE_PROJECT_DIR' && \
  if [ '$REMOTE_DOCKER_PREFIX' = 'sudo -n docker' ]; then sudo -n docker compose $COMPOSE_ARGS $COMPOSE_PROFILE_ARGS --env-file '$ENV_FILE' config >/dev/null; else docker compose $COMPOSE_ARGS $COMPOSE_PROFILE_ARGS --env-file '$ENV_FILE' config >/dev/null; fi"

# Best-effort migration: older configs used /tmp for storage (not volume-mounted).
# If any data exists there, copy it into /var/lib/model-vault (volume-mounted) before recreating.
echo "[deploy] Best-effort Model Vault storage migration (/tmp -> /var/lib/model-vault)..."
ssh $SSH_OPTS "$REMOTE_SSH" "cd '$REMOTE_PROJECT_DIR' && (\
  if [ '$REMOTE_DOCKER_PREFIX' = 'sudo -n docker' ]; then sudo -n -E bash tools/migrate-model-vault-storage.sh model-vault; else bash tools/migrate-model-vault-storage.sh model-vault; fi \
  || true)"

# Deploy/update
echo "[deploy] Applying update (build/pull as needed)..."
ssh $SSH_OPTS "$REMOTE_SSH" "cd '$REMOTE_PROJECT_DIR' && \
  if [ '$REMOTE_DOCKER_PREFIX' = 'sudo -n docker' ]; then sudo -n docker compose $COMPOSE_ARGS $COMPOSE_PROFILE_ARGS --env-file '$ENV_FILE' up $COMPOSE_UP_FLAGS; else docker compose $COMPOSE_ARGS $COMPOSE_PROFILE_ARGS --env-file '$ENV_FILE' up $COMPOSE_UP_FLAGS; fi"

# Wait for services
echo "[deploy] Waiting for containers to be running/healthy..."
ssh $SSH_OPTS "$REMOTE_SSH" "cd '$REMOTE_PROJECT_DIR' && \
  if [ '$REMOTE_DOCKER_PREFIX' = 'sudo -n docker' ]; then sudo -n docker compose $COMPOSE_ARGS $COMPOSE_PROFILE_ARGS --env-file '$ENV_FILE' ps; else docker compose $COMPOSE_ARGS $COMPOSE_PROFILE_ARGS --env-file '$ENV_FILE' ps; fi"

# Basic health wait loop (checks docker health status when present)
USE_SUDO=0
if [ "$REMOTE_DOCKER_PREFIX" = "sudo -n docker" ]; then
  USE_SUDO=1
fi

# NOTE: Use a quoted heredoc so that $(), $vars, and globs are evaluated on the
# remote host (not locally inside this script).
ssh $SSH_OPTS "$REMOTE_SSH" \
  "REMOTE_PROJECT_DIR='$REMOTE_PROJECT_DIR' USE_SUDO='$USE_SUDO' ENV_FILE='$ENV_FILE' COMPOSE_ARGS='$COMPOSE_ARGS' COMPOSE_PROFILE_ARGS='$COMPOSE_PROFILE_ARGS' bash -s" <<'REMOTE_SCRIPT'
set -euo pipefail

cd "$REMOTE_PROJECT_DIR"

dc() {
  if [ "${USE_SUDO}" = "1" ]; then
    sudo -n docker "$@"
  else
    docker "$@"
  fi
}

# Expand COMPOSE_ARGS (a string like: " -f a.yml -f b.yml") into an argv array.
read -r -a compose_args <<< "$COMPOSE_ARGS"
read -r -a profile_args <<< "$COMPOSE_PROFILE_ARGS"

ids=$(dc compose "${compose_args[@]}" "${profile_args[@]}" --env-file "$ENV_FILE" ps -q)
if [ -z "$ids" ]; then
  echo "[deploy] No containers found after up" >&2
  exit 1
fi

deadline=$((SECONDS+600))
while [ $SECONDS -lt $deadline ]; do
  all_ok=1
  for id in $ids; do
    status=$(dc inspect -f "{{.State.Status}}" "$id" 2>/dev/null || echo unknown)
    health=$(dc inspect -f "{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}" "$id" 2>/dev/null || echo unknown)
    if [ "$status" != "running" ]; then
      all_ok=0
    fi
    if [ "$health" != "none" ] && [ "$health" != "healthy" ]; then
      all_ok=0
    fi
  done

  if [ $all_ok -eq 1 ]; then
    echo "[deploy] All containers running/healthy."
    exit 0
  fi

  echo "[deploy] Waiting..."
  sleep 5
done

echo "[deploy] Timed out waiting for healthy containers." >&2
dc compose "${compose_args[@]}" "${profile_args[@]}" --env-file "$ENV_FILE" ps
dc compose "${compose_args[@]}" "${profile_args[@]}" --env-file "$ENV_FILE" logs --tail=200
exit 1
REMOTE_SCRIPT

echo "[deploy] Done. Your LAN ingress should be at https://<STACK_FQDN>/ (via Nginx)."
