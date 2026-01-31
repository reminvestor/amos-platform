# AMOS Platform Capabilities

> **Last Updated**: January 24, 2026
> **For**: Platform documentation, system understanding

This document defines what the AMOS platform can do.

---

## 🏗️ Platform Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         AMOS - The Orchestrator                          │
│                                                                          │
│   • Handles ALL user requests directly with tools                        │
│   • Dynamic guidance provides task-specific expertise                    │
│   • Self-aware of capabilities and limitations                           │
│   • Memory across conversations                                          │
│                                                                          │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│   ┌─── DYNAMIC GUIDANCE ─────────────────────────────────────────────┐  │
│   │ Task-specific expertise injected based on context:               │  │
│   │                                                                   │  │
│   │ • Landing Page Editing → HTML/CSS expertise + section tools      │  │
│   │ • Workflow Design → Automation expertise + workflow tools        │  │
│   │ • CRM Tasks → Contact/pipeline expertise + CRM tools             │  │
│   │ • Email Campaigns → Marketing expertise + email tools            │  │
│   │ • Data Analysis → Analytics expertise + query tools              │  │
│   │ • Integration Setup → API expertise + connection tools           │  │
│   └───────────────────────────────────────────────────────────────────┘  │
│                                                                          │
│   ┌─── TOOL SYSTEM ──────────────────────────────────────────────────┐  │
│   │ • Core Tools: Always available (memory, web search, canvas)     │  │
│   │ • Task Tools: Loaded based on detected task type                 │  │
│   │ • User Tools: Custom tools created via Tool Factory              │  │
│   │ • Integration Tools: Execute operations on connected platforms   │  │
│   └───────────────────────────────────────────────────────────────────┘  │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## 🤖 AMOS (The Orchestrator)

AMOS is the **single AI assistant** that handles everything. No delegation to separate agents - dynamic guidance provides specialized expertise when needed.

**Core Capabilities:**
- Landing pages: Create, edit, update sections, change colors, modify layouts
- Workflows: Design automations, set up triggers, configure actions
- CRM: Manage contacts, pipelines, opportunities, lead scoring
- Email: Create templates, send campaigns, set up sequences
- Data queries: Get contacts, list campaigns, show analytics, check statuses
- Simple edits: Update a field, change a name, toggle a setting
- Quick lookups: Check integration status, find a record, show history
- Memory operations: Remember things, recall context, search history
- Web research: Search the web for current info, sports, news, prices
- Browse websites: Interactive browsing or screenshot capture
- Tool discovery: Dynamically find tools when needed

**How Dynamic Guidance Works:**
1. User sends a message
2. System detects task type from canvas context + message content
3. Relevant guidance (expertise) is injected into AMOS's prompt
4. Task-specific tools are prioritized in the toolset
5. AMOS handles the request with full capability

---

## 🧬 AI Model Strategy

### Open-Source First Philosophy
To avoid vendor lock-in and maintain strategic flexibility, AMOS defaults to open-source models via AWS Bedrock's unified API.

### Current Default Model
**Qwen3-Next-80B** - Primary model for most tasks
- Excellent instruction-following
- Strong tool execution
- Good reasoning capabilities

### Model Selection by Task Type

| Task Type | Primary Model | Rationale |
|-----------|---------------|-----------|
| **General/Orchestration** | Qwen3-Next-80B | Best balance of capability and speed |
| **Complex Reasoning** | DeepSeek R1 | Extended thinking for complex analysis |
| **Multimodal** | Qwen3-VL-235B | Vision + language tasks |
| **Quick Tasks** | Qwen3-Next-80B | Fast, efficient |

### Two-Phase Architecture
Smart request routing to minimize tokens and optimize model selection:

```
┌─────────────────────────────────────────────────────────────────┐
│               PHASE 1: PARALLEL PREPROCESSING                    │
│  • Intent classification (~50ms)                                 │
│  • Canvas routing (rule-based + LLM fallback)                   │
│  • Dynamic guidance selection                                    │
│  • Tool discovery via RAG                                        │
└─────────────────────────────────────────────────────────────────┘
                              │
              ┌───────────────┴───────────────┐
              ▼                               ▼
┌─────────────────────────┐     ┌─────────────────────────────────┐
│  NO TOOLS NEEDED        │     │  TOOLS NEEDED                   │
│  Model: Qwen3           │     │  Model: Qwen3                   │
│  Tools: NONE            │     │  Tools: Selective (5-15 only)   │
│  Tokens: ~500           │     │  Tokens: ~2,000 (vs 15,000)     │
└─────────────────────────┘     └─────────────────────────────────┘
```

---

## 📦 Module System

### What Modules Are
Modules are custom business applications built within the platform. Each module has:
- **Data Model** - Custom fields and relationships
- **Canvases** - List, form, dashboard, calendar views
- **Tools** - CRUD operations + custom tools
- **Workflows** - Status-triggered automations
- **Scheduled Tasks** - Time-based automations

### Building Modules
AMOS builds modules directly when users request them:

```
User: "Build me a social media manager"
AMOS: Uses create_app_module, configure tools, set up integrations
```

No separate "Platform Factory" agent - AMOS handles it with the right tools.

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
| Accounting | QuickBooks, Xero | OAuth |

### Key iPaaS Components

| Component | Purpose |
|-----------|---------|
| `IntegrationSyncRecord` | Tracks external_id → internal_id mapping for upsert/dedup |
| `IntegrationSyncCursor` | Remembers last sync position for incremental fetches |
| `IntegrationStagingRecord` | Holds data awaiting human approval before import |
| `IntegrationSyncConfig` | Defines sync rules: field mappings, schedule, approval, transform code |
| `ETLPipelineService` | Orchestrates Extract → Transform → Load (pure Ruby, no AI) |

---

## 🔧 Tool System

### Tool Types

| Type | Description | Example |
|------|-------------|---------|
| Class Tools | Ruby classes in `app/services/tools/` | `web_search`, `send_email` |
| Dynamic Tools | `ToolDefinition` records | Module CRUD tools |
| Integration Tools | Via `UniversalIntegrationExecutor` | `execute_integration` |
| User-Created Tools | Built via Tool Factory | Custom automations |

### Core Tools (Always Available)

These tools are always available to AMOS:

| Tool | Purpose |
|------|---------|
| `get_data` | Query any object type in the system |
| `get_schema` | Understand data structure before modifying |
| `create_object` | Create records |
| `update_object` | Modify records |
| `delete_object` | Remove records |
| `web_search` | Search the internet |
| `view_web_page` | Browse websites (interactive or screenshot) |
| `discover_tools` | Find tools by description |
| `remember` | Save to memory |
| `recall` | Search memory |
| `execute_integration` | Run integration operations |

### Tool Discovery
When AMOS needs a tool that isn't in the current set, it can use `discover_tools` to search for relevant tools by description.

---

## 📄 Core Data Objects

### Understanding Before Acting

**CRITICAL**: Always understand the data structure before modifying objects:
1. Call `get_schema(object_type: "xxx")` to see available fields
2. Use the RIGHT tool for each object type

### Landing Pages

**Key Fields:**
- `id` - Unique identifier
- `title` - Page title
- `slug` - URL-friendly identifier
- `status` - "draft" or "published"
- `html_content` - The actual HTML content

**Editing Landing Pages:**
Use `edit_landing_page_section` for surgical edits:
```
edit_landing_page_section(
  landing_page_id: 166,
  section_identifier: "hero",
  instruction: "Change the background color to #0A2D5C"
)
```

### Contacts

**Key Fields:**
- `id`, `first_name`, `last_name`, `email`, `phone`
- `status` - "active", "unsubscribed", etc.

**Modifying Contacts:**
Use `update_object(object_type: "contact", id: X, data: {...})`

### Custom Modules

For modules, use:
- `get_schema(object_type: "module_slug")` to see the schema
- `get_data(object_type: "module_slug")` to query records
- `update_object(object_type: "module_slug", id: X, data: {...})` to modify

---

## 📅 Workflow System

### Visual Workflow Designer
Users can visually design automations with:
- **Triggers**: Record events, webhooks, scheduled times, manual
- **Actions**: Send email, create record, update record, API calls
- **Logic**: Conditions, branches, loops
- **Transforms**: Data formatting, calculations
- **Agent Tasks**: AI-powered processing steps

### Compilation
Workflows are designed visually, then **compiled** into deterministic execution steps. AI assists in design, but execution is pure code - reliable and fast.

```
Design (visual) → Compile → Execute (deterministic)
```

---

## 🌐 Canvas System

Canvases are dynamic views that display in the right panel of the chat interface.

### Canvas Types

| Canvas | Purpose |
|--------|---------|
| `default` | Dashboard with quick actions |
| `landing_page_viewer` | Browse and manage landing pages |
| `landing_page_editor` | Edit a specific landing page |
| `workflow_designer` | Visual workflow builder |
| `app_designer` | Drag-and-drop app builder |
| `integrations_manager` | Connect and manage integrations |
| `document_viewer` | View and analyze documents |
| `crm_pipeline` | Kanban-style pipeline view |
| `freeform` | Custom HTML/data display |

### Canvas Context
AMOS automatically knows which canvas is open and what's being viewed. When editing a landing page, AMOS knows the page ID and current content without asking.

---

## 🧠 Memory System

### Tiered Memory
AMOS has a tiered memory system:

| Layer | Purpose | Retention |
|-------|---------|-----------|
| L1 (Short-term) | Current conversation | Session |
| L2 (Working) | Recent context | Days |
| L3 (Long-term) | Important memories | Permanent |

### Fresh Start
Users can do a "Fresh Start" which:
- Sets a timestamp - messages before that are ignored
- Clears working context
- Long-term memories persist

---

## ✅ Current Capabilities (Shipped)

| Capability | Description |
|------------|-------------|
| **Direct Handling** | AMOS handles all tasks directly - no delegation overhead |
| **Dynamic Guidance** | Task-specific expertise injected based on context |
| **Voice Integration** | Real-time voice conversations |
| **Visual Workflows** | Drag-and-drop workflow designer with compilation |
| **Landing Page Editor** | Surgical HTML section editing |
| **iPaaS ETL Pipeline** | Full Extract-Transform-Load with AI-generated transforms |
| **Integration OAuth** | Connect to 100+ platforms via OAuth |
| **Document Processing** | Upload, OCR, and query documents |

---

## 🚀 What's Next

### Planned Enhancements

1. **Proactive Monitoring** - AMOS running background checks and proactively reaching out
2. **Invisible Module Creation** - "I need to track leads" and it just works
3. **Workflow Templates** - Pre-built automation recipes
4. **Enhanced RL Loop** - Continuous improvement of guidance and tool selection

---

## 📚 Key Models Reference

| Model | Purpose |
|-------|---------|
| `AgentPlugin` | Loadout definitions (deprecated as separate agents) |
| `AppModule` | Custom app/module |
| `ToolDefinition` | Dynamic tool definition |
| `ModuleCanvas` | UI view for a module |
| `Workflow` | Visual workflow design |
| `AutomationExecution` | Workflow execution record |
| `Integration` | External API connection |
| `Connection` | Entity's connection to integration |
| `ScoutMessage` | Conversation history |
| `UserMemory` | User preferences/context |
| `BusinessInsight` | Company knowledge |
| `LandingPage` | Landing page content |

---

---

## 🪙 Token Economy

AMOS includes a built-in token economy for contributor ownership:

### How It Works

| Component | Description |
|-----------|-------------|
| **Earning** | Contributors earn AMOS tokens for approved work |
| **Revenue Share** | 50% of platform revenue distributed to token holders |
| **Governance** | Token holders vote on features, budgets, strategy |
| **Decay** | Stakes decay over time to encourage ongoing participation |
| **Trading** | Tokens tradeable on Solana DEXs |

### Related Documentation

- [Simple Whitepaper](docs/whitepaper_simple.md) - Easy overview
- [Technical Whitepaper](docs/whitepaper_technical.md) - Full mechanics
- [Founding Charter](docs/founding_charter.md) - Constitutional principles

---

## 📜 License

AMOS is open source under the [Apache License 2.0](LICENSE).

---

*This document reflects the current architecture as of January 2026.*
