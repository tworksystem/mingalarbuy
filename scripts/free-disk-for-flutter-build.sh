#!/bin/bash
# Free disk space for Flutter/Android builds
# Run when you see "No space left on device" during flutter run/build
# Usage: ./scripts/free-disk-for-flutter-build.sh

set -e

echo "=== Disk space before ==="
df -h / | grep -E '^/|Filesystem'

echo ""
echo "=== Cleaning Flutter project ==="
flutter clean 2>/dev/null || true
rm -rf android/.gradle android/app/build 2>/dev/null || true

echo ""
echo "=== Clearing Gradle build cache (safe to regenerate) ==="
rm -rf ~/.gradle/caches/build-cache-1 2>/dev/null || true
mkdir -p ~/.gradle/caches/build-cache-1 2>/dev/null || true

echo ""
echo "=== Optional: Clear Gradle daemon (releases locks) ==="
cd android 2>/dev/null && ./gradlew --stop 2>/dev/null || true
cd - >/dev/null

echo ""
echo "=== Disk space after ==="
df -h / | grep -E '^/|Filesystem'

echo ""
echo "Done. You need at least 2–3 GB free for Android builds."
echo "Run: flutter pub get && flutter run"
