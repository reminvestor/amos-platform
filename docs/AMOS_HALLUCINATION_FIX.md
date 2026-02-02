# AMOS Hallucination Fix - Stripe Charges Issue

## Status: FIXED

**Fixed Issues:**
- ✅ Model selection from brain icon dropdown now works (was ignoring user's Opus selection)
- See "Model Selection Bug Fix" section below for details

---

## Problem Summary

When a user asked AMOS to pull the last 10 Stripe charges, the following issues occurred:

1. **Wrong Operation Selection**: AMOS tried `list_charges` instead of `stripe.list_charges`
2. **Invalid Parameters**: Passed `{"limit": 10, "order": "desc"}` but `order` isn't a valid Stripe parameter
3. **No Error Learning**: When the 400 Bad Request came back, AMOS didn't analyze WHY
4. **Scheduled Task Workaround**: Created a scheduled task that immediately failed due to insufficient tokens
5. **Hallucinated Response**: Told user "You'll receive a notification within 60 seconds" when the task was paused

## Root Causes

### 1. Duplicate/Conflicting Stripe Operations

The `integration_operations` table has multiple overlapping operations:

```sql
-- Multiple list_charges operations with different IDs
SELECT id, operation_id, name, path_template FROM integration_operations 
WHERE integration_id = 12 AND name ILIKE '%charge%';

-- Results:
-- 157 | stripe.list_charges | List Charges | /v1/charges (cursor pagination)
-- 184 | list charges        | List Charges | /v1/charges (no pagination)
-- 92  | stripe.create_charge | Create Charge | /v1/charges
```

AMOS called `list_charges` (no match) instead of `stripe.list_charges` (exact match).

### 2. Missing Parameter Validation

The AI doesn't know what parameters each operation accepts. It guessed `order: "desc"` which isn't valid.

### 3. Scheduled Task Silent Failure

When the scheduled task was paused due to insufficient tokens, this happened silently:
```
🚫 Auto-pausing scheduled task 12 due to insufficient tokens
```

But AMOS was never informed, so it told the user the task would run.

### 4. Conscience Module Logs But Doesn't Block

The conscience module detected the problem:
```
[CONSCIENCE] 🚨 CRITICAL: Response claims action without tool call!
```

But the response was still sent to the user.

## Fixes Required

### Fix 1: Clean Up Duplicate Operations

```ruby
# lib/tasks/integrations.rake
namespace :integrations do
  desc "Deduplicate Stripe operations"
  task dedupe_stripe: :environment do
    stripe = Integration.find_by(slug: 'stripe')
    
    # Keep operations with 'stripe.' prefix, disable duplicates
    stripe.integration_operations.each do |op|
      if op.operation_id.start_with?('stripe.')
        op.update!(is_enabled: true)
      elsif op.operation_id.include?(' ') # Operations with spaces are duplicates
        op.update!(is_enabled: false)
      end
    end
    
    puts "Stripe operations deduplicated"
  end
end
```

### Fix 2: Add Parameter Schema Validation

```ruby
# app/services/tools/execute_integration_action_tool.rb

def validate_inputs(operation, inputs)
  schema = operation.request_schema
  return true if schema.blank?
  
  invalid_params = inputs.keys - schema.dig('properties')&.keys.to_a
  if invalid_params.any?
    return {
      success: false,
      error: "Invalid parameters: #{invalid_params.join(', ')}. Valid params: #{schema.dig('properties')&.keys&.join(', ')}"
    }
  end
  
  true
end
```

### Fix 3: Scheduled Task Failure Notification

```ruby
# app/jobs/execute_scheduled_agent_task_job.rb

def perform(task_id)
  task = ScheduledAgentTask.find(task_id)
  
  unless task.can_run?
    # Notify the AI about the failure
    if task.user.work_token_balance < 0
      message = "Scheduled task '#{task.name}' was paused due to insufficient tokens. The user needs to add tokens before it can run."
    else
      message = "Scheduled task '#{task.name}' could not run: #{task.blocked_reason}"
    end
    
    # Send notification to user
    UserNotification.create!(
      user: task.user,
      entity: task.entity,
      title: "Scheduled Task Failed",
      body: message,
      notification_type: 'error'
    )
    
    return
  end
  
  # ... rest of execution
end
```

### Fix 4: Conscience Should Block Hallucinations

```ruby
# app/services/amos/conscience_service.rb

def validate_response(response, tools_called)
  issues = detect_issues(response, tools_called)
  
  critical_issues = issues.select { |i| i[:severity] == :critical }
  
  if critical_issues.any?
    Rails.logger.error "[CONSCIENCE] Blocking response due to critical issues: #{critical_issues.map { |i| i[:type] }.join(', ')}"
    
    # Return a safe response instead
    return {
      blocked: true,
      safe_response: generate_safe_response(critical_issues, tools_called),
      issues: issues
    }
  end
  
  { blocked: false, issues: issues }
end

def generate_safe_response(issues, tools_called)
  if issues.any? { |i| i[:type] == :unclaimed_action }
    "I attempted to complete this task but encountered some issues. Let me try a different approach or you can check the Integrations Manager to see available operations."
  else
    "I encountered an issue while processing your request. Please try again or rephrase your request."
  end
end
```

### Fix 5: Better Error Introspection

When a tool fails, inject the error details back to the AI so it can learn:

```ruby
# app/services/amos/orchestrator.rb

def handle_tool_error(tool_name, error, original_inputs)
  error_context = {
    tool: tool_name,
    error: error.message,
    inputs: original_inputs,
    suggestion: suggest_fix(tool_name, error)
  }
  
  # Add to conversation context so AI learns
  @learning_context[:recent_errors] ||= []
  @learning_context[:recent_errors] << error_context
  
  error_context
end

def suggest_fix(tool_name, error)
  case error.message
  when /Bad Request/
    "The parameters may be invalid. Check the operation's request_schema for valid parameters."
  when /Operation not found/
    "The operation name may be incorrect. Try listing operations first with list_operations."
  when /not permitted/
    "This operation requires different permissions. Check if the user has access."
  else
    "Review the error message and try with different parameters."
  end
end
```

### Fix 6: Operation Name Fuzzy Matching

```ruby
# app/services/integration_operation_finder.rb

def find_operation(integration_slug, action_name)
  integration = Integration.find_by(slug: integration_slug)
  return nil unless integration
  
  # Try exact match first
  operation = integration.integration_operations.find_by(operation_id: action_name)
  return operation if operation
  
  # Try with prefix
  operation = integration.integration_operations.find_by(operation_id: "#{integration_slug}.#{action_name}")
  return operation if operation
  
  # Try fuzzy match (name similarity)
  operations = integration.integration_operations.where(is_enabled: true)
  best_match = operations.min_by do |op|
    [
      levenshtein_distance(op.operation_id.downcase, action_name.downcase),
      levenshtein_distance(op.name.downcase, action_name.downcase)
    ].min
  end
  
  if best_match && levenshtein_distance(best_match.operation_id.downcase, action_name.downcase) <= 3
    Rails.logger.info "[IntegrationOperationFinder] Fuzzy matched '#{action_name}' to '#{best_match.operation_id}'"
    return best_match
  end
  
  nil
end
```

## Immediate Actions

1. **Run the deduplication task** for Stripe operations
2. **Add parameter validation** to `execute_integration_action` 
3. **Enable conscience blocking** for critical issues
4. **Add scheduled task failure notifications**

## Testing

```ruby
# test/services/integration_operation_finder_test.rb
class IntegrationOperationFinderTest < ActiveSupport::TestCase
  test "finds operation with stripe. prefix" do
    op = IntegrationOperationFinder.find_operation('stripe', 'list_charges')
    assert_equal 'stripe.list_charges', op.operation_id
  end
  
  test "rejects invalid parameters" do
    result = ExecuteIntegrationActionTool.new.validate_inputs(
      IntegrationOperation.find_by(operation_id: 'stripe.list_charges'),
      { limit: 10, order: 'desc' } # order is invalid
    )
    assert_equal false, result[:success]
    assert_includes result[:error], 'order'
  end
end
```

## Model Selection Bug Fix (COMPLETED)

### Problem

User selected "Claude Opus 4.5" from the brain icon dropdown, but AMOS continued using Qwen.

### Root Cause

1. **`ScoutGenericToolsServiceV2` line 348** unconditionally overwrote `@model`:
   ```ruby
   # BUG: This ignored user's explicit selection
   @model = @preprocess_result[:suggested_model] || 'qwen3-next-80b'
   ```

2. **`amos/scout_tools_service.rb`** never read `model_preference` from message metadata

### Fix Applied

**File: `app/services/scout_generic_tools_service_v2.rb`**
```ruby
# FIXED: Only use preprocessor's model if user didn't explicitly select one
if @model.nil?
  @model = @preprocess_result[:suggested_model] || 'qwen3-next-80b'
  Rails.logger.info "[Scout] Using auto-selected model: #{@model}"
else
  Rails.logger.info "[Scout] 👑 Using user-selected model: #{@model}"
end
```

**File: `app/services/amos/scout_tools_service.rb`**
```ruby
# FIXED: Read user's premium model selection from metadata
model_preference = last_message&.dig(:metadata, :model_preference)

service = ScoutGenericToolsServiceV2.new(
  @user, @entity, @session_id,
  agent_loadout: main_chat_loadout,
  model: model_preference,  # User's explicit selection
  # ... other params
)
```

### How It Works Now

1. User clicks brain icon → selects "Claude Opus 4.5"
2. Frontend saves to `localStorage` AND calls `POST /scout/set_premium_model`
3. Controller stores in `session[:premium_model]`
4. On chat, `selected_model = params[:model] || session[:premium_model]`
5. Passed to Amos via metadata: `model_preference: selected_model`
6. Amos reads from `last_message.dig(:metadata, :model_preference)`
7. Passes to `ScoutGenericToolsServiceV2.new(..., model: model_preference)`
8. Service respects user's choice: `if @model.nil?` → only then auto-select

---

## Long-Term Improvements

1. **Integration Factory Validation**: When operations are created, validate they don't duplicate existing ones
2. **AI-Assisted Schema Discovery**: Let AMOS query for valid parameters before making calls
3. **Error Pattern Learning**: Track common errors and inject guidance proactively
4. **Scheduled Task Dashboard**: Show task status in real-time, including failures
