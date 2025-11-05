#!/bin/bash

# Test Coverage Analysis Script
# Runs tests with coverage and generates detailed reports

set -e

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
COVERAGE_THRESHOLD=${COVERAGE_THRESHOLD:-80}
TEST_CATEGORY=${TEST_CATEGORY:-"all"}
OUTPUT_FORMAT=${OUTPUT_FORMAT:-"terminal"}

echo -e "${BLUE}📊 Test Coverage Analysis${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Check if SimpleCov is available
check_simplecov() {
    if ! grep -q "gem ['\"]simplecov['\"]" Gemfile; then
        echo -e "${YELLOW}⚠️  SimpleCov not found in Gemfile${NC}"
        echo -e "${BLUE}Adding SimpleCov to Gemfile...${NC}"

        # Add SimpleCov to Gemfile in development/test group
        if grep -q "group :development, :test do" Gemfile; then
            sed -i '/group :development, :test do/a \  gem "simplecov", require: false' Gemfile
        else
            echo "" >> Gemfile
            echo "group :development, :test do" >> Gemfile
            echo '  gem "simplecov", require: false' >> Gemfile
            echo "end" >> Gemfile
        fi

        echo -e "${GREEN}✓ Added SimpleCov to Gemfile${NC}"
        echo -e "${BLUE}Running bundle install...${NC}"
        bundle install
    fi
}

# Configure SimpleCov in test_helper
configure_simplecov() {
    if ! grep -q "SimpleCov.start" test/test_helper.rb; then
        echo -e "${BLUE}Configuring SimpleCov in test_helper.rb...${NC}"

        # Add SimpleCov configuration at the top of test_helper.rb
        cat > /tmp/simplecov_config.rb << 'EOF'
require 'simplecov'

SimpleCov.start 'rails' do
  add_filter '/test/'
  add_filter '/config/'
  add_filter '/vendor/'
  add_filter '/bin/'

  add_group 'Models', 'app/models'
  add_group 'Controllers', 'app/controllers'
  add_group 'Services', 'app/services'
  add_group 'Jobs', 'app/jobs'
  add_group 'Mailers', 'app/mailers'
  add_group 'Helpers', 'app/helpers'

  minimum_coverage 80
  refuse_coverage_drop
end

EOF

        # Prepend to test_helper.rb
        cat /tmp/simplecov_config.rb test/test_helper.rb > /tmp/test_helper_new.rb
        mv /tmp/test_helper_new.rb test/test_helper.rb
        rm /tmp/simplecov_config.rb

        echo -e "${GREEN}✓ SimpleCov configured${NC}"
    fi
}

# Run tests with coverage
run_tests_with_coverage() {
    echo -e "${BLUE}Running tests with coverage...${NC}"
    echo ""

    export COVERAGE=true

    case "$TEST_CATEGORY" in
        "models")
            docker-compose run --rm web rails test test/models/
            ;;
        "controllers")
            docker-compose run --rm web rails test test/controllers/
            ;;
        "services")
            docker-compose run --rm web rails test test/services/
            ;;
        "jobs")
            docker-compose run --rm web rails test test/jobs/
            ;;
        "system"|"e2e")
            docker-compose run --rm web rails test:system
            ;;
        "integration")
            docker-compose run --rm web rails test test/integration/
            ;;
        "all")
            docker-compose run --rm web rails test
            ;;
        *)
            docker-compose run --rm web rails test "$TEST_CATEGORY"
            ;;
    esac

    echo ""
}

# Parse coverage results
parse_coverage() {
    if [ ! -d "coverage" ]; then
        echo -e "${RED}✗ Coverage directory not found${NC}"
        echo "Make sure SimpleCov is properly configured"
        exit 1
    fi

    echo -e "${BLUE}📈 Coverage Summary${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    # Parse .resultset.json for coverage data
    if [ -f "coverage/.resultset.json" ]; then
        ruby << 'RUBY'
require 'json'

data = JSON.parse(File.read('coverage/.resultset.json'))
coverage = data['RSpec'] || data['MiniTest'] || data.values.first

if coverage && coverage['coverage']
  total_lines = 0
  covered_lines = 0

  coverage['coverage'].each do |file, lines|
    lines.each do |line|
      next if line.nil?
      total_lines += 1
      covered_lines += 1 if line > 0
    end
  end

  percentage = (covered_lines.to_f / total_lines * 100).round(2)
  puts "Total Lines: #{total_lines}"
  puts "Covered Lines: #{covered_lines}"
  puts "Coverage: #{percentage}%"
end
RUBY
    fi

    echo ""
    echo -e "${BLUE}View full report: ${GREEN}open coverage/index.html${NC}"
}

# Display coverage by group
display_group_coverage() {
    echo ""
    echo -e "${BLUE}Coverage by Category${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    # This would parse the HTML or use SimpleCov's JSON output
    # For now, just point to the report
    echo -e "See ${GREEN}coverage/index.html${NC} for detailed breakdown"
}

# Main execution
main() {
    # Check for Docker
    if ! command -v docker-compose &> /dev/null; then
        echo -e "${RED}✗ docker-compose not found${NC}"
        echo "This script requires Docker Compose"
        exit 1
    fi

    # Setup SimpleCov if needed
    check_simplecov
    configure_simplecov

    # Run tests
    run_tests_with_coverage

    # Parse and display results
    parse_coverage
    display_group_coverage

    echo ""
    echo -e "${GREEN}✓ Coverage analysis complete${NC}"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --threshold)
            COVERAGE_THRESHOLD="$2"
            shift 2
            ;;
        --category)
            TEST_CATEGORY="$2"
            shift 2
            ;;
        --format)
            OUTPUT_FORMAT="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

main
