#!/bin/bash

# Test Coverage Gap Detection Script
# Finds files without corresponding test files

set -e

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

echo -e "${BLUE}🔍 Test Coverage Gap Detection${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Arrays to store missing tests
declare -a HIGH_PRIORITY=()
declare -a MEDIUM_PRIORITY=()
declare -a LOW_PRIORITY=()

# Get file line count
get_line_count() {
    wc -l < "$1" | tr -d ' '
}

# Determine priority based on file characteristics
determine_priority() {
    local file=$1
    local lines=$(get_line_count "$file")

    # High priority: large files, critical directories
    if [[ $lines -gt 100 ]] || \
       [[ $file == *"/services/"* ]] || \
       [[ $file == *"/controllers/"* ]] || \
       [[ $file == *"_processor"* ]] || \
       [[ $file == *"_service"* ]]; then
        echo "HIGH"
    # Medium priority: medium files, jobs, mailers
    elif [[ $lines -gt 50 ]] || \
         [[ $file == *"/jobs/"* ]] || \
         [[ $file == *"/mailers/"* ]]; then
        echo "MEDIUM"
    else
        echo "LOW"
    fi
}

# Check models
check_models() {
    echo -e "${CYAN}Checking Models...${NC}"

    for model in app/models/*.rb; do
        [ -e "$model" ] || continue

        # Skip base classes and concerns
        if [[ $model == *"application_record.rb" ]] || \
           [[ $model == *"/concerns/"* ]]; then
            continue
        fi

        filename=$(basename "$model" .rb)
        test_file="test/models/${filename}_test.rb"

        if [ ! -f "$test_file" ]; then
            priority=$(determine_priority "$model")
            lines=$(get_line_count "$model")

            case $priority in
                HIGH)
                    HIGH_PRIORITY+=("$model ($lines lines) → $test_file")
                    ;;
                MEDIUM)
                    MEDIUM_PRIORITY+=("$model ($lines lines) → $test_file")
                    ;;
                LOW)
                    LOW_PRIORITY+=("$model ($lines lines) → $test_file")
                    ;;
            esac
        fi
    done
}

# Check controllers
check_controllers() {
    echo -e "${CYAN}Checking Controllers...${NC}"

    find app/controllers -name "*.rb" -type f | while read -r controller; do
        # Skip base classes
        if [[ $controller == *"application_controller.rb" ]] || \
           [[ $controller == *"/concerns/"* ]]; then
            continue
        fi

        # Construct expected test path
        rel_path=${controller#app/controllers/}
        test_file="test/controllers/${rel_path%.rb}_test.rb"

        if [ ! -f "$test_file" ]; then
            priority=$(determine_priority "$controller")
            lines=$(get_line_count "$controller")

            case $priority in
                HIGH)
                    HIGH_PRIORITY+=("$controller ($lines lines) → $test_file")
                    ;;
                MEDIUM)
                    MEDIUM_PRIORITY+=("$controller ($lines lines) → $test_file")
                    ;;
                LOW)
                    LOW_PRIORITY+=("$controller ($lines lines) → $test_file")
                    ;;
            esac
        fi
    done
}

# Check services
check_services() {
    echo -e "${CYAN}Checking Services...${NC}"

    find app/services -name "*.rb" -type f | while read -r service; do
        # Construct expected test path
        rel_path=${service#app/services/}
        test_file="test/services/${rel_path%.rb}_test.rb"

        if [ ! -f "$test_file" ]; then
            priority=$(determine_priority "$service")
            lines=$(get_line_count "$service")

            case $priority in
                HIGH)
                    HIGH_PRIORITY+=("$service ($lines lines) → $test_file")
                    ;;
                MEDIUM)
                    MEDIUM_PRIORITY+=("$service ($lines lines) → $test_file")
                    ;;
                LOW)
                    LOW_PRIORITY+=("$service ($lines lines) → $test_file")
                    ;;
            esac
        fi
    done
}

# Check jobs
check_jobs() {
    echo -e "${CYAN}Checking Jobs...${NC}"

    find app/jobs -name "*.rb" -type f | while read -r job; do
        # Skip base job
        if [[ $job == *"application_job.rb" ]]; then
            continue
        fi

        # Construct expected test path
        rel_path=${job#app/jobs/}
        test_file="test/jobs/${rel_path%.rb}_test.rb"

        if [ ! -f "$test_file" ]; then
            priority=$(determine_priority "$job")
            lines=$(get_line_count "$job")

            case $priority in
                HIGH)
                    HIGH_PRIORITY+=("$job ($lines lines) → $test_file")
                    ;;
                MEDIUM)
                    MEDIUM_PRIORITY+=("$job ($lines lines) → $test_file")
                    ;;
                LOW)
                    LOW_PRIORITY+=("$job ($lines lines) → $test_file")
                    ;;
            esac
        fi
    done
}

# Check mailers
check_mailers() {
    echo -e "${CYAN}Checking Mailers...${NC}"

    find app/mailers -name "*.rb" -type f | while read -r mailer; do
        # Skip base mailer
        if [[ $mailer == *"application_mailer.rb" ]]; then
            continue
        fi

        # Construct expected test path
        rel_path=${mailer#app/mailers/}
        test_file="test/mailers/${rel_path%.rb}_test.rb"

        if [ ! -f "$test_file" ]; then
            priority=$(determine_priority "$mailer")
            lines=$(get_line_count "$mailer")

            case $priority in
                HIGH)
                    HIGH_PRIORITY+=("$mailer ($lines lines) → $test_file")
                    ;;
                MEDIUM)
                    MEDIUM_PRIORITY+=("$mailer ($lines lines) → $test_file")
                    ;;
                LOW)
                    LOW_PRIORITY+=("$mailer ($lines lines) → $test_file")
                    ;;
            esac
        fi
    done
}

# Check e2e coverage for critical flows
check_e2e_flows() {
    echo -e "${CYAN}Checking E2E/System Test Coverage...${NC}"

    declare -a CRITICAL_FLOWS=(
        "Admin dashboard navigation"
        "User settings and profile management"
        "API integration connection flow"
        "Workflow template execution"
        "Tool invocation and response handling"
        "File upload and processing"
        "Error handling and recovery"
    )

    # Check existing system tests
    local system_test_count=$(find test/system -name "*.rb" -type f | wc -l)

    echo ""
    echo -e "${YELLOW}System Tests Found: $system_test_count${NC}"
    echo ""
    echo -e "${BLUE}Critical Flows to Consider:${NC}"

    for flow in "${CRITICAL_FLOWS[@]}"; do
        echo -e "  • $flow"
    done
}

# Display results
display_results() {
    echo ""
    echo -e "${BLUE}📋 Coverage Gap Summary${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    local total_gaps=$((${#HIGH_PRIORITY[@]} + ${#MEDIUM_PRIORITY[@]} + ${#LOW_PRIORITY[@]}))

    if [ $total_gaps -eq 0 ]; then
        echo -e "${GREEN}✓ No coverage gaps detected!${NC}"
        echo -e "All application files have corresponding test files."
        return
    fi

    echo -e "${YELLOW}⚠️  Found $total_gaps files without tests${NC}"
    echo ""

    if [ ${#HIGH_PRIORITY[@]} -gt 0 ]; then
        echo -e "${RED}HIGH PRIORITY (${#HIGH_PRIORITY[@]} files):${NC}"
        printf '%s\n' "${HIGH_PRIORITY[@]}" | head -10
        if [ ${#HIGH_PRIORITY[@]} -gt 10 ]; then
            echo -e "${CYAN}  ... and $((${#HIGH_PRIORITY[@]} - 10)) more${NC}"
        fi
        echo ""
    fi

    if [ ${#MEDIUM_PRIORITY[@]} -gt 0 ]; then
        echo -e "${YELLOW}MEDIUM PRIORITY (${#MEDIUM_PRIORITY[@]} files):${NC}"
        printf '%s\n' "${MEDIUM_PRIORITY[@]}" | head -5
        if [ ${#MEDIUM_PRIORITY[@]} -gt 5 ]; then
            echo -e "${CYAN}  ... and $((${#MEDIUM_PRIORITY[@]} - 5)) more${NC}"
        fi
        echo ""
    fi

    if [ ${#LOW_PRIORITY[@]} -gt 0 ]; then
        echo -e "${CYAN}LOW PRIORITY (${#LOW_PRIORITY[@]} files)${NC}"
        if [ ${#LOW_PRIORITY[@]} -le 3 ]; then
            printf '%s\n' "${LOW_PRIORITY[@]}"
        else
            echo -e "  (${#LOW_PRIORITY[@]} files - mostly helpers and small utilities)"
        fi
        echo ""
    fi
}

# Main execution
main() {
    check_models
    check_controllers
    check_services
    check_jobs
    check_mailers
    check_e2e_flows

    display_results

    echo ""
    echo -e "${GREEN}✓ Gap detection complete${NC}"
}

main
