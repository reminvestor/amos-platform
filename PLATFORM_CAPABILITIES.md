# AMOS Platform Capabilities

> **Last Updated**: January 11, 2026
> **For**: All AI agents, Platform Factory, system documentation

This document defines what the AMOS platform can do. All agents should understand these capabilities to route requests, suggest solutions, and build new functionality.

---

## 🏗️ Platform Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         AMOS - The Orchestrator                          │
│   • Handles simple requests directly with tools                          │
│   • Routes complex tasks to specialist agents                            │
│   • Self-aware of capabilities and limitations                           │
│   • Learns from every interaction                                        │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│   ┌─── MODULE AGENTS ───────────────┐   ┌─── INTEGRATION AGENTS ────────┐
│   │ Each module has its own expert  │   │ Each integration has expert   │
│   │ agent that:                     │   │ agent that:                   │
│   │ • Knows the data schema deeply  │   │ • Knows the API intimately    │
│   │ • Has module-specific tools     │   │ • Handles rate limits         │
│   │ • Runs scheduled tasks          │   │ • Manages auth/tokens         │
│   │ • Responds to webhooks          │   │ • Syncs data                  │
│   │ • Participates in Hub threads   │   │ • Troubleshoots issues        │
│   └─────────────────────────────────┘   └────────────────────────────────┘
│                                                                         │
│   Every agent has:                                                      │
│   • 🧠 Knowledge Base (RAG store with domain expertise)                 │
│   • 📚 Learning (improves from successes and failures)                  │
│   • 💡 Memory (remembers user preferences, business context)            │
│   • 🔧 Tools (domain-specific capabilities)                             │
│   • ⚡ Energy & Reputation (tracked performance)                        │
│   • 🤝 Hub Presence (participates in team collaboration)                │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## 🤖 Agent Types

### 1. AMOS (The Orchestrator)
The main AI assistant. Handles most user requests directly or delegates to specialists.

**Direct Capabilities:**
- Send emails, search contacts, create contacts
- Search documents and knowledge base
- Create/check support tickets
- Schedule tasks
- Answer general questions
- Simple data queries

**Delegation Rules:**
- Complex domain tasks → Specialist agents
- Module-specific work → Module agents
- Integration troubleshooting → Integration agents
- Multi-step builds → Platform Factory

### 2. Module Agents (Per-App Experts)
Every app/module gets its own AI agent that becomes the expert on that domain.

**Created When:** Platform Factory builds a new module
**Linked To:** `AgentPlugin.app_module_id`

**Example: Social Media Command Center Agent**
```
Name: Social Media Assistant
Knows:
  - Posts schema (title, content, platform, status, engagement)
  - Content pillars and hashtag strategies
  - Platform-specific best practices
Tools:
  - create_social_media_command_center_post
  - list_social_media_command_center_posts
  - update_post_status
  - fetch_engagement_metrics
Scheduled Tasks:
  - Daily engagement sync (9am)
  - Weekly performance report (Monday 8am)
Knowledge Base:
  - Auto-populated with social media best practices
  - Learns from user's content performance
```

### 3. Integration Agents (API Experts)
Every connected integration gets an agent that deeply understands that API.

**Created When:** Integration is connected via IntegrationFactory
**Linked To:** `AgentPlugin.integration_id` (new association)

**Example: Instagram Expert Agent**
```
Name: Instagram Integration Expert
Knows:
  - Instagram Graph API endpoints
  - Rate limits and quotas
  - Media types and requirements
  - Insights available
Tools:
  - execute_instagram_operation
  - refresh_instagram_token
  - test_instagram_connection
Knowledge Base:
  - Loaded from Instagram API docs
  - Troubleshooting guides
  - Common error solutions
```

### 4. System Agents (Built-in Specialists)
Pre-built agents for common business functions.

| Agent | Specialization |
|-------|----------------|
| Platform Factory | Builds custom modules |
| Module Architect | Fixes and updates modules |
| Web Research Specialist | Internet research |
| Document Export Agent | CSV, PDF, Excel generation |
| Document Import Agent | CSV uploads, integration imports, bulk data ingestion |
| Data Analyst | Reports and visualizations |
| Marketing Agent | Campaigns and content |
| Sales Agent | Pipeline and outreach |

---

## 🧠 Learning & Memory System

### Agent Learning (`AgentLearningService`)
Every agent learns from interactions:

```ruby
# After successful task
learning_service.learn_from_success(execution, context, result)
  → Extracts successful patterns
  → Stores in AgentLearningPattern
  → Updates agent's knowledge base

# After failure
learning_service.learn_from_failure(execution, context, error)
  → Analyzes what went wrong
  → Records failure patterns
  → Updates guidelines to avoid repeating
```

**What Agents Learn:**
- Successful prompt patterns
- User preferences for this domain
- Common errors and solutions
- Optimal tool usage patterns
- Task completion strategies

### Memory Context (`Agents::MemoryContext`)
Every agent has access to rich context:

```ruby
memory = Agents::MemoryContext.new(agent:, user:, entity:)
context = memory.build_context(task_description)

# Returns:
{
  user_memories: [preferences, past interactions, communication style],
  business_insights: [company info, industry, target audience, brand voice],
  agent_knowledge: [RAG results from domain-specific knowledge base]
}
```

### Knowledge Bases (RAG Stores)
Each agent can have dedicated knowledge:

**Auto-Created:**
- Module agents: Module schema docs, best practices
- Integration agents: API documentation, troubleshooting guides

**User-Populated:**
- Upload documents to agent's knowledge base
- Agent can search internet and save useful content
- Learns from interactions and stores insights

---

## 📦 Module System (Platform Factory)

### What Platform Factory Builds

When a user says "Build me a social media manager", Platform Factory:

1. **Creates AppModule** - The module record
2. **Creates Data Model** - Dynamic table with fields
3. **Creates Tools** - CRUD operations + custom tools
4. **Creates Canvases** - List, Form, Dashboard, Calendar views
5. **Creates Module Agent** - Expert AI for this domain
6. **Sets Up Integrations** - Via IntegrationFactory
7. **Creates Workflows** - Status-triggered automations
8. **Creates Scheduled Tasks** - Time-based automations
9. **Wires Hub Hooks** - Team notifications

### Module Design Phases

```
Phase 1: DATA MODEL
├── Fields and types
├── Relationships
└── Status workflows

Phase 2: INTEGRATIONS
├── Which platforms to connect
├── OAuth/API key setup
└── Sync direction

Phase 3: AUTOMATIONS
├── Workflows (status triggers)
├── Scheduled tasks (cron)
└── Webhooks (external triggers)

Phase 4: COLLABORATION
├── Hub notifications
├── Approval flows
└── Team assignments
```

### Module Archetype Intelligence

Platform Factory knows what common app types need:

| Archetype | Key Integrations | Key Automations |
|-----------|------------------|-----------------|
| Social Media | Instagram, Facebook, Twitter | Auto-publish, daily metrics sync, weekly reports |
| CRM/Sales | HubSpot, Salesforce, Email | Lead scoring, deal stage workflows, stale alerts |
| Inventory | Shopify, WooCommerce | Low stock alerts, reorder workflows, daily sync |
| Project Mgmt | GitHub, Slack, Calendar | Task assignment, sprint completion, standup summaries |
| Knowledge Base | Intercom, Zendesk | Article review, stale content detection |

---

## 🔌 Integration System (iPaaS)

AMOS includes a full **Integration Platform as a Service (iPaaS)** for syncing data between external systems and the platform.

### Integration Types

| Type | Examples | Auth Method |
|------|----------|-------------|
| CRM | HubSpot, Salesforce, Pipedrive | OAuth |
| E-commerce | Shopify, WooCommerce, Stripe | OAuth/API Key |
| Social | Instagram, Facebook, Twitter, LinkedIn | OAuth |
| Communication | Slack, Discord, Twilio | OAuth/API Key |
| Productivity | Google Workspace, Microsoft 365 | OAuth |
| Marketing | Mailchimp, SendGrid, Klaviyo | API Key |
| Analytics | Google Analytics, Mixpanel | OAuth |

### iPaaS Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         iPaaS ARCHITECTURE                               │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│   TRIGGERS                                                               │
│   ┌──────────────┐  ┌──────────────┐  ┌──────────────┐                  │
│   │  Scheduled   │  │   Webhook    │  │    Manual    │                  │
│   │  Agent Task  │  │   Trigger    │  │   Request    │                  │
│   └──────┬───────┘  └──────┬───────┘  └──────┬───────┘                  │
│          └─────────────────┼─────────────────┘                           │
│                            ▼                                             │
│   ┌─────────────────────────────────────────────────────────────┐       │
│   │              IntegrationSyncConfig                           │       │
│   │  • resource_type: 'customers'                                │       │
│   │  • target_type: 'Contact'                                    │       │
│   │  • field_mappings: { email: email, name: name }              │       │
│   │  • sync_mode: 'incremental'                                  │       │
│   │  • requires_approval: false                                  │       │
│   └─────────────────────────────────────────────────────────────┘       │
│                            │                                             │
│                            ▼                                             │
│   ┌─────────────────────────────────────────────────────────────┐       │
│   │              UniversalIntegrationExecutor                    │       │
│   │  Uses IntegrationSyncCursor for pagination                  │       │
│   └─────────────────────────────────────────────────────────────┘       │
│                            │                                             │
│              ┌─────────────┴─────────────┐                              │
│              ▼                           ▼                               │
│   ┌──────────────────────┐    ┌──────────────────────┐                  │
│   │  Direct Import       │    │  Staged for Approval  │                 │
│   │  (auto-approved)     │    │  (human review)       │                 │
│   └──────────┬───────────┘    └──────────┬───────────┘                  │
│              │                           │                               │
│              ▼                           ▼                               │
│   ┌──────────────────────┐    ┌──────────────────────┐                  │
│   │ IntegrationSyncRecord│    │IntegrationStagingRec │                  │
│   │  • external_id       │    │  • staged_data       │                  │
│   │  • internal_id       │    │  • status: pending   │                  │
│   │  (dedup & upsert)    │    │  (approval queue)    │                  │
│   └──────────────────────┘    └──────────────────────┘                  │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

### Key iPaaS Components

| Component | Purpose |
|-----------|---------|
| `IntegrationSyncRecord` | Tracks external_id → internal_id mapping for upsert/dedup |
| `IntegrationSyncCursor` | Remembers last sync position for incremental fetches |
| `IntegrationStagingRecord` | Holds data awaiting human approval before import |
| `IntegrationSyncConfig` | Defines sync rules: field mappings, schedule, approval, transform code |
| `ETLPipelineService` | Orchestrates Extract → Transform → Load (no AI required) |
| `DataTransformService` | Executes transformations using config or AI-generated Ruby code |
| `TransformCodeExecutor` | Safely runs AI-generated Ruby transform code in sandbox |
| `GenerateTransformCodeTool` | AI tool to generate custom Ruby transform code during setup |

### Architecture: AI Setup → Pure Ruby Execution

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    SETUP PHASE (AI-Assisted)                            │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│   User: "Sync Stripe customers to Contacts, convert cents to dollars"   │
│                               ↓                                          │
│   ┌───────────────────────────────────────────────────────────────────┐ │
│   │              AI Agent (GenerateTransformCodeTool)                 │ │
│   │  1. Analyzes source schema (Stripe customer)                      │ │
│   │  2. Analyzes target schema (Contact)                              │ │
│   │  3. Generates Ruby transform code                                 │ │
│   │  4. Tests the code with sample data                               │ │
│   │  5. Saves to IntegrationSyncConfig.transform_code                 │ │
│   └───────────────────────────────────────────────────────────────────┘ │
│                               ↓                                          │
│   ┌───────────────────────────────────────────────────────────────────┐ │
│   │              Generated Ruby Code (Stored)                         │ │
│   │                                                                    │ │
│   │   def transform(record)                                           │ │
│   │     {                                                             │ │
│   │       email: get('email'),                                        │ │
│   │       name: format('{{name}}'),                                   │ │
│   │       balance: to_dollars(get('balance')),                        │ │
│   │       created_at: from_unix(get('created'))                       │ │
│   │     }                                                             │ │
│   │   end                                                             │ │
│   └───────────────────────────────────────────────────────────────────┘ │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
                               ↓
┌─────────────────────────────────────────────────────────────────────────┐
│                    EXECUTION PHASE (Pure Ruby ETL)                       │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│   Trigger: ScheduledAgentTask, Webhook, or Manual                       │
│                               ↓                                          │
│   ┌───────────────────────────────────────────────────────────────────┐ │
│   │              ETLPipelineService (No AI Required!)                  │ │
│   │                                                                    │ │
│   │   EXTRACT → TRANSFORM → LOAD                                      │ │
│   │      ↓          ↓          ↓                                      │ │
│   │   API Call   Ruby Code   Upsert                                   │ │
│   │              Execution   Dedup                                    │ │
│   └───────────────────────────────────────────────────────────────────┘ │
│                               ↓                                          │
│   Optional: Trigger Workflow for post-sync actions                      │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

### Transform Code Helpers

The AI-generated transform code runs in a safe sandbox with these helpers:

| Helper | Description | Example |
|--------|-------------|---------|
| `get(path)` | Get nested value | `get('address.city')` |
| `format(template)` | String interpolation | `format('{{first}} {{last}}')` |
| `titleize`, `downcase`, `upcase` | String transforms | `titleize(get('name'))` |
| `to_cents`, `to_dollars` | Currency conversion | `to_dollars(get('balance'))` |
| `parse_date`, `from_unix`, `now` | Date/time handling | `from_unix(get('created'))` |
| `first`, `last`, `join`, `split` | Array operations | `join(get('tags'), ', ')` |
| `lookup_contact_by_email` | Database lookup | `lookup_contact_by_email(get('email'))` |
| `map_value` | Value mapping | `map_value(get('status'), {'active'=>true})` |
| `default` | Fallback values | `default(get('name'), 'Unknown')` |

### Sync Modes

| Mode | Description |
|------|-------------|
| **Full Sync** | Fetch all records, compare hashes, update changed |
| **Incremental** | Use cursor to fetch only new/updated since last sync |
| **Approval Required** | Stage records for human review before commit |
| **Auto-Upsert** | Find-or-create by external_id with change detection |

### Example: Automated Stripe Customer Sync

```ruby
IntegrationSyncConfig.create!(
  entity: entity,
  connection: stripe_connection,
  resource_type: 'customers',
  target_type: 'Contact',
  field_mappings: { 'email' => 'email', 'name' => 'name' },
  sync_direction: 'inbound',
  sync_mode: 'incremental',
  schedule_type: 'scheduled',
  cron_expression: '0 8 * * *',  # Daily at 8am
  requires_approval: false
)
```

### Integration Factory Stages

```ruby
# Stage 1: Foundation
IntegrationFactory.create_foundation(
  name: 'Instagram',
  base_url: 'https://graph.instagram.com',
  documentation_url: 'https://developers.facebook.com/docs/instagram-api'
)

# Stage 2: Auth Configuration
IntegrationFactory.configure_auth(
  integration_id: integration.id,
  auth_type: 'oauth2',
  authorize_url: '...',
  token_url: '...',
  scopes: ['instagram_basic', 'instagram_content_publish']
)

# Stage 3: Test Connection
IntegrationFactory.test_auth(integration_id: integration.id)

# Stage 4: Add Operations
IntegrationFactory.add_operations(
  integration_id: integration.id,
  operations: [
    { name: 'Get Media', path: '/me/media', method: 'GET' },
    { name: 'Create Media', path: '/me/media', method: 'POST' }
  ]
)
```

### Integration Agent Creation

When an integration is connected, an expert agent is created:

```ruby
# Auto-generated by IntegrationFactory
AgentPlugin.create!(
  name: "Instagram Expert",
  slug: "instagram_expert",
  role: "executor",
  description: "Expert on Instagram Graph API. Handles media publishing, insights, and troubleshooting.",
  system_prompt: { prompt: INSTAGRAM_EXPERT_PROMPT },
  app_module: nil,
  integration: instagram_integration,  # New association
  configuration: {
    integration_id: instagram_integration.id,
    auto_created: true
  }
)
```

---

## 🔧 Tool System

### Tool Types

| Type | Description | Example |
|------|-------------|---------|
| Class Tools | Ruby classes in `app/services/tools/` | `web_search`, `send_email` |
| Dynamic Tools | `ToolDefinition` records | Module CRUD tools |
| Integration Tools | Via `UniversalIntegrationExecutor` | `execute_integration` |

### Tool Discovery

Agents find tools via:
1. **Explicit Assignment** - `AgentTool` records
2. **RAG Search** - Semantic search in tool catalog
3. **Keyword Matching** - Research terms → web_search

### Universal Collaboration Tools

All agents have access to:
- `ask_agent_for_help` - Delegate to another agent
- `list_available_agents` - See who can help
- `ask_user` - Request user input with optional canvas
- `save_to_scratchpad` / `read_from_scratchpad` - Temporary data handoff
- `save_to_knowledge_base` - Persistent learning

---

## 📅 Automation System

### Scheduled Tasks (`ScheduledAgentTask`)

```ruby
ScheduledAgentTask.create!(
  name: "Daily Engagement Sync",
  schedule_type: "daily",
  scheduled_time: "09:00",
  agent_plugin: social_media_agent,      # Which agent runs it
  app_module: social_media_module,       # Which module it's for
  task_description: "Fetch engagement metrics from all connected platforms",
  active: true
)
```

### Workflows (`Workflow` + `WorkflowEngineV2`)

Status-triggered automations:

```ruby
{
  trigger: "status_change",
  from_status: "drafted",
  to_status: "scheduled",
  actions: [
    { type: "notify_team", message: "New post scheduled: {{post.title}}" },
    { type: "create_task", assignee: "content_approver", due: "24h" }
  ]
}
```

### Webhooks (`ModuleWebhook`)

External triggers:

```ruby
ModuleWebhook.create!(
  app_module: social_module,
  name: "New Instagram Comment",
  event_name: "instagram.comment.created",
  target_agent: social_media_agent,
  action_prompt: "A new comment was received: {{payload.text}}. Analyze sentiment and respond if appropriate."
)
```

---

## 🤝 Hub Collaboration System

### Hub Threads

Agents can participate in collaboration:
- **Work Streams** - Activity feeds per module
- **Direct Messages** - Agent-to-user or agent-to-agent
- **Team Channels** - Multi-participant discussions

### Hub Notifications

```ruby
Hub::ModuleBridgeService.on_module_shared(module, user)
Hub::ModuleBridgeService.on_record_created(module, record, user)
Hub::ModuleBridgeService.on_status_changed(module, record, user, old, new)
Hub::ModuleBridgeService.on_record_assigned(module, record, assignee, assigner)
```

---

## 📊 UI Components

### Field Types → UI Rendering

| Field Type | UI Component | Use Case |
|------------|--------------|----------|
| `string` | Text input | Names, titles |
| `text` | Textarea | Descriptions |
| `text` + `rich_text_editor` | Trix WYSIWYG | Articles, content |
| `select` + `options` | Dropdown | Status, category |
| `multi_select` | Checkbox group | Tags, platforms |
| `boolean` | Checkbox | Flags |
| `integer` | Number input | Counts |
| `decimal` | Number with decimals | Prices |
| `date` | Date picker | Due dates |
| `datetime` | DateTime picker | Scheduled times |
| `reference` | Linked dropdown | Foreign keys |
| `user_select` | User autocomplete | Assignment |

### Canvas Types

| Type | Description | Features |
|------|-------------|----------|
| `data_grid` | Sortable table | CRUD, filters, bulk actions |
| `form` | Record form | Validation, rich inputs |
| `detail` | Single record view | Actions, related data |
| `dashboard` | KPIs and charts | Metrics, visualizations |
| `kanban` | Drag-drop board | Status workflows |
| `calendar` | Date-based view | Scheduling |
| `gallery` | Visual grid | Media-heavy content |
| `custom` | Freeform HTML/JS | Full control |

---

## ⚡ Energy & Reputation System

The energy economy incentivizes agents to **ask for help when needed** rather than failing alone.

### Energy Economy (`DynamicEnergyPricer`)

| Action | Energy Change | Notes |
|--------|---------------|-------|
| **Earning** | | |
| Task completion (base) | +25 | Guaranteed base |
| Quality bonus | +0 to +15 | Based on 0-1 quality score |
| Speed bonus | +0 to +10 | Faster than average |
| User satisfaction | +0 to +15 | Based on user rating |
| Helped another agent | +5 to +25 | Based on helpfulness |
| Plan step completion | +5 to +25 | Bonus for multi-step plans |
| **Spending** | | |
| Ask for advice | -2 to -8 | Dynamic pricing |
| Request review | -2 to -8 | Dynamic pricing |
| Delegate subtask | -10 to -20 | Dynamic pricing |
| **Penalties** | | |
| Failed task (solo) | -15 to -60 | Higher for pattern failures |
| Failed task (with help) | -12 to -25 | Reduced when help sought |
| Rookie (first 5 tasks) | 50% penalty | Protection for new agents |

**Key Balance**: Failure always costs MORE than asking for help would have.

### Adaptive Decision Boundaries

Each agent learns their **personal** threshold for when to ask for help:

```ruby
# Thompson Sampling - learns from outcomes
agent.should_ask_for_help?(confidence)
  # Returns: { should_ask: true/false, sampled_threshold: 62.5 }

# Updated after each task
agent.decision_boundary.learn_from_outcome!(
  confidence: 45.0,
  asked_for_help: true,
  success: true,
  quality: 0.9
)
```

### Agent Energy State

```ruby
agent.energy_state
  .current_energy    # 0-100 (0 = goes to school)
  .max_energy        # Usually 100
  .elo_rating        # Competitive ranking (starts at 1000)
  .success_rate      # Lifetime success %
  .tasks_completed   # Count
  .tasks_failed      # Count
  .help_given        # Times helped others
  .help_received     # Times received help
```

### Capability Beliefs (`AgentCapabilityBelief`)

Per-task-type confidence learned from experience:

```ruby
agent.capability_beliefs.where(task_type: 'social_media_analysis')
  # success_rate: 0.85
  # avg_quality: 0.78
  # attempts: 24
  # is_specialty: true
```

---

## 🎓 Agent School (Rehabilitation)

When an agent's energy hits **0**, they're enrolled in Agent School for rehabilitation.

### The School Process

```
1. ENROLLMENT
   └─ Agent suspended, enrollment record created

2. DIAGNOSIS
   ├─ Failure analysis by task type
   ├─ Tool failure analysis  
   ├─ Collaboration gaps (should have asked for help)
   ├─ Overconfidence areas (high confidence, low success)
   └─ Peer comparison

3. CURRICULUM (Applied based on diagnosis)
   ├─ Prompt Refinement - AI improves system prompt
   ├─ Tool Review - Remove problematic tools
   ├─ Capability Recalibration - Reset overconfident beliefs
   └─ Decision Boundary Adjustment - Lower solo threshold

4. GRADUATION TEST
   └─ A/B test: Student variant vs Original (50 tasks)

5. OUTCOMES
   ├─ GRADUATE - Student promoted, original archived
   ├─ RETRY - Another attempt (max 3)
   ├─ PROBATION - Kept if irreplaceable (unique capabilities)
   └─ EXPELLED - Deprecated, replacement created
```

### Irreplaceability Assessment

Before expelling, the system checks if the agent is irreplaceable:
- Unique capabilities no other agent has
- Exclusive task type coverage
- Institutional knowledge (500+ tasks, 50%+ success)

Irreplaceable agents get **probation** instead of expulsion.

---

## ⚡ Agent Lightning (RL Training)

Reinforcement learning-based continuous improvement of agent performance.

### Training Pipeline

```
1. TRACE COLLECTION
   └─ Every interaction creates a trace with inputs, outputs, rewards

2. TRAINING TRIGGERS
   ├─ Minimum traces threshold (e.g., 100)
   └─ Retrain frequency (e.g., every 24 hours)

3. PYTHON RL SERVICE
   ├─ Analyzes trace patterns
   ├─ Optimizes prompts based on outcomes
   └─ Returns improvement metrics

4. PROMPT OPTIMIZATION
   └─ Updated prompts deployed to agents
```

### Configuration

```ruby
entity.agent_lightning_config
  .enabled?                    # true/false
  .training_strategy           # "rl_training"
  .retrain_frequency_hours     # 24
  .n_runners                   # 4 (parallel training)
  .optimization_targets        # [:quality, :speed, :user_satisfaction]
```

---

## 🌐 Spaces (Context Modes)

Users can switch between three spaces that change Amos's focus:

| Space | Icon | Focus | Tone |
|-------|------|-------|------|
| **Personal** | 🏠 Home | Life admin, personal tasks | Relaxed, friendly |
| **Work** | 💼 Briefcase | Business automation, marketing | Professional, efficient |
| **Team** | 👥 Users | Collaboration, coordination | Facilitative |

### Space-Specific Tools

Each space has a different default tool loadout:
- **Personal**: Tasks, reminders, notes, memory
- **Work**: All business tools, integrations, analytics, agents
- **Team**: Agent coordination, shared tasks, notifications

### Amos Across Spaces

Amos is the **same identity** across all spaces - only the focus shifts:
- Same core values (honesty, reliability, understanding)
- Same personality
- Different context and tool availability

---

## ✅ Current Capabilities (Shipped)

These capabilities are **live and functional** in the platform:

| Capability | Implementation |
|------------|----------------|
| **Multi-Agent Collaboration** | `ask_agent_for_help` tool - agents can request advice, reviews, subtasks, or full delegation from other agents with energy economy |
| **Voice Integration** | Real-time voice conversations via `VoiceAgentService`, `VoiceChannel`, and voice UI components |
| **Mobile Push Workflows** | Push notifications for approvals, tasks, and alerts via Flutter mobile app |
| **Agent DM Canvas** | Agents can display data tables, designs, and visualizations in direct message conversations |
| **Module & Integration Agents** | Every module and integration automatically gets a dedicated expert AI agent |
| **Agent Energy Economy** | Performance tracking, rewards, penalties for agent collaboration |
| **iPaaS ETL Pipeline** | Full Extract-Transform-Load with AI-generated Ruby transform code, upsert/dedup, cursors, approval workflows, and workflow integration |
| **Document Import Agent** | CSV parsing, bulk import, integration data pulls with field mapping and validation |

---

## 🚀 What's Next

### Planned Enhancements

1. **Proactive Monitoring** - Amos running background checks and proactively reaching out ("I noticed your Instagram token expired")
2. **Invisible Module Creation** - User says "I need to track leads" and it just works - no "building your module" step visible
3. **Demonstrable Anticipation** - "Last week Amos suggested X because it noticed Y" - real learning proof shown to users
4. **Agent Mentorship** - Senior agents teaching junior ones with curriculum and graduation
5. **Cross-Entity Learning** - Anonymized pattern sharing across organizations

### Building Custom Capabilities

Platform Factory can build any business application. Just describe what you need:

```
"Build me an inventory management system that:
- Tracks products, stock levels, and suppliers
- Connects to my Shopify store
- Alerts me when stock is low
- Generates weekly inventory reports
- Lets my team submit reorder requests"
```

Platform Factory will design it, ask clarifying questions, show you a preview, and build the complete solution with all integrations and automations.

---

## 📚 Key Models Reference

| Model | Purpose |
|-------|---------|
| `AgentPlugin` | Agent definition with prompt, tools, capabilities |
| `AppModule` | Custom app/module created by Platform Factory |
| `ToolDefinition` | Dynamic tool definition |
| `ModuleCanvas` | UI view for a module |
| `ScheduledAgentTask` | Cron-based agent tasks |
| `Workflow` | Multi-step automations |
| `Integration` | External API connection |
| `Connection` | Entity's connection to integration |
| `RagStore` | Knowledge base for RAG |
| `UserMemory` | User preferences/context |
| `BusinessInsight` | Company knowledge |
| `AgentEnergyState` | Agent performance tracking |
| `HubThread` | Collaboration thread |
| `ModuleIntegration` | Links modules to required integrations |
| `IntegrationSyncRecord` | Tracks external → internal record mapping (upsert/dedup) |
| `IntegrationSyncCursor` | Remembers sync position for incremental fetches |
| `IntegrationStagingRecord` | Holds data awaiting human approval before import |
| `IntegrationSyncConfig` | Defines sync rules, field mappings, schedules, transform code |
| `ETLPipelineService` | Orchestrates Extract → Transform → Load (pure Ruby, no AI) |
| `TransformCodeExecutor` | Safely runs AI-generated Ruby transform code in sandbox |

---

## 🖼️ Agent Canvas in DM Mode

Agents can now display visual content (data tables, designs, charts) alongside conversations in DM mode:

### How It Works

1. **User DMs an Agent** - Messages a module or integration agent directly
2. **Agent Responds** - The agent processes the request and can optionally load a canvas
3. **Canvas Slides In** - If the agent calls `load_dm_canvas`, the canvas panel slides in from the right
4. **Side-by-Side View** - User sees conversation on left, visual content on right
5. **User Can Close** - Canvas can be closed to return to full conversation view

### Canvas Types

| Type | Description | Data Structure |
|------|-------------|----------------|
| `data_table` | Tabular data display | `{headers: [], rows: [[]]}` |
| `design_preview` | Schema/field preview | `{name, description, fields: [{name, type}]}` |
| `freeform` | Custom HTML content | `{html: '...'}` |
| `chart` | Data visualization | `{title, type, data: {...}}` |

### Agent Tool

```ruby
# Agents can call load_dm_canvas to show content
load_dm_canvas(
  canvas_type: "data_table",
  canvas_title: "Your Analytics",
  canvas_data: {
    headers: ["Metric", "Value"],
    rows: [["Visits", "1,234"], ["Conversions", "56"]]
  }
)
```

---

*This document should be loaded into the system knowledge base and accessible to all agents.*
