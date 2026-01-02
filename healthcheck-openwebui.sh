#!/bin/sh
set -eu

# Best-effort healthcheck for OpenWebUI.
# Avoid curl (may not be present) and avoid IPv6 ::1 resolution issues.

python3 - <<'PY'
import sys
import urllib.request

urls = [
  "http://127.0.0.1:8080/api/v1/health",
  "http://127.0.0.1:8080/health",
  "http://127.0.0.1:8080/",
]

for url in urls:
    try:
        req = urllib.request.Request(url, headers={"User-Agent": "healthcheck"})
        with urllib.request.urlopen(req, timeout=5) as resp:
            if 200 <= resp.status < 400:
                sys.exit(0)
    except Exception:
        pass

sys.exit(1)
PY
