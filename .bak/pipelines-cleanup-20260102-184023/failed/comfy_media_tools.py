"""
title: ComfyUI Media Tools (Video/Audio)
author: comfyui-guy
date: 2026-01-02
version: 0.2.0
license: MIT
description: Function-calling tools that trigger ComfyUI workflows (video/audio) and return inline-playable file URLs.
requirements: requests

Notes:
- This runs inside ghcr.io/open-webui/pipelines:main.
- Keep module imports flat (single-file) to match Pipelines loader expectations.
"""

from __future__ import annotations

import os
from typing import Any, Optional

from blueprints.function_calling_blueprint import Pipeline as FunctionCallingBlueprint

from comfyui_client_lib import ComfyUIClient


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
            workflow_path = self.pipeline._env("COMFYUI_WORKFLOW_VIDEO")
            workflow = client.load_workflow_json(workflow_path)
            workflow = client.inject_prompt_text(workflow, prompt)

            prompt_id = client.submit_prompt(workflow)
            out_file = client.wait_for_output_file(prompt_id, want_exts=(".mp4", ".webm", ".gif"))
            url = client.public_file_url(out_file)
            return {
                "type": "file",
                "name": out_file.filename,
                "url": url,
                "meta": {"prompt_id": prompt_id, "kind": "video"},
            }

        def generate_audio(self, prompt: str) -> dict:
            client = self.pipeline._client()
            workflow_path = self.pipeline._env("COMFYUI_WORKFLOW_AUDIO")
            workflow = client.load_workflow_json(workflow_path)
            workflow = client.inject_prompt_text(workflow, prompt)

            prompt_id = client.submit_prompt(workflow)
            out_file = client.wait_for_output_file(prompt_id, want_exts=(".wav", ".mp3", ".flac", ".ogg"))
            url = client.public_file_url(out_file)
            return {
                "type": "file",
                "name": out_file.filename,
                "url": url,
                "meta": {"prompt_id": prompt_id, "kind": "audio"},
            }

        def langchain_query(self, query: str) -> str:
            import requests

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
