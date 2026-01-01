# Task 04: GPU Support & Resource Management

## Overview
Enable GPU acceleration for Ollama and ComfyUI with resource limits.

## Subtasks
1. **GPU Detection**: Auto-detect GPU and drivers (NVIDIA/AMD). ⏳ In Progress (Code implemented, testing mocked)
2. **Compose Updates**: Add GPU reservations to docker-compose.yml. ✅ Done
3. **Env Vars**: Add GPU_DRIVER, GPU_COUNT, GPU_CAPS vars. ✅ Done
4. **Fallback**: Ensure CPU fallback if GPU unavailable. ✅ Done (via env defaults)
5. **Resource Limits**: Set memory/CPU limits for GPU workloads. ⏳ In Progress
6. **Testing**: Benchmark performance with/without GPU. ⏳ Mocked (Reserve for desktop with 5080)

## Status
- [x] Subtask 2: Compose Updates
- [x] Subtask 3: Env Vars
- [x] Subtask 4: Fallback
- [ ] Subtask 1: GPU Detection
- [ ] Subtask 5: Resource Limits
- [ ] Subtask 6: Testing

## Notes
GPU reservations added for NVIDIA 590.44.x compatibility. Deploy section enabled for Ollama and ComfyUI. Testing reserved for actual GPU hardware.