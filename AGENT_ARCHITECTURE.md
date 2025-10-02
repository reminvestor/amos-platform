# Agent Architecture - Proper Division of Responsibilities

## Core Principle
**Separation of Planning from Execution**

Each specialized agent has a distinct role in the workflow system. Agents should never cross boundaries into other agents' responsibilities.

## V2 vs V1 Workflows

### V2: Phase-Based (ACTIVE - Default for all new workflows)
- **Structure**: Workflows have `phases` (gather_context → execute_goal → validate_result)
- **Execution**: Uses Phase Executors (`GatherContextExecutor`, `GoalExecutor`, `ValidationExecutor`)
- **Style**: Conversational, adaptive, intelligent
- **Use case**: Complex multi-step workflows that need flexibility
- **User interaction**: Natural conversation through phases
- **Detection**: `template_version: 2` or `phases` present in workflow

### V1: Step-Based (LEGACY - Reserved for future manual workflows)
- **Structure**: Workflows have `steps` (individual granular actions)
- **Execution**: Uses Specialized Agents (`ExecutorAgent`, `AnalystAgent`, `VerifierAgent`)
- **Style**: Prescribed, step-by-step, deterministic
- **Use case**: User-specified step-by-step workflows or shortcuts (future feature)
- **User interaction**: Follow predefined sequence
- **Detection**: No `template_version` or `steps` present in workflow

**Current Status**: Everything routes to V2. V1 exists for future use when users want to create custom step-by-step automations.

---

## V2 Phase Executors (ACTIVE SYSTEM)

### 1. GatherContextExecutor 📋
**Responsibility**: Intelligently collect all required information

**What it does**:
- Checks uploaded files for context (PDFs, images, docs)
- Reviews conversation history for mentioned details
- Uses entity profile data
- Asks user conversationally ONLY for missing info
- Extracts data from documents automatically

**Smart behavior**:
- Doesn't ask for what it already has
- Infers reasonable defaults
- Confirms assumptions vs asking from scratch
- Groups related questions naturally

### 2. GoalExecutor 🎯
**Responsibility**: Accomplish the main task adaptively

**What it does**:
- Executes the core workflow goal
- Uses tools adaptively to achieve objective
- Can chain multiple tools intelligently
- Self-heals if approaches fail
- Makes intelligent decisions

**Capabilities**:
- Adaptive execution (figures out how to do it)
- Tool chaining (multiple tools in sequence)
- Self-healing (tries alternative approaches)
- Context-aware (uses gathered info intelligently)

### 3. ValidationExecutor ✅
**Responsibility**: Verify the goal was achieved properly

**What it does**:
- Validates outputs meet requirements
- Checks quality criteria
- Verifies completeness
- Can trigger fixes via FixerAgent
- Provides success/failure feedback

---

## V1 Specialized Agents (LEGACY - For Future Use)

These agents are used in V1 step-based workflows only:

### 1. PlannerAgent 🎯
**Responsibility**: Create workflow plans ONLY

**What it does**:
- Analyzes user requests
- Decomposes complex tasks into steps
- Selects appropriate workflow templates
- Assigns agent roles to each step
- Estimates costs and duration
- Identifies dependencies

**What it does NOT do**:
- ❌ Execute workflow steps
- ❌ Run tools
- ❌ Modify data
- ❌ Interact with external systems

**Agent role assignment rules**:
- Assigns `agent_role: "executor"` for action steps
- Assigns `agent_role: "analyst"` for analysis steps
- Assigns `agent_role: "verifier"` for validation steps
- **NEVER** assigns `agent_role: "planner"` to execution steps

### 2. ExecutorAgent ⚙️
**Responsibility**: Execute workflow steps and perform actions

**What it does**:
- Executes tool_call steps
- Runs API calls
- Creates/updates/deletes data
- Invokes integrations
- Handles file operations
- Manages state changes

**Capabilities**:
- `tool_execution`
- `api_integration`
- `state_management`
- `error_recovery`
- `resource_coordination`

### 3. AnalystAgent 🧠
**Responsibility**: Think, analyze, and adapt workflows

**What it does**:
- Analyzes data and extracts insights
- Recognizes patterns
- Generates reports
- Makes decisions based on data
- **Analyzes workflow progress**
- **Suggests workflow modifications** (when things aren't working as expected)

**Capabilities**:
- `data_analysis`
- `pattern_recognition`
- `insight_generation`
- `report_creation`
- `trend_analysis`
- `performance_metrics`
- `workflow_analysis` ← NEW
- `adaptive_planning` ← NEW

**Use cases in workflows**:
- Analyze landing page requirements
- Extract business info from user requests
- Determine next best action based on context
- Suggest workflow adjustments if needed

### 4. VerifierAgent ✓
**Responsibility**: Validate results and verify requirements

**What it does**:
- Validates step outputs
- Checks data integrity
- Verifies requirements are met
- Ensures quality standards
- Confirms successful completion

**Capabilities**:
- `result_validation`
- `quality_assurance`
- `requirement_checking`
- `compliance_verification`

## Workflow Execution Flows

### V2 Flow (ACTIVE)
```
1. User Request
   ↓
2. PlannerAgent creates V2 workflow plan with phases
   ↓
3. Workflow Engine detects V2 (template_version: 2 or phases present)
   ↓
4. Route to execute_v2_workflow()
   ↓
5. Phase 1: GatherContextExecutor
   ├─ Check workflow_context (uploaded files)
   ├─ Check conversation_history
   ├─ Check entity_profile
   └─ Ask user conversationally (only for missing info)
   ↓
6. Phase 2: GoalExecutor
   ├─ Adaptively execute goal using allowed tools
   ├─ Chain tools as needed
   ├─ Self-heal on failures
   └─ Make intelligent decisions
   ↓
7. Phase 3: ValidationExecutor
   ├─ Verify outputs meet criteria
   ├─ Check quality standards
   └─ Trigger FixerAgent if needed
   ↓
8. Complete - Show results to user
```

### V1 Flow (LEGACY - Future Feature)
```
1. User Request
   ↓
2. PlannerAgent creates V1 workflow plan with steps
   ↓
3. Workflow Engine detects V1 (no template_version, has steps)
   ↓
4. Route to start_workflow()
   ↓
5. For each step:
   ├─ Check agent_role assigned in plan
   ├─ Route to appropriate agent:
   │  ├─ ExecutorAgent (most common)
   │  ├─ AnalystAgent (for thinking/analysis)
   │  └─ VerifierAgent (for validation)
   ↓
6. Agents execute their assigned steps
   ↓
7. Results flow back to Workflow Engine
   ↓
8. If step fails → FixerAgent attempts recovery
```

## Example: Landing Page Creation Workflow (V2)

### Phase 1: Gather Context
```json
{
  "id": "discovery",
  "type": "gather_context",
  "name": "Understand Requirements",
  "required_fields": [
    { "key": "business_name", "prompt": "What's your business name?" },
    { "key": "target_audience", "prompt": "Who is this page for?" },
    { "key": "main_goal", "prompt": "What should visitors do?" }
  ],
  "context_sources": [
    "workflow_context",      // Check uploaded files first
    "conversation_history",  // Review chat
    "entity_profile",        // Use known data
    "direct_conversation"    // Ask user (last resort)
  ]
}
```
**GatherContextExecutor** handles this:
- Checks if user uploaded brand guide → extracts business info
- Checks if user uploaded images → analyzes for brand colors
- Reviews conversation → looks for business details mentioned
- Only asks user for truly missing information

### Phase 2: Execute Goal
```json
{
  "id": "creation",
  "type": "execute_goal",
  "name": "Build Landing Page",
  "goal": "Create a professional, conversion-optimized landing page",
  "execution_strategy": {
    "approach": "adaptive",
    "allowed_tools": [
      "generate_ai_landing_page",
      "update_landing_page_content",
      "get_workflow_context"
    ]
  },
  "requires_from_previous": ["business_context", "design_preferences"]
}
```
**GoalExecutor** handles this:
- Uses gathered context intelligently
- Calls `generate_ai_landing_page` with all collected info
- If that fails, tries alternative approach
- Can chain tools to achieve goal

### Phase 3: Validate Result
```json
{
  "id": "validation",
  "type": "validate_result",
  "name": "Quality Check",
  "validation_criteria": {
    "required_outputs": ["landing_page_id"],
    "quality_checks": ["responsive_design", "has_cta"]
  }
}
```
**ValidationExecutor** handles this:
- Verifies landing page was created
- Checks quality criteria
- Can invoke FixerAgent if issues found

## Key Architectural Changes Made

### V2 Routing (Primary Changes)

1. **Updated PlannerAgent to Generate V2 Workflows**
   - Planning prompt now generates `phases` instead of `steps`
   - Sets `template_version: 2` in all new workflows
   - Creates 3-phase structure: gather_context → execute_goal → validate_result

2. **Fixed Auto-Execution Routing**
   - `interactive_task_service.rb` now detects V2 workflows
   - Routes V2 workflows to `execute_v2_workflow()` 
   - Routes V1 workflows to `start_workflow()` (legacy path)

3. **Updated Template Adaptation**
   - Preserves V2 `phases` structure when using templates
   - Falls back to V1 `steps` for legacy templates

### V1 Cleanup (Legacy Support)

4. **Removed `execute_step` from PlannerAgent**
   - PlannerAgent never executes - only plans
   - V1 specialized agents handle step execution

5. **Updated PlannerAgent V1 prompts**
   - Never assigns `agent_role: "planner"` to execution steps
   - Uses: `executor`, `analyst`, or `verifier`

6. **Enhanced AnalystAgent capabilities**
   - Added `workflow_analysis` capability
   - Added `adaptive_planning` capability
   - Can suggest workflow modifications

7. **Added `get` method to SharedContext**
   - Ensures consistency across all agents
   - Both `@context.read()` and `@context.get()` work

## Benefits of V2 Phase-Based Approach

✅ **Conversational UX** - Natural interaction through phases
✅ **Intelligent Context Gathering** - Doesn't ask for what it already has
✅ **Adaptive Execution** - AI figures out how to accomplish goals
✅ **Self-Healing** - Can recover from failures automatically
✅ **Flexible** - Handles complex, multi-step workflows elegantly
✅ **User-Friendly** - No rigid forms, natural conversation
✅ **Efficient** - Extracts data from uploads automatically

## Anti-Patterns to Avoid

### V2 Phase-Based (Active)
❌ **Don't** generate `steps` in new workflows - use `phases`
❌ **Don't** create rigid question forms - be conversational
❌ **Don't** ask users for info you can extract from uploads
❌ **Don't** route V2 workflows to V1 execution path

### V1 Step-Based (Legacy)
❌ **Don't** assign `agent_role: "planner"` to execution steps
❌ **Don't** make PlannerAgent execute steps
❌ **Don't** use V1 for new features - V2 is the default

