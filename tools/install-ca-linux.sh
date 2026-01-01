#!/usr/bin/env bash
set -euo pipefail

CA_PEM=${CA_PEM:-"$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/ssl/ca.pem"}
DEST_NAME=${DEST_NAME:-comfyui-stack-ca.crt}
DEST_DIR=/usr/local/share/ca-certificates
DEST_PATH="$DEST_DIR/$DEST_NAME"

if [[ ! -f "$CA_PEM" ]]; then
  echo "CA file not found: $CA_PEM" >&2
  echo "Generate it with: ./tools/generate-mtls-pki.sh" >&2
  exit 2
fi

if [[ $EUID -ne 0 ]]; then
  echo "This script needs sudo to install into $DEST_DIR" >&2
  echo "Run: sudo $0" >&2
  exit 2
fi

install -m 0644 "$CA_PEM" "$DEST_PATH"

if command -v update-ca-certificates >/dev/null 2>&1; then
  update-ca-certificates
else
  echo "update-ca-certificates not found; install 'ca-certificates' package" >&2
  exit 2
fi

echo "Installed CA to: $DEST_PATH"
echo "If Firefox still warns, enable enterprise roots or import CA manually (see docs/trusted-certs.md)."
