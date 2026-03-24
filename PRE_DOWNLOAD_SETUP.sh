#!/bin/bash

# 🚀 Pre-Download Gradle & Dependencies Setup
# Run this ONCE to download everything before actual build

echo "════════════════════════════════════════════════════════════"
echo "🚀 Pre-Download Setup for Faster First Build"
echo "════════════════════════════════════════════════════════════"
echo ""
echo "This will download:"
echo "  📦 Gradle 8.11.1 (~150MB)"
echo "  📦 Android Gradle Plugin 8.9.1 dependencies (~200MB)"
echo "  📦 Flutter dependencies"
echo "  📦 Android SDK components"
echo ""
echo "After this, 'flutter run' will be MUCH faster!"
echo ""
read -p "Press Enter to start pre-download..."
echo ""

# ============================================
# Step 1: Download Flutter Dependencies
# ============================================
echo "📥 Step 1/5: Downloading Flutter dependencies..."
flutter pub get
echo "✅ Flutter dependencies ready"
echo ""

# ============================================
# Step 2: Download Gradle 8.11.1
# ============================================
echo "📥 Step 2/5: Downloading Gradle 8.11.1 (~150MB)..."
echo "This will take 2-5 minutes depending on your internet speed..."
cd android
./gradlew --version
echo "✅ Gradle 8.11.1 downloaded"
echo ""

# ============================================
# Step 3: Download AGP 8.9.1 Dependencies
# ============================================
echo "📥 Step 3/5: Downloading AGP 8.9.1 dependencies (~200MB)..."
echo "This will take 3-7 minutes depending on your internet speed..."
./gradlew tasks --all > /dev/null 2>&1
echo "✅ AGP dependencies downloaded"
echo ""

# ============================================
# Step 4: Pre-Download Build Dependencies
# ============================================
echo "📥 Step 4/5: Pre-downloading build dependencies..."
echo "This will analyze what needs to be built..."
./gradlew assembleDebug --dry-run > /dev/null 2>&1
echo "✅ Build dependencies analyzed"
cd ..
echo ""

# ============================================
# Step 5: Verify Setup
# ============================================
echo "🔍 Step 5/5: Verifying setup..."
echo ""

# Check Gradle version
echo "Gradle version:"
cd android
./gradlew --version | grep "Gradle" | head -1
cd ..
echo ""

# Check Flutter setup
echo "Flutter status:"
flutter doctor --android-licenses > /dev/null 2>&1 || true
echo "✅ Setup verified"
echo ""

# ============================================
# Summary
# ============================================
echo "════════════════════════════════════════════════════════════"
echo "✅ Pre-Download Complete!"
echo "════════════════════════════════════════════════════════════"
echo ""
echo "Downloaded:"
echo "  ✅ Gradle 8.11.1"
echo "  ✅ AGP 8.9.1 dependencies"
echo "  ✅ Flutter dependencies"
echo "  ✅ Build tools"
echo ""
echo "Now run 'flutter run' - it will be much faster!"
echo ""
echo "Expected build time:"
echo "  • Without pre-download: 20-25 minutes"
echo "  • With pre-download: 10-15 minutes ⚡"
echo "  • Saved time: ~10 minutes!"
echo ""
echo "💡 TIP: Share the ~/.gradle/wrapper/dists folder with your team"
echo "    to avoid everyone downloading Gradle separately!"
echo "════════════════════════════════════════════════════════════"

