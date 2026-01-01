#!/usr/bin/env bash
set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "This script is for macOS." >&2
  exit 2
fi

# Remove by SHA-1 fingerprint match from the system keychain.
CA_PEM="${1:-ssl/ca.pem}"

if [[ ! -f "$CA_PEM" ]]; then
  echo "CA cert not found: $CA_PEM" >&2
  exit 2
fi

SHA1=$(openssl x509 -in "$CA_PEM" -noout -fingerprint -sha1 | sed 's/^.*=//; s/://g')
if [[ -z "$SHA1" ]]; then
  echo "Could not compute SHA1 fingerprint." >&2
  exit 1
fi

sudo security delete-certificate -Z "$SHA1" /Library/Keychains/System.keychain || true

echo "Removed CA from System keychain (if present)."
