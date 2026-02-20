#!/bin/bash

# Email Campaign V2 Workflow Test Runner
# This script runs comprehensive tests for the three-phase email campaign workflow

set -e

# Detect container engine
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
source "$PROJECT_ROOT/bin/detect-container-engine"

echo "=================================================="
echo "Email Campaign V2 Workflow Test Suite"
echo "=================================================="
echo ""

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test database setup
echo -e "${YELLOW}Setting up test database...${NC}"
$COMPOSE_CMD exec web bash -c "RAILS_ENV=test bin/rails db:migrate"

echo ""
echo -e "${YELLOW}Running comprehensive workflow tests...${NC}"
echo ""

# Run the comprehensive test suite
$COMPOSE_CMD exec web bash -c "RAILS_ENV=test bin/rails test test/services/email_campaign_workflow_comprehensive_test.rb"

TEST_EXIT_CODE=$?

echo ""
echo "=================================================="

if [ $TEST_EXIT_CODE -eq 0 ]; then
  echo -e "${GREEN}✅ All tests passed!${NC}"
  echo ""
  echo "Test Coverage:"
  echo "  ✓ Single message campaign creation"
  echo "  ✓ Multi-turn conversational workflow"
  echo "  ✓ Context persistence across turns"
  echo "  ✓ Phase 2 execution and data mapping"
  echo "  ✓ Phase 3 validation"
  echo "  ✓ Workflow isolation"
  echo "  ✓ Post-workflow conversation mode"
  echo "  ✓ Error handling"
  echo "  ✓ Template keyword matching"
else
  echo -e "${RED}❌ Some tests failed${NC}"
  echo ""
  echo "Check the output above for details"
fi

echo "=================================================="

exit $TEST_EXIT_CODE
