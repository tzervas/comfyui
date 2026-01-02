#!/bin/sh
set -eu

# Generate Basic Auth htpasswd file at container start.
# - Used when SSO is disabled.
# - Avoids committing secrets or relying on a prebuilt .htpasswd.

if [ "${SSO_ENABLED:-0}" = "1" ]; then
  echo "[nginx-basic-auth] SSO_ENABLED=1; skipping basic auth htpasswd generation"
  exit 0
fi

user="${NGINX_BASIC_AUTH_USER:-${BASIC_AUTH_USER:-admin}}"
pass="${NGINX_BASIC_AUTH_PASSWORD:-${BASIC_AUTH_PASSWORD:-}}"

if [ -z "$pass" ]; then
  echo "[nginx-basic-auth] Missing NGINX_BASIC_AUTH_PASSWORD (or BASIC_AUTH_PASSWORD). Refusing to start." >&2
  exit 1
fi

if ! command -v htpasswd >/dev/null 2>&1; then
  if command -v apk >/dev/null 2>&1; then
    echo "[nginx-basic-auth] Installing apache2-utils (provides htpasswd)" >&2
    apk add --no-cache apache2-utils >/dev/null
  else
    echo "[nginx-basic-auth] htpasswd not found and apk unavailable" >&2
    exit 1
  fi
fi

# Write as MD5 apr1 (compatible with nginx auth_basic_user_file).
htpasswd -bc /etc/nginx/.htpasswd "$user" "$pass" >/dev/null 2>&1
# nginx worker runs as non-root; ensure it can read the file.
chmod 644 /etc/nginx/.htpasswd || true

echo "[nginx-basic-auth] Wrote /etc/nginx/.htpasswd for user '$user'" >&2
