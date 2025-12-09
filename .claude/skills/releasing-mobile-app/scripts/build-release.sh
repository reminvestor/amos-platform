#!/bin/bash
# Build production releases for iOS and Android
# Usage: ./build-release.sh [android|ios|all]

set -e

PLATFORM="${1:-all}"
FLUTTER_DIR="$(dirname "$0")/../../../flutter_mobile"

cd "$FLUTTER_DIR" || {
  echo "Error: flutter_mobile directory not found"
  exit 1
}

echo "🚀 AMOS Mobile Release Build"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Clean
echo "🧹 Cleaning previous builds..."
flutter clean
flutter pub get

# Analyze
echo "🔍 Running analysis..."
if ! flutter analyze; then
  echo "⚠️  Analysis found issues. Continue anyway? (y/n)"
  read -r response
  if [[ "$response" != "y" ]]; then
    exit 1
  fi
fi

# Tests
echo "🧪 Running tests..."
if ! flutter test; then
  echo "⚠️  Tests failed. Continue anyway? (y/n)"
  read -r response
  if [[ "$response" != "y" ]]; then
    exit 1
  fi
fi

# Build Android
if [[ "$PLATFORM" == "android" || "$PLATFORM" == "all" ]]; then
  echo ""
  echo "🤖 Building Android App Bundle..."
  flutter build appbundle --release \
    --dart-define=ENVIRONMENT=production \
    --dart-define=API_BASE_URL=https://api.amoslabs.com

  echo "✅ Android build complete:"
  echo "   build/app/outputs/bundle/release/app-release.aab"
fi

# Build iOS
if [[ "$PLATFORM" == "ios" || "$PLATFORM" == "all" ]]; then
  echo ""
  echo "🍎 Building iOS..."
  flutter build ipa --release \
    --dart-define=ENVIRONMENT=production \
    --dart-define=API_BASE_URL=https://api.amoslabs.com

  echo "✅ iOS build complete:"
  echo "   build/ios/ipa/*.ipa"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ Release build complete!"
echo ""
echo "Next steps:"
echo "  Android: Upload AAB to Google Play Console"
echo "  iOS: Upload IPA to App Store Connect / TestFlight"
