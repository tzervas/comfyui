# ComfyUI workflow templates

These are starter templates that get copied into `/opt/ComfyUI/user/default/workflows/` at container start.

They intentionally avoid embedding any copyrighted model assets.

## API-format workflows (for /prompt)

The Pipelines module `comfy_media_tools` calls ComfyUI `/prompt`, which requires **API-format** workflow JSON (a dict keyed by node id -> `{class_type, inputs}`).

This repo includes minimal deterministic workflows:
- `video_workflow_api.json`: loads `sample_video.ppm` from ComfyUI `input/` and saves an image output.
- `audio_workflow_api.json`: loads `sample_audio.ppm` from ComfyUI `input/` and saves an image output.

These are intentionally simple “plumbing” workflows to validate end-to-end:
Pipelines → ComfyUI `/prompt` → output file → nginx `/comfyui/view?...` URL.

They require the ComfyUI container to have `./assets/comfyui/input` mounted to `/opt/ComfyUI/input` (wired in the single-node GPU compose).
Recommended next step:
- Pull / mount your own checkpoints into the ComfyUI model path, then clone this workflow and add the standard text-to-image nodes.
