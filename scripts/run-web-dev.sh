#!/usr/bin/env bash
# PlanetMM — Flutter Web local dev with CORS proxy (Chrome login/API fix)
#
# Usage:
#   ./scripts/run-web-dev.sh
#   ./scripts/run-web-dev.sh --release
#   PROXY_PORT=8788 ./scripts/run-web-dev.sh
#
# Do NOT use WEB_DEV_PROXY in production builds.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BACKEND="$ROOT/backend"
PROXY_PORT="${PROXY_PORT:-8787}"
PROXY_URL="http://127.0.0.1:${PROXY_PORT}"
PROXY_PID=""
STARTED_PROXY=0

proxy_is_up() {
  local code
  code="$(curl -s -o /dev/null -w '%{http_code}' -X OPTIONS \
    "${PROXY_URL}/wp-json/" \
    -H "Origin: http://127.0.0.1:1" \
    -H "Access-Control-Request-Method: GET" \
    --max-time 2 2>/dev/null || echo '000')"
  [[ "$code" == "204" ]]
}

start_proxy() {
  if [[ ! -d "$BACKEND/node_modules" ]]; then
    echo "Installing backend dependencies (express)..."
    (cd "$BACKEND" && npm install --no-audit --no-fund)
  fi

  echo "Starting CORS proxy on ${PROXY_URL} → https://mingalarbuy.com"
  PORT="$PROXY_PORT" node "$BACKEND/cors_proxy.js" &
  PROXY_PID=$!
  STARTED_PROXY=1

  for _ in $(seq 1 30); do
    if proxy_is_up; then
      echo "CORS proxy ready."
      return 0
    fi
    sleep 0.25
  done

  echo "ERROR: CORS proxy did not start on ${PROXY_URL} (port busy? try PROXY_PORT=8788)" >&2
  exit 1
}

cleanup() {
  if [[ "$STARTED_PROXY" == "1" && -n "$PROXY_PID" ]]; then
    kill "$PROXY_PID" 2>/dev/null || true
  fi
}
trap cleanup EXIT INT TERM

if proxy_is_up; then
  echo "CORS proxy already running at ${PROXY_URL}"
else
  start_proxy
fi

cd "$ROOT"
echo "Launching Flutter web (WEB_DEV_PROXY=${PROXY_URL})..."
exec flutter run -d chrome \
  --dart-define=WEB_DEV_PROXY="${PROXY_URL}" \
  "$@"
