#!/usr/bin/env bash
set -euo pipefail

CA_PEM="${1:-ssl/ca.pem}"

if [[ ! -f "$CA_PEM" ]]; then
  echo "CA cert not found: $CA_PEM" >&2
  exit 2
fi

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "This script is for macOS." >&2
  exit 2
fi

# Adds to the System keychain and marks as trusted.
# Requires admin password (sudo).
CERT_NAME="ComfyUI Stack Local CA"

sudo security add-trusted-cert -d -r trustRoot \
  -k /Library/Keychains/System.keychain \
  "$CA_PEM"

echo "Installed CA into System keychain."
