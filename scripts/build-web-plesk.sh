#!/usr/bin/env bash
# PlanetMM — Production Flutter Web build for Plesk
# Default: mingalarbuy.com/app/  |  Subdomain: ./scripts/build-web-subdomain.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

BASE_HREF="${BASE_HREF:-/app/}"
OUTPUT_DIR="$ROOT/build/web"
DEPLOY_DIR="${DEPLOY_DIR:-$ROOT/deploy/plesk-app}"
HTACCESS_SRC="${HTACCESS_SRC:-$ROOT/web/.htaccess}"
ZIP_PATH="${ZIP_PATH:-$ROOT/deploy/planetmm-web-plesk.zip}"
SITE_URL="${SITE_URL:-}"
WEB_API_ORIGIN="${WEB_API_ORIGIN:-}"

# Optional Firebase web config (export before running, or leave empty to skip FCM web push).
FIREBASE_API_KEY="${FIREBASE_API_KEY:-}"
FIREBASE_AUTH_DOMAIN="${FIREBASE_AUTH_DOMAIN:-}"
FIREBASE_PROJECT_ID="${FIREBASE_PROJECT_ID:-}"
FIREBASE_STORAGE_BUCKET="${FIREBASE_STORAGE_BUCKET:-}"
FIREBASE_MESSAGING_SENDER_ID="${FIREBASE_MESSAGING_SENDER_ID:-}"
FIREBASE_APP_ID="${FIREBASE_APP_ID:-}"
FIREBASE_MEASUREMENT_ID="${FIREBASE_MEASUREMENT_ID:-}"
FIREBASE_VAPID_KEY="${FIREBASE_VAPID_KEY:-}"

echo "==> PlanetMM Flutter Web — Plesk build"
echo "    Base href : $BASE_HREF"
echo "    Output    : $OUTPUT_DIR"
echo "    Deploy    : $DEPLOY_DIR"
if [[ -n "$WEB_API_ORIGIN" ]]; then
  echo "    API origin: $WEB_API_ORIGIN"
fi
if [[ -n "$FIREBASE_PROJECT_ID" ]]; then
  echo "    Firebase  : enabled ($FIREBASE_PROJECT_ID)"
else
  echo "    Firebase  : skipped (set FIREBASE_* env vars to enable web push)"
fi

# Ensure trailing slash on base href
if [[ "$BASE_HREF" != */ ]]; then
  BASE_HREF="${BASE_HREF}/"
fi

# Firebase SW and notification paths use the same prefix as base href
BASE_PATH="$BASE_HREF"
if [[ "$BASE_PATH" != "/" && "$BASE_PATH" != */ ]]; then
  BASE_PATH="${BASE_PATH}/"
fi

DART_DEFINES=()
add_define() {
  local key="$1"
  local val="$2"
  if [[ -n "$val" ]]; then
    DART_DEFINES+=( "--dart-define=${key}=${val}" )
  fi
}

add_define "FIREBASE_API_KEY" "$FIREBASE_API_KEY"
add_define "FIREBASE_AUTH_DOMAIN" "$FIREBASE_AUTH_DOMAIN"
add_define "FIREBASE_PROJECT_ID" "$FIREBASE_PROJECT_ID"
add_define "FIREBASE_STORAGE_BUCKET" "$FIREBASE_STORAGE_BUCKET"
add_define "FIREBASE_MESSAGING_SENDER_ID" "$FIREBASE_MESSAGING_SENDER_ID"
add_define "FIREBASE_APP_ID" "$FIREBASE_APP_ID"
add_define "FIREBASE_MEASUREMENT_ID" "$FIREBASE_MEASUREMENT_ID"
add_define "FIREBASE_VAPID_KEY" "$FIREBASE_VAPID_KEY"
add_define "WEB_API_ORIGIN" "$WEB_API_ORIGIN"

echo "==> flutter pub get"
flutter pub get

echo "==> flutter build web --release --base-href $BASE_HREF"
BUILD_CMD=(flutter build web --release --base-href "$BASE_HREF" --no-tree-shake-icons)
if ((${#DART_DEFINES[@]} > 0)); then
  BUILD_CMD+=("${DART_DEFINES[@]}")
fi
"${BUILD_CMD[@]}"

echo "==> Copy .htaccess into build output"
cp "$HTACCESS_SRC" "$OUTPUT_DIR/.htaccess"

# Release builds reference flutter.js.map but do not ship it — strip to avoid nginx 404 noise.
for _js in flutter.js flutter_bootstrap.js; do
  if [[ -f "$OUTPUT_DIR/$_js" ]]; then
    sed -i.bak '/sourceMappingURL=/d' "$OUTPUT_DIR/$_js"
    rm -f "$OUTPUT_DIR/$_js.bak"
  fi
done

if [[ -n "$SITE_URL" ]]; then
  echo "==> Patch index.html SEO meta for $SITE_URL"
  sed -i.bak \
    -e "s|content=\"https://mingalarbuy.com\"|content=\"${SITE_URL}\"|g" \
    -e "s|\"url\": \"https://mingalarbuy.com\"|\"url\": \"${SITE_URL}\"|g" \
    "$OUTPUT_DIR/index.html"
  rm -f "$OUTPUT_DIR/index.html.bak"
fi

if [[ -n "$FIREBASE_PROJECT_ID" && -n "$FIREBASE_API_KEY" && -n "$FIREBASE_APP_ID" ]]; then
  echo "==> Generate firebase-messaging-sw.js for FCM background push"
  AUTH_DOMAIN="$FIREBASE_AUTH_DOMAIN"
  if [[ -z "$AUTH_DOMAIN" ]]; then
    AUTH_DOMAIN="${FIREBASE_PROJECT_ID}.firebaseapp.com"
  fi
  STORAGE_BUCKET="$FIREBASE_STORAGE_BUCKET"
  if [[ -z "$STORAGE_BUCKET" ]]; then
    STORAGE_BUCKET="${FIREBASE_PROJECT_ID}.appspot.com"
  fi
  sed \
    -e "s|__FIREBASE_API_KEY__|${FIREBASE_API_KEY}|g" \
    -e "s|__FIREBASE_AUTH_DOMAIN__|${AUTH_DOMAIN}|g" \
    -e "s|__FIREBASE_PROJECT_ID__|${FIREBASE_PROJECT_ID}|g" \
    -e "s|__FIREBASE_STORAGE_BUCKET__|${STORAGE_BUCKET}|g" \
    -e "s|__FIREBASE_MESSAGING_SENDER_ID__|${FIREBASE_MESSAGING_SENDER_ID}|g" \
    -e "s|__FIREBASE_APP_ID__|${FIREBASE_APP_ID}|g" \
    -e "s|__FIREBASE_MEASUREMENT_ID__|${FIREBASE_MEASUREMENT_ID}|g" \
    -e "s|__BASE_PATH__|${BASE_PATH}|g" \
    "$ROOT/web/firebase-messaging-sw.js" > "$OUTPUT_DIR/firebase-messaging-sw.js"
else
  echo "==> Skipping firebase-messaging-sw.js (FIREBASE_* not set)"
fi

# Cache-bust app shell for Cloudflare/CDN without dashboard purge (new URL = cache miss).
BUILD_ID=""
if [[ -f "$OUTPUT_DIR/.last_build_id" ]]; then
  BUILD_ID="$(tr -d '[:space:]' < "$OUTPUT_DIR/.last_build_id")"
fi
if [[ -z "$BUILD_ID" ]]; then
  BUILD_ID="$(date +%s)"
fi
echo "==> Cache-bust deploy id: $BUILD_ID"
if [[ -f "$OUTPUT_DIR/flutter_bootstrap.js" ]]; then
  sed -i.bak "s|\"mainJsPath\":\"main.dart.js\"|\"mainJsPath\":\"main.dart.js?v=${BUILD_ID}\"|" \
    "$OUTPUT_DIR/flutter_bootstrap.js"
  rm -f "$OUTPUT_DIR/flutter_bootstrap.js.bak"
fi
if [[ -f "$OUTPUT_DIR/index.html" ]]; then
  sed -i.bak "s|src=\"flutter_bootstrap.js\"|src=\"flutter_bootstrap.js?v=${BUILD_ID}\"|" \
    "$OUTPUT_DIR/index.html"
  rm -f "$OUTPUT_DIR/index.html.bak"
fi

echo "==> Package deploy bundle"
rm -rf "$DEPLOY_DIR"
mkdir -p "$DEPLOY_DIR"
cp -R "$OUTPUT_DIR/." "$DEPLOY_DIR/"

# Zip for easy Plesk upload
mkdir -p "$(dirname "$ZIP_PATH")"
rm -f "$ZIP_PATH"
(cd "$DEPLOY_DIR" && zip -r -q "$ZIP_PATH" .)

echo ""
echo "✅ Build complete!"
echo "   Upload folder : $DEPLOY_DIR"
echo "   Zip archive   : $ZIP_PATH"
echo ""
if [[ "$BASE_HREF" == "/" ]]; then
  echo "Plesk steps (subdomain — app.mingalarbuy.com):"
  echo "  1. File Manager → app.mingalarbuy.com document root (httpdocs)"
  echo "  2. Upload contents of deploy/plesk-subdomain/ (or extract zip)"
  echo "  3. Do NOT create an /app/ subfolder"
  echo "  4. Visit https://app.mingalarbuy.com/"
  echo ""
  echo "Server checklist:"
  echo "  - WordPress: activate/update twork-cors plugin (allows app.mingalarbuy.com)"
  echo "  - Nginx: reload backend/nginx/twork-web-cors.conf if used"
  echo "  - Nginx SPA: try_files \$uri \$uri/ /index.html; in server block"
else
  echo "Plesk steps (path — mingalarbuy.com/app/):"
  echo "  1. File Manager → httpdocs/app/ (create if missing)"
  echo "  2. Upload contents of deploy/plesk-app/ (or extract zip)"
  echo "  3. Visit https://mingalarbuy.com/app/"
fi
echo ""
echo "Firebase web push (optional):"
echo "  export FIREBASE_API_KEY=... FIREBASE_PROJECT_ID=... \\"
echo "         FIREBASE_MESSAGING_SENDER_ID=... FIREBASE_APP_ID=... \\"
echo "         FIREBASE_VAPID_KEY=..."
echo "  ./scripts/build-web-subdomain.sh"
