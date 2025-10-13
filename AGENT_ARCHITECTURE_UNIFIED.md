# Unified Agent Architecture - How Everything Works Together

**Critical Analysis**: Ensuring we don't create two separate systems

---

## Current System (What Already Works)

### Layer 1: Main Chat Agent (AMOS/Scout)
**Location**: `ScoutGenericToolsServiceV2`  
**Role**: Customer conversation + simple tool execution  
**Tools**: Has access to tool catalog (filtered by agent loadout)

**Decision Logic**:
```
Simple Request → Use tools directly
Complex Multi-Step → delegate_to_planner
```

### Layer 2: Workflow System
**Components**:
- **PlannerAgent** - Creates workflow specs
- **WorkflowEngine** - Executes workflows
- **Phase Executors** (V2 - ACTIVE):
  - GatherContextExecutor
  - GoalExecutor ⭐ (This is like a specialized agent!)
  - ValidationExecutor
- **Step Agents** (V1 - Legacy):
  - ExecutorAgent
  - AnalystAgent
  - VerifierAgent
  - FixerAgent

**How It Works**:
```
User: "Create email campaign"
  ↓
AMOS: delegate_to_planner
  ↓
PlannerAgent: Creates workflow → selects template
  ↓
WorkflowEngine: Executes phases
  ↓
GoalExecutor: Uses allowed_tools for that phase
  ↓
Result returned to user
```

---

## Key Insight: Phase Executors ARE Specialized Agents!

Looking at **GoalExecutor**:
```ruby
class GoalExecutor < PhaseExecutor
  def execute
    # Gets allowed_tools from phase definition
    allowed_tools = strategy[:allowed_tools] || []
    
    # Uses ONLY those tools to achieve goal
    execute_adaptively(goal, allowed_tools, ...)
  end
end
```

**This is already a scoped, specialized executor!**

Example from `integration_builder_v2.yml`:
```yaml
- id: "build_rag_store"
  type: "execute_goal"
  execution_strategy:
    allowed_tools:
      - web_search
      - create_rag_store
      - get_workflow_context
```

**GoalExecutor becomes an "Integration Specialist" for this phase!**

---

## The REAL Problem

### Current State:
```
Main AMOS Agent:
  - Has 30+ tools in allowlist ❌
  - Tool overload for simple queries ❌
  - No clear delegation boundaries ❌

Workflow System:
  - Phase Executors with scoped tools ✅
  - Works great for complex tasks ✅
  - But only activated via delegate_to_planner ✅
```

### The Gap:
**When does AMOS use tools directly vs delegate to workflow?**

Currently unclear! AMOS might try to:
- Execute complex integration tasks with all 30 tools ❌
- When it should delegate to a workflow with scoped tools ✅

---

## The CORRECT Solution (No New Agents Needed!)

### Don't Create Separate IntegrationAgent

Instead, **use the existing workflow system better**:

1. **Main AMOS**: Fewer tools, better delegation decisions
2. **Workflows**: Handle ALL complex tasks (including integrations)
3. **Phase Executors**: Act as "specialized agents" with scoped tools

### Updated Architecture:

```
┌──────────────────────────────────────────────────────────┐
│ Layer 1: AMOS (Main Conversation Agent)                  │
│ Tools: Minimal set + delegate_to_planner                 │
│ Role: Conversation + simple queries + delegation         │
└──────────────────┬───────────────────────────────────────┘
                   │
      Simple Task? │ Use tool directly (e.g., get_data)
      Complex Task? ↓ Delegate to planner
                   │
┌──────────────────┴───────────────────────────────────────┐
│ Layer 2: Workflow System                                 │
│ PlannerAgent → Creates workflow with phases              │
└──────────────────┬───────────────────────────────────────┘
                   │
┌──────────────────┴───────────────────────────────────────┐
│ Layer 3: Phase Executors (Specialized Execution)         │
│                                                           │
│ GatherContextExecutor                                     │
│   Tools: get_workflow_context, conversation tools        │
│                                                           │
│ GoalExecutor ⭐ (Dynamic Specialization!)                │
│   Tools: ONLY allowed_tools from phase definition        │
│   Example phases:                                         │
│   - Integration Phase: [execute_integration, list_ops]   │
│   - Data Phase: [get_data, create_object]                │
│   - Content Phase: [generate_landing_page, ...]          │
│                                                           │
│ ValidationExecutor                                        │
│   Tools: Quality checking tools                          │
└───────────────────────────────────────────────────────────┘
```

---

## How They Work Together (Correctly)

### Scenario 1: Simple Query
```
User: "Show my campaigns"
  ↓
AMOS: get_data(object_type: "campaigns")
  ↓
Result: Campaigns displayed
```

**Agent**: Main AMOS only  
**System**: Direct tool execution  
**No Workflow Needed**: ✅

### Scenario 2: Simple Integration Query
```
User: "How many Stripe customers do I have?"
  ↓
AMOS: Should this use delegate_to_planner? 🤔
  
Option A (Current - Might happen):
  AMOS tries to use execute_integration directly
  → Has too many tools to choose from
  → Makes mistakes
  
Option B (Better - With improved delegation):
  AMOS: Recognizes this is simple
  → Uses execute_integration directly
  → Works! ✅
```

**Fix**: Update AMOS system prompt to know when to use execute_integration directly

### Scenario 3: Complex Integration Task
```
User: "Build a Twilio integration"
  ↓
AMOS: Recognizes complexity → delegate_to_planner
  ↓
PlannerAgent: Selects integration_builder_v2 template
  ↓
WorkflowEngine: Executes 9 phases
  ↓
Phase 4 (Build RAG): GoalExecutor
  allowed_tools: [web_search, create_rag_store]
  → Becomes "Integration Specialist" for this phase
  ↓
Phase 5 (Generate Scaffold): GoalExecutor  
  allowed_tools: [generate_integration_scaffold, add_integration_endpoint]
  → Becomes "Code Generator" for this phase
  ↓
Workflow Complete: Integration built
```

**Agent**: AMOS → PlannerAgent → GoalExecutor (with scoped tools per phase)  
**System**: Workflow system ✅  
**Specialized Execution**: Phase executors with allowed_tools ✅

---

## The REAL Fix: Don't Create New Agents!

### What We Actually Need:

1. **Better AMOS Tool Allowlist**
   - Reduce from 30+ to ~10-12 essential tools
   - Keep: execute_integration, get_data, create_object, delegate_to_planner
   - Remove: Workflow-specific tools that should only be in phases

2. **Improved Delegation Logic**
   - AMOS knows when task is simple (use tools) vs complex (delegate)
   - Clear criteria for delegation
   - Integration builder workflow handles complex integration tasks

3. **Phase-Level Specialization** (Already Works!)
   - Workflows define allowed_tools per phase
   - GoalExecutor acts as specialist for that domain
   - No need for separate IntegrationAgent class

---

## Revised Understanding

### Workflow System = Our Multi-Agent System!

**The Phase Executors ARE specialized agents:**

```yaml
# Integration workflow phase
- type: "execute_goal"
  goal: "Build integration"
  allowed_tools: [execute_integration, add_integration_endpoint, ...]
  # GoalExecutor becomes "IntegrationAgent" for this phase!

# Data workflow phase  
- type: "execute_goal"
  goal: "Process customer data"
  allowed_tools: [get_data, create_object, aggregate_artifact_data]
  # GoalExecutor becomes "DataAgent" for this phase!

# Content workflow phase
- type: "execute_goal"
  goal: "Create landing page"
  allowed_tools: [generate_ai_landing_page, ...]
  # GoalExecutor becomes "ContentAgent" for this phase!
```

**The system is already multi-agent! We just need to use it properly!**

---

## Updated Tool Distribution

### AMOS (Main Chat Agent)
**Allowlist** (Reduced to ~12 essential tools):
```ruby
'main_chat' => {
  tool_allowlist: [
    # Delegation
    'delegate_to_planner',
    
    # Simple queries (don't need workflow)
    'get_data',
    'execute_integration',      # For simple integration calls
    'list_operations',
    'list_connections',
    
    # Simple creation (don't need workflow)
    'create_object',
    
    # UI
    'load_canvas',
    
    # Analysis helpers
    'aggregate_artifact_data',
    'create_dynamic_visualization'
  ]
}
```

**Decision Criteria**:
- Simple single-tool task → Use directly
- Multi-step task → delegate_to_planner
- Complex domain task (build integration) → delegate_to_planner

### Workflow Phase Executors (Dynamic Specialization)

**Integration Builder Workflow**:
```yaml
phases:
  - type: execute_goal
    allowed_tools: [web_search, create_rag_store, query_rag_store]
    # GoalExecutor = "Research Specialist"
    
  - type: execute_goal
    allowed_tools: [generate_integration_scaffold, add_integration_endpoint]
    # GoalExecutor = "Code Generation Specialist"
    
  - type: execute_goal
    allowed_tools: [execute_integration, test_integration_endpoint]
    # GoalExecutor = "Testing Specialist"
```

**Landing Page Workflow**:
```yaml
phases:
  - type: execute_goal
    allowed_tools: [generate_ai_landing_page, process_images]
    # GoalExecutor = "Content Generation Specialist"
```

**The specialization happens via allowed_tools, not separate agent classes!**

---

## Correct Delegation Pattern

### Main AMOS System Prompt (Updated)

```
You are AMOS, a business advisor and orchestration assistant.

TOOL USAGE GUIDELINES:

Simple Tasks (Use tools directly):
- "Show my campaigns" → get_data
- "How many Stripe customers?" → execute_integration
- "List my integrations" → list_connections
- "Create a contact" → create_object

Complex Multi-Step Tasks (Delegate to planner):
- "Create an email campaign" → delegate_to_planner
- "Build a Slack integration" → delegate_to_planner  
- "Launch a product campaign" → delegate_to_planner
- "Analyze sales trends and create report" → delegate_to_planner

CRITICAL: If a task requires multiple steps, ALWAYS use delegate_to_planner.
The workflow system will handle it with specialized phase executors.
```

---

## Why This is Better Than New Agents

### ❌ Creating IntegrationAgent, DataAgent, ContentAgent:
- Duplicate of Phase Executor system
- Two ways to do the same thing
- Harder to maintain
- Conflicts with workflow architecture

### ✅ Using Existing Phase Executors:
- Already built and working
- Template-driven (no code changes for new domains)
- Proven architecture
- One system, properly scoped

---

## What We Should Actually Do

### 1. Update Main AMOS Allowlist (30 minutes)
Reduce tool count, improve decision making:

```ruby
# app/models/agent_loadout.rb
# ADD new role for main chat
'main_chat' => {
  tool_allowlist: [
    'delegate_to_planner',
    'get_data',
    'create_object', 
    'execute_integration',
    'list_operations',
    'list_connections',
    'load_canvas',
    'aggregate_artifact_data',
    'create_dynamic_visualization',
    'get_workflow_context',
    'get_my_ai_usage'
  ],
  budgets: { max_tokens: 8000, max_tool_calls: 15 }
}
```

### 2. Update Scout Service to Use New Loadout (15 minutes)
```ruby
# app/services/scout_generic_tools_service_v2.rb
def initialize(user, entity, session_id, context = {})
  # ...
  @agent_loadout = AgentLoadout.new(agent_role: 'main_chat')  # NEW!
  # ...
end
```

### 3. Improve Delegation Prompts (30 minutes)
Update system prompt with clear delegation criteria.

### 4. Create Domain-Specific Workflows (As Needed)
Already have:
- ✅ integration_builder_v2.yml
- ✅ landing_page_creation_v2.yml
- ✅ email_campaign_v2.yml

**GoalExecutor becomes specialist via allowed_tools!**

---

## Corrected Architecture Diagram

```
┌────────────────────────────────────────────────────────────┐
│ AMOS Main Chat Agent                                       │
│ Role: Conversation + Simple Tasks + Delegation            │
│ Tools: ~12 essential tools (reduced from 30+)             │
│                                                            │
│ Decision Logic:                                            │
│   Simple? → Use tool directly                             │
│   Complex? → delegate_to_planner                          │
└────────────────────┬───────────────────────────────────────┘
                     │
                     ↓ delegate_to_planner
┌────────────────────────────────────────────────────────────┐
│ PlannerAgent                                               │
│ Role: Create workflow spec (phases or steps)              │
│ Tools: get_schema, list_connections, list_operations      │
└────────────────────┬───────────────────────────────────────┘
                     │
                     ↓ Workflow created
┌────────────────────────────────────────────────────────────┐
│ WorkflowEngine                                             │
│ Role: Execute workflow phases                             │
└────────────────────┬───────────────────────────────────────┘
                     │
                     ↓ For each phase
┌────────────────────────────────────────────────────────────┐
│ Phase Executors (Dynamic Specialization!)                 │
│                                                            │
│ GatherContextExecutor                                      │
│   - Gathers requirements                                   │
│   - Tools: get_workflow_context, etc.                     │
│                                                            │
│ GoalExecutor ⭐ THE SPECIALIST!                           │
│   - Achieves phase goal                                    │
│   - Tools: ONLY allowed_tools from phase                  │
│   - Becomes domain specialist dynamically:                │
│     * Integration phase → Integration specialist          │
│     * Data phase → Data specialist                        │
│     * Content phase → Content specialist                  │
│                                                            │
│ ValidationExecutor                                         │
│   - Validates results                                      │
│   - Can trigger FixerAgent if issues                      │
└────────────────────────────────────────────────────────────┘
```

---

## Examples: How It Works

### Example 1: Simple Integration Query
```
User: "List my Stripe customers"
  ↓
AMOS: Simple single-tool task
  → execute_integration(integration: "stripe", operation: "list_customers")
  ↓
UniversalIntegrationExecutor → Results
  ↓
AMOS: "Here are your 150 customers [displays]"
```

**Agents Used**: AMOS only  
**Workflow**: NOT needed (simple task)  
**Phase Executors**: NOT used  

### Example 2: Complex Integration Build
```
User: "Build a Twilio integration"
  ↓
AMOS: Complex multi-step task
  → delegate_to_planner("build Twilio integration")
  ↓
PlannerAgent: Selects integration_builder_v2 template
  ↓
WorkflowEngine: Executes 9 phases
  ↓
Phase 2 (Research):
  GoalExecutor with allowed_tools: [web_search]
  → Becomes "Research Specialist"
  ↓
Phase 4 (Build RAG):
  GoalExecutor with allowed_tools: [create_rag_store, web_search]
  → Becomes "Knowledge Base Specialist"
  ↓
Phase 5 (Generate Code):
  GoalExecutor with allowed_tools: [generate_integration_scaffold, add_integration_endpoint]
  → Becomes "Code Generation Specialist"
  ↓
Phase 8 (Build Endpoints):
  GoalExecutor with allowed_tools: [add_integration_endpoint, execute_integration, query_rag_store]
  → Becomes "Integration Development Specialist"
  ↓
Integration complete!
```

**Agents Used**: AMOS → PlannerAgent → GoalExecutor (4 times, different specializations)  
**Workflow**: integration_builder_v2 ✅  
**Phase Executors**: GoalExecutor acts as 4 different specialists! ✅

### Example 3: Data Analysis Task
```
User: "Find customers who haven't purchased in 30 days and create a campaign"
  ↓
AMOS: Multi-step task
  → delegate_to_planner
  ↓
PlannerAgent: Creates custom workflow with 3 phases
  ↓
Phase 1 (Find Customers):
  GoalExecutor with allowed_tools: [get_data, aggregate_artifact_data]
  → Becomes "Data Specialist"
  ↓
Phase 2 (Create Campaign):
  GoalExecutor with allowed_tools: [create_object, get_schema]
  → Becomes "Campaign Specialist"
  ↓
Phase 3 (Validate):
  ValidationExecutor
  → Validates campaign
```

**Agents Used**: AMOS → PlannerAgent → GoalExecutor (2 phases)  
**Dynamic Specialization**: GoalExecutor adapts to each phase! ✅

---

## Key Realization

**GoalExecutor IS a universal specialist agent!**

It becomes whatever specialist is needed based on:
1. **Phase goal** - What needs to be accomplished
2. **Allowed tools** - What tools it can use
3. **Context** - What data it has

**This is more powerful than fixed IntegrationAgent!**

Why? Because GoalExecutor can be:
- Integration specialist (with integration tools)
- Data specialist (with data tools)
- Content specialist (with content tools)
- Research specialist (with search tools)
- ANY specialist based on allowed_tools!

---

## What We Should Do Instead

### Option 1: Optimize Current System (Recommended)

**1. Update AMOS Tool Allowlist** (30 min)
```ruby
'main_chat' => {
  tool_allowlist: [
    'delegate_to_planner',     # For complex tasks
    'get_data',                # Simple data queries
    'create_object',           # Simple object creation
    'execute_integration',     # Simple integration calls
    'list_operations',         # Discover integration capabilities
    'list_connections',        # See available integrations
    'load_canvas'              # UI
  ]
}
```

**2. Improve AMOS System Prompt** (30 min)
Add clear delegation criteria:
```
WHEN TO DELEGATE vs USE TOOLS DIRECTLY:

Use tools directly:
- Single data query: get_data
- Single integration call: execute_integration
- Simple object creation: create_object
- Checking integrations: list_operations

Always delegate to planner:
- Multi-step tasks (2+ tools needed)
- Complex workflows (email campaigns, integrations, product launches)
- Tasks requiring validation
- Tasks with user interaction loops
```

**3. Done!** (1 hour total)

No new agents. Use existing system properly.

### Option 2: Keep Phase Executor System + Add Task Intelligence

Instead of new agents, add **task classification**:

```ruby
# app/services/task_classifier.rb
class TaskClassifier
  def classify(user_request)
    # Use AI to classify:
    # - simple_query
    # - simple_action  
    # - complex_workflow
    # - integration_task
    # - data_task
    # - content_task
    
    # Returns recommended action and tools
  end
end
```

AMOS uses classifier → knows whether to delegate or execute directly.

---

## My Recommendation

**Don't build IntegrationAgent, DataAgent, ContentAgent!**

**Instead**:

1. ✅ **Keep workflow system** - It's already multi-agent via phases
2. ✅ **Reduce AMOS tool count** - From 30+ to ~10-12
3. ✅ **Improve delegation logic** - Clear criteria in system prompt
4. ✅ **Use Phase Executors** - They ARE the specialized agents
5. ✅ **Create workflows for domains** - Already have integration_builder_v2

**Why This Is Better**:
- ✅ One system, not two
- ✅ Already proven and working
- ✅ More flexible (GoalExecutor adapts to any domain)
- ✅ Less code to maintain
- ✅ Leverages existing V2 phase architecture

---

## Immediate Action Plan

### Today (2 hours):

1. **Update agent_loadout.rb** (30 min)
   - Add 'main_chat' role with reduced tools
   - Keep existing roles (planner, executor, analyst, verifier)

2. **Update ScoutGenericToolsServiceV2** (30 min)
   - Use 'main_chat' loadout
   - Update system prompt with delegation criteria

3. **Test** (1 hour)
   - Simple query: "Show campaigns"
   - Simple integration: "List Stripe customers"
   - Complex task: "Build Twilio integration"
   - Verify proper delegation

**Result**: AMOS smarter, proper delegation, one unified system ✅

---

## Does This Make Sense?

**Your concern**: "Don't want two separate ways of doing things"  
**My mistake**: Proposed new agents that duplicate Phase Executors  
**Correct approach**: Use existing workflow system, improve AMOS delegation  

**Should I**:
1. ✅ Abandon IntegrationAgent idea
2. ✅ Keep unified integration system we built (it's good!)
3. ✅ Update AMOS tool allowlist and delegation logic
4. ✅ Use Phase Executors as dynamic specialists

**Thoughts?**

