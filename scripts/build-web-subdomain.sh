#!/usr/bin/env bash
# PlanetMM — Flutter Web build for app.mingalarbuy.com (subdomain root, BASE_HREF=/)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

export BASE_HREF="/"
export DEPLOY_DIR="$ROOT/deploy/plesk-subdomain"
export HTACCESS_SRC="$ROOT/web/.htaccess.subdomain"
export ZIP_PATH="$ROOT/deploy/planetmm-web-subdomain.zip"
export SITE_URL="https://app.mingalarbuy.com"
export WEB_API_ORIGIN="https://mingalarbuy.com"

exec "$ROOT/scripts/build-web-plesk.sh"
