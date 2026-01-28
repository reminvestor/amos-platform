#!/bin/bash

# Start AMOS Web and Mobile - Built Fresh
# Usage: ./bin/start-all [--skip-rebuild] [--web-only] [--mobile-only]

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

echo "🚀 Starting AMOS Platform"
echo "========================="

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to check if command exists
command_exists() {
  command -v "$1" >/dev/null 2>&1
}

# Check prerequisites
echo ""
echo "📋 Checking prerequisites..."

if ! command_exists docker; then
  echo -e "${RED}❌ Docker is not installed${NC}"
  exit 1
fi

if ! command_exists flutter; then
  echo -e "${RED}❌ Flutter is not installed${NC}"
  exit 1
fi

echo -e "${GREEN}✅ Prerequisites met${NC}"

# Start Web (Docker)
if [ "$MOBILE_ONLY" = false ]; then
  echo ""
  echo "🌐 Starting Web Application..."
  echo "------------------------------"

  if [ "$SKIP_REBUILD" = false ]; then
    echo "📦 Rebuilding Docker containers with latest code..."
    docker compose build web

    echo "🛑 Stopping existing containers..."
    docker compose down
  fi

  echo "🔄 Starting Docker services..."
  docker compose up -d

  echo "⏳ Waiting for database to be ready..."
  sleep 5

  echo "🗃️  Running database migrations..."
  docker compose exec -T web rails db:migrate || echo "Migrations may have already been applied"

  echo "⏳ Waiting for Rails API to be ready..."
  MAX_ATTEMPTS=30
  ATTEMPT=0
  while [ $ATTEMPT -lt $MAX_ATTEMPTS ]; do
    if curl -s http://localhost:3000/health > /dev/null 2>&1 || curl -s http://localhost:3000 > /dev/null 2>&1; then
      echo -e "${GREEN}✅ Rails API is ready${NC}"
      break
    fi
    ATTEMPT=$((ATTEMPT + 1))
    echo "   Attempt $ATTEMPT/$MAX_ATTEMPTS..."
    sleep 2
  done

  if [ $ATTEMPT -eq $MAX_ATTEMPTS ]; then
    echo -e "${YELLOW}⚠️  Rails API may not be fully ready, continuing anyway...${NC}"
  fi

  echo -e "${GREEN}✅ Web application started at http://localhost:3000${NC}"
fi

# Start Mobile (Flutter)
if [ "$WEB_ONLY" = false ]; then
  echo ""
  echo "📱 Starting Mobile Application..."
  echo "---------------------------------"

  cd flutter_mobile

  # Clean and get dependencies for fresh build
  if [ "$SKIP_REBUILD" = false ]; then
    echo "🧹 Cleaning Flutter build cache..."
    flutter clean
  fi

  echo "📥 Getting Flutter dependencies..."
  flutter pub get

  # Open iOS Simulator if not running
  echo "📱 Opening iOS Simulator..."
  open -a Simulator 2>/dev/null || true

  # Wait for simulator to boot
  echo "⏳ Waiting for Simulator to boot..."
  sleep 3

  # Boot iPhone 16 Pro if not already booted
  DEVICE_ID=$(xcrun simctl list devices | grep "iPhone 16 Pro" | grep -v "unavailable" | head -1 | grep -oE '[A-F0-9-]{36}')
  if [ -n "$DEVICE_ID" ]; then
    xcrun simctl boot "$DEVICE_ID" 2>/dev/null || true
    sleep 2
  fi

  # Run Flutter app
  echo "🚀 Launching Flutter app on iOS Simulator..."
  echo ""
  echo -e "${YELLOW}📌 Flutter is starting in the foreground.${NC}"
  echo -e "${YELLOW}   Press 'r' for hot reload, 'R' for hot restart, 'q' to quit${NC}"
  echo ""

  flutter run -d "iPhone 16 Pro" --dart-define=API_BASE_URL=http://localhost:3000
fi

echo ""
echo "========================="
echo -e "${GREEN}🎉 AMOS Platform Started!${NC}"
echo ""
echo "Web:    http://localhost:3000"
echo "Mobile: Running on iOS Simulator"
echo ""
