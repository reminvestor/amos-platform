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

# Always open iOS Simulator
echo "📱 Opening iOS Simulator..."
open -a Simulator

# Wait for simulator to boot
echo "⏳ Waiting for Simulator to boot..."
sleep 5

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

# Find the booted simulator ID
SIMULATOR_ID=$(xcrun simctl list devices | grep -i "booted" | sed -n 's/.*(\([A-F0-9-]*\)).*/\1/p' | head -1)

if [ -z "$SIMULATOR_ID" ]; then
    echo "❌ No simulator is booted. Please open Simulator app first."
    exit 1
fi

echo "📱 Launching app on simulator $SIMULATOR_ID..."
flutter run -d "$SIMULATOR_ID" --dart-define=API_BASE_URL="$API_URL"
