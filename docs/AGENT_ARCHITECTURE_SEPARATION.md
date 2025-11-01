# Agent Architecture Separation

## 🤔 Why Two Agent Folders?

You have **two completely different agent systems** that serve different purposes:

```
app/services/
├── ai_agents/          ← AMOS Marketing Agents (existing)
└── agents/             ← AI Dev Pipeline Agents (new)
```

---

## 📊 Comparison Table

| Aspect | `ai_agents/` | `agents/` |
|--------|--------------|-----------|
| **Purpose** | User-facing marketing/content workflows | Internal software development automation |
| **Users** | End-users via Scout chat | Developers (via automated tickets) |
| **Input** | User requests like "create landing page" | JIRA/Azure DevOps tickets |
| **Output** | Marketing content, landing pages, headlines | Code, PRs, deployment to production |
| **Namespace** | `AiAgents::` | `Agents::` |
| **Base Class** | `AiAgents::BaseAgent` | `Agents::BaseAgent` |
| **Model Used** | Configurable (GPT-4, Claude, etc.) | Fixed per agent (Haiku, Sonnet 4.5) |
| **Cost Focus** | User-controlled budgets | Fixed $1.16 per ticket |
| **Examples** | ContentAgent, HeadlineAgent, DesignAgent | ClarifierAgent, CoderAgent, ReviewerAgent |

---

## 🎯 AMOS Marketing Agents (`app/services/ai_agents/`)

**Purpose**: Help users create marketing content and landing pages

### Agents:
1. **PlanningAgent** - Coordinates multi-step marketing workflows
2. **CoordinationAgent** - Manages agent collaboration
3. **ContentAgent** - Generates blog posts, emails, social media
4. **HeadlineAgent** - Creates catchy headlines
5. **DesignAgent** - Provides design suggestions
6. **ImagePromptAgent** - Creates AI image generation prompts
7. **LandingPageDslAgent** - Builds complete landing pages
8. **SEOAgent** - SEO optimization recommendations
9. **WebSearchAgent** - Searches web for context

### Example User Flow:
```
User: "Create a landing page for our new SaaS product"
  ↓
PlanningAgent: Breaks down into tasks
  ↓
WebSearchAgent: Researches competitor pages
  ↓
HeadlineAgent: Generates headline options
  ↓
ContentAgent: Writes copy for each section
  ↓
DesignAgent: Suggests layout and colors
  ↓
LandingPageDslAgent: Builds final HTML/CSS
  ↓
Result: Complete landing page shown in Scout canvas
```

**Cost**: User-controlled via workflow budgets
**Access**: Scout chat interface (`/scout`)
**Storage**: `WorkflowExecution`, `WorkflowContext` tables

---

## 🛠️ AI Dev Pipeline Agents (`app/services/agents/`)

**Purpose**: Automate software development from ticket to production

### Agents:
1. **ClarifierAgent** - Analyzes tickets, asks clarifying questions
2. **PlannerAgent** - Creates implementation plans with file lists
3. **CoderAgent** - Generates complete code with tests
4. **ReviewerAgent** - Security and quality code review
5. **BaseAgent** - Shared infrastructure for all pipeline agents
6. **WorkspaceManager** - Isolated file system workspaces

### Example Automation Flow:
```
JIRA Ticket: "Add user profile page"
  ↓
ClarifierAgent: Asks questions about requirements
  ↓
Human: Answers questions
  ↓
PlannerAgent: Creates implementation plan
  ↓
CoderAgent: Generates code, creates PR
  ↓
ReviewerAgent: Security scan, code review
  ↓
Automated Tests: Run test suite
  ↓
Deploy: Dev → Staging → Production
  ↓
Result: Feature live in production
```

**Cost**: Fixed $1.16 per ticket
**Access**: Automatic via TicketWatcherJob
**Storage**: `PipelineExecution`, `AgentExecution` tables

---

## ✅ Should They Stay Separate?

**YES! Absolutely keep them separate.** Here's why:

### 1. **Different Responsibilities (Single Responsibility Principle)**
```ruby
# WRONG - Mixing concerns
class BaseAgent
  def create_marketing_content(...)  # User-facing
  def review_code_for_security(...)  # Internal automation
end

# RIGHT - Separate concerns
module AiAgents
  class BaseAgent
    def create_marketing_content(...)
  end
end

module Agents
  class BaseAgent
    def review_code_for_security(...)
  end
end
```

### 2. **Different Data Models**
```
ai_agents/ uses:
- WorkflowExecution
- WorkflowContext
- TaskSession
- Entity (for multi-tenant workflows)

agents/ uses:
- PipelineExecution
- AgentExecution
- PipelineArtifact
- McpConnection (for JIRA/GitHub integration)
```

### 3. **Different Lifecycles**
```
ai_agents/:
- Interactive, user-controlled
- Can be canceled mid-execution
- Results shown immediately in UI
- User can iterate and refine

agents/:
- Fully automated background jobs
- Runs to completion or failure
- Results visible in admin UI
- No user interaction except approval gates
```

### 4. **Different Error Handling**
```ruby
# ai_agents/ - User-friendly errors
rescue => e
  return { error: "I couldn't complete that task. Try rephrasing?" }
end

# agents/ - Technical errors with rollback
rescue => e
  pipeline.update(status: :failed)
  Notifiers::SlackNotifier.new.send_failure_alert(pipeline, e.message)
  raise  # Let SolidQueue retry
end
```

### 5. **Different Testing Strategies**
```ruby
# ai_agents/ - Mock external APIs, test content quality
test "generates compelling headline" do
  agent = AiAgents::HeadlineAgent.new(...)
  result = agent.execute
  assert result.length < 60  # SEO best practice
end

# agents/ - Test state transitions, integration with real systems
test "clarifier blocks pipeline when needs clarification" do
  agent = Agents::ClarifierAgent.new(...)
  agent.execute!
  assert_equal 'blocked', pipeline.reload.status
  assert_not_nil pipeline.pipeline_interactions.first
end
```

---

## 🏗️ Shared Infrastructure They Both Use

Despite being separate, they share underlying AMOS infrastructure:

### Both Use:
- ✅ `BedrockService` - AWS Bedrock Claude API client
- ✅ `Entity` model - Multi-tenant scoping
- ✅ `SolidQueue` - Background job processing
- ✅ PostgreSQL database
- ✅ Rails caching
- ✅ ActiveStorage (for file uploads)

### What They DON'T Share:
- ❌ Base classes (different `BaseAgent`)
- ❌ Data models (different tables)
- ❌ Namespaces (`AiAgents::` vs `Agents::`)
- ❌ Controllers (different UI access points)
- ❌ Jobs (different queue priorities)

---

## 📁 Recommended File Organization

```
app/
├── services/
│   ├── ai_agents/              # Marketing/Content Agents
│   │   ├── base_agent.rb       # Base for marketing agents
│   │   ├── planning_agent.rb
│   │   ├── content_agent.rb
│   │   ├── landing_page_dsl_agent.rb
│   │   └── ...
│   │
│   ├── agents/                 # Dev Pipeline Agents
│   │   ├── base_agent.rb       # Base for pipeline agents
│   │   ├── clarifier_agent.rb
│   │   ├── planner_agent.rb    # Different from AiAgents::PlanningAgent!
│   │   ├── coder_agent.rb
│   │   ├── reviewer_agent.rb
│   │   └── workspace_manager.rb
│   │
│   ├── pipeline/               # Pipeline orchestration
│   │   ├── orchestrator.rb
│   │   └── state_machine.rb
│   │
│   └── mcp/                    # External system integrations
│       ├── jira_client.rb
│       └── azure_devops_client.rb
```

---

## 🎯 Summary

**Keep them separate!** They are:
- ✅ Solving different problems
- ✅ Used by different users
- ✅ Have different data models
- ✅ Have different lifecycles
- ✅ Already properly namespaced

**The separation makes maintenance EASIER because:**
1. You can update marketing agents without affecting dev automation
2. You can deploy dev pipeline features independently
3. Each system has its own tests and documentation
4. New developers can understand one system without learning both
5. No risk of accidentally mixing marketing logic with code generation

**Think of it like this:**
- `ai_agents/` = Customer-facing product (AMOS Scout)
- `agents/` = Internal DevOps automation (like CI/CD)

You wouldn't put CI/CD logic in your customer-facing app, right? Same principle here! 🎯
