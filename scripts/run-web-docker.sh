#!/usr/bin/env bash
# Build subdomain web + start Docker nginx on http://localhost:8080
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "==> Building Flutter web (subdomain)..."
"$ROOT/scripts/build-web-subdomain.sh"

echo "==> Starting Docker (nginx on http://localhost:8080)..."
cd "$ROOT/deploy/docker"
docker compose up -d --force-recreate

echo ""
echo "✅ Local server: http://localhost:8080"
echo "   (Same static files as app.mingalarbuy.com — API → https://mingalarbuy.com)"
echo ""
echo "Stop:  cd deploy/docker && docker compose down"
