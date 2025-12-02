#!/bin/bash

# Test Recommendation Script
# Analyzes code and suggests specific tests to add

set -e

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

TARGET_FILE=${1:-}

echo -e "${BLUE}💡 Test Recommendation Engine${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Analyze a model file
analyze_model() {
    local file=$1
    local filename=$(basename "$file" .rb)
    local test_file="test/models/${filename}_test.rb"

    echo -e "${MAGENTA}📝 $file${NC}"
    echo -e "${CYAN}   Test file: $test_file${NC}"
    echo ""
    echo -e "${BLUE}Recommended tests:${NC}"

    # Check for validations
    if grep -q "validates" "$file"; then
        echo -e "  ${GREEN}✓ Validations:${NC}"
        grep "validates" "$file" | sed 's/^/    /'
        echo ""
    fi

    # Check for associations
    if grep -qE "belongs_to|has_many|has_one" "$file"; then
        echo -e "  ${GREEN}✓ Associations:${NC}"
        grep -E "belongs_to|has_many|has_one" "$file" | sed 's/^/    /'
        echo ""
    fi

    # Check for scopes
    if grep -q "scope" "$file"; then
        echo -e "  ${GREEN}✓ Scopes:${NC}"
        grep "scope" "$file" | sed 's/^/    /'
        echo ""
    fi

    # Check for callbacks
    if grep -qE "before_|after_|around_" "$file"; then
        echo -e "  ${GREEN}✓ Callbacks:${NC}"
        grep -E "before_|after_|around_" "$file" | sed 's/^/    /'
        echo ""
    fi

    # Check for custom methods
    local methods=$(grep -E "^\s*def " "$file" | grep -v "def self" | wc -l)
    if [ "$methods" -gt 0 ]; then
        echo -e "  ${GREEN}✓ Instance Methods ($methods found):${NC}"
        grep -E "^\s*def " "$file" | grep -v "def self" | head -5 | sed 's/^/    /'
        echo ""
    fi

    # Check for class methods
    local class_methods=$(grep -E "def self\." "$file" | wc -l)
    if [ "$class_methods" -gt 0 ]; then
        echo -e "  ${GREEN}✓ Class Methods ($class_methods found):${NC}"
        grep -E "def self\." "$file" | head -3 | sed 's/^/    /'
        echo ""
    fi

    echo -e "${YELLOW}Suggested test structure:${NC}"
    cat << EOF
    require "test_helper"

    class ${filename^}Test < ActiveSupport::TestCase
      # Test validations
      test "should validate required fields" do
        # Add assertions for each validation
      end

      # Test associations
      test "should have correct associations" do
        # Verify belongs_to, has_many relationships
      end

      # Test scopes
      test "should filter correctly with scopes" do
        # Test each scope
      end

      # Test instance methods
      # Add test for each public method

      # Test class methods
      # Add test for each class method
    end
EOF
    echo ""
}

# Analyze a controller file
analyze_controller() {
    local file=$1
    local rel_path=${file#app/controllers/}
    local test_file="test/controllers/${rel_path%.rb}_test.rb"

    echo -e "${MAGENTA}📝 $file${NC}"
    echo -e "${CYAN}   Test file: $test_file${NC}"
    echo ""
    echo -e "${BLUE}Recommended tests:${NC}"

    # Check for actions
    local actions=$(grep -E "^\s*def " "$file" | grep -vE "private|protected" | wc -l)
    echo -e "  ${GREEN}✓ Actions found: $actions${NC}"

    # List actions
    if [ "$actions" -gt 0 ]; then
        echo -e "  ${CYAN}Actions to test:${NC}"
        grep -E "^\s*def " "$file" | grep -vE "private|protected" | sed 's/def //' | sed 's/^/    - /'
        echo ""
    fi

    # Check for before_action
    if grep -q "before_action" "$file"; then
        echo -e "  ${GREEN}✓ Before Actions:${NC}"
        grep "before_action" "$file" | sed 's/^/    /'
        echo ""
    fi

    echo -e "${YELLOW}Suggested test structure:${NC}"
    cat << 'EOF'
    require "test_helper"

    class YourControllerTest < ActionDispatch::IntegrationTest
      setup do
        @entity = entities(:one)
        @user = create_valid_user(entity: @entity)
        sign_in @user
      end

      # Test each action
      test "should get index" do
        get your_path
        assert_response :success
      end

      test "should show resource" do
        resource = # create resource
        get your_path(resource)
        assert_response :success
      end

      test "should create resource" do
        assert_difference('Resource.count') do
          post your_path, params: { resource: { /* attributes */ } }
        end
        assert_redirected_to # expected path
      end

      test "should update resource" do
        resource = # create resource
        patch your_path(resource), params: { resource: { /* attributes */ } }
        assert_redirected_to # expected path
      end

      test "should destroy resource" do
        resource = # create resource
        assert_difference('Resource.count', -1) do
          delete your_path(resource)
        end
        assert_redirected_to # expected path
      end

      # Test authorization
      test "should require authentication" do
        sign_out @user
        get your_path
        assert_redirected_to new_user_session_path
      end
    end
EOF
    echo ""
}

# Analyze a service file
analyze_service() {
    local file=$1
    local rel_path=${file#app/services/}
    local test_file="test/services/${rel_path%.rb}_test.rb"

    echo -e "${MAGENTA}📝 $file${NC}"
    echo -e "${CYAN}   Test file: $test_file${NC}"
    echo ""
    echo -e "${BLUE}Recommended tests:${NC}"

    # Check for initialize method
    if grep -q "def initialize" "$file"; then
        echo -e "  ${GREEN}✓ Has initialize method${NC}"
        echo "    Test: initialization with various parameters"
        echo ""
    fi

    # Check for execute/call/perform methods
    if grep -qE "def (execute|call|perform)" "$file"; then
        echo -e "  ${GREEN}✓ Main execution methods:${NC}"
        grep -E "def (execute|call|perform)" "$file" | sed 's/^/    /'
        echo ""
    fi

    # Check for error handling
    if grep -qE "raise|rescue|begin" "$file"; then
        echo -e "  ${GREEN}✓ Error handling found${NC}"
        echo "    Test: error cases and exception handling"
        echo ""
    fi

    # Check for external dependencies
    if grep -qE "HTTP|API|Request|Client" "$file"; then
        echo -e "  ${YELLOW}⚠️  External dependencies detected${NC}"
        echo "    Test: mock external API calls"
        echo ""
    fi

    echo -e "${YELLOW}Suggested test structure:${NC}"
    cat << 'EOF'
    require "test_helper"

    class YourServiceTest < ActiveSupport::TestCase
      setup do
        @entity = entities(:one)
        # Setup test data
      end

      test "executes successfully with valid input" do
        service = YourService.new(/* params */)
        result = service.execute

        assert result.success?
        assert_equal expected_value, result.data
      end

      test "handles errors gracefully" do
        service = YourService.new(/* invalid params */)
        result = service.execute

        assert_not result.success?
        assert_includes result.error_message, "expected error"
      end

      test "handles edge cases" do
        # Test nil values, empty arrays, etc.
      end

      # If service calls external APIs
      test "handles API failures" do
        # Mock API failure
        # Assert service handles it correctly
      end
    end
EOF
    echo ""
}

# Analyze a job file
analyze_job() {
    local file=$1
    local rel_path=${file#app/jobs/}
    local test_file="test/jobs/${rel_path%.rb}_test.rb"

    echo -e "${MAGENTA}📝 $file${NC}"
    echo -e "${CYAN}   Test file: $test_file${NC}"
    echo ""
    echo -e "${BLUE}Recommended tests:${NC}"

    echo -e "  ${GREEN}✓ Test perform method${NC}"
    echo "  ${GREEN}✓ Test idempotency${NC}"
    echo "  ${GREEN}✓ Test error handling and retries${NC}"
    echo ""

    echo -e "${YELLOW}Suggested test structure:${NC}"
    cat << 'EOF'
    require "test_helper"

    class YourJobTest < ActiveJob::TestCase
      test "performs successfully" do
        # Setup
        YourJob.perform_now(/* params */)

        # Assert expected outcome
      end

      test "is idempotent" do
        # Run job twice
        YourJob.perform_now(/* params */)
        YourJob.perform_now(/* params */)

        # Assert no duplicate effects
      end

      test "handles errors and retries" do
        # Mock a failure condition
        assert_raises(StandardError) do
          YourJob.perform_now(/* params */)
        end
      end
    end
EOF
    echo ""
}

# Recommend E2E tests
recommend_e2e_tests() {
    echo -e "${MAGENTA}🔄 E2E/System Test Recommendations${NC}"
    echo ""
    echo -e "${BLUE}Critical User Flows to Test:${NC}"
    echo ""

    cat << 'EOF'
1. Authentication Flow (test/system/user_authentication_test.rb)
   - User registration
   - User login/logout
   - Password reset
   - Session management

2. Core Workflow Execution (test/system/*_workflow_test.rb)
   - Complete workflow from start to finish
   - Multi-step workflows with user interaction
   - Error handling in workflows

3. File Upload and Processing
   - File upload UI
   - Processing completion
   - Error states

4. Integration Flows
   - External API connection setup
   - Operation invocation
   - Response handling

5. Admin Workflows
   - Entity management
   - User administration
   - System configuration

Example E2E Test Structure:
───────────────────────────────────────────────────────
require "application_system_test_case"

class YourWorkflowTest < ApplicationSystemTestCase
  setup do
    @entity = entities(:one)
    @user = create_valid_user(entity: @entity)
    login_as(@user, scope: :user)
  end

  test "complete workflow from start to finish" do
    visit root_path

    # Step 1: Navigate to feature
    click_on "Feature Name"
    assert_selector "h1", text: "Feature Page"

    # Step 2: Fill form and submit
    fill_in "Field Name", with: "Test Value"
    click_on "Submit"

    # Step 3: Verify results
    assert_text "Success Message"
    assert_selector ".result", text: "Expected Result"
  end

  test "handles errors gracefully" do
    visit root_path

    # Trigger error condition
    fill_in "Field Name", with: ""
    click_on "Submit"

    # Verify error handling
    assert_text "Error Message"
    assert_selector ".alert-danger"
  end
end
EOF
    echo ""
}

# Main execution
main() {
    if [ -n "$TARGET_FILE" ]; then
        # Analyze specific file
        if [ ! -f "$TARGET_FILE" ]; then
            echo -e "${RED}✗ File not found: $TARGET_FILE${NC}"
            exit 1
        fi

        case "$TARGET_FILE" in
            */models/*)
                analyze_model "$TARGET_FILE"
                ;;
            */controllers/*)
                analyze_controller "$TARGET_FILE"
                ;;
            */services/*)
                analyze_service "$TARGET_FILE"
                ;;
            */jobs/*)
                analyze_job "$TARGET_FILE"
                ;;
            *)
                echo -e "${YELLOW}⚠️  Unknown file type${NC}"
                echo "Supported: models, controllers, services, jobs"
                ;;
        esac
    else
        # Show general recommendations
        echo -e "${CYAN}No specific file provided. Showing E2E recommendations...${NC}"
        echo ""
        recommend_e2e_tests
    fi

    echo -e "${GREEN}✓ Recommendations complete${NC}"
}

main
