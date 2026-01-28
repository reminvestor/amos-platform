#!/bin/bash
set -e

# Amos Mobile Android Deployment Script (Fastlane)
# Usage: ./deploy-android.sh [--internal] [--beta] [--production] [--screenshots] [--skip-flutter-build]
#
# Prerequisites:
#   - Fastlane installed: gem install fastlane
#   - Bundle installed: gem install bundler && bundle install (in android/ directory)
#   - Google Play Console service account JSON key
#   - .env.production file with API_BASE_URL

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_step() {
    echo ""
    echo -e "${BLUE}=========================================="
    echo -e "  $1"
    echo -e "==========================================${NC}"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

# Default options
DEPLOY_TARGET="internal"
SKIP_FLUTTER_BUILD=false
CAPTURE_SCREENSHOTS=false
SCREENSHOTS_ONLY=false
SCREENSHOT_DEVICE=""

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --internal) DEPLOY_TARGET="internal"; shift ;;
        --alpha) DEPLOY_TARGET="alpha"; shift ;;
        --beta) DEPLOY_TARGET="beta"; shift ;;
        --production|--release) DEPLOY_TARGET="production"; shift ;;
        --skip-flutter-build) SKIP_FLUTTER_BUILD=true; shift ;;
        --screenshots) CAPTURE_SCREENSHOTS=true; shift ;;
        --screenshots-only) SCREENSHOTS_ONLY=true; CAPTURE_SCREENSHOTS=true; shift ;;
        --screenshot-device)
            SCREENSHOT_DEVICE="$2"
            CAPTURE_SCREENSHOTS=true
            shift 2
            ;;
        --screenshot-device=*)
            SCREENSHOT_DEVICE="${1#*=}"
            CAPTURE_SCREENSHOTS=true
            shift
            ;;
        --help)
            echo "Usage: ./deploy-android.sh [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --internal             Deploy to Internal Testing (default)"
            echo "  --alpha                Deploy to Alpha track"
            echo "  --beta                 Deploy to Beta track"
            echo "  --production           Deploy to Production"
            echo "  --skip-flutter-build   Skip Flutter build (use existing build)"
            echo "  --screenshots          Capture Play Store screenshots before deploy"
            echo "  --screenshots-only     Only capture screenshots (no deploy)"
            echo "  --screenshot-device    Capture on specific device (e.g. \"Pixel 8 Pro\")"
            echo "  --help                 Show this help message"
            echo ""
            echo "Environment variables:"
            echo "  GOOGLE_PLAY_JSON_KEY_PATH  Path to service account JSON key"
            echo "  API_BASE_URL               Production API URL"
            echo ""
            echo "Examples:"
            echo "  ./deploy-android.sh                                # Internal testing"
            echo "  ./deploy-android.sh --beta                         # Beta track"
            echo "  ./deploy-android.sh --screenshots-only             # Just capture screenshots"
            echo "  ./deploy-android.sh --screenshots --internal       # Screenshots + deploy"
            echo "  ./deploy-android.sh --screenshot-device \"Pixel 8\" # Single device"
            exit 0
            ;;
        *) shift ;;
    esac
done

print_step "Amos Mobile Android Deployment"
echo ""
echo "  Target: $DEPLOY_TARGET"

# ============================================
# Step 1: Load environment variables
# ============================================
print_step "Step 1: Loading environment"

# Load from .env files
if [ -f .env.production ]; then
    set -a
    source .env.production
    set +a
    print_success "Loaded .env.production"
elif [ -f .env ]; then
    set -a
    source .env
    set +a
    print_success "Loaded .env"
fi

# Also load Android fastlane .env if it exists
if [ -f android/fastlane/.env ]; then
    set -a
    source android/fastlane/.env
    set +a
    print_success "Loaded android/fastlane/.env"
fi

# Check required vars
if [ -z "$API_BASE_URL" ]; then
    print_error "API_BASE_URL not set!"
    echo "Create .env.production with: API_BASE_URL=https://your-api.com"
    exit 1
fi

echo ""
echo "Configuration:"
echo "  API URL: $API_BASE_URL"
echo "  Play JSON Key: ${GOOGLE_PLAY_JSON_KEY_PATH:-not set}"

# ============================================
# Step 2: Play Store Screenshots (optional)
# ============================================
if [ "$CAPTURE_SCREENSHOTS" = true ]; then
    print_step "Step 2: Capturing Play Store Screenshots"

    # Create screenshots directory
    mkdir -p screenshots

    # Build for debug (needed for integration tests)
    echo "Building debug APK for screenshots..."
    flutter build apk --debug || {
        print_error "Flutter debug build failed!"
        exit 1
    }

    # Determine devices
    if [ -n "$SCREENSHOT_DEVICE" ]; then
        DEVICES=("$SCREENSHOT_DEVICE")
    else
        # List available emulators
        echo "Available emulators:"
        emulator -list-avds 2>/dev/null || print_warning "Could not list emulators"

        DEVICES=(
            "Pixel_8_Pro"
            "Pixel_Tablet"
        )
    fi

    echo ""
    echo "Capturing on devices:"
    for device in "${DEVICES[@]}"; do
        echo "  - $device"
    done
    echo ""

    for device in "${DEVICES[@]}"; do
        echo ""
        echo -e "${YELLOW}Capturing: $device${NC}"

        # Check if emulator is available
        if ! emulator -list-avds 2>/dev/null | grep -q "$device"; then
            print_warning "Emulator not found: $device (skipping)"
            echo "Create it with: avdmanager create avd -n $device -k 'system-images;android-34;google_apis;x86_64'"
            continue
        fi

        # Start emulator in background
        emulator -avd "$device" -no-audio -no-window &
        EMULATOR_PID=$!

        # Wait for emulator to boot
        echo "Waiting for emulator to boot..."
        adb wait-for-device
        sleep 10

        # Run screenshot test
        flutter drive \
            --driver=test_driver/integration_test.dart \
            --target=integration_test/screenshot_test.dart \
            || print_warning "Some screenshots may have failed on $device"

        # Kill emulator
        kill $EMULATOR_PID 2>/dev/null || true

        print_success "Completed: $device"
    done

    print_success "Screenshots saved to flutter_mobile/screenshots/"

    # If screenshots-only, exit here
    if [ "$SCREENSHOTS_ONLY" = true ]; then
        echo ""
        echo -e "${GREEN}=========================================="
        echo -e "  Screenshots Complete!"
        echo -e "==========================================${NC}"
        echo ""
        echo "  Screenshots: flutter_mobile/screenshots/"
        echo ""
        echo "  Next steps:"
        echo "    1. Review screenshots"
        echo "    2. Upload: cd android && fastlane upload_screenshots"
        echo ""
        exit 0
    fi
fi

# ============================================
# Step 3: Flutter build
# ============================================
if [ "$SKIP_FLUTTER_BUILD" = false ]; then
    print_step "Step 3: Building Flutter Android"

    echo "Cleaning previous build..."
    flutter clean

    echo "Getting dependencies..."
    flutter pub get

    echo "Building Android App Bundle..."
    flutter build appbundle --release \
        --dart-define=API_BASE_URL="$API_BASE_URL" \
        --dart-define=IS_PRODUCTION=true \
        ${GEMINI_API_KEY:+--dart-define=GEMINI_API_KEY="$GEMINI_API_KEY"} \
        ${SENTRY_DSN:+--dart-define=SENTRY_DSN="$SENTRY_DSN"} \
        || {
            print_error "Flutter build failed!"
            exit 1
        }

    print_success "Flutter Android build complete"
else
    print_step "Step 3: Skipping Flutter build (--skip-flutter-build)"
fi

# ============================================
# Step 4: Fastlane deployment
# ============================================
print_step "Step 4: Running Fastlane"

# Set locale for fastlane
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

cd android

# Ensure bundle is installed
if [ ! -f "Gemfile.lock" ] || ! bundle check &> /dev/null; then
    echo "Installing Ruby dependencies..."
    bundle install
fi

# Run the appropriate fastlane lane
case $DEPLOY_TARGET in
    internal)
        echo "Deploying to Internal Testing via Fastlane..."
        bundle exec fastlane deploy_internal
        ;;
    alpha)
        echo "Deploying to Alpha via Fastlane..."
        bundle exec fastlane deploy_alpha
        ;;
    beta)
        echo "Deploying to Beta via Fastlane..."
        bundle exec fastlane deploy_beta
        ;;
    production)
        echo "Deploying to Production via Fastlane..."
        bundle exec fastlane deploy_production

        # Auto-upload screenshots if they were captured
        if [ "$CAPTURE_SCREENSHOTS" = true ] && [ -d "../screenshots" ]; then
            echo ""
            echo "Uploading screenshots to Play Store..."
            bundle exec fastlane upload_screenshots || print_warning "Screenshot upload failed (continuing...)"
            print_success "Screenshots uploaded"
        fi
        ;;
esac

cd ..

print_success "Fastlane deployment complete"

# ============================================
# Step 5: Git commit version bump
# ============================================
print_step "Step 5: Committing version bump"

# Get the new version from pubspec
NEW_VERSION=$(grep "^version:" pubspec.yaml | sed 's/version: //')

if git diff --quiet pubspec.yaml android/app/build.gradle 2>/dev/null; then
    print_warning "No changes to commit"
else
    git add pubspec.yaml android/app/build.gradle 2>/dev/null || true
    git commit -m "Bump Android version to $NEW_VERSION" || print_warning "Git commit skipped"
    print_success "Committed version bump to $NEW_VERSION"
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
echo "  Target:  $DEPLOY_TARGET"
echo ""
echo "  Next steps:"
case $DEPLOY_TARGET in
    internal)
        echo "    1. Wait for processing (~10-30 min)"
        echo "    2. Add testers in Play Console"
        echo "    3. Testers will receive invite email"
        ;;
    alpha|beta)
        echo "    1. Wait for processing"
        echo "    2. Promote to next track when ready"
        ;;
    production)
        echo "    1. Wait for processing"
        echo "    2. Monitor rollout in Play Console"
        ;;
esac
echo ""
