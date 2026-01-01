import os
import subprocess
import tempfile
import time
from typing import Any

from fastapi import FastAPI, HTTPException, Request
from fastapi.responses import JSONResponse, PlainTextResponse

app = FastAPI(title="Code Executor", version="1.0")

DEFAULT_TIMEOUT_SEC = float(os.getenv("EXEC_TIMEOUT_SEC", "3"))
DEFAULT_MAX_OUTPUT_BYTES = int(os.getenv("EXEC_MAX_OUTPUT_BYTES", str(64 * 1024)))
DEFAULT_MAX_MEMORY_MB = int(os.getenv("EXEC_MAX_MEMORY_MB", "256"))
DEFAULT_MAX_FILE_BYTES = int(os.getenv("EXEC_MAX_FILE_BYTES", str(1 * 1024 * 1024)))


def _limits_preexec() -> None:
    # Apply basic resource limits to the child process (Linux only).
    try:
        import resource

        cpu_seconds = max(1, int(DEFAULT_TIMEOUT_SEC) + 1)
        memory_bytes = max(64, DEFAULT_MAX_MEMORY_MB) * 1024 * 1024

        resource.setrlimit(resource.RLIMIT_CPU, (cpu_seconds, cpu_seconds))
        resource.setrlimit(resource.RLIMIT_AS, (memory_bytes, memory_bytes))
        resource.setrlimit(resource.RLIMIT_FSIZE, (DEFAULT_MAX_FILE_BYTES, DEFAULT_MAX_FILE_BYTES))
        resource.setrlimit(resource.RLIMIT_CORE, (0, 0))

        # Reasonable process/file descriptor limits
        resource.setrlimit(resource.RLIMIT_NOFILE, (128, 128))
        if hasattr(resource, "RLIMIT_NPROC"):
            resource.setrlimit(resource.RLIMIT_NPROC, (64, 64))
    except Exception:
        # Best-effort. Container hardening is handled by Docker options.
        return


def _truncate(s: str, max_bytes: int) -> tuple[str, bool]:
    raw = s.encode("utf-8", errors="replace")
    if len(raw) <= max_bytes:
        return s, False
    return raw[:max_bytes].decode("utf-8", errors="replace"), True


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}


@app.get("/")
def index() -> dict[str, str]:
    return {"service": "code-executor", "hint": "POST text/plain to / to execute"}


@app.post("/")
async def execute(request: Request) -> JSONResponse:
    content_type = (request.headers.get("content-type") or "").split(";")[0].strip().lower()

    code: str
    if content_type in ("application/json", "application/problem+json"):
        data: Any = await request.json()
        if not isinstance(data, dict) or "code" not in data:
            raise HTTPException(status_code=400, detail="JSON body must be {\"code\": \"...\"}")
        code = str(data["code"])
    else:
        # Default to text/plain
        code = (await request.body()).decode("utf-8", errors="replace")

    if not code.strip():
        raise HTTPException(status_code=400, detail="No code provided")

    start = time.time()
    with tempfile.TemporaryDirectory(prefix="code-exec-") as tmp:
        script_path = os.path.join(tmp, "main.py")
        with open(script_path, "w", encoding="utf-8") as f:
            f.write(code)

        env = {
            "PYTHONUNBUFFERED": "1",
            "PYTHONIOENCODING": "utf-8",
            "PYTHONDONTWRITEBYTECODE": "1",
            "HOME": "/tmp",
            "PATH": os.getenv("PATH", ""),
        }

        try:
            proc = subprocess.run(
                ["python", "-I", "-S", script_path],
                cwd=tmp,
                env=env,
                capture_output=True,
                text=True,
                timeout=DEFAULT_TIMEOUT_SEC,
                preexec_fn=_limits_preexec,
            )
        except subprocess.TimeoutExpired:
            duration_ms = int((time.time() - start) * 1000)
            raise HTTPException(status_code=408, detail=f"Execution timed out after {DEFAULT_TIMEOUT_SEC}s (duration_ms={duration_ms})")

    duration_ms = int((time.time() - start) * 1000)

    stdout, stdout_trunc = _truncate(proc.stdout or "", DEFAULT_MAX_OUTPUT_BYTES)
    stderr, stderr_trunc = _truncate(proc.stderr or "", DEFAULT_MAX_OUTPUT_BYTES)

    return JSONResponse(
        {
            "exit_code": proc.returncode,
            "duration_ms": duration_ms,
            "stdout": stdout,
            "stderr": stderr,
            "truncated": bool(stdout_trunc or stderr_trunc),
        }
    )


@app.exception_handler(HTTPException)
async def http_exc_handler(_: Request, exc: HTTPException) -> PlainTextResponse:
    return PlainTextResponse(str(exc.detail), status_code=exc.status_code)
