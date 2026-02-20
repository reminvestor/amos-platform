#!/bin/bash

# Run Flutter app on iOS Simulator
# Usage: ./run_ios.sh

API_URL="http://localhost:3000"

# Get the directory where this script lives
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

echo "Starting AMOS Mobile on iOS Simulator..."

# Detect container engine
source "$PROJECT_ROOT/bin/detect-container-engine"

# Check if container engine is running
if ! $CONTAINER_CMD info > /dev/null 2>&1; then
    echo "Container engine ($CONTAINER_CMD) is not running."
    if [ "$CONTAINER_CMD" = "podman" ]; then
        echo "Run: podman machine start"
    else
        echo "Please start Docker Desktop."
    fi
    exit 1
fi

# Start container services if not already running
echo "Ensuring container services are running..."
(cd "$PROJECT_ROOT" && $COMPOSE_CMD up -d)

# Check if a simulator is already booted
SIMULATOR_ID=$(xcrun simctl list devices | grep -i "booted" | sed -n 's/.*(\([A-F0-9-]*\)).*/\1/p' | head -1)

if [ -z "$SIMULATOR_ID" ]; then
    echo "No simulator booted. Starting iPhone 16 Pro..."
    SIMULATOR_ID=$(xcrun simctl list devices | grep "iPhone 16 Pro" | grep -v "Max" | sed -n 's/.*(\([A-F0-9-]*\)).*/\1/p' | head -1)

    if [ -z "$SIMULATOR_ID" ]; then
        SIMULATOR_ID=$(xcrun simctl list devices | grep "iPhone" | grep -v "unavailable" | sed -n 's/.*(\([A-F0-9-]*\)).*/\1/p' | head -1)
    fi

    if [ -z "$SIMULATOR_ID" ]; then
        echo "No iPhone simulator found. Please install one via Xcode."
        exit 1
    fi

    xcrun simctl boot "$SIMULATOR_ID" 2>/dev/null || true
    open -a Simulator

    echo "Waiting for Simulator to boot..."
    for i in {1..30}; do
        BOOT_STATUS=$(xcrun simctl list devices | grep "$SIMULATOR_ID" | grep -i "booted")
        if [ -n "$BOOT_STATUS" ]; then
            echo "Simulator booted"
            break
        fi
        sleep 1
    done
else
    echo "Using already booted simulator..."
    open -a Simulator
fi

# Wait for Rails API to be ready
echo "Waiting for Rails API..."
for i in {1..30}; do
    if curl -s "$API_URL/api/auth/me" > /dev/null 2>&1; then
        echo "Rails API is ready"
        break
    fi
    if [ $i -eq 30 ]; then
        echo "Rails API not responding, continuing anyway..."
    fi
    sleep 1
done

# Navigate to Flutter directory
cd "$SCRIPT_DIR"

echo "Getting Flutter dependencies..."
flutter pub get

# Re-check for booted simulator
SIMULATOR_ID=$(xcrun simctl list devices | grep -i "booted" | sed -n 's/.*(\([A-F0-9-]*\)).*/\1/p' | head -1)

if [ -z "$SIMULATOR_ID" ]; then
    echo "Simulator failed to boot. Try running: xcrun simctl boot 'iPhone 16 Pro'"
    exit 1
fi

echo "Launching app on simulator..."
flutter run -d "$SIMULATOR_ID" --dart-define=API_BASE_URL="$API_URL"
