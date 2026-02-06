# AI Agents Folder Organization

## 📁 Final Structure - Everything Under `ai_agents/`

All AI agent code is now consolidated in one place for easier maintenance and navigation.

```
app/services/ai_agents/
├── 📄 Marketing Agents (User-Facing Content Generation)
│   ├── base_agent.rb               # Base class for marketing agents
│   ├── planning_agent.rb           # Multi-step workflow coordinator
│   ├── coordination_agent.rb       # Agent collaboration manager
│   ├── content_agent.rb            # Blog posts, emails, social media
│   ├── headline_agent.rb           # Catchy headlines
│   ├── design_agent.rb             # Design suggestions
│   ├── image_prompt_agent.rb       # AI image prompts
│   ├── landing_page_dsl_agent.rb   # Complete landing pages
│   ├── seo_agent.rb                # SEO optimization
│   ├── web_search_agent.rb         # Web research
│   └── vector_store.rb             # RAG integration
│
├── 📁 pipeline/  (AI Development Pipeline - Internal Automation)
│   ├── base_agent.rb               # Base class for pipeline agents
│   ├── clarifier_agent.rb          # Ticket analysis & clarification
│   ├── planner_agent.rb            # Implementation planning
│   ├── coder_agent.rb              # Code generation (11-step workflow)
│   ├── reviewer_agent.rb           # Security & quality review
│   ├── workspace_manager.rb        # Isolated /tmp workspaces
│   ├── orchestrator.rb             # Pipeline coordinator
│   └── state_machine.rb            # 14-state workflow engine
│
├── 📁 mcp/  (Model Context Protocol - External Integrations)
│   ├── manager.rb                  # Multi-tenant MCP connection manager
│   ├── client.rb                   # Base MCP client
│   ├── jira_client.rb              # JIRA Cloud API v3
│   └── azure_devops_client.rb      # Azure DevOps REST API v7.0
│
└── 📁 notifiers/  (Notification Services)
    ├── slack_notifier.rb           # Slack Web API + Block Kit
    └── email_notifier.rb           # Mailgun HTML emails
```

---

## 🎯 Why This Structure?

### **Single Location for All AI Agents**
- **Before**: Scattered across `ai_agents/`, `agents/`, `pipeline/`, `mcp/`, `notifiers/`
- **After**: Everything in `ai_agents/` with clear subdirectories
- **Benefit**: One place to find all AI agent code

### **Clear Separation by Purpose**
- **Top-level files**: User-facing marketing agents (Scout chat)
- **`pipeline/`**: Internal dev automation (ticket → production)
- **`mcp/`**: External system integrations (JIRA, Azure DevOps)
- **`notifiers/`**: Communication channels (Slack, Email)

### **Easier Navigation**
```ruby
# Old (scattered)
app/services/agents/clarifier_agent.rb        # Pipeline agent
app/services/ai_agents/content_agent.rb       # Marketing agent
app/services/pipeline/orchestrator.rb         # Pipeline logic
app/services/mcp/jira_client.rb               # External integration

# New (consolidated)
app/services/ai_agents/content_agent.rb              # Marketing
app/services/ai_agents/pipeline/clarifier_agent.rb  # Pipeline
app/services/ai_agents/pipeline/orchestrator.rb     # Pipeline
app/services/ai_agents/mcp/jira_client.rb            # Integration
```

---

## 🔤 Namespaces

### **Marketing Agents**
```ruby
AiAgents::BaseAgent
AiAgents::PlanningAgent
AiAgents::ContentAgent
AiAgents::LandingPageDslAgent
# ... etc
```

**Usage**: Used by Scout chat interface for user-facing workflows
**Data**: WorkflowExecution, WorkflowContext, TaskSession

---

### **Pipeline Agents**
```ruby
AiAgents::Pipeline::BaseAgent
AiAgents::Pipeline::ClarifierAgent
AiAgents::Pipeline::PlannerAgent
AiAgents::Pipeline::CoderAgent
AiAgents::Pipeline::ReviewerAgent
AiAgents::Pipeline::WorkspaceManager
AiAgents::Pipeline::Orchestrator
AiAgents::Pipeline::StateMachine
```

**Usage**: Background jobs for automated development workflow
**Data**: PipelineExecution, AgentExecution, PipelineArtifact

---

### **MCP Clients**
```ruby
AiAgents::Mcp::Manager
AiAgents::Mcp::Client
AiAgents::Mcp::JiraClient
AiAgents::Mcp::AzureDevOpsClient
```

**Usage**: External system integrations for ticket systems
**Data**: McpConnection (stores encrypted credentials)

---

### **Notifiers**
```ruby
AiAgents::Notifiers::SlackNotifier
AiAgents::Notifiers::EmailNotifier
```

**Usage**: Send notifications during pipeline execution
**Data**: Uses PipelineExecution, PipelineInteraction

---

## 📊 Agent Comparison

| Aspect | Marketing Agents | Pipeline Agents |
|--------|-----------------|-----------------|
| **Location** | `ai_agents/*.rb` | `ai_agents/pipeline/*.rb` |
| **Namespace** | `AiAgents::` | `AiAgents::Pipeline::` |
| **Purpose** | Content creation for users | Code generation automation |
| **Triggered By** | User requests in Scout | JIRA/Azure DevOps tickets |
| **Output** | Landing pages, headlines, content | Code, PRs, deployments |
| **Access** | `/scout` chat interface | Background jobs + admin UI |
| **Models** | WorkflowExecution | PipelineExecution |
| **Cost** | User-controlled | Fixed $1.16/ticket |
| **Lifecycle** | Interactive (user-driven) | Automated (event-driven) |

---

## 🔧 File Responsibilities

### **Marketing Agents** (`ai_agents/*.rb`)

#### `base_agent.rb`
- Base class for all marketing agents
- GPT-4/Claude model configuration
- Context building and message handling
- Vector store integration for RAG

#### `planning_agent.rb`
- Coordinates multi-step marketing workflows
- Decides which agents to call in sequence
- Maintains workflow state

#### `content_agent.rb`
- Generates blog posts, emails, social media content
- SEO-optimized copy
- Brand voice consistency

#### `landing_page_dsl_agent.rb`
- Creates complete landing pages
- HTML/CSS generation
- Responsive design
- Integration with design system

---

### **Pipeline Agents** (`ai_agents/pipeline/*.rb`)

#### `base_agent.rb`
- Base class for all pipeline agents
- BedrockService integration (Claude AI)
- Workspace management
- Token/cost tracking
- Artifact storage

#### `clarifier_agent.rb` (Claude 3.5 Haiku - $0.02)
- Analyzes tickets for clarity
- Generates 3-5 clarifying questions
- Creates PipelineInteraction if needs clarification
- Outputs: `clarification_analysis.json`, `clarifications.md`

#### `planner_agent.rb` (Claude Sonnet 4.5 - $0.15)
- Reads ticket + clarifications
- Creates implementation plan
- Lists files to create/modify
- Defines test cases
- Outputs: `plan.md`, `test_spec.yaml`, `architecture.mermaid`

#### `coder_agent.rb` (Claude Sonnet 4.5 - $0.75)
- 11-step workflow:
  1. Create workspace
  2. Clone repository
  3. Create feature branch
  4. Read plan
  5. Generate code with Claude
  6. Parse FILE: markers
  7. Identify tests
  8-9. Push to GitHub
  10. Create PR
  11. Cleanup
- Outputs: Complete codebase + tests

#### `reviewer_agent.rb` (Claude 3.5 Sonnet - $0.24)
- Fetches PR diff from GitHub
- Security scan (secrets, vulnerabilities)
- Quality checks (test coverage, documentation)
- Posts review to GitHub PR
- Outputs: `review_report.md`, `gate.json`

#### `workspace_manager.rb`
- Creates isolated `/tmp/pipeline-{id}/{agent}` directories
- 0700 permissions (owner-only)
- Git operations within workspace
- Automatic cleanup after 24 hours

#### `orchestrator.rb`
- Main workflow coordinator
- Processes pipeline state
- Routes to appropriate agent
- Handles agent completion
- Creates human interactions (clarifications, approvals)

#### `state_machine.rb`
- 14-state workflow: NEW → CLARIFYING → PLANNING → IMPLEMENTING → REVIEW → TESTING → DEV → STAGING → AWAITING_PROD_APPROVAL → PROD → DONE/FAILED/ROLLED_BACK/BLOCKED
- Validates transitions
- Maps states to agents
- UI helpers (labels, colors, icons)

---

### **MCP Clients** (`ai_agents/mcp/*.rb`)

#### `manager.rb`
- Multi-tenant MCP connection pooling
- Dynamic credential injection per entity
- Server lifecycle management
- Health checking

#### `jira_client.rb`
- JIRA Cloud API v3
- JQL query building
- Ticket fetching with ADF parsing
- Comment posting
- State transitions
- File attachments

#### `azure_devops_client.rb`
- Azure DevOps REST API v7.0
- WIQL query building
- Work item operations
- JSON Patch updates
- File attachments

---

### **Notifiers** (`ai_agents/notifiers/*.rb`)

#### `slack_notifier.rb`
- Slack Web API integration
- Threaded messages per pipeline
- Block Kit rich formatting
- Channel routing (#ai-clarifications, #ai-pipeline-status, etc.)
- Rate limiting (10 msg/min)

#### `email_notifier.rb`
- Mailgun API integration
- HTML + plain text templates
- 4 email types (interaction, state change, failure, approval)
- Recipient routing
- Email tagging for analytics

---

## 🧪 Usage Examples

### **Marketing Agent (User-Facing)**
```ruby
# User asks in Scout chat: "Create a landing page for our new feature"
agent = AiAgents::PlanningAgent.new(
  context: { user_request: "Create landing page..." }
)
result = agent.execute

# Calls other agents:
# - AiAgents::WebSearchAgent (research)
# - AiAgents::HeadlineAgent (headlines)
# - AiAgents::ContentAgent (copy)
# - AiAgents::LandingPageDslAgent (build page)
```

### **Pipeline Agent (Automated)**
```ruby
# JIRA ticket detected by TicketWatcherJob
pipeline = PipelineExecution.create!(
  ticket_id: 'PROJ-123',
  status: :new
)

# Orchestrator processes
orchestrator = AiAgents::Pipeline::Orchestrator.new(pipeline)
orchestrator.process!

# Calls agents in sequence:
# 1. AiAgents::Pipeline::ClarifierAgent
# 2. AiAgents::Pipeline::PlannerAgent
# 3. AiAgents::Pipeline::CoderAgent
# 4. AiAgents::Pipeline::ReviewerAgent
```

---

## 🔍 Finding Code

### "Where is the code that generates blog posts?"
```
app/services/ai_agents/content_agent.rb
```

### "Where is the code that creates GitHub PRs?"
```
app/services/ai_agents/pipeline/coder_agent.rb
(See step 10 of 11-step workflow)
```

### "Where is the JIRA integration?"
```
app/services/ai_agents/mcp/jira_client.rb
```

### "Where is the pipeline state machine?"
```
app/services/ai_agents/pipeline/state_machine.rb
```

### "Where are Slack notifications sent?"
```
app/services/ai_agents/notifiers/slack_notifier.rb
```

---

## 🎨 IDE Organization

With this structure, your IDE sidebar looks like:

```
📁 ai_agents/
  📄 base_agent.rb
  📄 content_agent.rb
  📄 coordination_agent.rb
  📄 design_agent.rb
  📄 headline_agent.rb
  📄 image_prompt_agent.rb
  📄 landing_page_dsl_agent.rb
  📁 mcp/
    📄 azure_devops_client.rb
    📄 client.rb
    📄 jira_client.rb
    📄 manager.rb
  📁 notifiers/
    📄 email_notifier.rb
    📄 slack_notifier.rb
  📁 pipeline/
    📄 base_agent.rb
    📄 clarifier_agent.rb
    📄 coder_agent.rb
    📄 orchestrator.rb
    📄 planner_agent.rb
    📄 reviewer_agent.rb
    📄 state_machine.rb
    📄 workspace_manager.rb
  📄 planning_agent.rb
  📄 seo_agent.rb
  📄 vector_store.rb
  📄 web_search_agent.rb
```

Clean, organized, and easy to navigate! ✨

---

## 📝 Migration Notes

### What Changed?
- **Moved**: `app/services/agents/*_agent.rb` → `app/services/ai_agents/pipeline/`
- **Moved**: `app/services/pipeline/*.rb` → `app/services/ai_agents/pipeline/`
- **Moved**: `app/services/mcp/*.rb` → `app/services/ai_agents/mcp/`
- **Moved**: `app/services/notifiers/*.rb` → `app/services/ai_agents/notifiers/`

### Namespace Updates
- `Agents::` → `AiAgents::Pipeline::`
- `Pipeline::` → `AiAgents::Pipeline::`
- `MCP::` → `AiAgents::Mcp::`
- `Notifiers::` → `AiAgents::Notifiers::`

### Files Updated
- All job files (`app/jobs/*_job.rb`)
- All models using pipeline agents
- All controllers
- Test files

### Verified Working
```ruby
AiAgents::Pipeline::StateMachine.next_states('new')
# => ["clarifying"]

AiAgents::Mcp::JiraClient.name
# => "AiAgents::Mcp::JiraClient"

AiAgents::Notifiers::SlackNotifier.new
# => #<AiAgents::Notifiers::SlackNotifier...>
```

---

## ✅ Benefits of This Organization

1. **Single Source of Truth**: All AI agent code in `ai_agents/`
2. **Clear Boundaries**: Subdirectories by purpose (pipeline, mcp, notifiers)
3. **Easy Navigation**: Logical grouping makes finding code intuitive
4. **Scalable**: Easy to add new agent types (e.g., `ai_agents/testing/`)
5. **Maintainable**: Changes to one type don't affect others
6. **IDE-Friendly**: Clean folder tree in sidebar

---

**Last Updated**: October 29, 2025
**Namespace Convention**: `AiAgents::{Subdirectory}::{ClassName}`
**File Location**: `./app/services/ai_agents/`
