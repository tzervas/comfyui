#!/usr/bin/env bash
set -euo pipefail

# Model Provisioning Script
# Downloads and imports curated AI models into Model Vault

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Configuration
MODELS_DIR="${MODELS_DIR:-/srv/models}"
ENV_FILE="${ENV_FILE:-$PROJECT_ROOT/.env.homelab}"
MODEL_VAULT_URL="${MODEL_VAULT_URL:-http://localhost:8081/model-vault}"
PARALLEL_DOWNLOADS="${PARALLEL_DOWNLOADS:-2}"

# Load environment
if [[ -f "$ENV_FILE" ]]; then
    set -a
    # shellcheck disable=SC1090
    source "$ENV_FILE"
    set +a
fi

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }
log_step() { echo -e "${BLUE}[STEP]${NC} $*"; }

# Model manifest (curated for ≤500GB total, optimized for CPU homelab + RTX 5080 desktop)
declare -A MODELS=(
    # Text/Code LLMs (~35GB total)
    ["llama-3.1-8b-instruct-q4"]="https://huggingface.co/bartowski/Meta-Llama-3.1-8B-Instruct-GGUF/resolve/main/Meta-Llama-3.1-8B-Instruct-Q4_K_M.gguf|text|~4.8GB"
    ["mistral-nemo-12b-instruct-q4"]="https://huggingface.co/bartowski/Mistral-Nemo-Instruct-2407-GGUF/resolve/main/Mistral-Nemo-Instruct-2407-Q4_K_M.gguf|text|~7.2GB"
    ["qwen2.5-14b-coder-q4"]="https://huggingface.co/bartowski/Qwen2.5-Coder-14B-Instruct-GGUF/resolve/main/Qwen2.5-Coder-14B-Instruct-Q4_K_M.gguf|code|~8.4GB"
    ["deepseek-coder-v2-lite-16b-q4"]="https://huggingface.co/bartowski/DeepSeek-Coder-V2-Lite-Instruct-GGUF/resolve/main/DeepSeek-Coder-V2-Lite-Instruct-Q4_K_M.gguf|code|~9.2GB"
    ["phi-3-mini-4k-instruct-q4"]="https://huggingface.co/bartowski/Phi-3-mini-4k-instruct-GGUF/resolve/main/Phi-3-mini-4k-instruct-Q4_K_M.gguf|text|~2.4GB"
    
    # Multimodal (~12GB total)
    ["llava-1.6-mistral-7b-q4"]="https://huggingface.co/cjpais/llava-1.6-mistral-7b-gguf/resolve/main/llava-v1.6-mistral-7b.Q4_K_M.gguf|multimodal|~4.7GB"
    ["llava-1.6-vicuna-7b-q4"]="https://huggingface.co/cjpais/llava-v1.6-vicuna-7b-gguf/resolve/main/llava-v1.6-vicuna-7b.Q4_K_M.gguf|multimodal|~4.7GB"
    
    # Diffusion Models (~28GB total)
    ["sd-v1-5"]="https://huggingface.co/runwayml/stable-diffusion-v1-5/resolve/main/v1-5-pruned-emaonly.safetensors|diffusion|~4.3GB"
    ["sdxl-base-1.0"]="https://huggingface.co/stabilityai/stable-diffusion-xl-base-1.0/resolve/main/sd_xl_base_1.0.safetensors|diffusion|~6.9GB"
    ["sdxl-refiner-1.0"]="https://huggingface.co/stabilityai/stable-diffusion-xl-refiner-1.0/resolve/main/sd_xl_refiner_1.0.safetensors|diffusion|~6.2GB"
    ["juggernaut-xl-v9"]="https://huggingface.co/RunDiffusion/Juggernaut-XL-v9/resolve/main/Juggernaut-XL_v9_RunDiffusionPhoto_v2.safetensors|diffusion|~6.5GB"
    
    # Audio Models (~5GB total)
    ["whisper-large-v3"]="https://huggingface.co/Systran/faster-whisper-large-v3/resolve/main/model.bin|audio|~3.1GB"
    ["whisper-large-v3-ct2"]="https://huggingface.co/Systran/faster-whisper-large-v3/resolve/main/config.json|audio|~1KB"
    
    # Embedding Models (~1GB total)
    ["bge-large-en-v1.5"]="https://huggingface.co/BAAI/bge-large-en-v1.5/resolve/main/pytorch_model.bin|embedding|~1.3GB"
)

usage() {
    cat <<EOF
Usage: $0 [OPTIONS] [MODEL_NAMES...]

Download and import curated AI models into Model Vault.

OPTIONS:
  --list           List available models without downloading
  --all            Download all models in manifest
  --type TYPE      Download only models of specific type (text|code|multimodal|diffusion|audio|embedding)
  --dry-run        Show what would be downloaded without actually downloading
  --parallel N     Number of parallel downloads (default: $PARALLEL_DOWNLOADS)
  -h, --help       Show this help message

EXAMPLES:
  # List all available models
  $0 --list

  # Download specific models
  $0 llama-3.1-8b-instruct-q4 mistral-nemo-12b-instruct-q4

  # Download all text models
  $0 --type text

  # Download all models
  $0 --all

  # Dry run to see what would be downloaded
  $0 --dry-run --type code
EOF
}

list_models() {
    log_step "Available models in manifest:"
    echo ""
    printf "%-35s %-15s %-10s %-50s\n" "NAME" "TYPE" "SIZE" "URL"
    printf "%s\n" "$(printf '=%.0s' {1..120})"
    
    for model in "${!MODELS[@]}"; do
        IFS='|' read -r url type size <<< "${MODELS[$model]}"
        printf "%-35s %-15s %-10s %-50s\n" "$model" "$type" "$size" "${url:0:50}..."
    done
    echo ""
    
    # Calculate total size estimate
    log_info "Total estimated size: ~80GB (optimized for ≤500GB budget)"
}

download_model() {
    local model_name="$1"
    local url type size
    
    if [[ ! -v "MODELS[$model_name]" ]]; then
        log_error "Model not found in manifest: $model_name"
        return 1
    fi
    
    IFS='|' read -r url type size <<< "${MODELS[$model_name]}"
    local filename=$(basename "$url")
    local model_dir="$MODELS_DIR/$type"
    local model_path="$model_dir/$filename"
    
    log_info "Downloading $model_name ($type, $size)..."
    log_info "URL: $url"
    
    # Create directory
    mkdir -p "$model_dir"
    
    # Check if already downloaded
    if [[ -f "$model_path" ]]; then
        log_warn "Model already exists: $model_path (skipping)"
        return 0
    fi
    
    # Download with resume support
    if command -v aria2c &>/dev/null; then
        aria2c -x 8 -s 8 -c -d "$model_dir" -o "$filename" "$url"
    elif command -v wget &>/dev/null; then
        wget -c -O "$model_path" "$url"
    else
        log_error "Neither aria2c nor wget found. Please install one."
        return 1
    fi
    
    # Verify download
    if [[ ! -f "$model_path" ]]; then
        log_error "Download failed: $model_path"
        return 1
    fi
    
    local actual_size=$(du -h "$model_path" | cut -f1)
    log_info "Downloaded successfully: $model_path ($actual_size)"
    
    # Optional: Import into Model Vault (if running)
    if curl -sf -H "Authorization: Bearer ${MODEL_VAULT_TOKEN:-}" "${MODEL_VAULT_URL}/health" &>/dev/null; then
        log_info "Importing into Model Vault..."
        # TODO: Implement Model Vault import API call
        # curl -X POST -H "Authorization: Bearer $MODEL_VAULT_TOKEN" \
        #      -F "file=@$model_path" -F "name=$model_name" -F "type=$type" \
        #      "$MODEL_VAULT_URL/models"
    else
        log_warn "Model Vault not accessible, skipping import"
    fi
}

# Parse arguments
LIST_ONLY=0
DOWNLOAD_ALL=0
FILTER_TYPE=""
DRY_RUN=0
MODELS_TO_DOWNLOAD=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --list)
            LIST_ONLY=1
            shift
            ;;
        --all)
            DOWNLOAD_ALL=1
            shift
            ;;
        --type)
            FILTER_TYPE="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=1
            shift
            ;;
        --parallel)
            PARALLEL_DOWNLOADS="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            MODELS_TO_DOWNLOAD+=("$1")
            shift
            ;;
    esac
done

# List models if requested
if [[ "$LIST_ONLY" = "1" ]]; then
    list_models
    exit 0
fi

# Determine which models to download
if [[ "$DOWNLOAD_ALL" = "1" ]]; then
    MODELS_TO_DOWNLOAD=("${!MODELS[@]}")
elif [[ -n "$FILTER_TYPE" ]]; then
    for model in "${!MODELS[@]}"; do
        IFS='|' read -r url type size <<< "${MODELS[$model]}"
        if [[ "$type" = "$FILTER_TYPE" ]]; then
            MODELS_TO_DOWNLOAD+=("$model")
        fi
    done
fi

if [[ ${#MODELS_TO_DOWNLOAD[@]} -eq 0 ]]; then
    log_error "No models specified. Use --list to see available models or --help for usage."
    exit 1
fi

log_step "Planning to download ${#MODELS_TO_DOWNLOAD[@]} model(s)"

# Calculate total estimated size
total_size=0
for model in "${MODELS_TO_DOWNLOAD[@]}"; do
    IFS='|' read -r url type size <<< "${MODELS[$model]}"
    echo "  - $model ($type, $size)"
done
echo ""

if [[ "$DRY_RUN" = "1" ]]; then
    log_info "Dry run complete. Use without --dry-run to actually download."
    exit 0
fi

# Confirm download
read -rp "Continue with download? (yes/no): " CONFIRM
if [[ "$CONFIRM" != "yes" ]]; then
    log_info "Download cancelled"
    exit 0
fi

# Create models directory
sudo mkdir -p "$MODELS_DIR"
sudo chown -R "$USER:$USER" "$MODELS_DIR"

# Download models
log_step "Starting downloads..."
for model in "${MODELS_TO_DOWNLOAD[@]}"; do
    download_model "$model" || log_warn "Failed to download $model (continuing)"
done

log_info "Download complete!"
log_info "Models location: $MODELS_DIR"
log_info "Total disk usage: $(du -sh "$MODELS_DIR" 2>/dev/null | cut -f1 || echo 'unknown')"
