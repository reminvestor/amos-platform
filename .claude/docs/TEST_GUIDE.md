# Complete Test Guide for AMOS Platform

This guide explains all test types in the AMOS platform and how they work together.

## Test Architecture Overview

```
Tests (130 files total)
├── Unit Tests (86 files) - Fast, isolated, focus on single components
│   ├── Models (50) - Database models & validations
│   ├── Services (35) - Business logic & integrations
│   └── Mailers (1) - Email sending
│
├── Integration Tests (9 files) - Multi-component workflows
│   ├── Scout features (3) - File upload, RAG, session
│   ├── RAG system (3) - Document processing, semantic search
│   ├── Affiliate flow (1) - Referral tracking
│   ├── Commission flow (1) - Payout calculations
│   └── Other flows (1) - Various workflows
│
├── System Tests (8 files) - Browser automation, end-to-end
│   ├── Scout UI tests
│   ├── Authentication flow
│   ├── Email campaign workflow
│   ├── Landing page workflow
│   └── Other UI flows
│
└── Other (27 files)
    ├── Controllers (20) - HTTP request handling
    ├── Jobs (15) - Background task processing
    └── Direct aggregation tests
```

## Test Execution Flow

```
User runs: /run-tests [mode]
    ↓
Rails test runner loads test files
    ↓
Test database created (via test_helper.rb)
    ↓
Fixtures loaded (test/fixtures/*.yml)
    ↓
Tests execute in order:
    1. Unit tests (models/services) - Fast ⚡
    2. Controller tests - Medium 🔄
    3. Integration tests - Slow 🐢
    4. System tests (browser) - Slowest 🌐
    ↓
Results aggregated & reported
    ↓
Exit code: 0 (success) or 1+ (failures)
```

## How Each Test Type Works

### Unit Tests (Models & Services)

**Purpose:** Test individual components in isolation

**Example: Model Test** (`test/models/campaign_test.rb`)
```ruby
test "campaign validates required fields" do
  campaign = Campaign.new(name: nil)
  assert_not campaign.valid?
  assert campaign.errors[:name].present?
end
```

**Example: Service Test** (`test/services/bedrock_service_test.rb`)
```ruby
test "sends message to AWS Bedrock API" do
  service = BedrockService.new(user: @user, entity: @entity)
  response = service.send_message("Hello")
  assert response.include?("content")
end
```

**Execution:** <1 second per test, no database mutations, no external API calls

### Controller Tests

**Purpose:** Test HTTP request/response handling

**Example:** (`test/controllers/campaigns_controller_test.rb`)
```ruby
test "GET /campaigns returns campaigns for current entity" do
  get campaigns_path
  assert_response :success
  assert_template :index
end
```

**Execution:** <1 second per test, uses test database, simulates HTTP requests

### Integration Tests

**Purpose:** Test workflows spanning multiple components

**Example: Scout File Upload** (`test/integration/scout_file_upload_integration_test.rb`)
```ruby
test "file upload creates ImageAsset and RAG document" do
  # 1. Create temp file
  tempfile = Tempfile.new(['test', '.pdf'])
  # 2. Upload via Scout endpoint
  post "/scout/upload_files", params: { files: { 0 => tempfile } }
  # 3. Verify responses and side effects
  assert_response :success
  assert ImageAsset.find(response_json['asset_id'])
end
```

**Workflow:**
1. Setup: Create test data, entities, users
2. Action: Simulate real user action (file upload, API call)
3. Assertion: Verify all side effects occurred (database records, files, etc.)

**Execution:** 5-20 seconds per test, uses test database, may hit external services

### System Tests (Browser Automation)

**Purpose:** Test UI workflows with real browser

**Example: Scout File Upload UI** (`test/system/scout_file_upload_test.rb`)
```ruby
test "user can attach and upload a file in Scout chat" do
  sign_in_as(@user)
  visit "/scout"

  # Click attach button
  find(".attach-btn").click

  # Select file
  input_file = find("input#file-input", visible: false)
  input_file.send_keys(test_file)

  # Verify display
  assert_selector ".attached-file", text: File.basename(test_file)

  # Fill form and submit
  fill_in "message-input", with: "Analyze this"
  click_button "send-button"

  # Verify result
  assert_selector ".chat-message.user-message"
end
```

**Execution Setup:**
1. Starts Chrome browser in Docker
2. Connects via Selenium WebDriver
3. Loads Rails app at http://app.localhost:3000
4. Simulates real user interactions
5. Takes screenshots on failure

**Timing:** 10-30 seconds per test (slow due to browser startup)

## Scout AI Test Categories

### 1. Scout File Upload Tests (NEW ✅)

**What's tested:**
- File selection via UI
- File display in attachment list
- File icon rendering (Lucide)
- File removal functionality
- Storage choice modal
- Backend file processing
- ImageAsset creation
- read_document_tool integration

**Test files:**
- `test/integration/scout_file_upload_integration_test.rb` (6 tests)
- `test/system/scout_file_upload_test.rb` (4 tests)

**Status:** All passing ✅

### 2. Scout RAG Tests

**What's tested:**
- Document upload via Scout
- RAG store creation
- Document indexing (Docling/fallback)
- Semantic search functionality
- Multi-tenant isolation
- Document retrieval

**Test files:**
- `test/integration/scout_upload_rag_e2e_test.rb`
- `test/integration/scout_session_rag_test.rb`
- `test/integration/rag_end_to_end_test.rb`

**Status:** Some pre-existing failures (not related to file upload fix)

### 3. Scout Tool Tests

**What's tested:**
- Individual tool execution
- Tool parameter validation
- Tool result formatting
- Error handling

**Test files:**
- `test/services/tools/*.rb` (12 files)

**Examples:**
- query_document_content_tool_test.rb
- get_email_sequence_data_test.rb
- update_subscription_tool_test.rb

### 4. Scout Workflow Tests

**What's tested:**
- Workflow phase execution (gather, goal, validate)
- Context management
- Tool integration within workflows
- Error recovery

**Test files:**
- `test/models/workflow_test.rb`
- `test/models/sequence_step_test.rb`

### 5. Streaming & WebSocket Tests

**What's tested:**
- Server-Sent Events (SSE) streaming
- Message accumulation
- Event generation
- Real-time response handling

**Test files:**
- `test/controllers/concerns/scout/streaming_test.rb`

## Test Data & Fixtures

### Fixture Files
```yaml
test/fixtures/
├── users.yml           # Test users
├── entities.yml        # Test organizations
├── campaigns.yml       # Test email campaigns
├── contacts.yml        # Test contact lists
├── rag_stores.yml      # Test RAG stores
├── rag_documents.yml   # Test documents
├── rag_chunks.yml      # Test document chunks
└── workflows.yml       # Test workflow templates
```

### Test Database
- Separate from development database
- Created fresh for each test run
- Fixtures loaded before tests
- Transactions rolled back after each test

## Test Execution Modes

### Run All Tests
```bash
docker compose exec web rails test
```
- Runs all 130 test files
- Time: 5-10 minutes
- Best for: Pre-push verification

### Run By Category
```bash
# Models only
docker compose exec web rails test test/models

# Services only
docker compose exec web rails test test/services

# Scout tests
docker compose exec web rails test test/integration/scout* test/system/scout*

# RAG tests
docker compose exec web rails test test/integration/scout_upload_rag* test/integration/rag*

# Controllers only
docker compose exec web rails test test/controllers

# Integration tests
docker compose exec web rails test test/integration

# System tests
docker compose exec web rails test:system
```

### Run Specific File
```bash
docker compose exec web rails test test/integration/scout_file_upload_integration_test.rb
```

### Run Single Test
```bash
# Run by test name/line number
docker compose exec web rails test test/integration/scout_file_upload_integration_test.rb:50
```

## Test Failure Diagnosis

### Common Failure Patterns

**Pattern 1: Database Not Ready**
```
Error: ActiveRecord::NoDatabaseError: Unknown database 'app_test'
Fix: docker compose exec web rails db:test:prepare
```

**Pattern 2: Chrome Not Available (System Tests)**
```
Error: Selenium::WebDriver::Error::SessionNotCreatedError
Fix: Check Dockerfile.dev has Chrome installed
```

**Pattern 3: External Service Failure**
```
Error: Bedrock API returned error
Fix: Check AWS credentials in .env
```

**Pattern 4: Fixture Data Missing**
```
Error: ActiveRecord::RecordNotFound: Couldn't find User
Fix: Check test/fixtures/users.yml has required test data
```

## Performance Tips

1. **Run affected tests only during development:**
   ```bash
   docker compose exec web rails test --changed
   ```

2. **Run tests in parallel:**
   ```bash
   docker compose exec web rails test --parallel=4
   ```

3. **Skip slow tests during iteration:**
   ```bash
   docker compose exec web rails test --skip-system
   ```

4. **Run single category for focused work:**
   ```bash
   docker compose exec web rails test test/services
   ```

## Continuous Integration

Tests run automatically:
- **On commit:** Pre-commit hooks in `.git/hooks/`
- **On PR:** GitHub Actions in `.github/workflows/`
- **On deployment:** Before releasing to staging/production

## Writing New Tests

### Test Structure Template

```ruby
require "test_helper"

class YourFeatureTest < ActiveSupport::TestCase
  setup do
    @entity = entities(:demo_company)
    @user = users(:admin_user)
  end

  test "feature does expected thing" do
    # Setup
    data = SomeModel.create(name: "test")

    # Action
    result = SomeService.new(@user, @entity).process(data)

    # Assert
    assert result[:success]
    assert_equal expected_value, result[:data]
  end
end
```

### Integration Test Template

```ruby
require "test_helper"

class YourIntegrationTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = users(:admin_user)
    sign_in @user
  end

  test "multi-step workflow succeeds" do
    # Step 1
    post "/api/action", params: { data: "value" }
    assert_response :success

    # Step 2
    get "/api/result"
    assert_includes response.body, "expected"
  end
end
```

### System Test Template

```ruby
require "application_system_test_case"

class YourFeatureTest < ApplicationSystemTestCase
  test "user can do something in UI" do
    sign_in_as(@user)
    visit "/page"

    fill_in "field", with: "value"
    click_button "Submit"

    assert_text "success message"
  end
end
```

## Debugging Tests

### Run with Verbose Output
```bash
docker compose exec web rails test -v
```

### Run with Seed for Reproducible Order
```bash
docker compose exec web rails test --seed=12345
```

### Run with Screenshots (System Tests)
Screenshots saved to `tmp/screenshots/` on failure

### Debug a Single Test
```bash
docker compose exec web rails test test/file.rb:42 -v
```

## Related Files

- `.claudee/commands/run-tests.md` - Test command documentation
- `.claude/skills/running-tests/` - Test execution skill
- `test/test_helper.rb` - Test configuration
- `test/fixtures/` - Test data
- `Gemfile` - Testing gems (minitest, selenium, etc.)
- `.github/workflows/` - CI/CD configuration

## Summary

The AMOS test suite consists of:
- **130 test files** covering all major features
- **Unit tests** for fast feedback (models, services)
- **Integration tests** for workflow validation
- **System tests** for UI verification
- **Scout AI tests** for chat, file upload, RAG functionality
- **Comprehensive coverage** of business logic and user flows

Run `/run-tests all` before pushing code to ensure everything works!
