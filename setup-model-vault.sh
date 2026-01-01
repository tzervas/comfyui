#!/bin/bash

# Script to generate and set Model Vault token and registry secret
# Updates .env files and adds model-vault service to docker-compose.yml

set -e

# Generate secure tokens
MODEL_VAULT_TOKEN=$(openssl rand -hex 32)
REGISTRY_SECRET=$(openssl rand -hex 32)

echo "Generated MODEL_VAULT_TOKEN: $MODEL_VAULT_TOKEN"
echo "Generated REGISTRY_SECRET: $REGISTRY_SECRET"

# List of env files to update
ENV_FILES=(".env" ".env.example" ".env.desktop" ".env.homelab")

for env_file in "${ENV_FILES[@]}"; do
    if [ -f "$env_file" ]; then
        # Update MODEL_VAULT_TOKEN
        if grep -q "MODEL_VAULT_TOKEN=" "$env_file"; then
            sed -i "s/MODEL_VAULT_TOKEN=.*/MODEL_VAULT_TOKEN=$MODEL_VAULT_TOKEN/" "$env_file"
        else
            echo "MODEL_VAULT_TOKEN=$MODEL_VAULT_TOKEN" >> "$env_file"
        fi

        # Update REGISTRY_SECRET
        if grep -q "REGISTRY_SECRET=" "$env_file"; then
            sed -i "s/REGISTRY_SECRET=.*/REGISTRY_SECRET=$REGISTRY_SECRET/" "$env_file"
        else
            echo "REGISTRY_SECRET=$REGISTRY_SECRET" >> "$env_file"
        fi

        echo "Updated $env_file"
    else
        echo "Warning: $env_file not found, skipping"
    fi
done

# Check if model-vault service already exists in docker-compose.yml
if grep -q "model-vault:" docker-compose.yml; then
    echo "Model vault service already exists in docker-compose.yml"
else
    # Add model-vault service to docker-compose.yml
    cat >> docker-compose.yml << 'EOF'

  model-vault:
    build:
      context: .
      dockerfile: model-vault-Dockerfile
    container_name: model-vault
    environment:
      MODEL_VAULT_TOKEN: ${MODEL_VAULT_TOKEN}
      REGISTRY_SECRET: ${REGISTRY_SECRET}
      DATABASE_URL: ${DATABASE_URL}
    ports:
      - "${MODEL_VAULT_PORT:-8080}:8080"
    volumes:
      - model_vault_data:/var/lib/model-vault
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8080/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 40s
EOF

    # Add volume if not exists
    if ! grep -q "model_vault_data:" docker-compose.yml; then
        # Find the volumes section and add it
        sed -i '/volumes:/a\  model_vault_data:' docker-compose.yml
    fi

    echo "Added model-vault service to docker-compose.yml"
fi

echo "Setup complete. You can now run 'docker compose up -d' to deploy including the model vault."