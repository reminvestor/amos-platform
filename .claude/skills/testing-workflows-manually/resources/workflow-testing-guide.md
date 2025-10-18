# Workflow Testing Guide

Comprehensive guide for testing V2 workflow templates.

## Workflow V2 Architecture

V2 workflows use a three-phase structure defined in YAML templates.

### Template Structure

```yaml
name: "Example Workflow"
description: "What this workflow does"
template_version: 2

keywords:
  - "trigger phrase 1"
  - "trigger phrase 2"

phases:
  - name: "Gather Context"
    executor: "Agents::GatherContextExecutor"
    system_prompt: "Gather required information"
    tools:
      - get_workflow_context
      - ask_user

  - name: "Execute Goal"
    executor: "Agents::GoalExecutor"
    system_prompt: "Accomplish the task"
    approach: "structured"  # or "adaptive"
    tools:
      - create_campaign
      - send_email

  - name: "Validate Result"
    executor: "Agents::ValidationExecutor"
    system_prompt: "Verify success"
    validation_criteria:
      - "Campaign was created"
      - "Email was sent"
```

## Testing Approaches

### 1. Manual Browser Testing

**Best for:**
- End-to-end workflow validation
- UI interaction testing
- User experience verification

**Process:**
```bash
# 1. Start application
docker-compose up -d

# 2. Open browser
open http://app.localhost:3000

# 3. Sign in with test user
# Email: admin@test.test
# Password: password123

# 4. Navigate to Scout AI
# URL: /scout

# 5. Enter trigger phrase
"Create a new email campaign"

# 6. Observe workflow execution
# - Check phase transitions
# - Verify tool calls
# - Confirm outputs
```

### 2. Programmatic Testing

**Best for:**
- Workflow engine validation
- Phase executor testing
- Tool integration testing

**Process:**
```ruby
# In Rails console or test file
entity = Entity.first
user = entity.users.first

execution = WorkflowExecution.create!(
  entity: entity,
  user: user,
  template_name: 'create_campaign',
  status: 'in_progress'
)

engine = Agents::WorkflowEngine.new(
  user: user,
  entity: entity,
  workflow_execution: execution,
  template_name: 'create_campaign'
)

# Test single phase
result = engine.execute_phase('Gather Context', user_message: 'Test message')

# Test full workflow
result = engine.execute_workflow(user_message: 'Create campaign named Test')
```

### 3. Viewing Execution Logs

**Best for:**
- Debugging failures
- Understanding flow
- Performance analysis

**Query Executions:**
```ruby
# Recent executions
WorkflowExecution
  .where(template_name: 'create_campaign')
  .order(created_at: :desc)
  .limit(10)

# Execution details
execution = WorkflowExecution.find(123)
puts "Status: #{execution.status}"
puts "Current Phase: #{execution.metadata['current_phase']}"
puts "Errors: #{execution.metadata['errors']}"

# Context data
WorkflowContext
  .where(workflow_execution: execution)
  .each do |ctx|
    puts "#{ctx.context_key}: #{ctx.context_value}"
  end
```

## Phase Testing

### Gather Context Phase

**Purpose:** Collect required information

**Test Checklist:**
- [ ] Checks conversation history first
- [ ] Reviews uploaded files
- [ ] Retrieves entity business profile
- [ ] Only asks user for missing info
- [ ] Stores data in WorkflowContext
- [ ] Transitions to Execute Goal phase

**Test Script:**
```ruby
# Set up context with some data
WorkflowContext.create!(
  workflow_execution: execution,
  context_key: 'campaign_name',
  context_value: 'Summer Sale'
)

# Execute phase
result = engine.execute_phase('Gather Context', user_message: 'Create campaign')

# Verify it used existing context
assert result[:success]
assert_not_includes result[:response], 'What name' # Should not ask again
```

### Execute Goal Phase

**Purpose:** Accomplish the main task

**Test Checklist:**
- [ ] Uses correct approach (structured/adaptive)
- [ ] Calls appropriate tools
- [ ] Maintains context across tool invocations
- [ ] Handles tool failures gracefully
- [ ] Returns structured output
- [ ] Transitions to Validate Result phase

**Structured Approach Test:**
```ruby
# Structured workflows should follow predictable tool sequence
execution.update(metadata: { approach: 'structured' })

result = engine.execute_phase('Execute Goal', user_message: 'Go ahead')

# Verify expected tool calls
tool_calls = execution.reload.metadata['tool_calls']
assert_equal ['create_campaign', 'add_recipients'], tool_calls.map { |c| c['tool'] }
```

**Adaptive Approach Test:**
```ruby
# Adaptive workflows plan tool sequence dynamically
execution.update(metadata: { approach: 'adaptive' })

result = engine.execute_phase('Execute Goal', user_message: 'Create it')

# AI should decide tool sequence
assert result[:success]
assert execution.metadata['tool_calls'].any?
```

### Validate Result Phase

**Purpose:** Verify success and quality

**Test Checklist:**
- [ ] Runs all validation criteria
- [ ] Reports pass/fail for each check
- [ ] Attempts auto-fix on failures (max 2 attempts)
- [ ] Returns comprehensive report
- [ ] Updates execution status to 'completed' or 'failed'

**Test Script:**
```ruby
result = engine.execute_phase('Validate Result', user_message: '')

# Check validation report
assert result[:success]
report = result[:data][:validation_report]

report.each do |check|
  puts "#{check[:criterion]}: #{check[:passed] ? 'PASS' : 'FAIL'}"
  puts "  Details: #{check[:details]}" if check[:details]
end
```

## Integration Testing

### Full Workflow Test

```ruby
require 'test_helper'

class CreateCampaignWorkflowTest < ActiveSupport::TestCase
  def setup
    @entity = entities(:one)
    @user = users(:one)
  end

  test 'creates campaign from start to finish' do
    execution = WorkflowExecution.create!(
      entity: @entity,
      user: @user,
      template_name: 'create_campaign',
      status: 'in_progress'
    )

    engine = Agents::WorkflowEngine.new(
      user: @user,
      entity: @entity,
      workflow_execution: execution,
      template_name: 'create_campaign'
    )

    # Execute full workflow
    result = engine.execute_workflow(
      user_message: 'Create campaign named "Test Campaign" about summer sale'
    )

    assert result[:success]
    assert_equal 'completed', execution.reload.status

    # Verify campaign was created
    campaign = Campaign.accessible_by(@user).find_by(name: 'Test Campaign')
    assert_not_nil campaign
    assert_includes campaign.description, 'summer sale'
  end

  test 'handles missing information by asking user' do
    execution = WorkflowExecution.create!(
      entity: @entity,
      user: @user,
      template_name: 'create_campaign',
      status: 'in_progress'
    )

    engine = Agents::WorkflowEngine.new(
      user: @user,
      entity: @entity,
      workflow_execution: execution,
      template_name: 'create_campaign'
    )

    # Vague request
    result = engine.execute_workflow(user_message: 'Create a campaign')

    # Should ask for campaign name
    assert_includes result[:response], 'name'
    assert_equal 'gather_context', execution.reload.metadata['current_phase']
  end
end
```

## Common Issues

### Phase Not Executing

**Symptoms:**
- Workflow stuck in one phase
- No phase transitions

**Debug:**
```ruby
execution = WorkflowExecution.find(123)
puts "Current phase: #{execution.metadata['current_phase']}"
puts "Phase history: #{execution.metadata['phase_history']}"
puts "Errors: #{execution.metadata['errors']}"

# Check phase executor
executor_class = "Agents::#{execution.metadata['current_phase']}Executor".constantize
puts "Executor class: #{executor_class}"
```

### Tool Not Being Called

**Symptoms:**
- Expected tool not in tool_calls list
- Workflow completes without expected action

**Debug:**
```ruby
# Check available tools for phase
template = YAML.load_file("app/workflow_templates/#{template_name}_v2.yml")
phase = template['phases'].find { |p| p['name'] == 'Execute Goal' }
puts "Available tools: #{phase['tools']}"

# Check tool exists
require 'tools/tool_catalog'
catalog = Tools::ToolCatalog.instance
puts "Tool exists: #{catalog.all_tools.key?('create_campaign')}"
```

### Context Not Persisting

**Symptoms:**
- Workflow asks for same information twice
- Data not available in later phases

**Debug:**
```ruby
execution = WorkflowExecution.find(123)
contexts = WorkflowContext.where(workflow_execution: execution)

puts "Stored contexts:"
contexts.each do |ctx|
  puts "  #{ctx.context_key}: #{ctx.context_value}"
end

# Check context retrieval
tool = Tools::GetWorkflowContextTool.new(
  entity: execution.entity,
  user: execution.user,
  workflow_execution: execution
)
result = tool.execute({ 'key' => 'campaign_name' })
puts "Retrieved: #{result}"
```

### Validation Failing

**Symptoms:**
- Validation phase always fails
- Workflow status set to 'failed'

**Debug:**
```ruby
execution = WorkflowExecution.find(123)
validation_results = execution.metadata['validation_results']

validation_results.each do |check|
  next if check['passed']

  puts "Failed check: #{check['criterion']}"
  puts "Reason: #{check['details']}"
  puts "Fix attempts: #{check['fix_attempts']}"
end
```

## Performance Testing

### Measure Phase Execution Time

```ruby
require 'benchmark'

time = Benchmark.measure do
  engine.execute_phase('Execute Goal', user_message: 'Create it')
end

puts "Phase execution time: #{time.real} seconds"
```

### Track Tool Call Latency

```ruby
execution = WorkflowExecution.find(123)
tool_calls = execution.metadata['tool_calls']

tool_calls.each do |call|
  duration = call['ended_at'] - call['started_at']
  puts "#{call['tool']}: #{duration}s"
end
```

## Best Practices

### Test Data Setup

```ruby
# Use fixtures for consistent test data
@entity = entities(:one)
@user = users(:one)
@campaign_template = email_templates(:welcome)

# Or create specific test data
@entity = Entity.create!(name: 'Test Entity')
@user = @entity.users.create!(
  email: 'test@example.com',
  password: 'password123'
)
```

### Isolate Tests

```ruby
# Use transactions to rollback after each test
self.use_transactional_tests = true

# Or explicitly clean up
teardown do
  WorkflowExecution.where(entity: @entity).destroy_all
  WorkflowContext.where(entity: @entity).destroy_all
end
```

### Mock External Services

```ruby
# Stub AWS Bedrock calls in tests
class BedrockService
  def self.test_mode=(enabled)
    @test_mode = enabled
  end

  def call_claude(messages, tools)
    return mock_response if self.class.test_mode
    # ... real implementation
  end
end

# In test
setup do
  BedrockService.test_mode = true
end
```

## Resources

- [Workflow V2 Docs](../../../docs/V2_PURE_IMPLEMENTATION.md)
- [Phase Executors](../../../app/services/agents/)
- [Workflow Templates](../../../app/workflow_templates/)
- [WorkflowEngine Source](../../../app/services/agents/workflow_engine.rb)
