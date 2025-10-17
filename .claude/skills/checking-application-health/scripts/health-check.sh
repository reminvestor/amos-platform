#!/bin/bash
set -e

# Checking Application Health - Comprehensive health check
# Usage: health-check.sh [SCOPE] [--fix]
# Scopes: all, quick, tests, lint, security
# Examples:
#   health-check.sh                    # Interactive mode
#   health-check.sh all                # Full check
#   health-check.sh quick              # Quick check
#   health-check.sh lint --fix         # Lint with auto-fix

SCOPE="${1:-ask}"
FIX=false

# Parse flags
shift || true
while [[ $# -gt 0 ]]; do
  case $1 in
    --fix)
      FIX=true
      shift
      ;;
    *)
      echo "Unknown flag: $1"
      exit 1
      ;;
  esac
done

# Interactive scope selection
if [ "$SCOPE" = "ask" ]; then
  echo "🏥 Health Check"
  echo ""
  echo "Select check scope:"
  echo "  a) Full health check (all checks)"
  echo "  b) Quick check (linting + critical tests)"
  echo "  c) Tests only"
  echo "  d) Linting only"
  echo "  e) Security scan only"
  echo ""
  read -p "Your choice (a/b/c/d/e): " CHOICE

  case "$CHOICE" in
    a) SCOPE="all" ;;
    b) SCOPE="quick" ;;
    c) SCOPE="tests" ;;
    d) SCOPE="lint" ;;
    e) SCOPE="security" ;;
    *) echo "Invalid choice"; exit 1 ;;
  esac
fi

echo "🏥 Starting Health Check..."
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Initialize issue tracking
ISSUES=0

# Database Status (all only)
if [ "$SCOPE" = "all" ]; then
  echo "📊 Checking database status..."
  echo ""

  if docker-compose ps db | grep -q "Up"; then
    echo "  ✅ Database is running"
  else
    echo "  ❌ Database is not running"
    ((ISSUES++))
  fi

  # Check for pending migrations
  PENDING=$(docker-compose run --rm web rails db:migrate:status 2>/dev/null | grep "^\s*down" || true)

  if [ -z "$PENDING" ]; then
    echo "  ✅ No pending migrations"
  else
    echo "  ⚠️  Pending migrations found:"
    echo "$PENDING" | head -3
    ((ISSUES++))
  fi

  echo ""
fi

# Dependency Check (all only)
if [ "$SCOPE" = "all" ]; then
  echo "📦 Checking dependencies..."
  echo ""

  # Check for outdated gems
  OUTDATED=$(docker-compose run --rm web bundle outdated --strict 2>/dev/null | grep -c "newer version" || echo "0")

  if [ "$OUTDATED" = "0" ]; then
    echo "  ✅ All gems up to date"
  else
    echo "  ⚠️  $OUTDATED outdated gems found"
    echo "     Run: docker-compose run --rm web bundle outdated"
  fi

  # Check for security vulnerabilities
  echo ""
  echo "  Checking for vulnerabilities..."
  if docker-compose run --rm web bundle exec bundler-audit check --update 2>/dev/null; then
    echo "  ✅ No known vulnerabilities"
  else
    echo "  ❌ Security vulnerabilities found!"
    ((ISSUES++))
  fi

  echo ""
fi

# RuboCop Check
if [ "$SCOPE" = "all" ] || [ "$SCOPE" = "lint" ] || [ "$SCOPE" = "quick" ]; then
  echo "🔍 Running RuboCop..."
  echo ""

  if docker-compose run --rm web bundle exec rubocop --format simple; then
    echo "  ✅ No RuboCop offenses"
  else
    echo "  ❌ RuboCop offenses found"
    ((ISSUES++))

    if [ "$FIX" = true ]; then
      echo ""
      echo "  🔧 Auto-fixing RuboCop offenses..."
      docker-compose run --rm web bundle exec rubocop -a
    else
      echo "     Run with --fix to auto-correct"
    fi
  fi

  echo ""
fi

# Test Suite
if [ "$SCOPE" = "all" ] || [ "$SCOPE" = "tests" ] || [ "$SCOPE" = "quick" ]; then
  echo "🧪 Running test suite..."
  echo ""

  if [ "$SCOPE" = "quick" ]; then
    # Quick mode - run faster tests only
    echo "  Running quick tests (models + services)..."
    TEST_PATH="test/models test/services"
  else
    # Full test suite
    echo "  Running full test suite..."
    TEST_PATH=""
  fi

  if docker-compose run --rm web rails test $TEST_PATH; then
    echo "  ✅ All tests passing"
  else
    echo "  ❌ Test failures detected"
    ((ISSUES++))
  fi

  echo ""
fi

# Security Scan
if [ "$SCOPE" = "all" ] || [ "$SCOPE" = "security" ]; then
  echo "🔒 Running security scan..."
  echo ""

  # Check for Brakeman (Rails security scanner)
  if docker-compose run --rm web bundle exec brakeman -q 2>/dev/null; then
    echo "  ✅ No security issues found"
  else
    echo "  ⚠️  Potential security issues detected"
    echo "     Review with: docker-compose run --rm web bundle exec brakeman"
    ((ISSUES++))
  fi

  echo ""
fi

# Code Quality Metrics (all only)
if [ "$SCOPE" = "all" ]; then
  echo "📈 Code quality metrics..."
  echo ""

  # Count files
  RUBY_FILES=$(find app -name "*.rb" 2>/dev/null | wc -l | tr -d ' ')
  TEST_FILES=$(find test -name "*_test.rb" 2>/dev/null | wc -l | tr -d ' ')

  echo "  Ruby files: $RUBY_FILES"
  echo "  Test files: $TEST_FILES"

  # Calculate test ratio
  if [ "$RUBY_FILES" -gt 0 ]; then
    RATIO=$(awk "BEGIN {printf \"%.1f\", ($TEST_FILES / $RUBY_FILES) * 100}")
    echo "  Test coverage ratio: $RATIO%"

    # Check if ratio is below 50%
    if [ $(echo "$RATIO < 50" | bc -l 2>/dev/null || echo "0") -eq 1 ]; then
      echo "  ⚠️  Low test coverage"
    else
      echo "  ✅ Good test coverage"
    fi
  fi

  echo ""
fi

# Final Health Report
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📊 Health Check Report"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

EXIT_CODE=0

if [ "$ISSUES" = "0" ]; then
  echo "✅ All checks passed! Your application is healthy."
  echo ""
  echo "Status: 🟢 HEALTHY"
  EXIT_CODE=0
elif [ "$ISSUES" -le "2" ]; then
  echo "⚠️  $ISSUES issue(s) found - Minor issues detected"
  echo ""
  echo "Status: 🟡 NEEDS ATTENTION"
  EXIT_CODE=1
else
  echo "❌ $ISSUES issue(s) found - Critical issues detected"
  echo ""
  echo "Status: 🔴 UNHEALTHY"
  EXIT_CODE=2
fi

echo ""
echo "Recommendations:"

if [ "$ISSUES" -gt "0" ]; then
  echo "  - Review issues above"
  echo "  - Run with --fix to auto-fix where possible"
  echo "  - Use specific skills for detailed fixes:"
  echo "    • fixing-rubocop-offenses - Fix linting issues"
  echo "    • running-tests - Run and debug tests"
  echo "    • managing-docker-development - Database operations"
else
  echo "  - Keep up the good work!"
  echo "  - Run health checks regularly"
  echo "  - Consider adding more tests"
fi

echo ""

exit $EXIT_CODE
