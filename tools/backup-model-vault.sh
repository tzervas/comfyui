#!/usr/bin/env bash
set -euo pipefail

# Model Vault Backup Script
# Creates compressed archives of Model Vault database and model files with integrity checks

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Configuration
BACKUP_DIR="${BACKUP_DIR:-$PROJECT_ROOT/backups/model-vault}"
ENV_FILE="${ENV_FILE:-$PROJECT_ROOT/.env.homelab}"
COMPOSE_FILE="${COMPOSE_FILE:-$PROJECT_ROOT/docker-compose.homelab.yml}"
INCREMENTAL="${INCREMENTAL:-0}"
COMPRESS_LEVEL="${COMPRESS_LEVEL:-3}"  # zstd compression level (1-22)

# Load environment
if [[ -f "$ENV_FILE" ]]; then
    set -a
    # shellcheck disable=SC1090
    source "$ENV_FILE"
    set +a
fi

# Timestamp for backup
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
BACKUP_NAME="model-vault-${TIMESTAMP}"
BACKUP_PATH="$BACKUP_DIR/$BACKUP_NAME"

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

# Create backup directory
mkdir -p "$BACKUP_DIR"

log_info "Starting Model Vault backup: $BACKUP_NAME"

# Check if docker compose stack is running
if ! docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" ps model-vault | grep -q "Up\|running"; then
    log_warn "Model Vault container is not running. Backup may be inconsistent."
fi

# Create temporary backup staging area
TMP_BACKUP=$(mktemp -d)
trap 'rm -rf "$TMP_BACKUP"' EXIT

log_info "Staging backup to: $TMP_BACKUP"

# Backup database (with SQLite checkpoint to ensure consistency)
log_info "Backing up SQLite database..."
DB_BACKUP="$TMP_BACKUP/database"
mkdir -p "$DB_BACKUP"

docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" exec -T model-vault \
    sh -c 'sqlite3 /var/lib/model-vault/model-vault.db ".backup /var/lib/model-vault/model-vault-backup.db" && cat /var/lib/model-vault/model-vault-backup.db' \
    > "$DB_BACKUP/model-vault.db" 2>/dev/null || {
    log_warn "Hot backup failed, falling back to volume copy..."
    docker cp "$(docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" ps -q model-vault):/var/lib/model-vault/model-vault.db" \
        "$DB_BACKUP/model-vault.db"
}

# Get model files list from database
log_info "Querying model inventory..."
MODELS_JSON=$(docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" exec -T model-vault \
    sh -c 'sqlite3 -json /var/lib/model-vault/model-vault.db "SELECT name, path, size FROM models"' 2>/dev/null || echo "[]")

# Backup model files from Docker volume
log_info "Backing up model files..."
MODELS_BACKUP="$TMP_BACKUP/models"
mkdir -p "$MODELS_BACKUP"

# Copy model files from volume
VOLUME_NAME=$(docker volume ls --format '{{.Name}}' | grep model-vault-data | head -1)
if [[ -n "$VOLUME_NAME" ]]; then
    log_info "Copying from volume: $VOLUME_NAME"
    docker run --rm -v "$VOLUME_NAME:/data:ro" -v "$MODELS_BACKUP:/backup" alpine \
        sh -c 'cd /data && if [ -d models ]; then tar cf - models | (cd /backup && tar xf -); fi'
else
    log_warn "Model Vault data volume not found"
fi

# Create metadata file
log_info "Creating backup metadata..."
cat > "$TMP_BACKUP/metadata.json" <<EOF
{
  "timestamp": "$TIMESTAMP",
  "backup_type": "$([ "$INCREMENTAL" = "1" ] && echo "incremental" || echo "full")",
  "source": {
    "env_file": "$ENV_FILE",
    "compose_file": "$COMPOSE_FILE",
    "volume": "$VOLUME_NAME"
  },
  "database_size": $(stat -c%s "$DB_BACKUP/model-vault.db" 2>/dev/null || echo 0),
  "models": $MODELS_JSON,
  "compression": {
    "algorithm": "zstd",
    "level": $COMPRESS_LEVEL
  }
}
EOF

# Compress backup with zstd
log_info "Compressing backup (level $COMPRESS_LEVEL)..."
tar -C "$TMP_BACKUP" -cf - . | zstd -$COMPRESS_LEVEL -o "$BACKUP_PATH.tar.zst"

# Generate integrity checksum
log_info "Generating SHA-256 checksum..."
sha256sum "$BACKUP_PATH.tar.zst" > "$BACKUP_PATH.tar.zst.sha256"

# Calculate backup size
BACKUP_SIZE=$(du -h "$BACKUP_PATH.tar.zst" | cut -f1)

log_info "Backup completed successfully!"
log_info "Location: $BACKUP_PATH.tar.zst"
log_info "Size: $BACKUP_SIZE"
log_info "Checksum: $(cut -d' ' -f1 "$BACKUP_PATH.tar.zst.sha256")"

# Optional: Clean up old backups (keep last 7)
KEEP_BACKUPS="${KEEP_BACKUPS:-7}"
if [[ "$KEEP_BACKUPS" -gt 0 ]]; then
    log_info "Cleaning up old backups (keeping last $KEEP_BACKUPS)..."
    ls -1t "$BACKUP_DIR"/model-vault-*.tar.zst 2>/dev/null | tail -n +$((KEEP_BACKUPS + 1)) | xargs -r rm -f
    ls -1t "$BACKUP_DIR"/model-vault-*.tar.zst.sha256 2>/dev/null | tail -n +$((KEEP_BACKUPS + 1)) | xargs -r rm -f
fi

log_info "Backup process complete."
