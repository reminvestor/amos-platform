#!/bin/bash

# Fix Broken Tests Script
# Detects and attempts to fix common test failures

set -e

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration
TEST_OUTPUT_FILE="/tmp/test_failures.log"
FIXES_APPLIED=0
TESTS_FIXED=0

echo -e "${BLUE}🔧 Test Fixer${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Run tests and capture failures
run_tests() {
    echo -e "${CYAN}Running tests to detect failures...${NC}"
    echo ""

    # Run tests and capture output
    if docker-compose run --rm web rails test 2>&1 | tee "$TEST_OUTPUT_FILE"; then
        echo -e "${GREEN}✓ All tests passing!${NC}"
        exit 0
    else
        echo -e "${YELLOW}⚠️  Found test failures${NC}"
        return 1
    fi
}

# Parse test failures
parse_failures() {
    echo ""
    echo -e "${BLUE}📋 Analyzing Failures${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    # Extract failure count
    local failures=$(grep -E "^\d+ runs, \d+ assertions, (\d+) failures" "$TEST_OUTPUT_FILE" | grep -oE '\d+ failures' || echo "0 failures")
    local errors=$(grep -E "^\d+ runs, \d+ assertions, \d+ failures, (\d+) errors" "$TEST_OUTPUT_FILE" | grep -oE '\d+ errors' || echo "0 errors")

    echo -e "Failures: ${RED}$failures${NC}"
    echo -e "Errors: ${RED}$errors${NC}"
    echo ""
}

# Fix missing fixtures
fix_missing_fixtures() {
    echo -e "${CYAN}Checking for missing fixtures...${NC}"

    if grep -q "No fixture named" "$TEST_OUTPUT_FILE"; then
        echo -e "${YELLOW}Found missing fixture errors${NC}"

        # Extract fixture names
        grep "No fixture named" "$TEST_OUTPUT_FILE" | while read -r line; do
            fixture=$(echo "$line" | grep -oE "No fixture named '[^']+'" | cut -d"'" -f2)
            echo -e "  Missing fixture: ${RED}$fixture${NC}"

            # TODO: Auto-generate basic fixture
            echo -e "  ${BLUE}→ Add fixture to test/fixtures/${fixture}s.yml${NC}"
        done

        ((FIXES_APPLIED++))
        echo ""
    fi
}

# Fix nil reference errors
fix_nil_references() {
    echo -e "${CYAN}Checking for nil reference errors...${NC}"

    if grep -qE "undefined method.*for nil|NoMethodError.*nil:NilClass" "$TEST_OUTPUT_FILE"; then
        echo -e "${YELLOW}Found nil reference errors${NC}"

        # Show affected tests
        grep -B2 "undefined method.*for nil\|NoMethodError.*nil:NilClass" "$TEST_OUTPUT_FILE" | \
            grep "test_" | head -5 | while read -r line; do
            echo -e "  ${RED}$line${NC}"
        done

        echo ""
        echo -e "  ${BLUE}Recommendations:${NC}"
        echo "  - Add proper setup/initialization in test setup"
        echo "  - Check fixture data is being loaded"
        echo "  - Add nil checks before accessing methods"
        echo ""

        ((FIXES_APPLIED++))
    fi
}

# Fix route errors
fix_route_errors() {
    echo -e "${CYAN}Checking for route errors...${NC}"

    if grep -qE "No route matches|ActionController::UrlGenerationError" "$TEST_OUTPUT_FILE"; then
        echo -e "${YELLOW}Found route errors${NC}"

        # Extract route names
        grep -E "No route matches|undefined method.*_path" "$TEST_OUTPUT_FILE" | head -5 | while read -r line; do
            echo -e "  ${RED}$line${NC}"
        done

        echo ""
        echo -e "  ${BLUE}Recommendations:${NC}"
        echo "  - Run: rails routes | grep <controller_name>"
        echo "  - Verify route names in config/routes.rb"
        echo "  - Update test to use correct path helpers"
        echo ""

        ((FIXES_APPLIED++))
    fi
}

# Fix authentication issues
fix_authentication_issues() {
    echo -e "${CYAN}Checking for authentication errors...${NC}"

    if grep -qE "401 Unauthorized|redirect.*sign_in|authenticate_user" "$TEST_OUTPUT_FILE"; then
        echo -e "${YELLOW}Found authentication issues${NC}"

        echo ""
        echo -e "  ${BLUE}Common fixes:${NC}"
        echo "  - Add sign_in @user in test setup"
        echo "  - Include Devise::Test::IntegrationHelpers"
        echo "  - Create and authenticate test user before action"
        echo ""

        # Example fix
        cat << 'EOF'
  Example setup:
  ───────────────────────────────────────
  setup do
    @entity = entities(:one)
    @user = create_valid_user(entity: @entity)
    sign_in @user
  end
EOF
        echo ""

        ((FIXES_APPLIED++))
    fi
}

# Fix deprecation warnings
fix_deprecations() {
    echo -e "${CYAN}Checking for deprecation warnings...${NC}"

    if grep -q "DEPRECATION WARNING" "$TEST_OUTPUT_FILE"; then
        local count=$(grep -c "DEPRECATION WARNING" "$TEST_OUTPUT_FILE")
        echo -e "${YELLOW}Found $count deprecation warnings${NC}"

        # Show unique deprecations
        grep "DEPRECATION WARNING" "$TEST_OUTPUT_FILE" | sort -u | head -3 | while read -r line; do
            echo -e "  ${YELLOW}$line${NC}"
        done

        echo ""
        echo -e "  ${BLUE}Action needed:${NC}"
        echo "  - Update deprecated syntax to new methods"
        echo "  - See full list in test output"
        echo ""

        ((FIXES_APPLIED++))
    fi
}

# Fix assertion failures
fix_assertion_failures() {
    echo -e "${CYAN}Checking for assertion failures...${NC}"

    if grep -qE "Expected.*to be|Assertion.*failed" "$TEST_OUTPUT_FILE"; then
        echo -e "${YELLOW}Found assertion failures${NC}"

        # Count assertion failures
        local count=$(grep -cE "Expected.*to be|Assertion.*failed" "$TEST_OUTPUT_FILE" || echo 0)
        echo -e "  Assertion failures: ${RED}$count${NC}"

        echo ""
        echo -e "  ${BLUE}Recommendations:${NC}"
        echo "  - Review expected vs actual values"
        echo "  - Update assertions to match current behavior"
        echo "  - Verify test data setup is correct"
        echo ""
    fi
}

# Fix database state issues
fix_database_issues() {
    echo -e "${CYAN}Checking for database state issues...${NC}"

    if grep -qE "PG::|ActiveRecord::RecordInvalid|duplicate key" "$TEST_OUTPUT_FILE"; then
        echo -e "${YELLOW}Found database issues${NC}"

        echo ""
        echo -e "  ${BLUE}Common fixes:${NC}"
        echo "  - Add proper transaction rollback in teardown"
        echo "  - Use unique values for each test (SecureRandom)"
        echo "  - Check fixtures for duplicate data"
        echo ""

        cat << 'EOF'
  Example fix:
  ───────────────────────────────────────
  # Use unique emails
  @user = create_valid_user(
    email: "test#{SecureRandom.hex(4)}@example.com"
  )
EOF
        echo ""

        ((FIXES_APPLIED++))
    fi
}

# Generate fix report
generate_fix_report() {
    echo ""
    echo -e "${BLUE}📊 Fix Summary${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    if [ $FIXES_APPLIED -eq 0 ]; then
        echo -e "${YELLOW}No automatic fixes available${NC}"
        echo "Manual review required for test failures"
    else
        echo -e "${GREEN}Detected $FIXES_APPLIED issue categories${NC}"
        echo "Review recommendations above"
    fi

    echo ""
    echo -e "${CYAN}Next steps:${NC}"
    echo "1. Apply recommended fixes"
    echo "2. Run tests again: rails test"
    echo "3. Review remaining failures manually"
    echo ""
}

# Attempt automatic fixes for common patterns
apply_automatic_fixes() {
    echo -e "${BLUE}🤖 Attempting Automatic Fixes${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    # Fix 1: Add missing test helper includes
    echo -e "${CYAN}Checking for missing test helper includes...${NC}"

    find test/controllers -name "*_test.rb" | while read -r test_file; do
        if ! grep -q "include Devise::Test::IntegrationHelpers" "$test_file"; then
            # Check if it uses sign_in
            if grep -q "sign_in" "$test_file"; then
                echo -e "  ${YELLOW}Adding Devise test helpers to $test_file${NC}"

                # Add include after class definition
                sed -i '/class.*< ActionDispatch::IntegrationTest/a \  include Devise::Test::IntegrationHelpers' "$test_file"
                ((TESTS_FIXED++))
            fi
        fi
    done

    if [ $TESTS_FIXED -gt 0 ]; then
        echo -e "${GREEN}✓ Applied $TESTS_FIXED automatic fixes${NC}"
    else
        echo -e "${CYAN}No automatic fixes needed${NC}"
    fi

    echo ""
}

# Re-run tests after fixes
rerun_tests() {
    if [ $TESTS_FIXED -gt 0 ]; then
        echo -e "${BLUE}Re-running tests after fixes...${NC}"
        echo ""

        if docker-compose run --rm web rails test 2>&1 | tee "$TEST_OUTPUT_FILE.after"; then
            echo ""
            echo -e "${GREEN}✓ All tests now passing!${NC}"
            return 0
        else
            echo ""
            echo -e "${YELLOW}Some tests still failing${NC}"
            echo "Manual intervention required"
            return 1
        fi
    fi
}

# Main execution
main() {
    # Run tests to detect failures
    run_tests || true

    # Parse and categorize failures
    parse_failures

    # Analyze and suggest fixes
    fix_missing_fixtures
    fix_nil_references
    fix_route_errors
    fix_authentication_issues
    fix_deprecations
    fix_assertion_failures
    fix_database_issues

    # Attempt automatic fixes
    apply_automatic_fixes

    # Generate summary
    generate_fix_report

    # Re-run tests if fixes were applied
    rerun_tests || true

    echo -e "${GREEN}✓ Test fix analysis complete${NC}"
    echo ""
    echo -e "Full test output saved to: ${CYAN}$TEST_OUTPUT_FILE${NC}"
}

main
