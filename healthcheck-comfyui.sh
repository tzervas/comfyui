#!/bin/bash

# Check if ComfyUI web interface is responding and contains expected content
URL="http://localhost:18188/"

if command -v curl >/dev/null 2>&1; then
  if curl -fsS --max-time 10 "$URL" | grep -q "ComfyUI"; then
    exit 0
  fi
else
  # Many ComfyUI images ship Python but not curl.
  if python - <<'PY' | grep -q "ComfyUI"; then
import urllib.request

with urllib.request.urlopen("http://localhost:18188/", timeout=10) as resp:
    print(resp.read().decode("utf-8", errors="ignore"))
PY
    exit 0
  fi
fi

exit 1