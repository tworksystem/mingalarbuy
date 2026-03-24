#!/bin/bash

# 🔧 Quick Fix Script for Gradle Version Error
# Run this script to fix the build error

echo "🔧 Fixing Gradle Version Error..."
echo ""

# Step 1: Clean Flutter build
echo "📦 Step 1/5: Cleaning Flutter build..."
flutter clean
echo "✅ Clean complete"
echo ""

# Step 2: Stop Gradle daemon
echo "🛑 Step 2/5: Stopping Gradle daemon..."
cd android
./gradlew --stop 2>/dev/null || echo "⚠️  Gradle daemon not running (this is OK)"
cd ..
echo "✅ Gradle daemon stopped"
echo ""

# Step 3: Delete build cache
echo "🗑️  Step 3/5: Deleting build cache..."
rm -rf android/.gradle
rm -rf android/build
rm -rf android/app/build
echo "✅ Build cache deleted"
echo ""

# Step 4: Get Flutter dependencies
echo "📥 Step 4/5: Getting Flutter dependencies..."
flutter pub get
echo "✅ Dependencies ready"
echo ""

# Step 5: Ready to run
echo "🚀 Step 5/5: Ready to run!"
echo ""
echo "════════════════════════════════════════════════════════════"
echo "✅ All fixes applied! Now run:"
echo ""
echo "   flutter run"
echo ""
echo "Expected build time: 15-20 minutes (first time only)"
echo "After that, use hot reload (press 'r') for instant updates!"
echo "════════════════════════════════════════════════════════════"

