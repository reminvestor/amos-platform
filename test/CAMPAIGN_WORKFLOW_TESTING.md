# Email Campaign V2 Workflow Testing Guide

## Overview

This test suite provides comprehensive, automated testing for the three-phase email campaign workflow system. It ensures the workflow handles all scenarios correctly and can be run repeatedly in CI/CD pipelines.

## Performance Considerations

**⚠️ Important: These tests make real AWS Bedrock API calls**

- **Test Duration**: Each test takes 30-90 seconds due to AI model inference
- **Full Suite Runtime**: 6-10 minutes for all 17 tests
- **Why It's Slow**:
  - Real AWS Bedrock Claude Sonnet 4.5 API calls
  - Multiple phases per workflow (gather → execute → validate)
  - Multi-turn conversational tests require sequential API calls
  - Network latency to AWS endpoints

**Optimization Tips:**
- Run tests in AWS regions close to your Bedrock endpoint
- Consider implementing BedrockService mocking for faster development cycles
- Use `bin/rails test <specific_test_file>:<line>` to run individual tests
- Run full suite in CI/CD during off-peak hours

## Running the Tests

### Quick Start

```bash
# Run all campaign workflow tests
./test/run_campaign_workflow_tests.sh
```

### Manual Execution

```bash
# Run comprehensive test suite
RAILS_ENV=test bin/rails test test/services/email_campaign_workflow_comprehensive_test.rb

# Run specific test
RAILS_ENV=test bin/rails test test/services/email_campaign_workflow_comprehensive_test.rb:12

# Run with verbose output
RAILS_ENV=test bin/rails test test/services/email_campaign_workflow_comprehensive_test.rb -v
```

## Test Coverage

### 1. Single Message Campaign Creation (2 tests)
- ✅ Creates campaign with all info in single message
- ✅ Creates campaign with minimal info

**What it tests:**
- Original message context extraction
- Phase 1 completion without conversation
- Phase 2 campaign creation
- Phase 3 validation passing

### 2. Multi-Turn Conversation (3 tests)
- ✅ Creates campaign when missing name (asks for it)
- ✅ Handles info provided in reverse order
- ✅ Persists data across multiple turns

**What it tests:**
- Conversational information gathering
- Context persistence in WorkflowContext
- Data loading on workflow resume
- Flexible input order handling

### 3. Context Persistence (2 tests)
- ✅ Workflow context persists across conversation turns
- ✅ Workflow loads previous gathered data on resume

**What it tests:**
- `store_phase_output` functionality
- `load_previous_gathered_data` functionality
- WorkflowContext table integrity

### 4. Phase 2 Execution (2 tests)
- ✅ Phase 2 creates campaign with correct data from Phase 1
- ✅ Phase 2 does not use data from previous workflow executions

**What it tests:**
- Data mapping from Phase 1 to Phase 2
- Workflow execution isolation
- Campaign model field mapping

### 5. Phase 3 Validation (2 tests)
- ✅ Phase 3 validation passes when campaign is created
- ✅ Workflow completes successfully despite validation warnings

**What it tests:**
- AI validation with context data
- Validation rule execution
- Graceful handling of validation warnings

### 6. Workflow Isolation (1 test)
- ✅ Multiple sequential campaigns are isolated

**What it tests:**
- No data leakage between workflow executions
- Unique WorkflowExecution per campaign
- Clean context boundaries

### 7. Post-Workflow Conversation (2 tests)
- ✅ Single word response after workflow does not trigger new workflow
- ✅ New create request after workflow clears post-workflow mode

**What it tests:**
- Post-workflow conversation mode activation
- Planner not invoked for follow-up questions
- Smart detection of new action requests

### 8. Error Handling (2 tests)
- ✅ Workflow handles empty user input gracefully
- ✅ Workflow handles very long campaign names

**What it tests:**
- Edge case handling
- Graceful degradation
- Input validation

### 9. Template Keyword Matching (2 tests)
- ✅ Show campaign request does not trigger campaign creation workflow
- ✅ View campaign list does not trigger campaign creation workflow

**What it tests:**
- Workflow template keyword specificity
- Planner template selection accuracy
- Avoiding false positives

## Total Coverage: 18 Comprehensive Tests

## Test Architecture

### Service Layer Testing
Tests use `InteractiveTaskService` directly (not HTTP requests) for:
- Faster execution
- Direct access to internal state
- Precise assertions on workflow state

### Helper Methods

#### `wait_for_workflow(task_session, status:, timeout:)`
Polls workflow execution status until reaching desired state or timeout.

```ruby
workflow_execution = wait_for_workflow(
  service.task_session,
  status: "completed",
  timeout: 30
)
```

### Setup & Teardown
- Each test gets fresh database state
- Campaigns and workflows cleaned before each test
- Test user and entity created automatically

## Integration with CI/CD

### GitHub Actions Example

```yaml
name: Campaign Workflow Tests

on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2
      - name: Set up Ruby
        uses: ruby/setup-ruby@v1
        with:
          bundler-cache: true
      - name: Setup test database
        run: RAILS_ENV=test bin/rails db:setup
      - name: Run campaign workflow tests
        run: ./test/run_campaign_workflow_tests.sh
```

## Debugging Failed Tests

### View Detailed Logs
```bash
RAILS_ENV=test bin/rails test test/services/email_campaign_workflow_comprehensive_test.rb -v
```

### Check Workflow State
```ruby
# In test failure, add:
puts workflow_execution.status
puts workflow_execution.metadata.inspect
puts workflow_execution.workflow_contexts.pluck(:key, :value).inspect
```

### Common Issues

**Test times out waiting for workflow:**
- Check that WorkflowEngine is updating status correctly
- Verify Phase executors are returning proper status codes
- Check logs for exceptions during execution

**Campaign not created:**
- Verify Phase 2 is executing
- Check `setup_campaign_id` in WorkflowContext
- Look for validation errors on Campaign model

**Context not persisting:**
- Verify `store_phase_output` is being called
- Check WorkflowContext table has entries
- Ensure workflow_execution_id matches

## Performance Benchmarks

Expected test suite execution time: **~2-3 minutes**

Individual test timeout: **30 seconds**

If tests consistently timeout, check:
1. Database connection performance
2. AI model response times
3. Background job processing

## Maintenance

### Adding New Tests

1. Follow naming convention: `test "descriptive name of scenario"`
2. Clean setup in each test (done automatically)
3. Use `wait_for_workflow` helper for async operations
4. Add meaningful assertions with error messages

### Updating Tests After Code Changes

When modifying workflow logic:
1. Run full test suite: `./test/run_campaign_workflow_tests.sh`
2. Update affected tests to match new behavior
3. Add new tests for new features
4. Ensure all 18 tests still pass

## Success Criteria

All tests must pass for deployment:
- ✅ 18/18 tests passing
- ✅ No timeouts
- ✅ All assertions met
- ✅ Clean test output

## Support

For issues with tests:
1. Check test output for specific failure
2. Review workflow logs in test environment
3. Verify database state during test
4. Check CAMPAIGN_WORKFLOW_TESTING.md for debugging tips
