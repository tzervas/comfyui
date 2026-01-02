# Media Validation Plan (Semver + SFW)

This plan ladders from easiest to hardest, keeps everything SFW, and assumes semver tags (not `latest`/`main`). Switch to digests later if needed. Reference pins in `config/versions.lock.yaml` and set `COMFYUI_WORKFLOW_VIDEO/AUDIO` to the workflow you’re validating.

## Animation (easy → harder)
1) **Looped frame → GIF/MP4 (no extra models)**
   - Goal: Prove plumbing with a short clip (1–2s) built from a few frames.
   - Nodes: Base ComfyUI + `SaveAnimatedImage` or a simple image-sequence-to-video node. If missing, install `was-node-suite-comfyui` (pin commit) which includes basic video/gif tooling.
   - Workflow: Text→image (small SD checkpoint) → duplicate frames → save GIF/MP4.
   - Output: 256–512 px, 8–16 frames, ≤2 MB.
   - Pinning: checkpoint (e.g., a small open SD model), VAE, and the video helper node repo commit.

2) **Simple motion (bouncing ball / camera pan)**
   - Goal: Minimal motion using built-in transforms.
   - Nodes: Add a transform/translate node per frame or a lightweight motion node (if available in your chosen suite).
   - Workflow: Generate a base frame → apply per-frame transform → save MP4/GIF.
   - Output: 2–4s, 512 px, ≤5 MB.
   - Pinning: same as above + any motion helper node commit.

3) **Stylized animation (AnimateDiff or similar)**
   - Goal: Text-to-video with style control.
   - Nodes: Install AnimateDiff (or WAN if preferred) via ComfyUI-Manager; pin commit and model versions.
   - Workflow: Prompt → motion model + base checkpoint → video → save MP4/WebM.
   - Output: 4–8s, 512–720 px, target ≤15 MB.
   - Pinning: motion model, base checkpoint, VAE; record SHAs in `versions.lock.yaml`.

4) **Higher-compute / longer clips (optional later)**
   - Goal: Longer duration or higher res once shorter clips are stable.
   - Nodes/Models: Same as above, but consider tiling/denoising passes; may need more VRAM.
   - Output: 10–15s, 720p, target ≤30 MB.

## Audio (TTS → SFX → music)
1) **TTS first (easiest)**
   - Goal: Deterministic spoken line (e.g., “System test complete”).
   - Nodes: Add a TTS node pack (e.g., Bark/SpeechT5/XTTS node); pin repo commit and model weights.
   - Workflow: Text → TTS → save WAV.
   - Output: ≤10s WAV, mono ok.
   - Pinning: TTS node repo commit, model version; record in `versions.lock.yaml`.

2) **SFX**
   - Goal: Short sound effect (e.g., “camera shutter”, “button click”).
   - Nodes: Same TTS/audio pack or a lightweight SFX generator node; pin commit.
   - Workflow: Text → SFX → save WAV/OGG.
   - Output: ≤5s.
   - Pinning: SFX model/version.

3) **Music (hardest of the three)**
   - Goal: Short loop (e.g., 4–8 bars) to prove end-to-end.
   - Nodes: Music-capable node pack (e.g., musicgen/audiogen); pin commit and model.
   - Workflow: Text → music model → save WAV/MP3.
   - Output: ≤15s.
   - Pinning: model checkpoint version; note sample rate/bitrate.

## Wiring into Pipelines
- Place API-format workflows under `assets/comfyui/workflows/` (one per step) and set:
  - `COMFYUI_WORKFLOW_VIDEO` to the chosen animation workflow.
  - `COMFYUI_WORKFLOW_AUDIO` to the chosen audio workflow.
- If a workflow needs a different output type, adjust `comfy_media_tools` `want_exts` for that step, or add a dedicated tool entry.

## Validation contract (per step)
- Inputs: SFW prompt list (deterministic phrases per step) checked into docs.
- Call path: `POST /pipelines/v1/comfy_media_tools/filter/inlet` via nginx with Basic Auth + `X-Pipelines-Authorization`.
- Expected: HTTP 200, returned `/comfyui/view?...` URL, fetchable via nginx, file size within target bounds.
- Record: tag/commit/weights used, prompt, output shape/duration, and date → store in `config/versions.lock.yaml` (or a sibling `media-validation-log.md`).
