#!/bin/bash
set -e

# Checking Deployments - Pre-deployment checklist
# Usage: check-deployment.sh [ENVIRONMENT] [--fix]

ENVIRONMENT="${1:-production}"
FIX=false

shift || true
while [[ $# -gt 0 ]]; do
  case $1 in
    --fix) FIX=true; shift ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

echo "🚀 Pre-Deployment Checklist"
echo ""
echo "Environment: $ENVIRONMENT"
echo "Branch: $(git branch --show-current)"
echo "Commit: $(git log -1 --oneline)"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

ISSUES=0

# 1. Git Status
echo "1️⃣ Checking Git status..."
CURRENT_BRANCH=$(git branch --show-current)

if [ "$CURRENT_BRANCH" != "main" ] && ! echo "$CURRENT_BRANCH" | grep -q "^release/"; then
  echo "  ⚠️  Not on main or release branch: $CURRENT_BRANCH"
  ((ISSUES++))
else
  echo "  ✅ On deployment branch"
fi

if ! git diff --quiet || ! git diff --cached --quiet; then
  echo "  ❌ Uncommitted changes"
  ((ISSUES++))
else
  echo "  ✅ No uncommitted changes"
fi
echo ""

# 2. Migrations
echo "2️⃣ Checking migrations..."
NEW_MIGRATIONS=$(find db/migrate -name "*.rb" -type f | tail -3)
if [ -n "$NEW_MIGRATIONS" ]; then
  echo "  ⚠️  Recent migrations found - remember to run after deploy"
fi

UNSAFE=$(grep -l "change_column\|remove_column\|drop_table" db/migrate/*.rb 2>/dev/null || true)
if [ -n "$UNSAFE" ]; then
  echo "  ⚠️  Unsafe migrations detected - review carefully"
else
  echo "  ✅ No unsafe migrations"
fi
echo ""

# 3. Tests
echo "3️⃣ Running tests..."
if docker-compose run --rm web rails test; then
  echo "  ✅ All tests passing"
else
  echo "  ❌ Test failures"
  ((ISSUES++))
fi
echo ""

# 4. RuboCop
echo "4️⃣ Running RuboCop..."
if docker-compose run --rm web bundle exec rubocop --format simple; then
  echo "  ✅ No RuboCop offenses"
else
  echo "  ⚠️  RuboCop offenses found"
  [ "$FIX" = true ] && docker-compose run --rm web bundle exec rubocop -a
fi
echo ""

# 5. Security
echo "5️⃣ Checking security..."
if docker-compose run --rm web bundle exec bundler-audit check 2>/dev/null; then
  echo "  ✅ No known vulnerabilities"
else
  echo "  ❌ Security vulnerabilities found"
  ((ISSUES++))
fi
echo ""

# Final Report
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📊 Deployment Readiness Report"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

if [ "$ISSUES" = "0" ]; then
  echo "✅ ALL CHECKS PASSED - READY TO DEPLOY"
  echo "Status: 🟢 READY"
  EXIT_CODE=0
elif [ "$ISSUES" -le "2" ]; then
  echo "⚠️  $ISSUES ISSUE(S) FOUND - REVIEW BEFORE DEPLOYING"
  echo "Status: 🟡 CAUTION"
  EXIT_CODE=1
else
  echo "❌ $ISSUES ISSUE(S) FOUND - DO NOT DEPLOY"
  echo "Status: 🔴 NOT READY"
  EXIT_CODE=2
fi

echo ""
echo "Post-Deployment Steps:"
echo "  1. Run migrations: rails db:migrate"
echo "  2. Restart app servers"
echo "  3. Verify health checks"
echo ""

exit $EXIT_CODE
