# Run Tests

Comprehensive test execution for the AMOS platform with intelligent test selection and reporting.

## Description

Execute tests at multiple levels: full suite, specific categories, or affected tests based on git changes. This command understands all test types in the project and provides smart execution strategies.

**What it does:**
- ✅ Runs full test suite or specific test categories
- ✅ Tests models, services, controllers, integration tests
- ✅ Tests Scout AI functionality (chat, file upload, tools)
- ✅ Tests RAG system (document indexing, semantic search)
- ✅ Tests workflows and email campaigns
- ✅ System tests (browser automation tests)
- ✅ Generates test summary with pass/fail counts
- ✅ Can run affected tests (tests impacted by your code changes)

## Test Categories Explained

### Unit Tests (Fast - ~30 seconds)
- **Models** (50 files) - Database models, validations, associations
  - Entity, Campaign, Contact, Email Template, RAG models, etc.
- **Services** (35 files) - Business logic, API integrations
  - Bedrock service, RAG services, Affiliate services, etc.
- **Jobs** (15 files) - Background job processing
  - Campaign processing, RAG indexing, document extraction, etc.
- **Mailers** (1 file) - Email sending functionality

### Controller Tests (Medium - ~1 minute)
- **Controllers** (20 files) - HTTP request/response handling
  - Admin, Affiliate, Scout, Campaign controllers, etc.

### Integration Tests (Slow - ~2 minutes)
- **Integration Tests** (9 files) - Multi-component flows
  - Scout file upload, RAG E2E, affiliate tracking, payout flow, etc.
- **System Tests** (8 files) - Full browser automation
  - User authentication, email campaigns, landing pages, workflows, etc.

## When to Use Each Mode

### `/run-tests all` - Full Suite
- Before pushing to GitHub
- Pre-release verification
- Major refactoring completion
- Time: ~5-10 minutes

### `/run-tests models` - Just Models
- Quick feedback during development
- Model validation changes
- Time: ~30 seconds

### `/run-tests services` - Just Services
- Business logic changes
- Integration code changes
- Time: ~1 minute

### `/run-tests scout` - Scout AI Tests
- Scout chat features
- File upload functionality
- AI tool changes
- Time: ~2 minutes

### `/run-tests rag` - RAG System Tests
- Document indexing
- Semantic search
- RAG store operations
- Time: ~1 minute

### `/run-tests controllers` - Controller Tests
- HTTP handler changes
- Route changes
- Authentication changes
- Time: ~1 minute

### `/run-tests integration` - Integration Tests
- Multi-component workflows
- API integration flows
- Time: ~2 minutes

### `/run-tests system` - System/Browser Tests
- UI functionality
- End-to-end user flows
- Visual regression detection
- Time: ~3 minutes

### `/run-tests affected` - Smart Test Selection
- Runs only tests that may be affected by your git changes
- Time: Varies (usually 1-2 minutes)

## Usage

```bash
# Run everything
/run-tests all

# Run by category
/run-tests models
/run-tests services
/run-tests scout
/run-tests rag
/run-tests controllers
/run-tests integration
/run-tests system

# Run affected tests (smart selection)
/run-tests affected

# Run specific test file
/run-tests test/integration/scout_file_upload_integration_test.rb

# Run with line number (single test)
/run-tests test/models/campaign_test.rb:42
```

## Test File Locations

```
test/
├── models/              # Unit tests for database models (50 files)
├── services/            # Business logic & API integration tests (35 files)
├── controllers/         # HTTP request/response tests (20 files)
├── integration/         # Multi-component workflow tests (9 files)
│   ├── scout_file_upload_integration_test.rb ✅
│   ├── scout_upload_rag_e2e_test.rb
│   ├── scout_session_rag_test.rb
│   ├── rag_end_to_end_test.rb
│   ├── affiliate_tracking_flow_test.rb
│   ├── commission_creation_flow_test.rb
│   ├── payout_flow_test.rb
│   └── ...
├── system/              # Browser automation tests (8 files)
│   ├── scout_file_upload_test.rb ✅
│   ├── user_authentication_test.rb
│   ├── email_campaign_v2_workflow_test.rb
│   ├── landing_page_workflow_test.rb
│   └── ...
├── jobs/                # Background job tests (15 files)
├── mailers/             # Email sending tests (1 file)
├── fixtures/            # Test data
└── test_helper.rb       # Test configuration
```

## Test Results Interpretation

**SUCCESS OUTPUT:**
```
Running XX tests...
Finished in X.XXXXXXs, X.XXXX runs/s, X.XXXX assertions/s.
XX runs, XXX assertions, 0 failures, 0 errors, X skips
```

**FAILURE OUTPUT:**
```
1 failures
2 errors
```

## Scout File Upload Tests
- ✅ **test/integration/scout_file_upload_integration_test.rb** (6 tests)
  - File upload creates ImageAsset
  - Multiple file upload
  - Different MIME types
  - Authentication checks
  - File extension preservation
  - read_document_tool integration

- ✅ **test/system/scout_file_upload_test.rb** (4 tests)
  - UI interaction testing
  - File attachment display
  - File removal
  - Modal workflow

## Scout AI Test Categories

### Tools Tests
- `test/services/tools/` - AI tool functionality
- Tests: query_document_content, get_email_sequence_data, etc.

### Workflow Tests
- `test/models/workflow_test.rb` - Workflow execution
- Tests: phase execution, context management, tool calling

### RAG Tests
- `test/integration/scout_upload_rag_e2e_test.rb` - Document upload & indexing
- `test/integration/scout_session_rag_test.rb` - Session-based RAG
- Tests: semantic search, multi-tenant isolation, document retrieval

## Pro Tips

1. **Run affected tests first** during active development:
   ```bash
   /run-tests affected
   ```

2. **Run specific category** for focused work:
   ```bash
   /run-tests scout     # Only Scout tests
   /run-tests rag       # Only RAG tests
   ```

3. **Run full suite before push**:
   ```bash
   /run-tests all
   ```

4. **Run single test file for quick feedback**:
   ```bash
   /run-tests test/integration/scout_file_upload_integration_test.rb
   ```

## CI/CD Integration

These tests are also run automatically:
- On every git commit (pre-commit hooks)
- On pull requests (GitHub Actions)
- On deployment (before release)

## Troubleshooting

**Tests failing locally?**
1. Check Docker is running: `docker compose ps`
2. Check database is created: `docker compose exec web rails db:create`
3. Run migrations: `docker compose exec web rails db:migrate`
4. Reset test database: `/reset-database`

**System tests not running?**
- Requires Chrome/ChromeDriver
- Check Dockerfile.dev for Chrome installation
- Run without -webkit flag

**Memory issues?**
- Run tests by category instead of all at once
- Close other applications
- Increase Docker memory limit

## Related Commands

- `/check-deployment` - Health check before testing
- `/test-rag` - Interactive RAG testing
- `/prepare-dev-env` - Setup test environment
- `/reset-database` - Clean test database
