#!/bin/bash

set -euo pipefail

# Generates a small local PKI suitable for LAN TLS + optional mTLS at the ingress.
# Outputs into ./ssl by default:
# - ssl/ca.pem, ssl/ca-key.pem
# - ssl/cert.pem, ssl/key.pem (server cert for STACK_FQDN)
# - ssl/clients/gpu-worker.pem, ssl/clients/gpu-worker-key.pem
#
# Usage:
#   STACK_FQDN=ai.homelab.lan ./tools/generate-mtls-pki.sh
# Optional:
#   MTLS_CLIENT_NAME=gpu-worker STACK_IP=192.168.1.170 ./tools/generate-mtls-pki.sh

OUT_DIR=${OUT_DIR:-./ssl}
CLIENT_NAME=${MTLS_CLIENT_NAME:-gpu-worker}
STACK_FQDN=${STACK_FQDN:-ai.homelab.lan}
STACK_IP=${STACK_IP:-}

mkdir -p "$OUT_DIR/clients"
chmod 700 "$OUT_DIR" "$OUT_DIR/clients" || true

CA_KEY="$OUT_DIR/ca-key.pem"
CA_CERT="$OUT_DIR/ca.pem"
SERVER_KEY="$OUT_DIR/key.pem"
SERVER_CERT="$OUT_DIR/cert.pem"

CLIENT_KEY="$OUT_DIR/clients/${CLIENT_NAME}-key.pem"
CLIENT_CERT="$OUT_DIR/clients/${CLIENT_NAME}.pem"

if ! command -v openssl >/dev/null 2>&1; then
  echo "openssl is required" >&2
  exit 1
fi

# Create CA (if missing)
if [ ! -f "$CA_KEY" ] || [ ! -f "$CA_CERT" ]; then
  echo "[pki] Creating CA..."
  openssl genrsa -out "$CA_KEY" 4096
  openssl req -x509 -new -nodes -key "$CA_KEY" -sha256 -days 3650 \
    -subj "/CN=comfyui-homelab-ca" \
    -out "$CA_CERT"
  chmod 600 "$CA_KEY" || true
fi

# Create server cert for STACK_FQDN (+ optional IP SAN)
echo "[pki] Creating server cert for $STACK_FQDN ${STACK_IP:+(IP $STACK_IP)}..."
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

cat > "$TMPDIR/server-openssl.cnf" <<EOF
[ req ]
default_bits       = 4096
distinguished_name = req_distinguished_name
req_extensions     = req_ext
prompt             = no

[ req_distinguished_name ]
CN = ${STACK_FQDN}

[ req_ext ]
subjectAltName = @alt_names

[ alt_names ]
DNS.1 = ${STACK_FQDN}
EOF

if [ -n "$STACK_IP" ]; then
  echo "IP.1 = ${STACK_IP}" >> "$TMPDIR/server-openssl.cnf"
fi

openssl genrsa -out "$SERVER_KEY" 4096
openssl req -new -key "$SERVER_KEY" -out "$TMPDIR/server.csr" -config "$TMPDIR/server-openssl.cnf"
openssl x509 -req -in "$TMPDIR/server.csr" -CA "$CA_CERT" -CAkey "$CA_KEY" -CAcreateserial \
  -out "$SERVER_CERT" -days 825 -sha256 -extfile "$TMPDIR/server-openssl.cnf" -extensions req_ext
chmod 600 "$SERVER_KEY" || true

# Create client cert
echo "[pki] Creating client cert: $CLIENT_NAME"
cat > "$TMPDIR/client-openssl.cnf" <<EOF
[ req ]
default_bits       = 2048
distinguished_name = req_distinguished_name
prompt             = no

[ req_distinguished_name ]
CN = ${CLIENT_NAME}
EOF

openssl genrsa -out "$CLIENT_KEY" 2048
openssl req -new -key "$CLIENT_KEY" -out "$TMPDIR/client.csr" -config "$TMPDIR/client-openssl.cnf"
openssl x509 -req -in "$TMPDIR/client.csr" -CA "$CA_CERT" -CAkey "$CA_KEY" -CAcreateserial \
  -out "$CLIENT_CERT" -days 825 -sha256
chmod 600 "$CLIENT_KEY" || true

echo "[pki] Wrote:"
echo "  - $CA_CERT"
echo "  - $SERVER_CERT"
echo "  - $CLIENT_CERT"

echo "[pki] Next: set MTLS_VERIFY=optional (or on) in .env.homelab and redeploy nginx."
