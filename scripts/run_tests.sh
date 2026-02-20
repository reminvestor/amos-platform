#!/bin/bash
# ════════════════════════════════════════════════════════════════════
# Test Runner for AMOS Platform
# ════════════════════════════════════════════════════════════════════
#
# Usage:
#   ./scripts/run_tests.sh              # Run all unit tests
#   ./scripts/run_tests.sh v3           # Run V3 tool/service tests only
#   ./scripts/run_tests.sh bob          # Run BOB benchmark (quick)
#   ./scripts/run_tests.sh bob:full     # Run BOB benchmark (all tasks)
#   ./scripts/run_tests.sh e2e          # Run HTTP E2E integration tests
#   ./scripts/run_tests.sh all          # Run everything
#   ./scripts/run_tests.sh single FILE  # Run a specific test file
#
# All commands run inside containers via podman/docker compose exec web.
# Ensure 'podman compose up' is running first.
# ════════════════════════════════════════════════════════════════════

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../bin/detect-container-engine"

EXEC_CMD="$COMPOSE_CMD exec web"

case "${1:-unit}" in
  unit|tests)
    echo "════════════════════════════════════════════════════════════"
    echo "Running unit tests (excluding .deprecated)"
    echo "════════════════════════════════════════════════════════════"
    $EXEC_CMD bash -c "find test/models test/services test/controllers test/jobs test/mailers test/helpers -name '*_test.rb' -not -path '*/.deprecated/*' | sort | xargs bundle exec rails test"
    ;;

  v3)
    echo "════════════════════════════════════════════════════════════"
    echo "Running V3 tests"
    echo "════════════════════════════════════════════════════════════"
    $EXEC_CMD bundle exec rails test test/services/v3/ -v
    ;;

  bob)
    echo "════════════════════════════════════════════════════════════"
    echo "Running BOB v4 Benchmark (quick - 2 per tier)"
    echo "════════════════════════════════════════════════════════════"
    $EXEC_CMD bundle exec rake benchmark:bob4:quick
    ;;

  bob:full)
    echo "════════════════════════════════════════════════════════════"
    echo "Running BOB v4 Benchmark (full)"
    echo "════════════════════════════════════════════════════════════"
    $EXEC_CMD bundle exec rake benchmark:bob4:full
    ;;

  bob:single)
    echo "════════════════════════════════════════════════════════════"
    echo "Running BOB v4 single task: ${2}"
    echo "════════════════════════════════════════════════════════════"
    $EXEC_CMD bundle exec rake "benchmark:bob4:single[${2}]"
    ;;

  e2e)
    echo "════════════════════════════════════════════════════════════"
    echo "Running HTTP E2E integration tests"
    echo "(Requires Bedrock access for real LLM calls)"
    echo "════════════════════════════════════════════════════════════"
    $EXEC_CMD bundle exec rails test test/integration/scout_e2e_test.rb -v
    ;;

  integration)
    echo "════════════════════════════════════════════════════════════"
    echo "Running all integration tests"
    echo "════════════════════════════════════════════════════════════"
    $EXEC_CMD bundle exec rails test test/integration/ -v
    ;;

  single)
    echo "════════════════════════════════════════════════════════════"
    echo "Running: ${2}"
    echo "════════════════════════════════════════════════════════════"
    $EXEC_CMD bundle exec rails test "${2}" -v
    ;;

  all)
    echo "════════════════════════════════════════════════════════════"
    echo "Running FULL test suite"
    echo "════════════════════════════════════════════════════════════"
    echo ""
    echo "--- Phase 1: Unit Tests ---"
    $EXEC_CMD bash -c "find test/models test/services test/controllers test/jobs test/mailers test/helpers -name '*_test.rb' -not -path '*/.deprecated/*' | sort | xargs bundle exec rails test"
    echo ""
    echo "--- Phase 2: Integration Tests ---"
    $EXEC_CMD bundle exec rails test test/integration/ -v
    echo ""
    echo "--- Phase 3: BOB Benchmark (quick) ---"
    $EXEC_CMD bundle exec rake benchmark:bob4:quick
    echo ""
    echo "════════════════════════════════════════════════════════════"
    echo "ALL TESTS COMPLETE"
    echo "════════════════════════════════════════════════════════════"
    ;;

  list)
    echo "Available test commands:"
    echo "  ./scripts/run_tests.sh              # Unit tests"
    echo "  ./scripts/run_tests.sh v3           # V3 tool/service tests"
    echo "  ./scripts/run_tests.sh bob          # BOB benchmark (quick)"
    echo "  ./scripts/run_tests.sh bob:full     # BOB benchmark (all)"
    echo "  ./scripts/run_tests.sh bob:single ID # Single BOB task"
    echo "  ./scripts/run_tests.sh e2e          # HTTP E2E tests"
    echo "  ./scripts/run_tests.sh integration  # All integration tests"
    echo "  ./scripts/run_tests.sh single FILE  # Specific test file"
    echo "  ./scripts/run_tests.sh all          # Everything"
    echo "  ./scripts/run_tests.sh list         # This help"
    echo ""
    echo "BOB task IDs: b1_data_001, b1_canvas_001, b1_template_001, b1_delete_001,"
    echo "  b2_automation_001, b2_schema_001, b3_welcome_flow_001, etc."
    echo "  Run '$COMPOSE_CMD exec web bundle exec rake benchmark:bob4:list' for full list."
    ;;

  *)
    echo "Unknown command: ${1}"
    echo "Run './scripts/run_tests.sh list' for available commands."
    exit 1
    ;;
esac
