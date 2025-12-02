# Checking Test Coverage

Analyzes test coverage, recommends missing tests, and fixes broken tests.

## Description

This skill provides comprehensive test coverage analysis for Rails applications. It checks both unit and e2e test coverage, identifies untested code, recommends specific test additions, and can automatically fix broken tests. The skill works with Rails Minitest and integrates coverage reporting using SimpleCov.

**Key capabilities:**
- Analyzes unit test coverage (models, services, controllers, jobs)
- Analyzes e2e/system test coverage for critical user flows
- Identifies files with missing or insufficient tests
- Provides specific test recommendations based on code structure
- Detects and fixes broken tests automatically
- Generates detailed coverage reports with actionable insights

**Use this skill when:**
- Assessing overall test coverage of the application
- Finding gaps in test coverage before releases
- Planning which tests to add next
- Fixing failing tests in the test suite
- Establishing baseline coverage metrics
- Ensuring critical paths have e2e test coverage

## Instructions

### Overview

The skill operates in multiple modes to provide comprehensive test analysis:
1. **Coverage Analysis** - Runs tests with coverage reporting
2. **Gap Detection** - Identifies untested or under-tested code
3. **Recommendation** - Suggests specific tests to add
4. **Fix Broken Tests** - Automatically repairs failing tests
5. **Full Report** - Complete coverage analysis with recommendations

### Usage Modes

**Mode 1: Quick Coverage Check**
- Runs test suite with coverage enabled
- Displays coverage percentages by category
- Highlights low-coverage areas

**Mode 2: Gap Analysis**
- Finds files without corresponding test files
- Identifies methods/functions lacking test coverage
- Categorizes by priority (critical vs nice-to-have)

**Mode 3: Test Recommendations**
- Analyzes code structure and suggests specific tests
- Provides test templates and examples
- Prioritizes based on code complexity and criticality

**Mode 4: Fix Broken Tests**
- Runs test suite to detect failures
- Analyzes failure messages and stack traces
- Attempts automatic fixes for common issues
- Reports fixes made and remaining issues

**Mode 5: Full Report**
- Combines all modes above
- Generates comprehensive HTML/markdown report
- Includes coverage trends and historical data

### Coverage Analysis Process

1. **Setup Coverage Tool**
   - Checks if SimpleCov is installed
   - Adds SimpleCov to Gemfile if needed
   - Configures coverage thresholds and exclusions

2. **Run Tests with Coverage**
   - Executes full test suite or specific categories
   - Collects coverage data for all test types
   - Generates coverage report in coverage/ directory

3. **Parse Coverage Results**
   - Extracts coverage percentages by file/directory
   - Identifies files below coverage threshold
   - Calculates overall coverage metrics

4. **Generate Insights**
   - Lists untested files with file paths
   - Highlights critical code paths without tests
   - Shows coverage trends vs previous runs

### Gap Detection Strategy

The skill maps application files to their expected test files:

**Unit Tests:**
- `app/models/*.rb` → `test/models/*_test.rb`
- `app/services/*.rb` → `test/services/*_test.rb`
- `app/services/tools/*.rb` → `test/services/tools/*_test.rb`
- `app/controllers/*.rb` → `test/controllers/*_test.rb`
- `app/jobs/*.rb` → `test/jobs/*_test.rb`
- `app/mailers/*.rb` → `test/mailers/*_test.rb`
- `app/helpers/*.rb` → `test/helpers/*_test.rb`

**E2E/System Tests:**
- Critical user flows (authentication, checkout, campaigns)
- Workflow executions (email campaigns, landing pages)
- Integration points (API connections, webhooks)

For each missing test file, the skill determines:
- File complexity (lines of code, method count)
- Business criticality (based on directory/naming patterns)
- Priority level (high/medium/low)

### Test Recommendation Engine

The skill analyzes code structure and generates specific test recommendations:

**For Models:**
- Validations (presence, uniqueness, format)
- Associations (belongs_to, has_many, has_one)
- Scopes and custom queries
- Callbacks (before_save, after_create, etc.)
- Instance and class methods

**For Services:**
- Main execute/call method with various inputs
- Error handling and edge cases
- External API interactions (mocked)
- Data transformations and validations

**For Controllers:**
- Each action (index, show, create, update, destroy)
- Authentication and authorization
- Parameter handling and validation
- Response formats (HTML, JSON)

**For Jobs:**
- Successful execution path
- Retry logic and error handling
- Idempotency checks

**For E2E Tests:**
- Complete user flows from start to finish
- Multi-step workflows (create campaign → add contacts → send)
- Authentication flows (login, logout, password reset)
- Payment/subscription flows
- File upload and processing workflows

### Fixing Broken Tests

The skill can automatically fix common test failures:

**Common Issues Detected:**
1. **Missing fixtures** - Creates missing fixture data
2. **Outdated assertions** - Updates assertions to match current behavior
3. **Nil reference errors** - Adds proper setup/initialization
4. **Route errors** - Updates routes or test paths
5. **Deprecation warnings** - Modernizes deprecated syntax
6. **Authentication issues** - Adds proper login/session setup
7. **Database state issues** - Adds proper cleanup/isolation
8. **Timing issues** - Adds proper waits for async operations

**Fix Process:**
1. Run tests and capture failures
2. Parse failure messages and stack traces
3. Identify failure patterns
4. Apply appropriate fixes
5. Re-run tests to verify fixes
6. Report results and any remaining issues

### Output Format

The skill provides detailed output including:

**Coverage Summary:**
```
📊 Test Coverage Report
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Overall Coverage:        78.5% (Target: 80%)
Models:                  92.3% ✓
Controllers:             71.2% ⚠️
Services:                85.6% ✓
Jobs:                    68.4% ⚠️
```

**Coverage Gaps:**
```
⚠️ Files Missing Tests (12 files)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
HIGH PRIORITY:
  app/services/payment_processor.rb (127 lines)
  app/controllers/admin/reports_controller.rb (98 lines)

MEDIUM PRIORITY:
  app/services/analytics_tracker.rb (64 lines)
  app/jobs/cleanup_old_data_job.rb (43 lines)
```

**Test Recommendations:**
```
💡 Recommended Tests
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
1. test/services/payment_processor_test.rb
   - Test successful payment processing
   - Test payment failures and retries
   - Test refund handling
   - Test webhook verification

2. test/system/checkout_flow_test.rb
   - Test complete checkout from cart to confirmation
   - Test payment failure handling
   - Test coupon code application
```

## Examples

### Example 1: Quick Coverage Check

```
Use checking-test-coverage skill
```

**Expected outcome:**
Runs tests with coverage, displays summary with percentages and identifies areas below threshold.

### Example 2: Find Coverage Gaps

```
Use checking-test-coverage skill with mode=gaps
```

**Expected outcome:**
Lists all files missing tests, categorized by priority and type.

### Example 3: Get Test Recommendations

```
Use checking-test-coverage skill with mode=recommend
```

**Expected outcome:**
Analyzes code and provides specific test recommendations with templates.

### Example 4: Fix Broken Tests

```
Use checking-test-coverage skill with mode=fix
```

**Expected outcome:**
Runs tests, detects failures, attempts automatic fixes, reports results.

### Example 5: Full Coverage Report

```
Use checking-test-coverage skill with mode=full
```

**Expected outcome:**
Complete analysis including coverage, gaps, recommendations, and fix attempts.

### Example 6: Check Specific Category

```
Use checking-test-coverage skill with category=models
```

**Expected outcome:**
Coverage analysis focused only on model tests.

### Example 7: E2E Coverage Only

```
Use checking-test-coverage skill with test_type=e2e
```

**Expected outcome:**
Analyzes system test coverage for critical user flows.

## Resources

- [Coverage Analysis Script](scripts/analyze-coverage.sh) - Runs tests with coverage and parses results
- [Gap Detection Script](scripts/detect-gaps.sh) - Finds files missing tests
- [Test Recommender Script](scripts/recommend-tests.sh) - Generates test recommendations
- [Test Fixer Script](scripts/fix-tests.sh) - Attempts to fix broken tests
- [Coverage Report Template](resources/coverage-report-template.md) - HTML report format
- [Test Templates](resources/test-templates.md) - Common test patterns and examples
