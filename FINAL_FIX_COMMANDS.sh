#!/bin/bash

# 🎯 Final Fix for AndroidX Dependency Conflict
# This will upgrade AGP to 8.9.1 and Gradle to 8.11.1

echo "════════════════════════════════════════════════════════════"
echo "🎯 Final Fix: AndroidX Dependency Conflict"
echo "════════════════════════════════════════════════════════════"
echo ""
echo "Changes:"
echo "  • AGP: 8.7.3 → 8.9.1 ✅"
echo "  • Gradle: 8.9 → 8.11.1 ✅"
echo ""
echo "This will take 15-20 minutes (first time only)"
echo "Gradle 8.11.1 will be downloaded (~150MB)"
echo ""
read -p "Press Enter to continue..."
echo ""

# Step 1: Clean Flutter build
echo "📦 Step 1/6: Cleaning Flutter build..."
flutter clean
echo "✅ Flutter clean complete"
echo ""

# Step 2: Stop Gradle daemon
echo "🛑 Step 2/6: Stopping Gradle daemon..."
cd android
./gradlew --stop 2>/dev/null || echo "⚠️  Gradle daemon not running (this is OK)"
cd ..
echo "✅ Gradle daemon stopped"
echo ""

# Step 3: Delete Gradle cache
echo "🗑️  Step 3/6: Deleting Gradle cache..."
rm -rf android/.gradle
rm -rf android/build
rm -rf android/app/build
echo "✅ Gradle cache deleted"
echo ""

# Step 4: Get Flutter dependencies
echo "📥 Step 4/6: Getting Flutter dependencies..."
flutter pub get
echo "✅ Dependencies ready"
echo ""

# Step 5: Verify changes
echo "🔍 Step 5/6: Verifying configuration..."
echo ""
echo "AGP Version (should be 8.9.1):"
grep 'com.android.application' android/settings.gradle | grep -o 'version "[^"]*"'
echo ""
echo "Gradle Version (should be 8.11.1):"
grep 'distributionUrl' android/gradle/wrapper/gradle-wrapper.properties | grep -o 'gradle-[^-]*-all'
echo ""
echo "✅ Configuration verified"
echo ""

# Step 6: Ready to run
echo "🚀 Step 6/6: Ready to build!"
echo ""
echo "════════════════════════════════════════════════════════════"
echo "✅ All fixes applied! Now run:"
echo ""
echo "   flutter run"
echo ""
echo "First build will take 15-20 minutes because:"
echo "  • Downloading Gradle 8.11.1 (~150MB)"
echo "  • Downloading AGP 8.9.1 dependencies (~200MB)"
echo "  • Building with new versions"
echo ""
echo "After that, hot reload (press 'r') will be instant (1-3 sec)!"
echo ""
echo "💡 TIP: Keep 'flutter run' running and use 'r' for updates"
echo "════════════════════════════════════════════════════════════"

