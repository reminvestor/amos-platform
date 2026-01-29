#!/bin/bash
# App Store Screenshot Generator for AMOS Mobile
# Usage: ./take_screenshots.sh [device]
#
# Examples:
#   ./take_screenshots.sh                      # All required devices
#   ./take_screenshots.sh "iPhone 16 Pro Max"  # Single device
#   ./take_screenshots.sh --quick              # Just iPhone 16 Pro Max (fast)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}AMOS Mobile - App Store Screenshot Generator${NC}"
echo "=============================================="

# Create screenshots directory
mkdir -p screenshots

# Check if Flutter is installed
if ! command -v flutter &> /dev/null; then
    echo -e "${RED}Error: Flutter is not installed or not in PATH${NC}"
    exit 1
fi

# Quick mode - just one device
if [[ "$1" == "--quick" ]]; then
    DEVICES=("iPhone 16 Pro Max")
# Single device specified
elif [[ -n "$1" ]]; then
    DEVICES=("$1")
# All required devices for App Store
else
    DEVICES=(
        "iPhone 16 Pro Max"
        "iPhone 16 Pro"
        "iPad Pro 13-inch (M4)"
    )
fi

echo ""
echo "Devices to capture:"
for device in "${DEVICES[@]}"; do
    echo "  - $device"
done
echo ""

# Run Flutter build first
echo -e "${YELLOW}Building Flutter app...${NC}"
flutter build ios --simulator

# Capture screenshots on each device
for device in "${DEVICES[@]}"; do
    echo ""
    echo -e "${YELLOW}Capturing screenshots on: $device${NC}"
    echo "-----------------------------------------------"

    # Boot simulator if needed
    DEVICE_ID=$(xcrun simctl list devices available | grep "$device" | head -1 | grep -o '\([A-F0-9-]*\)' | tr -d '()')

    if [[ -z "$DEVICE_ID" ]]; then
        echo -e "${RED}Device not found: $device${NC}"
        echo "Available devices:"
        xcrun simctl list devices available | grep -E "(iPhone|iPad)"
        continue
    fi

    echo "Device ID: $DEVICE_ID"
    xcrun simctl boot "$DEVICE_ID" 2>/dev/null || true

    # Run screenshot test
    flutter drive \
        --driver=test_driver/integration_test.dart \
        --target=integration_test/screenshot_test.dart \
        -d "$DEVICE_ID" \
        || echo -e "${YELLOW}Warning: Some screenshots may have failed on $device${NC}"

    echo -e "${GREEN}Completed: $device${NC}"
done

echo ""
echo "=============================================="
echo -e "${GREEN}Screenshots saved to: flutter_mobile/screenshots/${NC}"
echo ""
echo "Next steps:"
echo "  1. Review screenshots in screenshots/ directory"
echo "  2. Add device frames: cd ios && fastlane frame_screenshots"
echo "  3. Upload to App Store: cd ios && fastlane upload_screenshots"
echo ""
