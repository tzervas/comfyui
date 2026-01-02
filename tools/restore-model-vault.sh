#!/usr/bin/env bash
set -euo pipefail

# Model Vault Restore Script
# Restores Model Vault database and model files from backup archive

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Configuration
BACKUP_DIR="${BACKUP_DIR:-$PROJECT_ROOT/backups/model-vault}"
ENV_FILE="${ENV_FILE:-$PROJECT_ROOT/.env.homelab}"
COMPOSE_FILE="${COMPOSE_FILE:-$PROJECT_ROOT/docker-compose.homelab.yml}"
VERIFY_CHECKSUM="${VERIFY_CHECKSUM:-1}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $*"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
}

usage() {
    cat <<EOF
Usage: $0 [OPTIONS] BACKUP_FILE

Restore Model Vault from backup archive.

OPTIONS:
  --no-verify      Skip checksum verification
  --force          Skip confirmation prompt
  -h, --help       Show this help message

EXAMPLES:
  # Restore from specific backup
  $0 backups/model-vault/model-vault-20260101-120000.tar.zst

  # Restore latest backup without verification
  $0 --no-verify \$(ls -1t backups/model-vault/*.tar.zst | head -1)
EOF
}

# Parse arguments
FORCE=0
BACKUP_FILE=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --no-verify)
            VERIFY_CHECKSUM=0
            shift
            ;;
        --force)
            FORCE=1
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            BACKUP_FILE="$1"
            shift
            ;;
    esac
done

if [[ -z "$BACKUP_FILE" ]]; then
    log_error "No backup file specified"
    usage
    exit 1
fi

if [[ ! -f "$BACKUP_FILE" ]]; then
    log_error "Backup file not found: $BACKUP_FILE"
    exit 1
fi

log_info "Restore from: $BACKUP_FILE"

# Verify checksum
if [[ "$VERIFY_CHECKSUM" = "1" ]] && [[ -f "$BACKUP_FILE.sha256" ]]; then
    log_info "Verifying backup integrity..."
    if ! sha256sum -c "$BACKUP_FILE.sha256"; then
        log_error "Checksum verification failed!"
        exit 1
    fi
    log_info "Checksum verified successfully"
else
    log_warn "Skipping checksum verification"
fi

# Confirmation prompt
if [[ "$FORCE" != "1" ]]; then
    log_warn "This will overwrite existing Model Vault data!"
    read -rp "Continue? (yes/no): " CONFIRM
    if [[ "$CONFIRM" != "yes" ]]; then
        log_info "Restore cancelled"
        exit 0
    fi
fi

# Load environment
if [[ -f "$ENV_FILE" ]]; then
    set -a
    # shellcheck disable=SC1090
    source "$ENV_FILE"
    set +a
fi

# Stop Model Vault service
log_info "Stopping Model Vault service..."
docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" stop model-vault || true

# Extract backup to temporary directory
TMP_RESTORE=$(mktemp -d)
trap 'rm -rf "$TMP_RESTORE"' EXIT

log_info "Extracting backup..."
zstd -d -c "$BACKUP_FILE" | tar -C "$TMP_RESTORE" -xf -

# Verify backup metadata
if [[ -f "$TMP_RESTORE/metadata.json" ]]; then
    log_info "Backup metadata:"
    jq -r '.timestamp, .backup_type, .source.volume' "$TMP_RESTORE/metadata.json" || cat "$TMP_RESTORE/metadata.json"
fi

# Restore database
if [[ -f "$TMP_RESTORE/database/model-vault.db" ]]; then
    log_info "Restoring database..."
    
    # Get volume name
    VOLUME_NAME=$(docker volume ls --format '{{.Name}}' | grep model-vault-data | head -1)
    if [[ -z "$VOLUME_NAME" ]]; then
        log_error "Model Vault data volume not found"
        exit 1
    fi
    
    # Copy database to volume
    docker run --rm -v "$VOLUME_NAME:/data" -v "$TMP_RESTORE/database:/restore:ro" alpine \
        sh -c 'cp /restore/model-vault.db /data/model-vault.db && chmod 666 /data/model-vault.db'
    
    log_info "Database restored"
else
    log_warn "No database found in backup"
fi

# Restore model files
if [[ -d "$TMP_RESTORE/models" ]]; then
    log_info "Restoring model files..."
    
    VOLUME_NAME=$(docker volume ls --format '{{.Name}}' | grep model-vault-data | head -1)
    docker run --rm -v "$VOLUME_NAME:/data" -v "$TMP_RESTORE/models:/restore:ro" alpine \
        sh -c 'cd /restore && tar cf - . | (cd /data && tar xf -)'
    
    log_info "Model files restored"
else
    log_warn "No model files found in backup"
fi

# Restart Model Vault service
log_info "Starting Model Vault service..."
docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" up -d model-vault

# Wait for health check
log_info "Waiting for Model Vault to become healthy..."
for i in {1..30}; do
    if docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" ps model-vault | grep -q "healthy"; then
        log_info "Model Vault is healthy"
        break
    fi
    if [[ $i -eq 30 ]]; then
        log_warn "Model Vault did not become healthy within 30 seconds"
        docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" logs --tail 50 model-vault
    fi
    sleep 1
done

log_info "Restore completed successfully!"
log_info "Verify models: curl -H 'Authorization: Bearer \$MODEL_VAULT_TOKEN' http://localhost:8081/model-vault/models"
