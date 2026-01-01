#!/bin/bash

# ComfyUI/Ollama Management Script
# Usage: ./manage.sh [start|stop|restart|update|build|watch|logs|status|test]

set -e

COMPOSE_FILE="docker-compose.yml"
PROJECT_NAME="comfyui-ollama"

case "$1" in
  start)
    echo "Starting services..."
    docker compose -f $COMPOSE_FILE -p $PROJECT_NAME up -d
    echo "Services started. Check status with ./manage.sh status"
    ;;
  stop)
    echo "Stopping services..."
    docker compose -f $COMPOSE_FILE -p $PROJECT_NAME down
    echo "Services stopped."
    ;;
  restart)
    echo "Restarting services..."
    docker compose -f $COMPOSE_FILE -p $PROJECT_NAME restart
    echo "Services restarted."
    ;;
  logs)
    service=${2:-""}
    if [ -n "$service" ]; then
      docker compose -f $COMPOSE_FILE -p $PROJECT_NAME logs -f $service
    else
      docker compose -f $COMPOSE_FILE -p $PROJECT_NAME logs -f
    fi
    ;;
  status)
    echo "Service status:"
    docker compose -f $COMPOSE_FILE -p $PROJECT_NAME ps
    echo ""
    echo "Health checks:"
    docker compose -f $COMPOSE_FILE -p $PROJECT_NAME exec ollama /app/healthcheck-ollama.sh && echo "Ollama: Healthy" || echo "Ollama: Unhealthy"
    docker compose -f $COMPOSE_FILE -p $PROJECT_NAME exec comfyui /app/healthcheck-comfyui.sh && echo "ComfyUI: Healthy" || echo "ComfyUI: Unhealthy"
    docker compose -f $COMPOSE_FILE -p $PROJECT_NAME exec langflow /app/healthcheck-langflow.sh && echo "LangFlow: Healthy" || echo "LangFlow: Unhealthy"
    docker compose -f $COMPOSE_FILE -p $PROJECT_NAME exec langchain /app/healthcheck-langchain.sh && echo "LangChain: Healthy" || echo "LangChain: Unhealthy"
    ;;
  test)
    echo "Running API tests..."
    # Test Ollama API
    if curl -f http://localhost:11434/api/tags > /dev/null 2>&1; then
      echo "Ollama API: OK"
    else
      echo "Ollama API: FAIL"
    fi
    # Test ComfyUI
    if curl -f http://localhost:8188/ > /dev/null 2>&1; then
      echo "ComfyUI: OK"
    else
      echo "ComfyUI: FAIL"
    fi
    # Test LangFlow
    if curl -f http://localhost:7860/ > /dev/null 2>&1; then
      echo "LangFlow: OK"
    else
      echo "LangFlow: FAIL"
    fi
    # Test LangChain
    if curl -f http://localhost:8000/docs > /dev/null 2>&1; then
      echo "LangChain: OK"
    else
      echo "LangChain: FAIL"
    fi
    ;;
  update)
    echo "Updating services incrementally..."
    docker compose pull
    docker compose up -d --force-recreate
    echo "Services updated. Check status with ./manage.sh status"
    ;;
  build)
    echo "Building custom images..."
    docker compose build --parallel
    echo "Images built."
    ;;
  watch)
    echo "Watching for changes in Dockerfiles and rebuilding..."
    while true; do
      inotifywait -e modify,create,delete Dockerfile.* && ./manage.sh build
    done
    ;;   backup)
    echo "Creating backup..."
    TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    BACKUP_DIR="./backups/$TIMESTAMP"
    mkdir -p "$BACKUP_DIR"
    
    # Stop services to ensure consistency
    docker compose -f $COMPOSE_FILE -p $PROJECT_NAME stop
    
    # Backup volumes
    VOLUMES=("ollama_data" "comfyui_models" "comfyui_outputs" "comfyui_user_profiles" "langchain_vectorstore" "langflow_data")
    for vol in "${VOLUMES[@]}"; do
      echo "Backing up $vol..."
      docker run --rm -v ${PROJECT_NAME}_${vol}:/data -v $(pwd)/$BACKUP_DIR:/backup alpine tar czf /backup/${vol}.tar.gz -C /data .
    done
    
    # Backup configs
    cp docker-compose.yml "$BACKUP_DIR/"
    cp .env "$BACKUP_DIR/" 2>/dev/null || true
    cp .htpasswd "$BACKUP_DIR/" 2>/dev/null || true
    
    # Start services
    docker compose -f $COMPOSE_FILE -p $PROJECT_NAME start
    
    echo "Backup created in $BACKUP_DIR"
    ;;
  restore)
    BACKUP_DIR=${2:-"./backups/latest"}
    if [ ! -d "$BACKUP_DIR" ]; then
      echo "Backup directory $BACKUP_DIR not found"
      exit 1
    fi
    echo "Restoring from $BACKUP_DIR..."
    
    # Stop services
    docker compose -f $COMPOSE_FILE -p $PROJECT_NAME stop
    
    # Restore volumes
    VOLUMES=("ollama_data" "comfyui_models" "comfyui_outputs" "comfyui_user_profiles" "langchain_vectorstore" "langflow_data")
    for vol in "${VOLUMES[@]}"; do
      if [ -f "$BACKUP_DIR/${vol}.tar.gz" ]; then
        echo "Restoring $vol..."
        docker run --rm -v ${PROJECT_NAME}_${vol}:/data -v $(pwd)/$BACKUP_DIR:/backup alpine sh -c "cd /data && tar xzf /backup/${vol}.tar.gz"
      fi
    done
    
    # Restore configs if present
    if [ -f "$BACKUP_DIR/docker-compose.yml" ]; then
      cp "$BACKUP_DIR/docker-compose.yml" .
    fi
    if [ -f "$BACKUP_DIR/.env" ]; then
      cp "$BACKUP_DIR/.env" .
    fi
    if [ -f "$BACKUP_DIR/.htpasswd" ]; then
      cp "$BACKUP_DIR/.htpasswd" .
    fi
    
    # Start services
    docker compose -f $COMPOSE_FILE -p $PROJECT_NAME start
    
    echo "Restore completed from $BACKUP_DIR"
    ;;
  monitor)
    echo "Monitoring services (Ctrl+C to stop)..."
    while true; do
      echo "$(date): Checking services..."
      ./manage.sh status
      sleep 60
    done
    ;;
  *)
    echo "Usage: $0 {start|stop|restart|build|watch|logs [service]|status|test|backup|restore [backup_dir]|monitor}"
    exit 1
    ;;
esac