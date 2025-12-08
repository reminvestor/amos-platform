# Scout Tool Architecture Proposal

## The Core Question

**What should Scout do NATIVELY vs DELEGATE to agents?**

Scout's identity: **Orchestrator/Concierge** - NOT a specialist

Scout should be excellent at:
1. Understanding user intent
2. Showing/accessing existing data
3. Knowing which agents can help
4. Delegating appropriately
5. Memory/context management
6. Real-time information access

Scout should NOT:
- Create complex content (landing pages, emails, etc.)
- Build integrations
- Perform complex multi-step workflows
- Do anything a specialist agent does better

---

## Proposed Tool Tiers

### Tier 1: Core System Tools (10-12 tools) - ALWAYS AVAILABLE

These are Scout's "native abilities" - the tools that define what Scout IS.

| Tool | Purpose | Why Core? |
|------|---------|-----------|
| **get_data** | Query CRM data (contacts, campaigns, etc.) | Scout must show user's data |
| **get_schema** | Understand data structure | Needed to use get_data intelligently |
| **query_document_content** | Search uploaded documents | Scout must access knowledge |
| **load_canvas** | Display visual interfaces | Scout's primary way to SHOW things |
| **create_dynamic_visualization** | Create charts/dashboards | Data visualization is core |
| **list_available_agents** | Find specialist agents | Core orchestration |
| **delegate_to_agent** | Hand off to specialists | Core orchestration |
| **respond_to_agent** | Handle agent questions | Core orchestration |
| **web_search** | Real-time information | Scout needs current data |
| **list_connections** | Show integration status | User needs to know what's connected |
| **retrieve_history** | Access past conversation | Memory is core |
| **search_history** | Find specific past topics | Memory is core |

**Total: 12 core tools**

### Tier 2: Configurable Tools (5-10 tools) - USER CHOOSES

These extend Scout's capabilities based on user preference/trust level.

| Tool | Purpose | Why Optional? |
|------|---------|---------------|
| **create_object** | Create contacts, campaigns | Some users want Scout to create |
| **update_object** | Modify existing records | Some users want Scout to edit |
| **execute_integration** | Run integration operations | Power user feature |
| **read_document** | Read specific document | Granular doc access |
| **analyze_dataset** | Complex data analysis | Power user feature |
| **create_scheduled_task** | Schedule future tasks | Automation feature |
| **list_scheduled_tasks** | View scheduled work | Automation feature |
| **manage_scheduled_task** | Edit/cancel schedules | Automation feature |
| **update_landing_page_content** | Quick page edits | Quick edit vs full rebuild |
| **get_work_inbox** | View pending agent work | For workflow-heavy users |

**Total: Up to 10 configurable tools**

### Tier 3: Agent-Only Tools - ALWAYS DELEGATE

These should NEVER be given to Scout - they're specialist work.

```
generate_ai_landing_page        → ai_landing_page_creator
process_landing_page_images     → ai_landing_page_creator
create_agent                    → agent_architect
create_tool                     → tool_builder
create_integration_foundation   → integration_architect
configure_integration_auth      → integration_architect
generate_integration_code       → integration_architect
... (all complex creation tools)
```

---

## Design Philosophy

### Scout's Native Abilities (What Scout IS)

```
┌─────────────────────────────────────────────────────────┐
│                    SCOUT IDENTITY                       │
│                                                         │
│  👁️  SEE      - Show data, documents, visualizations   │
│  🧠  REMEMBER - Conversation history, user context     │
│  🔍  SEARCH   - Web search, document search            │
│  🤝  CONNECT  - Integration status, connections        │
│  🎯  ROUTE    - Find agents, delegate tasks            │
│  💬  TALK     - Converse, explain, advise              │
│                                                         │
└─────────────────────────────────────────────────────────┘
```

### Agent Abilities (What Specialists DO)

```
┌─────────────────────────────────────────────────────────┐
│                   AGENT IDENTITIES                      │
│                                                         │
│  🎨  CREATE   - Landing pages, emails, content         │
│  🔧  BUILD    - Integrations, workflows, tools         │
│  📊  ANALYZE  - Deep analytics, reports, insights      │
│  📥  IMPORT   - Data migration, CSV imports            │
│  🤖  AUTOMATE - Complex multi-step workflows           │
│                                                         │
└─────────────────────────────────────────────────────────┘
```

### The Principle

> **Scout SHOWS and ROUTES. Agents CREATE and BUILD.**

---

## Implementation Changes

### 1. Update ScoutLoadoutConfiguration

```ruby
# app/models/scout_loadout_configuration.rb

# Core tools - ALWAYS available, cannot be removed
CORE_TOOLS = %w[
  get_data
  get_schema
  query_document_content
  load_canvas
  create_dynamic_visualization
  list_available_agents
  delegate_to_agent
  respond_to_agent
  web_search
  list_connections
  retrieve_history
  search_history
].freeze

# Configurable tools - User can enable/disable
CONFIGURABLE_TOOLS = %w[
  create_object
  update_object
  execute_integration
  read_document
  analyze_dataset
  create_scheduled_task
  list_scheduled_tasks
  manage_scheduled_task
  update_landing_page_content
  get_work_inbox
].freeze

# Default configurable tools (what new users get)
DEFAULT_CONFIGURABLE = %w[
  create_object
  update_object
  read_document
].freeze
```

### 2. Update effective_tool_allowlist

```ruby
def effective_tool_allowlist
  # Core tools are ALWAYS included
  tools = CORE_TOOLS.dup
  
  # Add user-configured tools
  if configured_tools.present?
    valid_configured = configured_tools & CONFIGURABLE_TOOLS
    tools += valid_configured
  else
    # Default for new users
    tools += DEFAULT_CONFIGURABLE
  end
  
  tools.uniq
end
```

### 3. Update System Prompt to Match

```ruby
def build_system_prompt(current_canvas = nil)
  # ... existing prompt ...
  
  <<~PROMPT
    ═══════════════════════════════════════════════════════════════
    YOUR NATIVE ABILITIES (always available)
    ═══════════════════════════════════════════════════════════════
    
    👁️  SEE & SHOW DATA
    • get_data - Query contacts, campaigns, landing pages, etc.
    • load_canvas - Display visual interfaces to the user
    • create_dynamic_visualization - Create charts and dashboards
    
    🧠  REMEMBER & RECALL
    • retrieve_history - Get older conversation messages
    • search_history - Find specific topics from past conversation
    
    🔍  SEARCH & DISCOVER
    • web_search - Get real-time information from the web
    • query_document_content - Search uploaded documents
    
    🤝  CONNECT & ORCHESTRATE
    • list_available_agents - Find specialists for tasks
    • delegate_to_agent - Hand off complex work to specialists
    • list_connections - See what integrations are connected
    
    ═══════════════════════════════════════════════════════════════
    WHEN TO USE AGENTS (not your job)
    ═══════════════════════════════════════════════════════════════
    
    🎨  CONTENT CREATION → Delegate
    • "Create a landing page" → ai_landing_page_creator
    • "Build an email campaign" → email_sequence_architect
    • "Write blog content" → content_creator
    
    🔧  BUILDING & INTEGRATION → Delegate
    • "Connect to Stripe" → integration_architect
    • "Build a workflow" → workflow_builder
    • "Create a new tool" → tool_builder
    
    📊  DEEP ANALYSIS → Delegate (for complex analysis)
    • "Analyze my sales funnel" → analytics_agent
    • "Create a revenue report" → analytics_agent
    
    📥  DATA OPERATIONS → Delegate
    • "Import my contacts from CSV" → data_agent
    • "Clean up duplicate contacts" → data_agent
    
    ═══════════════════════════════════════════════════════════════
    THE RULE: If it requires CREATING or BUILDING → DELEGATE
    ═══════════════════════════════════════════════════════════════
  PROMPT
end
```

---

## Token Impact Analysis

### Current State: ~31 tools

```
Average tool definition: ~150 tokens
31 tools × 150 = ~4,650 tokens per request
```

### Proposed: 12 core + 3 default configurable = 15 tools

```
15 tools × 150 = ~2,250 tokens per request
Savings: ~2,400 tokens per request (52% reduction)
```

### Annual Impact (rough estimate)

```
Requests/day: 10,000 (example)
Token savings/request: 2,400
Daily savings: 24M tokens
Monthly savings: 720M tokens
Cost savings: Significant!
```

---

## UI Considerations

### Scout Settings Page

```
┌─────────────────────────────────────────────────────────┐
│  Scout Capabilities                                     │
├─────────────────────────────────────────────────────────┤
│                                                         │
│  CORE ABILITIES (always enabled)                        │
│  ✓ View and query your data                            │
│  ✓ Search documents and web                            │
│  ✓ Remember conversation context                       │
│  ✓ Delegate to specialist agents                       │
│  ✓ Display visualizations                              │
│                                                         │
├─────────────────────────────────────────────────────────┤
│                                                         │
│  EXTENDED ABILITIES (toggle on/off)                     │
│  ☑ Create contacts and campaigns directly              │
│  ☑ Edit existing records                               │
│  ☐ Execute integration operations                       │
│  ☑ Read individual documents                           │
│  ☐ Perform complex data analysis                        │
│  ☐ Manage scheduled tasks                               │
│  ☐ Edit landing page content directly                   │
│                                                         │
│  [Save Preferences]                                     │
│                                                         │
└─────────────────────────────────────────────────────────┘
```

---

## Migration Path

### Phase 1: Define New Constants
- Add CORE_TOOLS and CONFIGURABLE_TOOLS constants
- Don't change behavior yet

### Phase 2: Update effective_tool_allowlist
- New logic that respects tiers
- Existing users keep current tools temporarily

### Phase 3: Update System Prompt
- New prompt structure emphasizing Scout's identity
- Clear delegation instructions

### Phase 4: Add UI
- Settings page for tool configuration
- Default new users to minimal configurable set

### Phase 5: Migrate Existing Users
- Analyze usage patterns
- Set sensible defaults based on actual usage
- Notify users of changes

---

## Open Questions

1. **Should `get_message_count` be core?**
   - Probably not needed if `retrieve_history` and `search_history` exist
   - Scout can infer count from search results

2. **Should `list_operations` and `explain_query` be configurable?**
   - Power user features for integration exploration
   - Probably configurable, not core

3. **What about `invoke_agent_plugin`?**
   - Currently exists alongside `delegate_to_agent`
   - May want to consolidate to just `delegate_to_agent`

4. **Should `save_visualization` be core or configurable?**
   - If Scout can create visualizations, should it save them?
   - Probably configurable

5. **What about `ask_agent_for_help` and `update_agent`?**
   - These are agent management tools
   - Probably not needed for Scout at all - delegate to agent_architect

---

## Recommendation

Start with this 12-core + 3-default-configurable approach:

**Core (12):**
```
get_data, get_schema, query_document_content, load_canvas,
create_dynamic_visualization, list_available_agents, delegate_to_agent,
respond_to_agent, web_search, list_connections, retrieve_history, search_history
```

**Default Configurable (3):**
```
create_object, update_object, read_document
```

**Available Configurable (7 more):**
```
execute_integration, analyze_dataset, create_scheduled_task,
list_scheduled_tasks, manage_scheduled_task, update_landing_page_content, get_work_inbox
```

This gives Scout **15 tools by default** (down from 31) with clear purpose and identity.
