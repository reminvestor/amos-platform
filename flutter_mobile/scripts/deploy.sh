#!/bin/bash
set -e

# AMOS Mobile Deployment Script
# Single entry point for iOS (TestFlight/App Store) and Android (Play Store) deployments.
# Uses Fastlane for signing, building, and uploading.
#
# Usage: ./scripts/deploy.sh <platform> [options] [--changelog "message"]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_step()    { echo ""; echo -e "${BLUE}=========================================="; echo -e "  $1"; echo -e "==========================================${NC}"; }
print_success() { echo -e "${GREEN}✓ $1${NC}"; }
print_warning() { echo -e "${YELLOW}⚠ $1${NC}"; }
print_error()   { echo -e "${RED}✗ $1${NC}"; }

show_help() {
    cat << 'EOF'
AMOS Mobile Deploy

USAGE
  ./scripts/deploy.sh <platform> [options]

PLATFORMS
  ios             Deploy to TestFlight (default) or App Store
  android         Deploy to Play Store Internal Testing (default)
  all             Deploy to both iOS and Android
  metadata        Upload store metadata only (no binary)

OPTIONS
  --release             Full store release (App Store / Play Store production)
  --beta                Android Beta track
  --submit              Submit for App Store review after upload (iOS only)
  --changelog "text"    Release notes / What to Test notes
  --skip-build          Skip Flutter build (use existing IPA/AAB)
  --skip-tests          Skip running tests before build
  --skip-metadata       Skip metadata upload
  --skip-screenshots    Skip screenshot upload with metadata
  --screenshots         Capture store screenshots before deploy
  --screenshots-only    Only capture screenshots (no deploy)
  --clean               Clean build first (flutter clean)
  --help                Show this help

EXAMPLES
  ./scripts/deploy.sh ios --changelog "Bug fixes"
  ./scripts/deploy.sh ios --release --submit --changelog "v1.1 release"
  ./scripts/deploy.sh android --changelog "New features"
  ./scripts/deploy.sh android --beta --changelog "Beta release"
  ./scripts/deploy.sh all --changelog "Major release"
  ./scripts/deploy.sh metadata --skip-screenshots

ENVIRONMENT
  Copy .env.example to .env.production and fill in your credentials.
  See .env.example for all available variables.
EOF
    exit 0
}

# ============================================
# Parse Arguments
# ============================================
PLATFORM=""
RELEASE=false
BETA=false
CHANGELOG=""
SKIP_BUILD=false
SKIP_TESTS=false
SKIP_METADATA=false
SKIP_SCREENSHOTS=false
SCREENSHOTS=false
SCREENSHOTS_ONLY=false
CLEAN=false
SUBMIT=false

# First arg is platform
if [[ $# -gt 0 ]] && [[ "$1" != --* ]]; then
    PLATFORM="$1"; shift
fi

while [[ $# -gt 0 ]]; do
    case $1 in
        --release)          RELEASE=true; shift ;;
        --beta)             BETA=true; shift ;;
        --changelog)        CHANGELOG="$2"; shift 2 ;;
        --changelog=*)      CHANGELOG="${1#*=}"; shift ;;
        --skip-build)       SKIP_BUILD=true; shift ;;
        --skip-tests)       SKIP_TESTS=true; shift ;;
        --skip-metadata)    SKIP_METADATA=true; shift ;;
        --skip-screenshots) SKIP_SCREENSHOTS=true; shift ;;
        --screenshots)      SCREENSHOTS=true; shift ;;
        --screenshots-only) SCREENSHOTS_ONLY=true; SCREENSHOTS=true; shift ;;
        --clean)            CLEAN=true; shift ;;
        --submit)           SUBMIT=true; shift ;;
        --help|-h)          show_help ;;
        *)
            # Treat bare argument as changelog if not set
            if [[ "$1" != --* ]] && [[ -z "$CHANGELOG" ]]; then
                CHANGELOG="$1"
            fi
            shift ;;
    esac
done

if [ -z "$PLATFORM" ]; then
    print_error "No platform specified!"
    echo "Usage: ./scripts/deploy.sh <ios|android|all|metadata> [options]"
    echo "Run with --help for full usage."
    exit 1
fi

case "$PLATFORM" in
    ios|android|all|metadata) ;;
    *) print_error "Unknown platform: $PLATFORM"; exit 1 ;;
esac

# Determine deploy targets
IOS_TARGET="testflight"
ANDROID_TARGET="internal"
[ "$RELEASE" = true ] && IOS_TARGET="production" && ANDROID_TARGET="production"
[ "$BETA" = true ] && ANDROID_TARGET="beta"

cd "$PROJECT_DIR"

print_step "AMOS Mobile Deployment"
echo ""
echo "  Platform: $PLATFORM"
[[ "$PLATFORM" == "ios" || "$PLATFORM" == "all" ]] && echo "  iOS:      $([ "$IOS_TARGET" = "testflight" ] && echo 'TestFlight' || echo 'App Store')"
[[ "$PLATFORM" == "android" || "$PLATFORM" == "all" ]] && echo "  Android:  $ANDROID_TARGET"
[ -n "$CHANGELOG" ] && echo "  Notes:    $CHANGELOG"
echo ""

# ============================================
# Step 1: Load environment
# ============================================
print_step "Step 1: Loading environment"

if [ -f .env.production ]; then
    set -a; source .env.production; set +a
    print_success "Loaded .env.production"
elif [ -f .env ]; then
    set -a; source .env; set +a
    print_success "Loaded .env"
else
    print_error "No .env.production or .env file found!"
    echo "Copy .env.example to .env.production and fill in your credentials."
    exit 1
fi

# Platform-specific env overrides (if present)
[ -f ios/fastlane/.env ]     && { set -a; source ios/fastlane/.env; set +a; print_success "Loaded ios/fastlane/.env"; }
[ -f android/fastlane/.env ] && { set -a; source android/fastlane/.env; set +a; print_success "Loaded android/fastlane/.env"; }

export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

# Validate
if [ -z "$API_BASE_URL" ] && [ "$PLATFORM" != "metadata" ]; then
    print_error "API_BASE_URL not set in .env.production"
    exit 1
fi

if [[ "$PLATFORM" == "ios" || "$PLATFORM" == "all" ]] && [ "$PLATFORM" != "metadata" ]; then
    if [ -z "$FASTLANE_APPLE_APPLICATION_SPECIFIC_PASSWORD" ] && [ -z "$ASC_KEY_ID" ]; then
        print_error "iOS authentication not configured!"
        echo "Set ASC_KEY_ID/ASC_ISSUER_ID/ASC_KEY_CONTENT or FASTLANE_APPLE_APPLICATION_SPECIFIC_PASSWORD in .env.production"
        exit 1
    fi
fi

if [[ "$PLATFORM" == "android" || "$PLATFORM" == "all" ]] && [ "$PLATFORM" != "metadata" ]; then
    if [ -z "$GOOGLE_PLAY_JSON_KEY_PATH" ]; then
        print_warning "GOOGLE_PLAY_JSON_KEY_PATH not set — Android upload may fail"
    fi
fi

echo ""
echo "  API URL: $API_BASE_URL"
echo "  Ruby:    $(ruby --version 2>/dev/null | head -c 40)"

# ============================================
# Metadata Only (early exit)
# ============================================
if [ "$PLATFORM" = "metadata" ]; then
    print_step "Uploading metadata"

    if [ -d ios/fastlane/metadata ]; then
        echo "Uploading iOS metadata..."
        cd ios
        bundle check &>/dev/null || bundle install
        DELIVER_ARGS="--skip_binary_upload --force"
        [ "$SKIP_SCREENSHOTS" = true ] && DELIVER_ARGS="$DELIVER_ARGS --skip_screenshots"
        bundle exec fastlane deliver $DELIVER_ARGS
        cd ..
        print_success "iOS metadata uploaded"
    fi

    if [ -d android/fastlane/metadata ]; then
        echo "Uploading Android metadata..."
        cd android
        bundle check &>/dev/null || bundle install
        bundle exec fastlane supply --skip_upload_aab --skip_upload_apk
        cd ..
        print_success "Android metadata uploaded"
    fi

    echo ""
    echo -e "${GREEN}Metadata upload complete!${NC}"
    exit 0
fi

# ============================================
# Step 2: Increment build number
# ============================================
print_step "Step 2: Incrementing build number"

CURRENT_VERSION=$(grep "^version:" pubspec.yaml | sed 's/version: //' | tr -d '[:space:]')
VERSION_PART=$(echo "$CURRENT_VERSION" | cut -d'+' -f1)
BUILD_NUM=$(echo "$CURRENT_VERSION" | cut -d'+' -f2)
NEW_BUILD_NUM=$((BUILD_NUM + 1))
NEW_VERSION="${VERSION_PART}+${NEW_BUILD_NUM}"

sed -i '' "s/version: .*/version: ${NEW_VERSION}/" pubspec.yaml

# iOS version is synced automatically via $(FLUTTER_BUILD_NAME) and $(FLUTTER_BUILD_NUMBER)
# variables in Info.plist — no need for agvtool

echo "  $CURRENT_VERSION → $NEW_VERSION"

# ============================================
# Step 3: Screenshots (optional)
# ============================================
if [ "$SCREENSHOTS" = true ]; then
    print_step "Step 3: Capturing store screenshots"

    mkdir -p screenshots

    if [[ "$PLATFORM" == "ios" || "$PLATFORM" == "all" ]]; then
        echo "Building for iOS Simulator..."
        flutter build ios --simulator

        DEVICES=("iPhone 16 Pro Max" "iPhone 16 Pro" "iPad Pro 13-inch (M4)")
        for device in "${DEVICES[@]}"; do
            echo -e "${YELLOW}Capturing: $device${NC}"
            DEVICE_ID=$(xcrun simctl list devices available | grep "$device" | head -1 | grep -oE '[A-F0-9-]{36}' || true)
            if [ -z "$DEVICE_ID" ]; then
                print_warning "Device not found: $device (skipping)"
                continue
            fi
            xcrun simctl boot "$DEVICE_ID" 2>/dev/null || true
            flutter drive \
                --driver=test_driver/integration_test.dart \
                --target=integration_test/screenshot_test.dart \
                -d "$DEVICE_ID" \
                --dart-define=API_BASE_URL="$API_BASE_URL" \
                --dart-define=SCREENSHOT_MODE=true \
                || print_warning "Screenshots may have failed on $device"
            print_success "Completed: $device"
        done
    fi

    if [[ "$PLATFORM" == "android" || "$PLATFORM" == "all" ]]; then
        echo "Capturing Android screenshots via Fastlane..."
        cd android
        bundle check &>/dev/null || bundle install
        bundle exec fastlane screenshots || print_warning "Android screenshots failed"
        cd ..
    fi

    print_success "Screenshots saved to screenshots/"

    if [ "$SCREENSHOTS_ONLY" = true ]; then
        echo ""
        echo -e "${GREEN}Screenshots complete! Check flutter_mobile/screenshots/${NC}"
        exit 0
    fi
fi

# ============================================
# Step 4: Run tests
# ============================================
if [ "$SKIP_TESTS" = false ] && [ "$SKIP_BUILD" = false ]; then
    print_step "Step 4: Running tests"
    flutter test --exclude-tags=integration 2>&1 | tail -20 || {
        print_error "Tests failed! Fix tests before deploying."
        exit 1
    }
    print_success "All tests passed"
else
    print_step "Step 4: Skipping tests"
fi

# ============================================
# Step 5: Build
# ============================================
if [ "$SKIP_BUILD" = false ]; then
    print_step "Step 5: Building Flutter"

    [ "$CLEAN" = true ] && { echo "Cleaning..."; flutter clean; }

    echo "Getting dependencies..."
    flutter pub get

    DART_DEFINES=(
        --dart-define=API_BASE_URL="$API_BASE_URL"
        --dart-define=IS_PRODUCTION=true
    )
    [ -n "$GEMINI_API_KEY" ] && DART_DEFINES+=(--dart-define=GEMINI_API_KEY="$GEMINI_API_KEY")
    [ -n "$SENTRY_DSN" ]     && DART_DEFINES+=(--dart-define=SENTRY_DSN="$SENTRY_DSN")

    # --- iOS ---
    if [[ "$PLATFORM" == "ios" || "$PLATFORM" == "all" ]]; then
        echo ""
        echo "Building iOS IPA (automatic signing, team $TEAM_ID)..."
        flutter build ipa --release \
            --export-options-plist=ios/ExportOptions.plist \
            "${DART_DEFINES[@]}" \
            || { print_error "iOS build failed!"; exit 1; }

        print_success "iOS IPA built"
    fi

    # --- Android ---
    if [[ "$PLATFORM" == "android" || "$PLATFORM" == "all" ]]; then
        echo ""
        echo "Building Android App Bundle..."
        flutter build appbundle --release \
            "${DART_DEFINES[@]}" \
            || { print_error "Android build failed!"; exit 1; }

        print_success "Android AAB built"
    fi
else
    print_step "Step 5: Skipping build (--skip-build)"
fi

# ============================================
# Step 6: Upload iOS
# ============================================
if [[ "$PLATFORM" == "ios" || "$PLATFORM" == "all" ]]; then
    print_step "Step 6: Uploading iOS → $([ "$IOS_TARGET" = "testflight" ] && echo 'TestFlight' || echo 'App Store')"

    IPA_PATH=$(find build/ios/ipa -name "*.ipa" 2>/dev/null | head -1)
    if [ -z "$IPA_PATH" ]; then
        print_error "IPA not found in build/ios/ipa/"
        exit 1
    fi
    echo "  IPA: $IPA_PATH"

    echo "Uploading via xcrun altool (app-specific password)..."
    xcrun altool --upload-app \
        -f "$IPA_PATH" \
        -u "$APPLE_ID" \
        -p "$FASTLANE_APPLE_APPLICATION_SPECIFIC_PASSWORD" \
        --type ios \
        || { print_error "Upload failed!"; exit 1; }

    print_success "iOS deployment complete"
fi

# ============================================
# Step 7: Upload Android
# ============================================
if [[ "$PLATFORM" == "android" || "$PLATFORM" == "all" ]]; then
    print_step "Step 7: Uploading Android → $ANDROID_TARGET"

    AAB_PATH="build/app/outputs/bundle/release/app-release.aab"
    if [ ! -f "$AAB_PATH" ] && [ "$SKIP_BUILD" = false ]; then
        print_error "AAB not found at $AAB_PATH"
        exit 1
    fi

    cd android
    bundle check &>/dev/null || bundle install
    bundle exec fastlane "deploy_${ANDROID_TARGET}"

    if [ "$ANDROID_TARGET" = "production" ] && [ "$SCREENSHOTS" = true ] && [ -d "../screenshots" ]; then
        echo "Uploading screenshots..."
        bundle exec fastlane upload_screenshots || print_warning "Screenshot upload failed"
    fi

    cd ..
    print_success "Android deployment complete"
fi

# ============================================
# Step 8: Git commit version bump
# ============================================
print_step "Step 8: Committing version bump"

if git diff --quiet pubspec.yaml 2>/dev/null; then
    print_warning "No version changes to commit"
else
    FILES_TO_ADD="pubspec.yaml"
    [[ "$PLATFORM" == "android" || "$PLATFORM" == "all" ]] && FILES_TO_ADD="$FILES_TO_ADD android/app/build.gradle.kts"

    git add $FILES_TO_ADD 2>/dev/null || true
    git commit -m "Bump version to $NEW_VERSION [$PLATFORM]" || print_warning "Git commit skipped"
    print_success "Committed version bump → $NEW_VERSION"
fi

# ============================================
# Summary
# ============================================
echo ""
echo -e "${GREEN}=========================================="
echo -e "  Deployment Complete!"
echo -e "==========================================${NC}"
echo ""
echo "  Version: $NEW_VERSION"
[[ "$PLATFORM" == "ios" || "$PLATFORM" == "all" ]]     && echo "  iOS:     $([ "$IOS_TARGET" = "testflight" ] && echo 'TestFlight' || echo 'App Store') ✓"
[[ "$PLATFORM" == "android" || "$PLATFORM" == "all" ]] && echo "  Android: $ANDROID_TARGET ✓"
[ -n "$CHANGELOG" ] && echo "  Notes:   $CHANGELOG"
echo ""
