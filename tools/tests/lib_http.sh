#!/usr/bin/env bash
set -euo pipefail

# Shared curl wrapper.
# - Uses local curl if present, else falls back to a dockerized curl.
# - Always prints status code on stderr when failing.

have_cmd() { command -v "$1" >/dev/null 2>&1; }

dockerized_curl() {
  docker run --rm --network host curlimages/curl:8.6.0 "$@"
}

http_curl() {
  if have_cmd curl; then
    curl "$@"
  else
    dockerized_curl "$@"
  fi
}

# Args: METHOD URL [curl args...]
http_req() {
  local method=$1
  local url=$2
  shift 2

  http_curl -sS -D /tmp/headers.$$ -o /tmp/body.$$ -X "$method" "$url" "$@" || {
    echo "HTTP request failed: $method $url" >&2
    if [ -f /tmp/headers.$$ ]; then
      head -n 20 /tmp/headers.$$ >&2 || true
    fi
    if [ -f /tmp/body.$$ ]; then
      head -c 2048 /tmp/body.$$ >&2 || true
      echo >&2
    fi
    rm -f /tmp/headers.$$ /tmp/body.$$
    return 1
  }

  local status
  status=$(head -n 1 /tmp/headers.$$ | awk '{print $2}')
  cat /tmp/body.$$
  rm -f /tmp/headers.$$ /tmp/body.$$
  echo "$status" >&2
}

# Prints body to stdout; echoes status to stderr.
http_get() {
  local url=$1
  shift
  http_req GET "$url" "$@"
}

http_post_json() {
  local url=$1
  local json=$2
  shift 2
  http_req POST "$url" -H "Content-Type: application/json" --data "$json" "$@"
}

http_post_text() {
  local url=$1
  local text=$2
  shift 2
  http_req POST "$url" -H "Content-Type: text/plain" --data-binary "$text" "$@"
}
