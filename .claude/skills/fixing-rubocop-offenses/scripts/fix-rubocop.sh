#!/bin/bash
# Fix RuboCop offenses with auto-correct

set -e

TARGET="${1:-.}"
UNSAFE="${2:-false}"
COMMIT="${3:-true}"

echo "🔍 Checking RuboCop offenses..."
echo ""

# Run check to see current state
if docker-compose run --rm web bundle exec rubocop "$TARGET"; then
  echo "✅ No RuboCop offenses found!"
  exit 0
else
  echo ""
  echo "Found offenses. Proceeding with auto-correct..."
fi

# Apply auto-correct
if [ "$UNSAFE" = "true" ]; then
  echo "⚠️  Running UNSAFE auto-correct..."
  echo "This may change code behavior!"
  echo ""
  docker-compose run --rm web bundle exec rubocop -A "$TARGET"
else
  echo "🔧 Running safe auto-correct..."
  echo ""
  docker-compose run --rm web bundle exec rubocop -a "$TARGET"
fi

# Final check
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Final RuboCop check..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

if docker-compose run --rm web bundle exec rubocop "$TARGET"; then
  echo "✅ All auto-correctable offenses fixed!"
  RESULT="success"
else
  echo "⚠️  Some offenses require manual fixing"
  RESULT="partial"
fi

# Show changes
echo ""
echo "📝 Changes made:"
echo ""

if git diff --quiet; then
  echo "No changes made (already compliant)"
  exit 0
fi

git diff --stat
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Commit if requested
if [ "$COMMIT" = "true" ]; then
  if ! git diff --quiet; then
    echo "📝 Committing RuboCop fixes..."
    echo ""

    git add .
    git commit -m "Fix RuboCop offenses

Auto-corrected linting issues

🤖 Generated with Claude Code"

    echo "✅ Changes committed!"
    echo ""
    git log -1 --oneline
    echo ""
    echo "Push changes with: git push"
  fi
fi

# Summary
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📊 RuboCop Fix Summary"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

if [ "$RESULT" = "success" ]; then
  echo "✅ Status: All offenses fixed!"
  echo ""
  echo "Your code is now RuboCop compliant."
else
  echo "⚠️  Status: Partially fixed"
  echo ""
  echo "Some offenses require manual attention:"
  echo ""
  docker-compose run --rm web bundle exec rubocop --format simple "$TARGET"
  echo ""
  echo "Common manual fixes:"
  echo "  - Complex code style issues"
  echo "  - Metrics violations (method/class length)"
  echo "  - Security concerns"
  echo "  - Disabled cops in specific files"
fi
