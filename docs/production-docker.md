# Production Docker Compose Deployment Guide

## Overview
This guide documents the production-grade Docker Compose setup for the ComfyUI/Ollama AI stack, designed for homelab deployment with a clear migration path to Kubernetes.

## Architecture Principles

### Namespacing
- **Stack name**: `comfyui-homelab` (set via `name:` in compose file)
- **Container naming**: Auto-prefixed pattern (`comfyui-homelab-*-1`)
- **Network isolation**: Custom bridge network `comfyui-homelab-net`
- **Volume namespacing**: External volume `comfyui-homelab-model-vault-data`

### Service Discovery
- **Internal DNS**: Docker embedded DNS (127.0.0.11) for service-to-service communication
- **Service names**: `model-vault:8080`, `langchain:8000`, `langflow:7860`, `code_executor:5000`, `oauth2-proxy:4180`
- **Nginx resolver**: `resolver 127.0.0.11 valid=10s;` for dynamic DNS resolution
- **Pattern**: Mirrors Kubernetes Service DNS (`<service-name>.<namespace>.svc.cluster.local`)

### Port Strategy
- **External access**: Only nginx exposes host ports (8081:80, 8444:443)
- **Internal services**: No host port mappings, rely on Docker DNS
- **Security**: Minimizes attack surface, enforces ingress routing

### Volume Management
- **External volumes**: `comfyui-homelab-model-vault-data` for persistence
- **Named volumes**: `langchain_vectorstore`, `langflow_data` for service data
- **Host mounts**: Limited to config files (read-only where possible)

## Directory Structure
```
comfyui/
├── docker-compose.homelab.yml   # Production compose file
├── .env.homelab                 # Environment variables
├── nginx.conf.template          # Nginx template with service discovery
├── tools/
│   ├── nginx-envsubst.sh        # Variable substitution for nginx
│   ├── backup-model-vault.sh    # Backup automation
│   ├── restore-model-vault.sh   # Restore automation
│   └── provision-models.sh      # Model download/import
├── src/
│   └── bin/
│       └── certman.rs           # SSL cert automation (Rust)
├── ssl/
│   ├── ca/                      # Certificate Authority files
│   ├── certs/                   # Generated certificates
│   └── k8s/                     # K8s cert-manager exports
└── docs/
    ├── production-docker.md     # This file
    ├── backup-recovery.md       # Backup/restore procedures
    └── ssl-automation.md        # SSL/TLS certificate automation
```

## Deployment

### Prerequisites
- Docker 24.0+ with Compose V2
- SSH access to homelab server (key-based auth)
- 3TB+ storage for models
- LAN DNS configured (homelab.lan → 192.168.1.170)

### Initial Setup

1. **Copy files to homelab**:
```bash
scp docker-compose.homelab.yml .env.homelab nginx.conf.template homelab:/home/kang/Documents/projects/comfyui/
scp -r tools ssl homelab:/home/kang/Documents/projects/comfyui/
```

2. **Create external volumes**:
```bash
ssh homelab 'sudo docker volume create comfyui-homelab-model-vault-data'
```

3. **Initialize Model Vault database**:
```bash
ssh homelab 'sudo docker run --rm -v comfyui-homelab-model-vault-data:/data alpine sh -c "mkdir -p /data && touch /data/model-vault.db && chmod 666 /data/model-vault.db"'
```

4. **Generate htpasswd** (if not using SSO):
```bash
ssh homelab 'cd /home/kang/Documents/projects/comfyui && echo "admin:$(openssl passwd -apr1 admin)" > .htpasswd'
```

5. **Deploy stack**:
```bash
ssh homelab 'cd /home/kang/Documents/projects/comfyui && sudo docker compose -f docker-compose.homelab.yml --env-file .env.homelab up -d'
```

### Verification

```bash
# Check service status
ssh homelab 'sudo docker compose -f docker-compose.homelab.yml --env-file .env.homelab ps'

# Test nginx healthcheck
ssh homelab 'curl -s http://localhost:8081/healthz'

# Test Model Vault (with basic auth)
ssh homelab 'curl -s -u admin:admin http://localhost:8081/model-vault/health'

# Check logs
ssh homelab 'sudo docker compose -f docker-compose.homelab.yml --env-file .env.homelab logs -f nginx model-vault'
```

## SSL/TLS Automation

### Certificate Management (certman)
The stack includes a Rust-based tool for automated SSL certificate provisioning:

```bash
# Enable SSL automation in .env.homelab
SSL_AUTO_PROVISION=1
SSL_KEY_TYPE=ecdsa-p384
SSL_DOMAIN=*.homelab.lan
SSL_AUTO_TRUST=0  # Set to 1 to auto-install Root CA

# Deploy with SSL profile
sudo docker compose --profile ssl-auto -f docker-compose.homelab.yml --env-file .env.homelab up -d
```

**Generated structure**:
- `ssl/ca/root-ca.{crt,key}` - Root CA (10 year validity)
- `ssl/ca/intermediate-ca.{crt,key}` - Intermediate CA (5 year validity)
- `ssl/certs/homelab.lan/wildcard.{crt,key}` - Wildcard cert (397 days)
- `ssl/certs/homelab.lan/fullchain.pem` - Full chain for nginx

**Key features**:
- ECDSA P-384 or RSA 4096 keys
- Modern validity periods (397 days for leaf certs)
- Automatic trust store installation (Linux/macOS/Windows)
- K8s cert-manager compatible export format

See [ssl-automation.md](ssl-automation.md) for detailed documentation.

## Backup & Recovery

### Automated Backups

```bash
# Manual backup
ssh homelab '/home/kang/Documents/projects/comfyui/tools/backup-model-vault.sh'

# Scheduled backup (cron)
0 2 * * * /home/kang/Documents/projects/comfyui/tools/backup-model-vault.sh

# Configure retention
export KEEP_BACKUPS=7  # Keep last 7 backups
```

**Backup includes**:
- SQLite database (with checkpoint)
- Model files from Docker volume
- Metadata (timestamp, inventory, sizes)
- SHA-256 checksum for integrity

**Output**: `backups/model-vault/model-vault-YYYYMMDD-HHMMSS.tar.zst`

### Restore

```bash
# List available backups
ls -lh backups/model-vault/

# Restore from backup
ssh homelab '/home/kang/Documents/projects/comfyui/tools/restore-model-vault.sh backups/model-vault/model-vault-20260101-120000.tar.zst'

# Force restore without confirmation
ssh homelab '/home/kang/Documents/projects/comfyui/tools/restore-model-vault.sh --force backups/model-vault/model-vault-20260101-120000.tar.zst'
```

## Model Provisioning

### Download Curated Models

```bash
# List available models (~80GB total)
tools/provision-models.sh --list

# Download specific models
tools/provision-models.sh llama-3.1-8b-instruct-q4 mistral-nemo-12b-instruct-q4

# Download all text/code models
tools/provision-models.sh --type text
tools/provision-models.sh --type code

# Download all models
tools/provision-models.sh --all

# Dry run to see what would be downloaded
tools/provision-models.sh --dry-run --type diffusion
```

**Model categories**:
- **Text/Code**: Llama 3.1 8B, Mistral Nemo 12B, Qwen2.5 14B Coder, DeepSeek Coder V2 Lite 16B
- **Multimodal**: Llava 1.6 (Mistral & Vicuna variants)
- **Diffusion**: SD1.5, SDXL base/refiner, Juggernaut XL
- **Audio**: Whisper Large V3
- **Embedding**: BGE Large EN v1.5

**Storage**: Models downloaded to `/srv/models/<type>/` on homelab.

## Secrets Management

### Current (Docker Compose)
Secrets stored in `.env.homelab`:
- `MODEL_VAULT_TOKEN` - Protects Model Vault API endpoints
- `REGISTRY_SECRET` - Protects worker registration endpoints
- `OAUTH2_PROXY_COOKIE_SECRET` - OAuth2 session encryption
- Basic auth passwords in `.htpasswd`

### Kubernetes Migration
Convert to Kubernetes Secrets:
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: model-vault-tokens
  namespace: comfyui-homelab
type: Opaque
stringData:
  model-vault-token: "{{ MODEL_VAULT_TOKEN }}"
  registry-secret: "{{ REGISTRY_SECRET }}"
  oauth2-cookie-secret: "{{ OAUTH2_PROXY_COOKIE_SECRET }}"
```

Reference in Deployments:
```yaml
env:
  - name: MODEL_VAULT_TOKEN
    valueFrom:
      secretKeyRef:
        name: model-vault-tokens
        key: model-vault-token
```

## Kubernetes Migration Path

### Phase 1: Docker Compose (Current)
- Single-node deployment
- Docker DNS for service discovery
- External volumes for persistence
- Nginx ingress

### Phase 2: Kubernetes Manifests
1. **Convert services to Deployments**:
   - `model-vault` → `Deployment` with `PersistentVolumeClaim`
   - `nginx` → `Ingress` controller + `Service`
   - Internal services → `ClusterIP` Services

2. **Networking**:
   - Docker network → Kubernetes namespace
   - Service names remain unchanged
   - DNS: `<service>.<namespace>.svc.cluster.local`

3. **Storage**:
   - External volumes → `PersistentVolume` + `PersistentVolumeClaim`
   - Host paths → `hostPath` or NFS volumes

4. **Secrets**:
   - `.env` variables → `Secret` + `ConfigMap` resources
   - `.htpasswd` → `Secret` (type: `Opaque`)

### Phase 3: Helm Chart
Package as Helm chart for repeatable deployments:
```yaml
# values.yaml
modelVault:
  replicas: 1
  storage:
    size: 1Ti
    storageClass: local-path
  token: ""  # Set via --set or sealed secrets

nginx:
  ingress:
    enabled: true
    className: nginx
    host: homelab.lan
    tls:
      enabled: true
      secretName: homelab-tls
```

### Example Manifest Conversion

**Docker Compose** (current):
```yaml
services:
  model-vault:
    image: comfyui-homelab-model-vault
    networks:
      - comfyui-net
    volumes:
      - model_vault_data:/var/lib/model-vault
    environment:
      - MODEL_VAULT_TOKEN=${MODEL_VAULT_TOKEN}
```

**Kubernetes Deployment**:
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: model-vault
  namespace: comfyui-homelab
spec:
  replicas: 1
  selector:
    matchLabels:
      app: model-vault
  template:
    metadata:
      labels:
        app: model-vault
    spec:
      containers:
      - name: model-vault
        image: comfyui-homelab-model-vault:latest
        env:
        - name: MODEL_VAULT_TOKEN
          valueFrom:
            secretKeyRef:
              name: model-vault-tokens
              key: model-vault-token
        volumeMounts:
        - name: data
          mountPath: /var/lib/model-vault
      volumes:
      - name: data
        persistentVolumeClaim:
          claimName: model-vault-data
---
apiVersion: v1
kind: Service
metadata:
  name: model-vault
  namespace: comfyui-homelab
spec:
  selector:
    app: model-vault
  ports:
  - port: 8080
    targetPort: 8080
  type: ClusterIP
```

## Security Hardening

### Network Security
- [ ] Only nginx exposes host ports
- [ ] Internal services isolated on custom bridge network
- [ ] No direct host-to-service access (except via nginx)
- [ ] Consider Wireguard VPN for remote access

### Authentication
- [ ] Basic auth for development (admin/admin)
- [ ] OAuth2/OIDC via oauth2-proxy for production
- [ ] Keycloak for self-hosted IdP
- [ ] mTLS for worker-to-Model-Vault communication

### Secrets
- [ ] Never commit `.env.*` files to git
- [ ] Use `.env.example` as template
- [ ] Rotate secrets regularly (see `tools/rotate-secrets.sh`)
- [ ] Consider sealed-secrets or Vault for K8s

### SSL/TLS
- [ ] Use certman for automated cert generation
- [ ] Install Root CA to trusted stores only on managed devices
- [ ] Enable SSL_AUTO_TRUST=1 only in controlled environments
- [ ] Consider Let's Encrypt for public-facing deployments

## Troubleshooting

### Service Unhealthy
```bash
# Check logs
ssh homelab 'sudo docker logs comfyui-homelab-<service>-1 --tail 50'

# Inspect healthcheck
ssh homelab 'sudo docker inspect comfyui-homelab-<service>-1 | jq ".[].State.Health"'

# Test directly (bypass nginx)
ssh homelab 'sudo docker exec comfyui-homelab-nginx-1 wget -q -O- http://<service>:<port>/health'
```

### DNS Resolution Issues
```bash
# Check resolver config in nginx
ssh homelab 'sudo docker exec comfyui-homelab-nginx-1 cat /etc/nginx/nginx.conf | grep resolver'

# Test DNS from nginx container
ssh homelab 'sudo docker exec comfyui-homelab-nginx-1 nslookup model-vault'

# Verify service is on correct network
ssh homelab 'sudo docker inspect comfyui-homelab-<service>-1 | jq ".[].NetworkSettings.Networks"'
```

### Volume Permissions
```bash
# Fix Model Vault DB permissions
ssh homelab 'sudo docker run --rm -v comfyui-homelab-model-vault-data:/data alpine sh -c "chmod 666 /data/model-vault.db"'

# Check volume contents
ssh homelab 'sudo docker run --rm -v comfyui-homelab-model-vault-data:/data alpine ls -la /data'
```

### Port Conflicts
```bash
# Check what's using ports
ssh homelab 'sudo ss -tlnp | grep -E ":(8081|8444)"'

# Ensure compose file doesn't expose internal ports
grep -n "ports:" docker-compose.homelab.yml
```

## Monitoring & Observability

### Health Checks
- Nginx: `http://localhost:8081/healthz`
- Model Vault: `http://localhost:8081/model-vault/health`
- Langchain: `http://langchain:8000/health` (internal)
- Langflow: `http://langflow:7860/` (internal)

### Logs
```bash
# All services
sudo docker compose -f docker-compose.homelab.yml logs -f

# Specific service
sudo docker compose -f docker-compose.homelab.yml logs -f model-vault

# With timestamps
sudo docker compose -f docker-compose.homelab.yml logs -f --timestamps
```

### Metrics (Future)
- Prometheus exporters for services
- Grafana dashboards for visualization
- Alertmanager for notifications

## References
- [Docker Compose Best Practices](https://docs.docker.com/compose/production/)
- [Kubernetes Service DNS](https://kubernetes.io/docs/concepts/services-networking/dns-pod-service/)
- [cert-manager Documentation](https://cert-manager.io/docs/)
- [nginx Ingress Controller](https://kubernetes.github.io/ingress-nginx/)
