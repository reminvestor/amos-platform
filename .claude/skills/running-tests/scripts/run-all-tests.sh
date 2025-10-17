#!/bin/bash
# Run all tests in the Rails test suite

set -e

echo "🧪 Running all tests..."
echo ""

# Check if coverage should be enabled
if [ "$COVERAGE" = "true" ]; then
  echo "📊 Coverage enabled"
  COVERAGE=true docker-compose run --rm web rails test
else
  docker-compose run --rm web rails test
fi

echo ""
echo "✅ Test run complete!"
