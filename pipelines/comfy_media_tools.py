"""
title: ComfyUI Media Tools (Video/Audio)
author: comfyui-guy
date: 2026-01-02
version: 1.0.1
license: MIT
description: Function-calling tools that trigger ComfyUI workflows (video/audio) and return inline-playable file URLs.
requirements: requests

Notes:
- Pipelines loader loads only `*.py` directly under PIPELINES_DIR.
- Avoid `@dataclass`: Pipelines loader does not insert modules into `sys.modules` before exec, which can break dataclasses.
"""

from __future__ import annotations

import json
import os
import time
from pathlib import Path
from typing import Any, Optional

import requests
from blueprints.function_calling_blueprint import Pipeline as FunctionCallingBlueprint


class ComfyFile:
    def __init__(self, filename: str, subfolder: str = "", type: str = "output") -> None:
        self.filename = filename
        self.subfolder = subfolder
        self.type = type


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
        public = (public_base_url or "").rstrip("/")
        self.public_base_url = (public + "/") if public else (self.base_url + "/")
        self.poll_seconds = poll_seconds
        self.timeout_seconds = timeout_seconds
        self.session = session or requests.Session()

    def _url(self, path: str) -> str:
        if not path.startswith("/"):
            path = "/" + path
        return f"{self.base_url}{path}"

    def submit_prompt(self, workflow: dict[str, Any], client_id: str = "openwebui-pipelines") -> str:
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

    def wait_for_output_file(self, prompt_id: str, want_exts: tuple[str, ...]) -> ComfyFile:
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
        params: dict[str, str] = {
            "filename": file.filename,
            "type": file.type,
        }
        if file.subfolder:
            params["subfolder"] = file.subfolder

        query = "&".join([f"{k}={requests.utils.quote(str(v), safe='')}" for k, v in params.items()])
        return f"{self.public_base_url}view?{query}"

    @staticmethod
    def load_workflow_json(path: str) -> dict[str, Any]:
        workflow_path = Path(path)
        if not workflow_path.exists():
            raise FileNotFoundError(
                f"Workflow JSON not found: {path}. Set COMFYUI_WORKFLOW_VIDEO/AUDIO to a ComfyUI API-format workflow JSON."
            )
        data = json.loads(workflow_path.read_text(encoding="utf-8"))
        if isinstance(data, dict) and "nodes" in data and "links" in data:
            raise ValueError(
                "Workflow JSON appears to be a ComfyUI UI-export (contains 'nodes'/'links'). "
                "ComfyUI /prompt requires API-format. Export/convert to API format and retry."
            )
        return data

    @staticmethod
    def inject_prompt_text(workflow: dict[str, Any], prompt: str) -> dict[str, Any]:
        updated = json.loads(json.dumps(workflow))

        for _node_id, node in updated.items():
            if not isinstance(node, dict):
                continue
            class_type = node.get("class_type")
            inputs = node.get("inputs")
            if not isinstance(inputs, dict):
                continue

            if class_type == "CLIPTextEncode" and "text" in inputs:
                inputs["text"] = prompt

            if class_type in {"String", "Text", "TextInput"}:
                if "text" in inputs:
                    inputs["text"] = prompt
                if "string" in inputs:
                    inputs["string"] = prompt

        return updated

    @staticmethod
    def _find_first_matching_file(outputs: dict[str, Any], want_exts: tuple[str, ...]) -> Optional[ComfyFile]:
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


class Pipeline(FunctionCallingBlueprint):
    class Valves(FunctionCallingBlueprint.Valves):
        pass

    class Tools:
        def __init__(self, pipeline: "Pipeline") -> None:
            self.pipeline = pipeline

        def media_generate(self, message: str) -> dict:
            msg = (message or "").strip()
            if msg.lower().startswith("video:"):
                return self.generate_video(msg.split(":", 1)[1].strip())
            if msg.lower().startswith("audio:"):
                return self.generate_audio(msg.split(":", 1)[1].strip())

            return {
                "type": "text",
                "content": "Unrecognized format. Use 'video: <prompt>' or 'audio: <prompt>'.",
            }

        def generate_video(self, prompt: str) -> dict:
            client = self.pipeline._client()
            workflow_path = self.pipeline._workflow_path("COMFYUI_WORKFLOW_VIDEO")
            workflow = client.load_workflow_json(workflow_path)
            workflow = client.inject_prompt_text(workflow, prompt)

            prompt_id = client.submit_prompt(workflow)
            out_file = client.wait_for_output_file(
                prompt_id,
                want_exts=(".mp4", ".webm", ".gif", ".png", ".jpg", ".jpeg", ".webp"),
            )
            url = client.public_file_url(out_file)
            return {
                "type": "file",
                "name": out_file.filename,
                "url": url,
                "meta": {"prompt_id": prompt_id, "kind": "video"},
            }

        def generate_audio(self, prompt: str) -> dict:
            client = self.pipeline._client()
            workflow_path = self.pipeline._workflow_path("COMFYUI_WORKFLOW_AUDIO")
            workflow = client.load_workflow_json(workflow_path)
            workflow = client.inject_prompt_text(workflow, prompt)

            prompt_id = client.submit_prompt(workflow)
            out_file = client.wait_for_output_file(
                prompt_id,
                want_exts=(".wav", ".mp3", ".flac", ".ogg", ".png", ".jpg", ".jpeg", ".webp"),
            )
            url = client.public_file_url(out_file)
            return {
                "type": "file",
                "name": out_file.filename,
                "url": url,
                "meta": {"prompt_id": prompt_id, "kind": "audio"},
            }

        def langchain_query(self, query: str) -> str:
            base = self.pipeline._env("LANGCHAIN_API_URL", default="http://langchain:8000").rstrip("/")
            resp = requests.post(f"{base}/query", json={"query": query}, timeout=120)
            resp.raise_for_status()
            data = resp.json()
            return data.get("response") or data.get("result") or str(data)

        def stateful_media_agent(self, goal: str, __metadata__: Optional[dict] = None) -> dict:
            chat_id = None
            if isinstance(__metadata__, dict):
                chat_id = __metadata__.get("chat_id") or __metadata__.get("id")
            if not chat_id:
                chat_id = "default"

            state = self.pipeline._state.setdefault(chat_id, {"history": []})
            state["history"].append({"goal": goal})

            g = (goal or "").lower()
            if "video" in g or g.startswith("video:"):
                prompt = goal.split(":", 1)[1].strip() if g.startswith("video:") else goal
                result = self.generate_video(prompt)
                state["history"].append({"result": result})
                return result
            if "audio" in g or "music" in g or g.startswith("audio:"):
                prompt = goal.split(":", 1)[1].strip() if g.startswith("audio:") else goal
                result = self.generate_audio(prompt)
                state["history"].append({"result": result})
                return result

            return {
                "type": "text",
                "content": "I can generate media. Say 'video: <prompt>' or 'audio: <prompt>' (or mention video/audio in your goal).",
                "meta": {"chat_id": chat_id, "state_items": len(state["history"])},
            }

    def __init__(self):
        super().__init__()

        self.name = "ComfyUI Media Tools"
        self.valves = self.Valves(
            **{
                **self.valves.model_dump(),
                "pipelines": ["*"],
            }
        )

        self.tools = self.Tools(self)
        self._state: dict[str, dict[str, Any]] = {}

    async def inlet(self, body: dict, user: Optional[dict] = None) -> dict:
        messages = body.get("messages")
        if not isinstance(messages, list) or not messages:
            return body

        last = messages[-1]
        if not isinstance(last, dict) or last.get("role") != "user":
            return body

        content = last.get("content")
        if not isinstance(content, str):
            return body

        text = content.strip()
        if not (text.lower().startswith("video:") or text.lower().startswith("audio:")):
            return body

        try:
            result = self.tools.media_generate(text)
        except Exception as e:
            messages.append({"role": "assistant", "content": f"Media generation failed: {e}"})
            return body

        if isinstance(result, dict) and result.get("type") == "file" and result.get("url"):
            url = result.get("url")
            name = result.get("name") or "output"
            kind = (result.get("meta") or {}).get("kind") or "media"
            messages.append({"role": "assistant", "content": f"Generated {kind}: {name}\n{url}"})
            return body

        if isinstance(result, dict) and result.get("type") == "text":
            messages.append({"role": "assistant", "content": result.get("content") or ""})
            return body

        messages.append({"role": "assistant", "content": f"Unexpected result: {result}"})
        return body

    def _env(self, key: str, default: Optional[str] = None) -> str:
        val = os.getenv(key, default)
        if val is None or val == "":
            raise RuntimeError(f"Missing required env var: {key}")
        return val

    def _client(self) -> ComfyUIClient:
        base = self._env("COMFYUI_BASE_URL")
        public = os.getenv("COMFYUI_PUBLIC_BASE_URL", base) or base
        poll = float(os.getenv("COMFYUI_POLL_SECONDS", "2"))
        timeout = float(os.getenv("COMFYUI_TIMEOUT_SECONDS", "900"))
        return ComfyUIClient(base_url=base, public_base_url=public, poll_seconds=poll, timeout_seconds=timeout)

    def _workflow_path(self, key: str) -> str:
        defaults = {
            "COMFYUI_WORKFLOW_VIDEO": "/app/assets/comfyui/workflows/video_workflow_api.json",
            "COMFYUI_WORKFLOW_AUDIO": "/app/assets/comfyui/workflows/audio_workflow_api.json",
        }
        return self._env(key, default=defaults.get(key))
