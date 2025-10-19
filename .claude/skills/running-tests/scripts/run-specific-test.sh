#!/bin/bash
# Run a specific test file

set -e

TEST_PATH="$1"

if [ -z "$TEST_PATH" ]; then
  echo "📁 Available test files:"
  echo ""
  find test -name "*_test.rb" -type f | head -20
  echo ""
  echo "Usage: $0 <test_file_path>"
  exit 1
fi

if [ ! -f "$TEST_PATH" ]; then
  echo "❌ Test file not found: $TEST_PATH"
  exit 1
fi

echo "🧪 Running: $TEST_PATH"
echo ""

docker-compose run --rm web rails test "$TEST_PATH"

echo ""
echo "✅ Test complete!"
