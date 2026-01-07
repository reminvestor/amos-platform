#!/bin/bash

# Run Flutter app on iOS Simulator
# Usage: ./run_ios.sh [device_name]
# Example: ./run_ios.sh "iPhone 16 Pro"

API_URL="http://localhost:3000"

# Use provided device or auto-detect first available iOS simulator
if [ -n "$1" ]; then
    DEVICE="$1"
else
    # Get first iOS simulator from flutter devices
    DEVICE_LINE=$(flutter devices 2>/dev/null | grep -i "ios.*simulator" | head -1)
    if [ -n "$DEVICE_LINE" ]; then
        # Extract device ID (the UUID between bullets)
        DEVICE=$(echo "$DEVICE_LINE" | sed -n 's/.*• \([A-F0-9-]*\) •.*/\1/p')
    fi
    if [ -z "$DEVICE" ]; then
        DEVICE="iPhone 16 Pro"  # fallback
    fi
fi

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

# Run on iOS Simulator
echo "📱 Launching on $DEVICE..."
flutter run -d "$DEVICE" --dart-define=API_BASE_URL="$API_URL"
