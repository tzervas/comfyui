#!/usr/bin/env bash
set -euo pipefail

# Migration helper to avoid losing Model Vault downloads when switching
# storage.path from /tmp to /var/lib/model-vault.
#
# Safe behavior:
# - Only copies from /tmp -> /var/lib if /tmp has data AND /var/lib is empty-ish.
# - Does not delete /tmp contents.
#
# Usage:
#   tools/migrate-model-vault-storage.sh [container_name]

CONTAINER=${1:-model-vault}

if ! command -v docker >/dev/null 2>&1; then
  echo "docker not found" >&2
  exit 1
fi

if ! docker inspect "$CONTAINER" >/dev/null 2>&1; then
  echo "container not found: $CONTAINER" >&2
  exit 2
fi

echo "[migrate] Inspecting $CONTAINER..."

docker exec "$CONTAINER" sh -lc '
set -eu

SRC=/tmp
DST=/var/lib/model-vault

src_has=0
if [ -d "$SRC" ] && [ "$(ls -A "$SRC" 2>/dev/null | wc -l)" -gt 0 ]; then
  src_has=1
fi

dst_has=0
if [ -d "$DST" ] && [ "$(ls -A "$DST" 2>/dev/null | wc -l)" -gt 0 ]; then
  dst_has=1
fi

echo "[migrate] src=$SRC has_data=$src_has"
echo "[migrate] dst=$DST has_data=$dst_has"

if [ "$src_has" -ne 1 ]; then
  echo "[migrate] Nothing to migrate (source empty)."
  exit 0
fi

if [ "$dst_has" -eq 1 ]; then
  echo "[migrate] Destination already has data; not copying."
  exit 0
fi

echo "[migrate] Copying $SRC -> $DST (best-effort, non-destructive)..."
mkdir -p "$DST"
cp -a "$SRC"/. "$DST"/

echo "[migrate] Done."
'
