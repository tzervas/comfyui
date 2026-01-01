# Task 15: CPU-Only Ollama Deployment for R&D

## Overview
Produce a precise, production-grade deployment plan for a CPU-only Ollama instance running in Docker, focused on R&D experimentation with open-weight models.

## Context & Hard Constraints
- Target hardware: modern consumer/workstation, 16–32 GiB RAM, no GPU, fast NVMe storage
- Total storage budget after all models: preferably < 60 GB
- Must support: strong CPU-optimized inference, uncensored variants, multimodal, and good base models for future custom quantization experiments
- All models must be open-weight and license-compliant for research use
- No Kubernetes, no GPU passthrough, no cloud dependencies

## Deliverables
1. Deployment Setup
   - Recommended `docker run` command with named volumes, port mapping, restart policy
   - Persistent volume layout explanation

2. Authentication & Model Access
   - How to handle Hugging Face token inside container (best current practice 2025)
   - Other relevant sources (Ollama library, any special cases)

3. Model Selection & Categorization
   Present in a clear Markdown table with columns:
   | Category | Model Name | Parameters | Approx. Quantized Size | Purpose / Strengths | Source | CPU Inference Notes |
   Select 2–3 models per category:
   - CPU-optimized small/fast (1–8B range, strong quantization)
   - Uncensored / aligned-light / strong instruction following
   - Multimodal (vision + text)
   - Strong base models suitable for future custom quantization

4. Prefetching & Population Workflow
   - Recommended sequence of `ollama pull` commands
   - Rationale for ordering & choices

5. Storage Management & Cleanup
   - Commands to monitor total model storage (`du`, `ollama list`, etc.)
   - Routine Docker prune / cleanup procedure to keep footprint minimal

6. Risk Assessment & Mitigations
   - Top 5–7 realistic risks (memory pressure, download failures, model incompatibilities, etc.)
   - Concrete mitigation for each

7. R&D Extension Hooks
   - Quick paths to llama.cpp quantization experiments
   - One-paragraph note on future expansion directions

## Executive Summary
- CPU-only Ollama deployment optimized for 16-32GB RAM systems with <60GB storage budget.
- Selection of 12 open-weight models across four categories for R&D experimentation.
- Docker containerization with persistent volumes ensures model isolation and persistence.
- Authentication via SSH key for Hugging Face gated models; direct pulls from Ollama library for public models.
- Prefetching sequence prioritizes small models to minimize initial resource usage.
- Monitoring and cleanup procedures prevent storage overflow.
- Mitigations address memory pressure, download reliability, and compatibility risks.
- Extension hooks enable custom quantization via llama.cpp for advanced CPU optimization.

## 1. Deployment Setup
Recommended `docker run` command:
```
docker run -d --name ollama -v ollama:/root/.ollama -p 11434:11434 --restart unless-stopped ollama/ollama
```
Persistent volume layout: The `ollama` named volume mounts to `/root/.ollama` inside the container, storing model files, configurations, and metadata for persistence across container restarts.

## 2. Authentication & Model Access
For Hugging Face gated models, generate an SSH key pair inside the container (`ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519 -N ""`), copy the public key (`cat ~/.ssh/id_ed25519.pub`), and add it to your Hugging Face account settings under SSH keys. This enables pulls of private or restricted GGUF models via `ollama run hf.co/username/repository`. For public models, no authentication is required. Primary source is the Ollama library for direct, optimized pulls; Hugging Face serves as a secondary source for custom quantizations or unavailable variants.

## 3. Model Selection & Categorization

| Category | Model Name | Parameters | Approx. Quantized Size | Purpose / Strengths | Source | CPU Inference Notes |
|----------|------------|------------|-------------------------|---------------------|--------|---------------------|
| CPU-optimized small/fast | Gemma 3 | 1B | 815MB | Lightweight general tasks, reasoning, multilingual support. | Ollama Library | Highly efficient on 16GB+ RAM; minimal latency for text generation. |
| CPU-optimized small/fast | DeepSeek R1 | 1.5B | 1.1GB | Advanced reasoning, math, coding; distilled for performance. | Ollama Library | Optimized for consumer hardware; strong speed-accuracy balance. |
| CPU-optimized small/fast | SmolLM2 | 1.7B | 1.8GB | Compact language tasks, on-device deployment. | Ollama Library | Low memory footprint; suitable for resource-limited setups. |
| Uncensored / aligned-light / strong instruction following | Dolphin-Llama 3 | 8B | 4.7GB | Reasoning, coding, agentic abilities; function calling. | Ollama Library | Efficient on 16-32GB RAM; uncensored for flexible experimentation. |
| Uncensored / aligned-light / strong instruction following | Wizard-Vicuna-Uncensored | 7B | 3.8GB | All-rounder based on Llama 2; versatile for creative tasks. | Ollama Library | Low resource needs; reliable for uncensored outputs. |
| Uncensored / aligned-light / strong instruction following | Llama2 Uncensored | 7B | 3.8GB | Straightforward responses; no alignment filters. | Ollama Library | Widely optimized; performs well on standard CPUs. |
| Multimodal (vision + text) | Llava | 7B | 4.7GB | End-to-end visual-language understanding; image analysis. | Ollama Library | Quantization reduces overhead; suitable for CPU with image caching. |
| Multimodal (vision + text) | Moondream | 1.8B | 1.7GB | Compact vision-language; edge-device focused. | Ollama Library | Low footprint; efficient for basic multimodal tasks on CPU. |
| Strong base models suitable for future custom quantization | Llama3.1 | 8B | 4.9GB | State-of-the-art foundation; long contexts, tool use. | Ollama Library | Base for llama.cpp quantization; balances performance and customizability. |
| Strong base models suitable for future custom quantization | Mistral | 7B | 4.4GB | Efficient general-purpose; coding focus. | Ollama Library | Easy to quantize; strong baseline for CPU experiments. |
| Strong base models suitable for future custom quantization | Gemma | 7B | 5.0GB | Lightweight, high performance; multilingual. | Ollama Library | Test quantization trade-offs; optimized for inference. |

## 4. Prefetching & Population Workflow
Recommended sequence: Start with CPU-optimized models (Gemma 3, DeepSeek R1, SmolLM2) to verify deployment and minimize initial RAM usage, followed by uncensored variants (Dolphin-Llama 3, Wizard-Vicuna-Uncensored, Llama2 Uncensored) for experimentation, then multimodal models (Llava, Moondream) to test vision capabilities, and finally base models (Llama3.1, Mistral, Gemma) for quantization prep. Pull sequentially to monitor storage and avoid overwhelming the system.
```
ollama pull gemma3:1b
ollama pull deepseek-r1:1.5b
ollama pull smollm2:1.7b
ollama pull dolphin-llama3:8b
ollama pull wizard-vicuna-uncensored:7b
ollama pull llama2-uncensored:7b
ollama pull llava:7b
ollama pull moondream:1.8b
ollama pull llama3.1:8b
ollama pull mistral:7b
ollama pull gemma:7b
```
Rationale: Ordering by size and category ensures gradual resource consumption, allowing early validation of CPU performance before committing to larger models.

## 5. Storage Management & Cleanup
Monitor total storage with `ollama list` for model inventory and `du -sh /root/.ollama/models` for directory size. Routine cleanup: Run `docker system prune -a` weekly to remove unused containers/images, and `docker volume prune` to reclaim orphaned volumes. This maintains footprint under 60GB by clearing cache layers from failed pulls or builds.

## 6. Risk Assessment & Mitigations
- Memory pressure on 16GB systems: Monitor RAM via `htop` or `free -h`; mitigate by running smaller models first and avoiding concurrent loads; fallback to further quantization if needed.
- Download failures due to network issues: Retry pulls with `ollama pull --retry 3`; ensure stable internet; use local mirrors if available.
- Model incompatibilities with hardware/OS: Verify Ollama version (0.5+) and test small models initially; check logs with `docker logs ollama` for errors.
- Storage overflow during prefetching: Pull in batches and prune after each; set volume size limits in Docker if supported.
- Security risks from exposed ports: Bind to localhost only (`-p 127.0.0.1:11434:11434`); avoid running as root.
- Performance degradation over time: Regularly update Ollama (`docker pull ollama/ollama`); re-quantize models for better CPU fit.
- License or source verification issues: Stick to Ollama library and HF public repos; audit model cards for compliance.

## 7. R&D Extension Hooks
For custom quantization experiments, use llama.cpp: Clone the repo (`git clone https://github.com/ggerganov/llama.cpp`), convert base models (e.g., `python convert.py --outfile model.gguf --outtype q4_0 model.pth` for Llama3.1), then test inference speed with `./main -m model.gguf --prompt "test"`). Future expansion: Integrate ComfyUI for UI-driven workflows by adding a second container with shared volumes, or scale to multi-user via Nginx reverse proxy for LAN access.

## Estimated Total Storage
35-45GB

## Next Steps
- Execute the `docker run` command to initialize the Ollama container.
- Begin prefetching models in the recommended sequence.
- Monitor resources and adjust as needed for R&D experimentation.

## Testing & Safety Measures
To prevent system overload (e.g., hard shutdowns from memory exhaustion), implement the following safeguards during testing and experimentation:

- **Memory Monitoring**: Before and during tests, run `free -h` or `htop` to ensure available RAM stays above 1GB. Stop tests if usage exceeds 80% of total RAM.
- **Sequential Testing**: Run one model test at a time; avoid concurrent loads. Pause 30-60 seconds between tests for system stabilization.
- **Model Limits**: For CPU-optimized models (Gemma 3, DeepSeek R1, SmolLM2), limit prompts to <100 tokens and responses to <200 tokens to minimize compute.
- **Docker Resource Limits**: Update the Ollama container with `--memory=4g --cpus=2` to cap resources: `docker update --memory=4g --cpus=2 ollama`.
- **Inference Timeouts**: Use API calls with timeouts (e.g., `curl --max-time 30`) to prevent hanging.
- **ComfyUI Integration**: Test simple workflows first; monitor ComfyUI logs for errors. Use Ollama nodes with low batch sizes.
- **Fallback**: If RAM drops below 500MB available, kill the Ollama container (`docker stop ollama`) and restart after cooldown.
- **Logging**: Capture test outputs to files for analysis without overloading console.

These measures ensure safe desktop deployment without crashes.