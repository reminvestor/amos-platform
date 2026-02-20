#!/bin/bash

# Start AMOS Web and Mobile - Built Fresh
# Usage: ./start-all.sh [--skip-rebuild] [--web-only] [--mobile-only]

set -e

SKIP_REBUILD=false
WEB_ONLY=false
MOBILE_ONLY=false

# Parse arguments
for arg in "$@"; do
  case $arg in
    --skip-rebuild)
      SKIP_REBUILD=true
      ;;
    --web-only)
      WEB_ONLY=true
      ;;
    --mobile-only)
      MOBILE_ONLY=true
      ;;
  esac
done

echo "Starting AMOS Platform"
echo "========================="

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Detect container engine
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/bin/detect-container-engine"

# Check prerequisites
echo ""
echo "Checking prerequisites..."

echo -e "${GREEN}Container engine: $CONTAINER_CMD${NC}"

if ! command -v flutter >/dev/null 2>&1; then
  echo -e "${RED}Flutter is not installed${NC}"
  exit 1
fi

echo -e "${GREEN}Prerequisites met${NC}"

# Start Web (Containers)
if [ "$MOBILE_ONLY" = false ]; then
  echo ""
  echo "Starting Web Application..."
  echo "------------------------------"

  if [ "$SKIP_REBUILD" = false ]; then
    echo "Cleaning build cache..."
    $CONTAINER_CMD system prune -a -f 2>/dev/null || true

    echo "Rebuilding containers with latest code..."
    $COMPOSE_CMD build web

    echo "Stopping existing containers..."
    $COMPOSE_CMD down
  fi

  echo "Starting services..."
  $COMPOSE_CMD up -d

  echo "Waiting for database to be ready..."
  sleep 5

  echo "Running database migrations..."
  $COMPOSE_CMD exec -T web rails db:migrate || echo "Migrations may have already been applied"

  echo "Waiting for Rails API to be ready..."
  MAX_ATTEMPTS=30
  ATTEMPT=0
  while [ $ATTEMPT -lt $MAX_ATTEMPTS ]; do
    if curl -s http://localhost:3000/health > /dev/null 2>&1 || curl -s http://localhost:3000 > /dev/null 2>&1; then
      echo -e "${GREEN}Rails API is ready${NC}"
      break
    fi
    ATTEMPT=$((ATTEMPT + 1))
    echo "   Attempt $ATTEMPT/$MAX_ATTEMPTS..."
    sleep 2
  done

  if [ $ATTEMPT -eq $MAX_ATTEMPTS ]; then
    echo -e "${YELLOW}Rails API may not be fully ready, continuing anyway...${NC}"
  fi

  echo -e "${GREEN}Web application started at http://localhost:3000${NC}"
fi

# Start Mobile (Flutter)
if [ "$WEB_ONLY" = false ]; then
  echo ""
  echo "Starting Mobile Application..."
  echo "---------------------------------"

  cd flutter_mobile

  if [ "$SKIP_REBUILD" = false ]; then
    echo "Cleaning Flutter build cache..."
    flutter clean
  fi

  echo "Getting Flutter dependencies..."
  flutter pub get

  echo "Opening iOS Simulator..."
  open -a Simulator 2>/dev/null || true

  echo "Waiting for Simulator to boot..."
  sleep 3

  DEVICE_ID=$(xcrun simctl list devices | grep "iPhone 16 Pro" | grep -v "unavailable" | head -1 | grep -oE '[A-F0-9-]{36}')
  if [ -n "$DEVICE_ID" ]; then
    xcrun simctl boot "$DEVICE_ID" 2>/dev/null || true
    sleep 2
  fi

  echo "Launching Flutter app on iOS Simulator..."
  echo ""
  echo -e "${YELLOW}Flutter is starting in the foreground.${NC}"
  echo -e "${YELLOW}   Press 'r' for hot reload, 'R' for hot restart, 'q' to quit${NC}"
  echo ""

  flutter run -d "iPhone 16 Pro" --dart-define=API_BASE_URL=http://localhost:3000
fi

echo ""
echo "========================="
echo -e "${GREEN}AMOS Platform Started!${NC}"
echo ""
echo "Web:    http://localhost:3000"
echo "Mobile: Running on iOS Simulator"
echo ""
