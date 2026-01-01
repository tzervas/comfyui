#!/usr/bin/env bash
set -euo pipefail

DEST_NAME=${DEST_NAME:-comfyui-stack-ca.crt}
DEST_DIR=/usr/local/share/ca-certificates
DEST_PATH="$DEST_DIR/$DEST_NAME"

if [[ $EUID -ne 0 ]]; then
  echo "This script needs sudo." >&2
  echo "Run: sudo $0" >&2
  exit 2
fi

if [[ -f "$DEST_PATH" ]]; then
  rm -f "$DEST_PATH"
fi

if command -v update-ca-certificates >/dev/null 2>&1; then
  update-ca-certificates
fi

echo "Removed CA: $DEST_PATH"
