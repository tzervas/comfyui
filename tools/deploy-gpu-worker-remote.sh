#!/bin/bash

set -euo pipefail

# Deploy/update the GPU worker stack on a remote machine (default 192.168.1.99)
# into a stable /data/projects path.
#
# It rsyncs this repo to WORKER_PROJECT_DIR then runs:
#   docker compose -f docker-compose.desktop.yml --env-file .env.desktop up -d --build

WORKER_USER=${WORKER_USER:-kang}
WORKER_HOST=${WORKER_HOST:-192.168.1.99}
WORKER_SSH=${WORKER_SSH:-"${WORKER_USER}@${WORKER_HOST}"}

# Safer-than-off: accept and pin new host keys on first connect.
SSH_OPTS=${SSH_OPTS:-"-o StrictHostKeyChecking=accept-new"}

# Some hosts require sudo for Docker access.
# - WORKER_DOCKER_SUDO=auto|1|0
#   auto: try docker, fallback to sudo -n docker
WORKER_DOCKER_SUDO=${WORKER_DOCKER_SUDO:-auto}

WORKER_BASE_DIR=${WORKER_BASE_DIR:-/data/projects}
WORKER_PROJECT_NAME=${WORKER_PROJECT_NAME:-comfyui-worker}
WORKER_PROJECT_DIR=${WORKER_PROJECT_DIR:-"${WORKER_BASE_DIR}/${WORKER_PROJECT_NAME}"}

COMPOSE_FILE=${COMPOSE_FILE:-docker-compose.desktop.yml}
ENV_FILE=${ENV_FILE:-.env.desktop}
RSYNC_FILES=${RSYNC_FILES:-tools/rsync-files-desktop.txt}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || { echo "Missing required command: $1" >&2; exit 1; }
}

require_cmd ssh
require_cmd rsync

if [ ! -f "$COMPOSE_FILE" ]; then
  echo "Missing $COMPOSE_FILE in current directory" >&2
  exit 1
fi
if [ ! -f "$ENV_FILE" ]; then
  echo "Missing $ENV_FILE in current directory" >&2
  exit 1
fi
if [ ! -f "$RSYNC_FILES" ]; then
  echo "Missing $RSYNC_FILES" >&2
  exit 1
fi

echo "[worker] Remote: $WORKER_SSH"
echo "[worker] Remote dir: $WORKER_PROJECT_DIR"

detect_worker_docker_prefix() {
  if [ "$WORKER_DOCKER_SUDO" = "1" ]; then
    echo "sudo -n docker"; return 0
  fi
  if [ "$WORKER_DOCKER_SUDO" = "0" ]; then
    echo "docker"; return 0
  fi

  if ssh $SSH_OPTS "$WORKER_SSH" "docker info >/dev/null 2>&1"; then
    echo "docker"; return 0
  fi
  if ssh $SSH_OPTS "$WORKER_SSH" "command -v sudo >/dev/null 2>&1 && sudo -n docker info >/dev/null 2>&1"; then
    echo "sudo -n docker"; return 0
  fi
  echo "docker"
}

WORKER_DOCKER_PREFIX=$(detect_worker_docker_prefix)
echo "[worker] Remote docker prefix: $WORKER_DOCKER_PREFIX"

# Ensure remote directory exists (may require sudo on /data)
ssh $SSH_OPTS "$WORKER_SSH" "bash -lc '
  set -euo pipefail
  if mkdir -p "'$WORKER_PROJECT_DIR'" 2>/dev/null; then
    exit 0
  fi
  if command -v sudo >/dev/null 2>&1; then
    sudo -n mkdir -p "'$WORKER_PROJECT_DIR'"
    sudo -n chown -R "'$WORKER_USER':'$WORKER_USER'" "'$WORKER_PROJECT_DIR'" || true
    exit 0
  fi
  echo "[worker] Failed to create remote dir and sudo not available" >&2
  exit 1
'"

echo "[worker] Syncing minimal bundle via rsync (preserves worker ./ssl)..."
rsync -az --relative --files-from="$RSYNC_FILES" \
  -e "ssh $SSH_OPTS" \
  ./ "$WORKER_SSH:$WORKER_PROJECT_DIR/"

echo "[worker] Validating compose config on worker..."
ssh $SSH_OPTS "$WORKER_SSH" "cd '$WORKER_PROJECT_DIR' && \
  if [ '$WORKER_DOCKER_PREFIX' = 'sudo -n docker' ]; then sudo -n docker compose -f '$COMPOSE_FILE' --env-file '$ENV_FILE' config >/dev/null; else docker compose -f '$COMPOSE_FILE' --env-file '$ENV_FILE' config >/dev/null; fi"

echo "[worker] Deploying worker stack..."
ssh $SSH_OPTS "$WORKER_SSH" "cd '$WORKER_PROJECT_DIR' && \
  if [ '$WORKER_DOCKER_PREFIX' = 'sudo -n docker' ]; then sudo -n docker compose -f '$COMPOSE_FILE' --env-file '$ENV_FILE' up -d --build; else docker compose -f '$COMPOSE_FILE' --env-file '$ENV_FILE' up -d --build; fi"

echo "[worker] Waiting for containers to be running/healthy..."
ssh $SSH_OPTS "$WORKER_SSH" "bash -lc '
  set -euo pipefail
  cd "$WORKER_PROJECT_DIR"
  COMPOSE_FILE="$COMPOSE_FILE"
  ENV_FILE="$ENV_FILE"

  DOCKER="$WORKER_DOCKER_PREFIX"

  ids=$($DOCKER compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" ps -q)
  if [ -z "$ids" ]; then
    echo "[worker] No containers found after up" >&2
    exit 1
  fi

  deadline=$((SECONDS+240))
  while [ $SECONDS -lt $deadline ]; do
    all_ok=1
    for id in $ids; do
      status=$($DOCKER inspect -f "{{.State.Status}}" "$id" 2>/dev/null || echo unknown)
      health=$($DOCKER inspect -f "{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}" "$id" 2>/dev/null || echo unknown)
      if [ "$status" != "running" ]; then
        all_ok=0
      fi
      if [ "$health" != "none" ] && [ "$health" != "healthy" ]; then
        all_ok=0
      fi
    done

    if [ $all_ok -eq 1 ]; then
      echo "[worker] All containers running/healthy."
      exit 0
    fi

    echo "[worker] Waiting..."
    sleep 5
  done

  echo "[worker] Timed out waiting for healthy containers." >&2
  $DOCKER compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" ps
  $DOCKER compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" logs --tail=200
  exit 1
'"

echo "[worker] Status:"
ssh $SSH_OPTS "$WORKER_SSH" "cd '$WORKER_PROJECT_DIR' && \
  if [ '$WORKER_DOCKER_PREFIX' = 'sudo -n docker' ]; then sudo -n docker compose -f '$COMPOSE_FILE' --env-file '$ENV_FILE' ps; else docker compose -f '$COMPOSE_FILE' --env-file '$ENV_FILE' ps; fi"

echo "[worker] Done."