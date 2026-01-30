#!/bin/bash
set -e

# Amos Mobile iOS Deployment Script (Fastlane)
# Usage: ./deploy-ios.sh [--testflight] [--production] [--screenshots] [--skip-flutter-build] [--notes "message"]
#
# Prerequisites:
#   - Fastlane installed: gem install fastlane
#   - Bundle installed: gem install bundler && bundle install (in ios/ directory)
#   - App Store Connect API key configured in environment
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
DEPLOY_TARGET="testflight"
SKIP_FLUTTER_BUILD=false
TESTFLIGHT_NOTES=""
CAPTURE_SCREENSHOTS=false
SCREENSHOTS_ONLY=false
SCREENSHOT_DEVICE=""

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --testflight) DEPLOY_TARGET="testflight"; shift ;;
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
        --notes)
            TESTFLIGHT_NOTES="$2"
            shift 2
            ;;
        --notes=*)
            TESTFLIGHT_NOTES="${1#*=}"
            shift
            ;;
        --help)
            echo "Usage: ./deploy-ios.sh [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --testflight           Deploy to TestFlight (default)"
            echo "  --production           Deploy to App Store"
            echo "  --skip-flutter-build   Skip Flutter build (use existing build)"
            echo "  --notes \"message\"      What to Test notes for TestFlight testers"
            echo "  --screenshots          Capture App Store screenshots before deploy"
            echo "  --screenshots-only     Only capture screenshots (no deploy)"
            echo "  --screenshot-device    Capture on specific device (e.g. \"iPhone 16 Pro Max\")"
            echo "  --help                 Show this help message"
            echo ""
            echo "Environment variables:"
            echo "  ASC_KEY_ID             App Store Connect API Key ID"
            echo "  ASC_ISSUER_ID          App Store Connect Issuer ID"
            echo "  ASC_KEY_CONTENT        App Store Connect API Key (base64)"
            echo "  APPLE_APP_ID           Apple App ID (numeric)"
            echo "  API_BASE_URL           Production API URL"
            echo "  TESTFLIGHT_CHANGELOG   What to Test notes (alternative to --notes)"
            echo ""
            echo "Examples:"
            echo "  ./deploy-ios.sh --notes \"Fixed time format, added notification sounds\""
            echo "  ./deploy-ios.sh --testflight --notes \"New feature: voice input\""
            echo "  ./deploy-ios.sh --screenshots-only                    # Just capture screenshots"
            echo "  ./deploy-ios.sh --screenshots --testflight            # Screenshots + deploy"
            echo "  ./deploy-ios.sh --screenshot-device \"iPhone 16 Pro\"   # Single device"
            exit 0
            ;;
        *) shift ;;
    esac
done

print_step "Amos Mobile iOS Deployment"
echo ""
echo "  Target: $([ "$DEPLOY_TARGET" = "testflight" ] && echo 'TestFlight' || echo 'App Store')"

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

# Also load iOS fastlane .env if it exists
if [ -f ios/fastlane/.env ]; then
    set -a
    source ios/fastlane/.env
    set +a
    print_success "Loaded ios/fastlane/.env"
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
echo "  ASC Key ID: ${ASC_KEY_ID:-not set}"

# ============================================
# Step 2: App Store Screenshots (optional)
# ============================================
if [ "$CAPTURE_SCREENSHOTS" = true ]; then
    print_step "Step 2: Capturing App Store Screenshots"

    # Create screenshots directory
    mkdir -p screenshots

    # Build for simulator first
    echo "Building for iOS Simulator..."
    flutter build ios --simulator || {
        print_error "Flutter simulator build failed!"
        exit 1
    }

    # Determine devices
    if [ -n "$SCREENSHOT_DEVICE" ]; then
        DEVICES=("$SCREENSHOT_DEVICE")
    else
        DEVICES=(
            "iPhone 16 Pro Max"
            "iPhone 16 Pro"
            "iPad Pro 13-inch (M4)"
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

        # Find device ID
        DEVICE_ID=$(xcrun simctl list devices available | grep "$device" | head -1 | grep -oE '[A-F0-9-]{36}' || true)

        if [ -z "$DEVICE_ID" ]; then
            print_warning "Device not found: $device (skipping)"
            continue
        fi

        # Boot simulator
        xcrun simctl boot "$DEVICE_ID" 2>/dev/null || true

        # Run screenshot test
        flutter drive \
            --driver=test_driver/integration_test.dart \
            --target=integration_test/screenshot_test.dart \
            -d "$DEVICE_ID" \
            || print_warning "Some screenshots may have failed on $device"

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
        echo "    2. Add frames: cd ios && fastlane frame_app_screenshots"
        echo "    3. Upload: cd ios && fastlane upload_screenshots"
        echo ""
        exit 0
    fi
fi

# ============================================
# Step 3: Flutter build
# ============================================
if [ "$SKIP_FLUTTER_BUILD" = false ]; then
    print_step "Step 3: Building Flutter iOS"

    echo "Cleaning previous build..."
    flutter clean

    echo "Getting dependencies..."
    flutter pub get

    echo "Building iOS release..."
    flutter build ios --release \
        --dart-define=API_BASE_URL="$API_BASE_URL" \
        --dart-define=IS_PRODUCTION=true \
        ${GEMINI_API_KEY:+--dart-define=GEMINI_API_KEY="$GEMINI_API_KEY"} \
        ${SENTRY_DSN:+--dart-define=SENTRY_DSN="$SENTRY_DSN"} \
        || {
            print_error "Flutter build failed!"
            exit 1
        }

    print_success "Flutter iOS build complete"
else
    print_step "Step 3: Skipping Flutter build (--skip-flutter-build)"
fi

# ============================================
# Step 4: TestFlight Notes (if deploying to TestFlight)
# ============================================
if [ "$DEPLOY_TARGET" = "testflight" ]; then
    # Use --notes argument, or TESTFLIGHT_CHANGELOG env var, or prompt
    if [ -n "$TESTFLIGHT_NOTES" ]; then
        export TESTFLIGHT_CHANGELOG="$TESTFLIGHT_NOTES"
        print_success "Using provided notes: $TESTFLIGHT_NOTES"
    elif [ -z "$TESTFLIGHT_CHANGELOG" ]; then
        print_step "What to Test Notes"
        echo "Enter notes for testers (what changed, what to test):"
        echo "(Press Enter for default, or Ctrl+C to cancel)"
        echo ""
        read -p "> " USER_NOTES
        if [ -n "$USER_NOTES" ]; then
            export TESTFLIGHT_CHANGELOG="$USER_NOTES"
        else
            export TESTFLIGHT_CHANGELOG="Bug fixes and improvements"
        fi
        print_success "Notes: $TESTFLIGHT_CHANGELOG"
    fi
fi

# ============================================
# Step 5: Fastlane deployment
# ============================================
print_step "Step 5: Running Fastlane"

# Set locale for fastlane
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

cd ios

# Ensure bundle is installed
if [ ! -f "Gemfile.lock" ] || ! bundle check &> /dev/null; then
    echo "Installing Ruby dependencies..."
    bundle install
fi

# Run the appropriate fastlane lane
if [ "$DEPLOY_TARGET" = "testflight" ]; then
    echo "Deploying to TestFlight via Fastlane..."
    bundle exec fastlane deploy_testflight
else
    echo "Deploying to App Store via Fastlane..."
    bundle exec fastlane deploy_production

    # Auto-upload screenshots if they were captured
    if [ "$CAPTURE_SCREENSHOTS" = true ] && [ -d "../screenshots" ]; then
        echo ""
        echo "Uploading screenshots to App Store Connect..."
        bundle exec fastlane upload_screenshots || print_warning "Screenshot upload failed (continuing...)"
        print_success "Screenshots uploaded"
    fi
fi

cd ..

print_success "Fastlane deployment complete"

# ============================================
# Step 6: Git commit version bump
# ============================================
print_step "Step 6: Committing version bump"

# Get the new version from pubspec
NEW_VERSION=$(grep "^version:" pubspec.yaml | sed 's/version: //')

if git diff --quiet pubspec.yaml ios/Runner.xcodeproj/project.pbxproj 2>/dev/null; then
    print_warning "No changes to commit"
else
    git add pubspec.yaml ios/Runner.xcodeproj/project.pbxproj ios/Runner/Info.plist 2>/dev/null || true
    git commit -m "Bump iOS version to $NEW_VERSION" || print_warning "Git commit skipped"
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
if [ "$DEPLOY_TARGET" = "testflight" ]; then
    echo "  Target:  TestFlight"
    echo ""
    echo "  Next steps:"
    echo "    1. Wait for processing (~10-30 min)"
    echo "    2. Add testers in App Store Connect"
    echo "    3. Testers will receive TestFlight invite"
else
    echo "  Target:  App Store"
    echo ""
    echo "  Next steps:"
    echo "    1. Wait for processing"
    echo "    2. Submit for review in App Store Connect"
fi
echo ""
