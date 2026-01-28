#!/bin/bash

# Run Flutter app on iOS Simulator
# Usage: ./run_ios.sh

API_URL="http://localhost:3000"

# Get the directory where this script lives
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

echo "🚀 Starting AMOS Mobile on iOS Simulator..."

# Check if Docker is running
if ! docker info > /dev/null 2>&1; then
    echo "❌ Docker is not running. Please start Docker first."
    exit 1
fi

# Start Docker services if not already running
echo "📦 Ensuring Docker services are running..."
(cd "$PROJECT_ROOT" && docker compose up -d)

# Check if a simulator is already booted
SIMULATOR_ID=$(xcrun simctl list devices | grep -i "booted" | sed -n 's/.*(\([A-F0-9-]*\)).*/\1/p' | head -1)

if [ -z "$SIMULATOR_ID" ]; then
    echo "📱 No simulator booted. Starting iPhone 16 Pro..."
    # Find iPhone 16 Pro simulator ID
    SIMULATOR_ID=$(xcrun simctl list devices | grep "iPhone 16 Pro" | grep -v "Max" | sed -n 's/.*(\([A-F0-9-]*\)).*/\1/p' | head -1)

    if [ -z "$SIMULATOR_ID" ]; then
        # Fallback to any available iPhone
        SIMULATOR_ID=$(xcrun simctl list devices | grep "iPhone" | grep -v "unavailable" | sed -n 's/.*(\([A-F0-9-]*\)).*/\1/p' | head -1)
    fi

    if [ -z "$SIMULATOR_ID" ]; then
        echo "❌ No iPhone simulator found. Please install one via Xcode."
        exit 1
    fi

    # Boot the simulator
    xcrun simctl boot "$SIMULATOR_ID" 2>/dev/null || true
    open -a Simulator

    # Wait for simulator to fully boot
    echo "⏳ Waiting for Simulator to boot..."
    for i in {1..30}; do
        BOOT_STATUS=$(xcrun simctl list devices | grep "$SIMULATOR_ID" | grep -i "booted")
        if [ -n "$BOOT_STATUS" ]; then
            echo "✅ Simulator booted"
            break
        fi
        sleep 1
    done
else
    echo "📱 Using already booted simulator..."
    open -a Simulator
fi

# Wait for Rails API to be ready
echo "⏳ Waiting for Rails API..."
for i in {1..30}; do
    if curl -s "$API_URL/api/auth/me" > /dev/null 2>&1; then
        echo "✅ Rails API is ready"
        break
    fi
    if [ $i -eq 30 ]; then
        echo "⚠️  Rails API not responding, continuing anyway..."
    fi
    sleep 1
done

# Navigate to Flutter directory
cd "$SCRIPT_DIR"

# Get dependencies
echo "📥 Getting Flutter dependencies..."
flutter pub get

# Re-check for booted simulator (in case it changed)
SIMULATOR_ID=$(xcrun simctl list devices | grep -i "booted" | sed -n 's/.*(\([A-F0-9-]*\)).*/\1/p' | head -1)

if [ -z "$SIMULATOR_ID" ]; then
    echo "❌ Simulator failed to boot. Try running: xcrun simctl boot 'iPhone 16 Pro'"
    exit 1
fi

echo "📱 Launching app on simulator..."
flutter run -d "$SIMULATOR_ID" --dart-define=API_BASE_URL="$API_URL"
