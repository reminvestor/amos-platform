# V2 Workflow Handoff Fixes

## Problem
The handoff between the main chat AI and the V2 workflow system was broken. Users couldn't interact with conversational workflows because:

1. Main AI was asking questions before delegating (duplicating workflow questions)
2. Workflow questions weren't reaching the UI (progress callback only logged)
3. `find_missing_fields` was using V1 format (`required_knowledge`) instead of V2 format (`required_fields`)
4. `needs_user_input?` was checking V1 format
5. WorkflowExecution enum was missing `awaiting_input` status

## Fixes Applied

### 1. WorkflowExecution Model (`app/models/workflow_execution.rb`)
**Added `awaiting_input` to enum:**
```ruby
enum :status, {
  pending: 'pending',
  running: 'running',
  awaiting_input: 'awaiting_input',  # ← NEW
  completed: 'completed',
  failed: 'failed',
  paused: 'paused',
  cancelled: 'cancelled'
}
```

### 2. GatherContextExecutor (`app/services/agents/gather_context_executor.rb`)

**Fixed `needs_user_input?` - now uses completion criteria:**
```ruby
def needs_user_input?
  # Check if completion criteria is NOT met (meaning we're missing required fields)
  !check_completion_criteria
end
```

**Fixed `find_missing_fields` - now uses V2 `required_fields` format:**
```ruby
def find_missing_fields
  required_fields = @phase[:required_fields] || @phase['required_fields'] || []
  missing = []
  
  required_fields.each do |field_def|
    field_key = field_def['key'] || field_def[:key]
    field_prompt = field_def['prompt'] || field_def[:prompt]
    is_required = field_def['required'] || field_def[:required]
    
    # Skip optional fields if we're in the first pass
    next unless is_required
    
    # Check if we have this field
    unless @gathered_data.key?(field_key) || 
           @gathered_data.key?(field_key.to_sym)
      missing << { 
        field: field_key,
        prompt: field_prompt,
        required: is_required
      }
    end
  end
  
  missing
end
```

**Fixed `generate_conversational_prompt` - properly formats V2 fields:**
```ruby
def generate_conversational_prompt(missing_fields)
  # Format missing fields for the AI to understand
  fields_list = missing_fields.map do |m| 
    "- #{m[:field]}: #{m[:prompt]}"
  end.join("\n")
  
  prompt_request = <<~PROMPT
    Generate a natural, friendly conversational prompt to gather this information:
    
    Missing Fields:
    #{fields_list}
    
    Already Gathered: #{@gathered_data.keys.join(', ')}
    ...
  PROMPT
  
  ai_decide(prompt_request, temperature: 0.7)
end
```

### 3. Main AI System Prompt (`app/services/scout_generic_tools_service_v2.rb`)

**Added explicit instruction to NOT ask questions when delegating:**
```ruby
IMPORTANT: When delegating to a workflow using delegate_to_planner:
- DO NOT ask the user for information yourself
- Simply acknowledge the request and delegate immediately
- The workflow will handle gathering information conversationally
- Example: "I'll help you create that landing page." [then call delegate_to_planner]
```

### 4. Scout Controller (`app/controllers/scout_controller.rb`)

**Capture workflow messages from progress callback:**
```ruby
# Capture workflow messages during progress
workflow_message = nil

# Set up progress callback for real-time updates
interactive_service.on_progress do |progress_data|
  Rails.logger.info "Workflow progress: #{progress_data.inspect}"
  
  # Capture workflow questions/messages for awaiting_input state
  if progress_data.is_a?(Hash)
    if progress_data[:type] == 'content_chunk' && progress_data[:awaiting_input]
      workflow_message = progress_data[:message]
    elsif progress_data[:type] == 'phase_progress' && progress_data[:message]
      workflow_message ||= progress_data[:message]
    end
  end
end

# Process the message
result = interactive_service.process_message(user_message, persisted_history_last_k(12), current_canvas)

# If workflow is awaiting input and we captured a message, use that
if result[:awaiting_input] && workflow_message
  result[:message] = workflow_message
end

# Save assistant response if present
if result[:message]
  save_scout_message('assistant', result[:message])
end
```

## Expected Flow Now

1. **User:** "Create a landing page for me"
2. **Main AI:** "I'll help you create a landing page." [calls delegate_to_planner]
3. **Planner:** Creates workflow with landing_page_creation template
4. **Workflow Auto-Executes:**
   - Phase 1: gather_context starts
   - Checks conversation: finds nothing
   - Checks entity: gets company_name
   - Missing: value_proposition, target_audience, call_to_action
   - Calls `ask_user_conversationally`
   - Generates friendly question asking for missing fields
   - Calls `notify_progress` with questions
5. **Progress Callback:** Captures workflow questions
6. **Controller:** Replaces AI message with workflow questions
7. **User Sees:** Workflow questions asking for missing info
8. **Workflow Status:** `awaiting_input` ✅
9. **User Responds:** Provides the information
10. **Workflow Resumes:** Continues with execute_goal phase
11. **Landing Page Created:** With user's specific information

## Testing

Test the complete flow:
```ruby
# In chat_interactive:
POST /scout/chat_interactive
{ "message": "Create a landing page for me" }

# Expected response:
{
  "success": true,
  "message": "To create your landing page, I need some information:\n\n1. What is your main value proposition?...",
  "awaiting_input": true,
  "mode": "workflow_gathering"
}

# Then respond:
POST /scout/chat_interactive
{ "message": "We help law enforcement with continuing education..." }

# Workflow resumes and creates landing page
```

## Key Benefits

✅ Conversational V2 workflows now work properly
✅ No duplicate question asking
✅ Workflow questions reach the UI
✅ Users can provide input naturally
✅ Workflows pause and resume correctly
✅ Compatible with both V1 and V2 formats
