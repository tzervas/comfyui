# Model Vault Project Context

## Overview
A secure Rust-based model vault service that manages AI model storage, downloading, and serving for the ComfyUI/Ollama stack. This decouples model management from the main application stack, providing faster startups, secure storage, and centralized model management.

## Project Location
- Path: `~/Documents/projects/model-vault`
- Type: Rust binary application
- Name: `model-vault`

## Core Requirements

### 1. Model Storage & Security
- Secure local storage directory (configurable path)
- File integrity verification (checksums)
- Access control and authentication
- Encryption at rest (optional)

### 2. Model Management API
- REST API for model operations
- Download models from HuggingFace, Ollama registry, etc.
- List available models
- Delete models
- Model metadata storage (size, hash, source, etc.)

### 3. Model Serving
- HTTP endpoints to serve model files
- Streaming downloads for large files
- Authentication for model access
- Rate limiting and access logging

### 4. Integration with Ollama
- API compatible with Ollama's model loading
- Support for Ollama's manifest format
- Automatic model discovery and registration

### 5. CLI Management
- Download models: `model-vault download <model-name>`
- List models: `model-vault list`
- Serve models: `model-vault serve --port 8080`
- Import existing models: `model-vault import <path>`

## Technical Specifications

### Dependencies
```toml
[dependencies]
axum = "0.7"
tokio = { version = "1.0", features = ["full"] }
serde = { version = "1.0", features = ["derive"] }
serde_json = "1.0"
reqwest = { version = "0.11", features = ["json", "stream"] }
sha2 = "0.10"
hex = "0.4"
clap = { version = "4.0", features = ["derive"] }
config = "0.14"
tracing = "0.1"
tracing-subscriber = "0.3"
sqlx = { version = "0.7", features = ["sqlite", "runtime-tokio-rustls"] }
```

### Configuration
```yaml
# config/model-vault.yaml
storage:
  path: "/var/lib/model-vault"
  max_size_gb: 100

server:
  host: "127.0.0.1"
  port: 8080
  auth_token: "your-secret-token"

models:
  registries:
    - name: "ollama"
      url: "https://registry.ollama.ai"
    - name: "huggingface"
      url: "https://huggingface.co"
```

### API Endpoints
```
GET    /health          - Health check
GET    /models          - List models
POST   /models/download - Download model
GET    /models/{name}   - Get model info
DELETE /models/{name}   - Delete model
GET    /files/{name}    - Download model file (authenticated)
```

### Database Schema
```sql
CREATE TABLE models (
    id INTEGER PRIMARY KEY,
    name TEXT NOT NULL UNIQUE,
    registry TEXT NOT NULL,
    version TEXT,
    size_bytes INTEGER,
    sha256 TEXT,
    download_url TEXT,
    local_path TEXT,
    status TEXT, -- downloading, ready, error
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
);
```

## Integration with ComfyUI/Ollama Stack

### Docker Integration
Add to docker-compose.yml:
```yaml
model-vault:
  build:
    context: ../model-vault
    dockerfile: Dockerfile
  container_name: model-vault
  volumes:
    - model_vault_data:/var/lib/model-vault
  ports:
    - "${MODEL_VAULT_PORT:-8080}:8080"
  environment:
    - MODEL_VAULT_STORAGE_PATH=/var/lib/model-vault
    - MODEL_VAULT_AUTH_TOKEN=${MODEL_VAULT_TOKEN}
  healthcheck:
    test: ["CMD", "curl", "-f", "http://localhost:8080/health"]
    interval: 30s
    timeout: 10s
    retries: 3
  restart: unless-stopped
```

### Ollama Integration
Modify ollama-init.sh to use vault:
```bash
# Instead of: ollama pull tinyllama
curl -H "Authorization: Bearer $MODEL_VAULT_TOKEN" \
     http://model-vault:8080/models/download \
     -d '{"name": "tinyllama", "registry": "ollama"}'

# Wait for download completion
# Then load from vault
```

### Environment Variables
Add to .env.example:
```
MODEL_VAULT_PORT=8080
MODEL_VAULT_TOKEN=your-secure-token-here
MODEL_VAULT_STORAGE_PATH=/var/lib/model-vault
```

### Management Integration
Add to manage.sh:
```bash
vault-download)
  model=${2:-""}
  if [ -n "$model" ]; then
    docker compose exec model-vault /app/model-vault download $model
  fi
  ;;
vault-list)
  docker compose exec model-vault /app/model-vault list
  ;;
```

## Security Considerations
- API authentication using Bearer tokens
- File permission restrictions (600)
- Input validation and sanitization
- Rate limiting on downloads
- Audit logging for all operations
- Secure token generation and storage

## Development Roadmap
1. Basic Rust project setup with Axum
2. Model storage and file operations
3. REST API implementation
4. Authentication middleware
5. Model download functionality
6. Ollama integration testing
7. Docker containerization
8. Integration with main stack
9. Documentation and testing
10. Production hardening

## Testing Requirements
- Unit tests for core functionality
- Integration tests with Ollama
- Load testing for concurrent downloads
- Security testing for authentication
- Docker integration tests

## Monitoring & Observability
- Health check endpoints
- Metrics collection (downloads, storage usage)
- Structured logging
- Error tracking

## Future Enhancements
- Model compression/decompression
- CDN integration for faster downloads
- Model versioning and rollback
- Backup and restore functionality
- Multi-registry support
- GUI management interface