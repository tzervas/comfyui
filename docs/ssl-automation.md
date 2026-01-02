# SSL/TLS Certificate Automation

## Overview
The `certman` tool automates SSL/TLS certificate provisioning for the ComfyUI stack, eliminating manual certificate management and ensuring trusted HTTPS connections across all services.

## Features
- **Automated CA hierarchy**: Root CA → Intermediate CA → service certificates
- **Wildcard certificates**: Single cert for `*.homelab.lan`
- **Trust automation**: One-command Root CA installation to system trust stores
- **Modern cryptography**: ECDSA P-384 (default) or RSA 4096
- **K8s-ready**: Export format compatible with cert-manager
- **Secure by default**: Proper key permissions, validity periods, extensions

## Architecture

### Certificate Hierarchy
```
Root CA (10 years)
  └── Intermediate CA (5 years)
      └── Wildcard Cert (397 days)
          ├── *.homelab.lan
          └── homelab.lan
```

### File Layout
```
ssl/
├── ca/
│   ├── root-ca.key          # Root CA private key (NEVER share)
│   ├── root-ca.crt          # Root CA certificate
│   ├── intermediate-ca.key  # Intermediate CA private key
│   ├── intermediate-ca.crt  # Intermediate CA certificate
│   ├── chain.pem            # Full chain (intermediate + root)
│   └── metadata.json        # CA metadata
├── certs/
│   └── homelab.lan/
│       ├── wildcard.key     # Wildcard private key
│       ├── wildcard.crt     # Wildcard certificate
│       ├── fullchain.pem    # cert + chain (for nginx)
│       └── metadata.json    # Cert metadata
└── k8s/
    └── cert-manager-format.yaml  # K8s export
```

## Quick Start

### 1. Enable SSL Automation
Add to `.env.homelab`:
```bash
SSL_AUTO_PROVISION=1              # Enable auto cert generation
SSL_KEY_TYPE=ecdsa-p384           # Key algorithm
SSL_DOMAIN=*.homelab.lan          # Wildcard domain
SSL_AUTO_TRUST=0                  # Don't auto-trust (manual for security)
```

### 2. Deploy with SSL Profile
```bash
cd /home/kang/Documents/projects/comfyui
sudo docker compose --profile ssl-auto -f docker-compose.homelab.yml --env-file .env.homelab up -d
```

This will:
1. Build `certman` binary from Rust source
2. Initialize Root CA and Intermediate CA (if not exists)
3. Generate wildcard certificate for `*.homelab.lan`
4. Place certificates in `ssl/` directory
5. Start nginx with new certificates

### 3. Install Root CA (Manual)
For trusted HTTPS in browsers:

**Linux**:
```bash
sudo cp ssl/ca/root-ca.crt /usr/local/share/ca-certificates/comfyui-root-ca.crt
sudo update-ca-certificates
```

**macOS**:
```bash
sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain ssl/ca/root-ca.crt
```

**Windows**:
```powershell
certutil -addstore -f "ROOT" ssl\ca\root-ca.crt
```

**Or use certman** (requires sudo):
```bash
docker run --rm -v ./ssl:/ssl comfyui-homelab-certman install-trust --os linux
```

### 4. Verify HTTPS
```bash
# Test from local machine
curl -v https://homelab.lan:8444/healthz

# Should show:
# * SSL connection using TLSv1.3 / ECDHE-ECDSA-AES256-GCM-SHA384
# * Server certificate:
# *  subject: CN=*.homelab.lan
# *  issuer: CN=ComfyUI Intermediate CA
```

## Manual Usage

### Build certman Binary
```bash
cd /home/kang/Documents/projects/comfyui
docker build -t certman -f Dockerfile.certman .
```

### Initialize CA
```bash
docker run --rm -v ./ssl:/ssl certman init-ca \
  --key-type ecdsa-p384 \
  --root-validity-days 3650 \
  --intermediate-validity-days 1825
```

**Output**:
- `ssl/ca/root-ca.{crt,key}`
- `ssl/ca/intermediate-ca.{crt,key}`
- `ssl/ca/chain.pem`

### Generate Wildcard Certificate
```bash
docker run --rm -v ./ssl:/ssl certman generate-cert \
  --domain "*.homelab.lan" \
  --validity-days 397
```

**Output**:
- `ssl/certs/homelab.lan/wildcard.{crt,key}`
- `ssl/certs/homelab.lan/fullchain.pem`

### Generate Single-Domain Certificate
```bash
docker run --rm -v ./ssl:/ssl certman generate-cert \
  --domain "homelab.lan" \
  --validity-days 397
```

## Configuration Variables

### .env Variables
```bash
# Enable/disable automation
SSL_AUTO_PROVISION=0|1

# Key algorithm
SSL_KEY_TYPE=ecdsa-p384|rsa4096

# Validity periods (days)
SSL_ROOT_VALIDITY_DAYS=3650           # Root CA: 10 years
SSL_INTERMEDIATE_VALIDITY_DAYS=1825   # Intermediate: 5 years
SSL_CERT_VALIDITY_DAYS=397            # Leaf certs: 397 days (browser limit)

# Certificate domain
SSL_DOMAIN=*.homelab.lan              # Wildcard or single domain

# Trust automation
SSL_AUTO_TRUST=0|1                    # Auto-install Root CA (use with caution)

# Renewal threshold
SSL_RENEW_DAYS_BEFORE=30              # Renew if expiring within 30 days
```

### Security Considerations

**SSL_AUTO_TRUST=0 (Recommended)**:
- Manual trust installation ensures control
- Prevents accidental trust of potentially compromised CA
- Allows per-device trust decisions

**SSL_AUTO_TRUST=1 (Use with caution)**:
- Only enable in fully controlled environments
- Requires sudo/admin privileges
- Installs Root CA to system trust store automatically

## Certificate Renewal

### Manual Renewal
```bash
# Regenerate certificate (keeps same CA)
docker run --rm -v ./ssl:/ssl certman generate-cert \
  --domain "*.homelab.lan" \
  --validity-days 397

# Restart nginx to pick up new cert
sudo docker compose -f docker-compose.homelab.yml restart nginx
```

### Automated Renewal (Future)
Add to cron:
```bash
# Check and renew certificates daily at 3 AM
0 3 * * * /home/kang/Documents/projects/comfyui/tools/renew-certs.sh
```

Create `tools/renew-certs.sh`:
```bash
#!/usr/bin/env bash
cd /home/kang/Documents/projects/comfyui

# Check if renewal needed (certman renew command - not yet implemented)
docker run --rm -v ./ssl:/ssl certman renew --days-before 30

# Reload nginx if certs were renewed
if [ -f /tmp/certs-renewed ]; then
    sudo docker compose -f docker-compose.homelab.yml restart nginx
    rm /tmp/certs-renewed
fi
```

## Kubernetes Migration

### cert-manager Export
```bash
docker run --rm -v ./ssl:/ssl certman export-k8s --namespace comfyui-homelab
```

**Output** (`ssl/k8s/cert-manager-format.yaml`):
```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: comfyui-ca
spec:
  ca:
    secretName: comfyui-root-ca
---
apiVersion: v1
kind: Secret
metadata:
  name: comfyui-root-ca
  namespace: cert-manager
type: kubernetes.io/tls
data:
  tls.crt: <base64-encoded-root-ca-crt>
  tls.key: <base64-encoded-root-ca-key>
---
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: homelab-wildcard
  namespace: comfyui-homelab
spec:
  secretName: homelab-tls
  issuerRef:
    name: comfyui-ca
    kind: ClusterIssuer
  dnsNames:
    - "*.homelab.lan"
    - "homelab.lan"
  privateKey:
    algorithm: ECDSA
    size: 384
  duration: 8760h  # 1 year
  renewBefore: 720h  # 30 days
```

### Apply to Kubernetes
```bash
kubectl apply -f ssl/k8s/cert-manager-format.yaml

# Verify certificate
kubectl get certificate -n comfyui-homelab
kubectl describe certificate homelab-wildcard -n comfyui-homelab
```

## Troubleshooting

### Certificate Not Trusted
```bash
# Check certificate chain
openssl s_client -connect homelab.lan:8444 -showcerts

# Verify Root CA is installed
# Linux
ls /usr/local/share/ca-certificates/ | grep comfyui

# macOS
security find-certificate -c "ComfyUI Root CA" -a

# Windows
certutil -store ROOT | findstr "ComfyUI"
```

### Permission Denied
```bash
# Check key file permissions (should be 600)
ls -l ssl/ca/*.key ssl/certs/*/wildcard.key

# Fix if needed
chmod 600 ssl/ca/*.key ssl/certs/*/wildcard.key
```

### Certificate Expired
```bash
# Check validity
openssl x509 -in ssl/certs/homelab.lan/wildcard.crt -noout -dates

# Regenerate
docker run --rm -v ./ssl:/ssl certman generate-cert --domain "*.homelab.lan"
sudo docker compose -f docker-compose.homelab.yml restart nginx
```

### Wrong Domain
```bash
# Check SANs (Subject Alternative Names)
openssl x509 -in ssl/certs/homelab.lan/wildcard.crt -noout -text | grep -A1 "Subject Alternative Name"

# Should show:
#   DNS:*.homelab.lan, DNS:homelab.lan
```

## Best Practices

### Key Management
- **Root CA key**: Store offline, encrypted, backed up securely
- **Intermediate CA key**: Keep on deployment server, restrict access
- **Certificate keys**: 600 permissions, owned by docker user

### Validity Periods
- **Root CA**: 10 years (rarely renewed, offline)
- **Intermediate CA**: 5 years (online signing)
- **Leaf certificates**: 397 days (Apple/Chrome requirement)

### Trust Distribution
- **Development**: Manual trust on developer machines only
- **Production**: Distribute Root CA via MDM/GPO/Ansible
- **Public**: Use Let's Encrypt instead of self-signed CA

### Rotation Schedule
- **Root CA**: Every 10 years (or on compromise)
- **Intermediate CA**: Every 5 years
- **Leaf certificates**: Auto-renew 30 days before expiry

## References
- [RFC 5280: X.509 Certificate Format](https://tools.ietf.org/html/rfc5280)
- [cert-manager Documentation](https://cert-manager.io/docs/)
- [Mozilla SSL Configuration Generator](https://ssl-config.mozilla.org/)
- [Chrome Root Certificate Policy](https://www.chromium.org/Home/chromium-security/root-ca-policy/)
