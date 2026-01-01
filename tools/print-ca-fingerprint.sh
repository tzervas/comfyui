#!/usr/bin/env bash
set -euo pipefail

CA_PEM=${CA_PEM:-"$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/ssl/ca.pem"}

if [[ ! -f "$CA_PEM" ]]; then
  echo "CA file not found: $CA_PEM" >&2
  exit 2
fi

openssl x509 -in "$CA_PEM" -noout -subject -issuer -fingerprint -sha256
