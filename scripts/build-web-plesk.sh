#!/usr/bin/env bash
# PlanetMM — Production Flutter Web build for Plesk (mingalarbuy.com/app/)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

BASE_HREF="${BASE_HREF:-/app/}"
OUTPUT_DIR="$ROOT/build/web"
DEPLOY_DIR="$ROOT/deploy/plesk-app"

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
if [[ -n "$FIREBASE_PROJECT_ID" ]]; then
  echo "    Firebase  : enabled ($FIREBASE_PROJECT_ID)"
else
  echo "    Firebase  : skipped (set FIREBASE_* env vars to enable web push)"
fi

# Ensure trailing slash on base href
if [[ "$BASE_HREF" != */ ]]; then
  BASE_HREF="${BASE_HREF}/"
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

echo "==> flutter pub get"
flutter pub get

echo "==> flutter build web --release --base-href $BASE_HREF"
flutter build web \
  --release \
  --base-href "$BASE_HREF" \
  --no-tree-shake-icons \
  "${DART_DEFINES[@]}"

echo "==> Copy .htaccess into build output"
cp "$ROOT/web/.htaccess" "$OUTPUT_DIR/.htaccess"

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
    "$ROOT/web/firebase-messaging-sw.js" > "$OUTPUT_DIR/firebase-messaging-sw.js"
else
  echo "==> Skipping firebase-messaging-sw.js (FIREBASE_* not set)"
fi

echo "==> Package deploy bundle"
rm -rf "$DEPLOY_DIR"
mkdir -p "$DEPLOY_DIR"
cp -R "$OUTPUT_DIR/." "$DEPLOY_DIR/"

# Zip for easy Plesk upload
ZIP_PATH="$ROOT/deploy/planetmm-web-plesk.zip"
rm -f "$ZIP_PATH"
(cd "$DEPLOY_DIR" && zip -r -q "$ZIP_PATH" .)

echo ""
echo "✅ Build complete!"
echo "   Upload folder : $DEPLOY_DIR"
echo "   Zip archive   : $ZIP_PATH"
echo ""
echo "Plesk steps:"
echo "  1. File Manager → httpdocs/app/ (create if missing)"
echo "  2. Upload contents of deploy/plesk-app/ (or extract zip)"
echo "  3. Visit https://mingalarbuy.com/app/"
echo ""
echo "Firebase web push (optional):"
echo "  export FIREBASE_API_KEY=... FIREBASE_PROJECT_ID=... \\"
echo "         FIREBASE_MESSAGING_SENDER_ID=... FIREBASE_APP_ID=... \\"
echo "         FIREBASE_VAPID_KEY=..."
echo "  ./scripts/build-web-plesk.sh"
