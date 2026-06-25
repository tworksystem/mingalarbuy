#!/usr/bin/env bash
# PlanetMM — Android release build (APK + optional AAB)
# Preserves all lib/ features; only configures JDK/Gradle environment for reproducible builds.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

BUILD_NAME="${BUILD_NAME:-1.0.1}"
BUILD_NUMBER="${BUILD_NUMBER:-4}"
BUILD_AAB="${BUILD_AAB:-0}"
BUILD_SPLIT_APK="${BUILD_SPLIT_APK:-0}"
GRADLE_USER_HOME="${GRADLE_USER_HOME:-$HOME/.gradle}"

# Avoid proxy/SOCKS blocking Gradle wrapper downloads when a local cache exists.
unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY ALL_PROXY all_proxy 2>/dev/null || true

log() { printf '==> %s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

find_compatible_java_home() {
  if [[ -n "${JAVA_HOME:-}" ]] && "$JAVA_HOME/bin/java" -version 2>&1 | grep -qE 'version "(1[7-9]|[2-4][0-9])'; then
    echo "$JAVA_HOME"
    return 0
  fi

  local candidate
  for candidate in \
    /Library/Java/JavaVirtualMachines/temurin-21.jdk/Contents/Home \
    /Library/Java/JavaVirtualMachines/temurin-17.jdk/Contents/Home \
    /Library/Java/JavaVirtualMachines/temurin-24.jdk/Contents/Home \
    /usr/lib/jvm/java-21-openjdk \
    /usr/lib/jvm/java-17-openjdk; do
    if [[ -x "$candidate/bin/java" ]]; then
      echo "$candidate"
      return 0
    fi
  done

  if command -v /usr/libexec/java_home >/dev/null 2>&1; then
    local detected
    for detected in 21 17 24; do
      candidate="$(/usr/libexec/java_home -v "$detected" 2>/dev/null || true)"
      if [[ -n "$candidate" && -x "$candidate/bin/java" ]]; then
        echo "$candidate"
        return 0
      fi
    done
  fi

  return 1
}

verify_release_signing() {
  local props_file="$ROOT/android/key.properties"
  [[ -f "$props_file" ]] || die "Missing android/key.properties (release signing config)."

  local store_file
  store_file="$(grep -E '^storeFile=' "$props_file" | cut -d= -f2- | tr -d '[:space:]')"
  [[ -n "$store_file" && -f "$store_file" ]] || die "Release keystore not found: ${store_file:-<empty>}"
}

verify_post_build() {
  local apk="$ROOT/build/app/outputs/flutter-apk/app-release.apk"
  [[ -f "$apk" ]] || die "Release APK not found at $apk"

  log "Release APK: $apk ($(du -h "$apk" | cut -f1))"

  local apksigner=""
  if [[ -n "${ANDROID_HOME:-}" && -d "$ANDROID_HOME/build-tools" ]]; then
    apksigner="$(find "$ANDROID_HOME/build-tools" -name apksigner -type f 2>/dev/null | sort -V | tail -1)"
  elif [[ -d "$HOME/Library/Android/sdk/build-tools" ]]; then
    apksigner="$(find "$HOME/Library/Android/sdk/build-tools" -name apksigner -type f 2>/dev/null | sort -V | tail -1)"
  fi

  if [[ -n "$apksigner" ]]; then
    log "Verifying APK signature"
    "$apksigner" verify --verbose "$apk" | head -20
  else
    log "apksigner not found — skip signature verify (install Android build-tools)"
  fi
}

JAVA_HOME="$(find_compatible_java_home)" || die \
  "Compatible JDK not found. Install Temurin 17/21/24 or set JAVA_HOME before running."

export JAVA_HOME
export GRADLE_USER_HOME
export ORG_GRADLE_JAVA_HOME="$JAVA_HOME"

log "Using JAVA_HOME=$JAVA_HOME"
log "Using GRADLE_USER_HOME=$GRADLE_USER_HOME"

java_major="$("$JAVA_HOME/bin/java" -version 2>&1 | head -1 | sed -E 's/.*"([0-9]+).*/\1/')"
if [[ "$java_major" -ge 25 ]]; then
  die "JDK $java_major is too new for current Gradle/Kotlin toolchain. Use JDK 17–24."
fi

verify_release_signing

log "flutter pub get"
flutter pub get

APK_FLAGS=(--release "--build-name=$BUILD_NAME" "--build-number=$BUILD_NUMBER")
if [[ "$BUILD_SPLIT_APK" == "1" ]]; then
  APK_FLAGS+=(--split-per-abi)
fi

log "flutter build apk ${APK_FLAGS[*]}"
flutter build apk "${APK_FLAGS[@]}"

if [[ "$BUILD_AAB" == "1" ]]; then
  log "flutter build appbundle --release --build-name=$BUILD_NAME --build-number=$BUILD_NUMBER"
  flutter build appbundle --release "--build-name=$BUILD_NAME" "--build-number=$BUILD_NUMBER"
  local_aab="$ROOT/build/app/outputs/bundle/release/app-release.aab"
  [[ -f "$local_aab" ]] && log "Release AAB: $local_aab ($(du -h "$local_aab" | cut -f1))"
fi

verify_post_build

log "Android release build complete (v${BUILD_NAME}+${BUILD_NUMBER})"
