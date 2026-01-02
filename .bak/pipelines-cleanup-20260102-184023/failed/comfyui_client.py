import json
import os
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Optional

import requests


@dataclass(frozen=True)
class ComfyFile:
    filename: str
    subfolder: str = ""
    type: str = "output"


class ComfyUIClient:
    def __init__(
        self,
        base_url: str,
        public_base_url: str,
        poll_seconds: float = 2.0,
        timeout_seconds: float = 900.0,
        session: Optional[requests.Session] = None,
    ) -> None:
        self.base_url = base_url.rstrip("/")
        self.public_base_url = public_base_url.rstrip("/") + "/"
        self.poll_seconds = poll_seconds
        self.timeout_seconds = timeout_seconds
        self.session = session or requests.Session()

    def _url(self, path: str) -> str:
        if not path.startswith("/"):
            path = "/" + path
        return f"{self.base_url}{path}"

    def submit_prompt(self, workflow: dict[str, Any], client_id: str = "openwebui-pipelines") -> str:
        # ComfyUI expects: {"prompt": <workflow_dict>, "client_id": "..."}
        resp = self.session.post(
            self._url("/prompt"),
            json={"prompt": workflow, "client_id": client_id},
            timeout=30,
        )
        resp.raise_for_status()
        data = resp.json()
        prompt_id = data.get("prompt_id")
        if not prompt_id:
            raise RuntimeError(f"ComfyUI /prompt response missing prompt_id: {data}")
        return prompt_id

    def get_history(self, prompt_id: str) -> dict[str, Any]:
        resp = self.session.get(self._url(f"/history/{prompt_id}"), timeout=30)
        resp.raise_for_status()
        return resp.json()

    def wait_for_output_file(
        self,
        prompt_id: str,
        want_exts: tuple[str, ...],
    ) -> ComfyFile:
        deadline = time.time() + self.timeout_seconds
        last_history: dict[str, Any] | None = None

        while time.time() < deadline:
            last_history = self.get_history(prompt_id)
            prompt_history = last_history.get(prompt_id)
            if isinstance(prompt_history, dict):
                outputs = prompt_history.get("outputs")
                if isinstance(outputs, dict):
                    found = self._find_first_matching_file(outputs, want_exts)
                    if found:
                        return found

            time.sleep(self.poll_seconds)

        raise TimeoutError(
            f"Timed out waiting for ComfyUI output for prompt_id={prompt_id}. Last history keys={list((last_history or {}).keys())}"
        )

    def public_file_url(self, file: ComfyFile) -> str:
        # ComfyUI serves files via /view
        # Example: /view?filename=foo.mp4&subfolder=bar&type=output
        params = {
            "filename": file.filename,
            "type": file.type,
        }
        if file.subfolder:
            params["subfolder"] = file.subfolder

        # Build a stable URL without importing urllib (keep deps minimal)
        query = "&".join(
            [
                f"{k}={requests.utils.quote(str(v), safe='')}"
                for k, v in params.items()
            ]
        )
        return f"{self.public_base_url}view?{query}"

    @staticmethod
    def load_workflow_json(path: str) -> dict[str, Any]:
        workflow_path = Path(path)
        if not workflow_path.exists():
            raise FileNotFoundError(f"Workflow JSON not found: {path}")
        return json.loads(workflow_path.read_text(encoding="utf-8"))

    @staticmethod
    def inject_prompt_text(workflow: dict[str, Any], prompt: str) -> dict[str, Any]:
        """Best-effort prompt injection.

        ComfyUI workflows vary wildly; this tries common patterns and leaves TODOs
        for you to hard-map specific node ids for video/audio workflows.
        """
        updated = json.loads(json.dumps(workflow))  # deep copy

        for _node_id, node in updated.items():
            if not isinstance(node, dict):
                continue
            class_type = node.get("class_type")
            inputs = node.get("inputs")
            if not isinstance(inputs, dict):
                continue

            # Common text prompt node
            if class_type == "CLIPTextEncode" and "text" in inputs:
                inputs["text"] = prompt

            # Some workflows use a plain "String" node
            if class_type in {"String", "Text", "TextInput"}:
                if "text" in inputs:
                    inputs["text"] = prompt
                if "string" in inputs:
                    inputs["string"] = prompt

        return updated

    @staticmethod
    def _find_first_matching_file(outputs: dict[str, Any], want_exts: tuple[str, ...]) -> Optional[ComfyFile]:
        # ComfyUI history output structure:
        # outputs[node_id]["images"][0] = {filename, subfolder, type}
        # outputs[node_id]["gifs"][0] = {...}
        # Some custom nodes use "videos" or "audio" keys.
        media_keys = ("videos", "gifs", "images", "audio", "audios")

        for _node_id, node_out in outputs.items():
            if not isinstance(node_out, dict):
                continue
            for key in media_keys:
                items = node_out.get(key)
                if not isinstance(items, list):
                    continue
                for item in items:
                    if not isinstance(item, dict):
                        continue
                    filename = item.get("filename")
                    if not filename or not isinstance(filename, str):
                        continue
                    if want_exts and not any(filename.lower().endswith(ext) for ext in want_exts):
                        continue
                    return ComfyFile(
                        filename=filename,
                        subfolder=item.get("subfolder") or "",
                        type=item.get("type") or "output",
                    )

        return None
