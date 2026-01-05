#!/bin/bash
# Run Flutter app on specified device
# Usage: ./flutter-run.sh [device] [--api-url=URL]

set -e

DEVICE="${1:-chrome}"
API_URL=""

# Parse arguments
for arg in "$@"; do
  case $arg in
    --api-url=*)
      API_URL="${arg#*=}"
      shift
      ;;
  esac
done

cd "$(dirname "$0")/../../../flutter_mobile" || {
  echo "Error: flutter_mobile directory not found"
  exit 1
}

echo "🚀 Starting Flutter app on $DEVICE..."

# Build run command
RUN_CMD="flutter run -d $DEVICE"

if [ -n "$API_URL" ]; then
  RUN_CMD="$RUN_CMD --dart-define=API_BASE_URL=$API_URL"
  echo "📡 Using API URL: $API_URL"
fi

# Check if device is available
if ! flutter devices | grep -qi "$DEVICE"; then
  echo "⚠️  Device '$DEVICE' not found. Available devices:"
  flutter devices
  exit 1
fi

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Hot Reload: r | Hot Restart: R | Quit: q"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

$RUN_CMD
