# Scalable Workflow Architecture - Deep Dive

## Core Philosophy

**The system should be template-driven and LLM-guided, NOT hardcoded.**

Every new workflow capability should be added by:
1. Creating a new YAML template
2. No code changes required
3. LLM automatically discovers and uses it

## The Correct Flow

### 1. **User Request** → Main Chat AI
```
User: "Create an email campaign"
↓
Main AI analyzes request
↓
Decision: Simple query OR complex task?
  - Simple → Answer directly
  - Complex → delegate_to_planner tool
```

**Main AI System Prompt Location:** `app/services/scout_generic_tools_service_v2.rb`

**Key Rule:**
```
CRITICAL DELEGATION RULE:
When you call delegate_to_planner:
1. Briefly acknowledge (1 sentence max)
2. Call the tool
3. STOP - do not ask questions
```

---

### 2. **Planner Agent** → Template Selection

**Code:** `app/services/planner_agent_service.rb`

**Process:**
```ruby
def plan_workflow(request_text, context = {})
  # 1. Gather available templates
  planning_context = gather_planning_context(request_text, context)
  #    ↳ Gets templates from WorkflowTemplate.active_with_files
  #    ↳ Gets available tools from ToolCatalog
  
  # 2. Let LLM decide
  llm_result = generate_llm_plan(request_text, planning_context)
  #    ↳ LLM sees all templates
  #    ↳ LLM decides: use template OR create custom plan
  #    ↳ Returns { template_to_use: "slug" } OR { phases: [...] }
  
  # 3. Build workflow
  if llm_result[:template_slug]
    workflow = build_workflow_from_template(template)
  else
    workflow = build_workflow_from_llm_phases(llm_result)
  end
end
```

**Planner Prompt:** `build_planner_prompt` method

**Key Section:**
```
AVAILABLE WORKFLOW TEMPLATES:
#{context[:available_templates].map { |t| "- #{t[:slug]}: #{t[:description]}" }.join("\n")}

PLANNING GUIDELINES:
1. Check if any existing templates match - set "template_to_use" to slug
2. If using template, system uses template's phases (ignore custom steps)
3. If no template matches, set "template_to_use" to null and create phases
```

---

### 3. **Workflow Execution** → Phase-Based

**Code:** `app/services/workflow_engine.rb#execute_v2_workflow`

**Process:**
```ruby
def execute_v2_workflow(workflow_spec, initial_inputs = {})
  phases = workflow_spec['phases']
  
  phases.each do |phase|
    case phase['type']
    when 'gather_context'
      executor = Agents::GatherContextExecutor.new(phase, context)
    when 'execute_goal'
      executor = Agents::GoalExecutor.new(phase, context)
    when 'validate_result'
      executor = Agents::ValidationExecutor.new(phase, context)
    end
    
    result = executor.execute
    
    # If awaiting_input, pause workflow
    return { status: 'awaiting_input', message: result[:message] } if result[:status] == 'awaiting_input'
    
    # Continue to next phase
  end
end
```

---

## Template Format (V2)

### Minimal Example: `landing_page_creation.yml`

```yaml
template_version: 2
name: "Create AI-Powered Landing Page"
slug: "landing_page_creation"
description: "Interactive workflow to create landing pages"

phases:
  - id: "gather_context"
    type: "gather_context"
    name: "Gather Requirements"
    goal: "Collect business information"
    
    required_fields:
      - key: "company_name"
        prompt: "What is your company name?"
        required: true
        validation: "text"
      - key: "value_proposition"
        prompt: "What is your main value proposition?"
        required: true
        validation: "text"
    
    context_sources:
      - "direct_conversation"
      - "conversation_history"
      - "entity_profile"
  
  - id: "execute_goal"
    type: "execute_goal"
    name: "Generate Landing Page"
    goal: "Create landing page with gathered info"
    
    requires_from_previous:
      - company_name
      - value_proposition
    
    execution_strategy:
      approach: "adaptive"
      allowed_tools:
        - generate_ai_landing_page
      
      success_when:
        landing_page_id_exists: true
    
    ai_instructions: |
      Use generate_ai_landing_page tool with the gathered data.
      Ensure the landing_page_id is returned.
  
  - id: "validate_result"
    type: "validate_result"
    name: "Verify Creation"
    
    validation_criteria:
      required_outputs:
        - landing_page_id
    
    success_message: "Landing page created successfully!"
```

---

## Current Issues & Fixes

### Issue 1: Email Campaign Template is V1 Format
**Problem:** Uses `required_knowledge` (nested hash) instead of `required_fields` (array)

**Fix:** ✅ Updated to V2 format with simple `required_fields`

### Issue 2: Success Criteria Not Properly Checked
**Problem:** `meets_success_criteria?` was accepting ANY successful tool call

**Fix:** ✅ Now checks:
- If only read-only tools (get_schema, get_data) → NOT success
- If `success_when` criteria defined → Check each one
- Properly evaluates `campaign_id_exists`, `landing_page_id_exists`, etc.

### Issue 3: Goal is Multi-Step but AI Only Executes One Action
**Problem:** AI creates action plan with only `get_schema`, then stops

**Why:** The AI is being too conservative in its planning

**Solution:** The `ai_instructions` in the phase must be VERY explicit about ALL steps required

---

## How to Add New Templates (Scalable Approach)

### Step 1: Create YAML Template

**File:** `app/workflow_templates/my_new_workflow.yml`

```yaml
template_version: 2
name: "My New Workflow"
slug: "my_new_workflow"
description: "What this workflow does"
category: "my_category"

keywords:
  - keyword1
  - keyword2

phases:
  - id: "gather_context"
    type: "gather_context"
    required_fields:
      - key: "field_name"
        prompt: "Question to ask user"
        required: true
    context_sources:
      - "direct_conversation"
  
  - id: "execute_goal"
    type: "execute_goal"
    goal: "What to accomplish"
    execution_strategy:
      allowed_tools:
        - tool_name
      success_when:
        some_id_exists: true
    ai_instructions: |
      EXPLICIT step-by-step instructions for the AI
  
  - id: "validate_result"
    type: "validate_result"
    validation_criteria:
      required_outputs:
        - output_field
```

### Step 2: That's It!

- ✅ Planner automatically discovers it
- ✅ LLM matches it based on keywords/description
- ✅ Workflow engine executes it
- ✅ No code changes needed

---

## Critical Points for Consistency

### 1. Template Discovery
**Location:** `PlannerAgentService#gather_planning_context`

```ruby
available_templates = WorkflowTemplate.active_with_files.map do |template|
  {
    name: template.name,
    slug: template.slug,
    description: template.description,
    keywords: template.metadata['keywords'] || [],
    category: template.category
  }
end
```

This gets templates from:
- **Database:** `WorkflowTemplate` records
- **Files:** YAML files in `app/workflow_templates/`

### 2. LLM Template Selection
**Location:** `PlannerAgentService#find_matching_template` (if used) OR built into `generate_llm_plan`

The LLM receives:
```
AVAILABLE WORKFLOW TEMPLATES:
- landing_page_creation: Interactive workflow to create landing pages
- email_campaign: Create email campaigns conversationally
```

And decides:
```json
{
  "template_to_use": "landing_page_creation",
  "reasoning": "User wants to create a landing page"
}
```

### 3. Phase Execution
**Each phase type has its own executor:**
- `gather_context` → `Agents::GatherContextExecutor`
- `execute_goal` → `Agents::GoalExecutor`
- `validate_result` → `Agents::ValidationExecutor`

**These are GENERIC** - they work for ANY template!

---

## Where Things Break (Current Analysis)

### ❌ Problem 1: AI Only Executes First Action
**Symptom:** Gets schema, says "Goal achieved!" without creating campaign

**Root Cause:**  
The AI in `GoalExecutor#get_ai_action_plan` creates a plan with only ONE action when it should create MULTIPLE actions in sequence.

**Why:**
The prompt might not be explicit enough that ALL steps must be included in ONE action plan.

**Fix Needed:**
Make `get_ai_action_plan` prompt more explicit:
```
You MUST include ALL steps needed to achieve the goal in a single action plan.
Do not return only discovery steps - include the actual creation/modification steps.
```

### ❌ Problem 2: Success Criteria Mismatch
**Symptom:** Workflow says complete but nothing created

**Root Cause:**
- Template has `success_when: { campaign_created: true }`
- But `meets_success_criteria?` was checking `result[:success]` for empty criteria
- Schema retrieval returns `success: true` with no campaign_id

**Fix Applied:** ✅
- Check if only read-only tools were used
- Require actual creation tools to be executed
- Properly evaluate `success_when` criteria

---

## Testing the Full Flow

### Test 1: Landing Page (Already Working ✅)
1. User: "Create a landing page"
2. Main AI: delegates to planner
3. Planner: Matches "landing_page_creation" template
4. Workflow: gather_context → execute_goal → validate
5. Result: Landing page created, editor opens

### Test 2: Email Campaign (Should Work Now)
1. User: "Create an email campaign"
2. Main AI: delegates to planner
3. Planner: Matches "email_campaign" template (now V2)
4. Workflow: gather_context → execute_goal (creates campaign) → validate
5. Result: Campaign created with ID

### Test 3: Custom Request (Needs Testing)
1. User: "Analyze my campaign performance and create a report"
2. Main AI: delegates to planner
3. Planner: NO template matches
4. Planner: Creates custom V2 workflow with phases
5. Workflow: Executes custom phases
6. Result: Report generated

---

## Key Files to Monitor

1. **Template Discovery:** `app/services/planner_agent_service.rb#gather_planning_context`
2. **Template Matching:** LLM decision in `generate_llm_plan`
3. **V2 Detection:** `build_workflow_from_plan` checks for `phases` key
4. **Phase Execution:** `app/services/workflow_engine.rb#execute_v2_workflow`
5. **Success Evaluation:** `app/services/agents/goal_executor.rb#meets_success_criteria?`

---

## To Make It Truly Scalable

### Current State:
- ✅ Templates auto-discovered from files/DB
- ✅ LLM selects templates intelligently
- ✅ V2 phase executors are generic
- ⚠️ AI action planning needs to be more complete
- ⚠️ Success criteria evaluation needs refinement

### Recommendations:

1. **Update Remaining V1 Templates to V2**
   - Convert all templates in `app/workflow_templates/` to use `required_fields`
   - Ensure `success_when` criteria are explicit

2. **Improve AI Action Planning**
   - Make the prompt in `get_ai_action_plan` more directive
   - Require AI to include ALL steps, not just discovery

3. **Add Template Validation**
   - Validate templates on load
   - Ensure all required keys present
   - Check success_when matches available checks

4. **Add Logging/Debugging**
   - Log when templates are discovered
   - Log LLM's template selection reasoning
   - Log phase execution progress

Would you like me to implement these improvements?
