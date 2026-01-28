#!/bin/bash
set -e

# Amos Mobile iOS Deployment Script (Fastlane)
# Usage: ./deploy-ios.sh [--testflight] [--production] [--skip-flutter-build]
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

# Parse arguments
for arg in "$@"; do
    case $arg in
        --testflight) DEPLOY_TARGET="testflight" ;;
        --production|--release) DEPLOY_TARGET="production" ;;
        --skip-flutter-build) SKIP_FLUTTER_BUILD=true ;;
        --help)
            echo "Usage: ./deploy-ios.sh [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --testflight         Deploy to TestFlight (default)"
            echo "  --production         Deploy to App Store"
            echo "  --skip-flutter-build Skip Flutter build (use existing build)"
            echo "  --help               Show this help message"
            echo ""
            echo "Environment variables:"
            echo "  ASC_KEY_ID           App Store Connect API Key ID"
            echo "  ASC_ISSUER_ID        App Store Connect Issuer ID"
            echo "  ASC_KEY_CONTENT      App Store Connect API Key (base64)"
            echo "  APPLE_APP_ID         Apple App ID (numeric)"
            echo "  API_BASE_URL         Production API URL"
            exit 0
            ;;
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
# Step 2: Flutter build
# ============================================
if [ "$SKIP_FLUTTER_BUILD" = false ]; then
    print_step "Step 2: Building Flutter iOS"

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
    print_step "Step 2: Skipping Flutter build (--skip-flutter-build)"
fi

# ============================================
# Step 3: Fastlane deployment
# ============================================
print_step "Step 3: Running Fastlane"

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
fi

cd ..

print_success "Fastlane deployment complete"

# ============================================
# Step 4: Git commit version bump
# ============================================
print_step "Step 4: Committing version bump"

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
