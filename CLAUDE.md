# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

### Development
```bash
# Start development server (runs Rails + asset compilation)
bin/dev

# Run Rails console
rails console

# Database operations
rails db:create db:migrate db:seed
rails db:rollback  # Rollback last migration
```

### Testing
```bash
# Run all tests
rails test

# Run specific test file
rails test test/models/campaign_test.rb

# Run agent system tests
rails test:agents
```

### Asset Building
```bash
# Build JavaScript
yarn build

# Build CSS
yarn build:css

# Watch CSS changes
yarn watch:css
```

## High-Level Architecture

### AI Agent System (Core)

AMOS is a **conversational AI platform** that uses AWS Bedrock (Claude) to execute user requests through an intelligent workflow system.

**Flow**: User Message → Scout Controller → Planner Agent → Workflow Engine → Phase Executors → Tools → Response Stream

**Key Components**:
- `ScoutController` - Main chat interface, handles streaming responses via Server-Sent Events
- `PlannerAgentService` - Analyzes user intent and selects appropriate workflow template
- `WorkflowEngine` - Orchestrates V2 phase-based workflow execution
- `BedrockService` - AWS Bedrock Claude integration with tool calling support

### V2 Workflow System (Phase-Based)

The system uses **three-phase workflows** defined in YAML templates (`app/workflow_templates/*.yml`):

1. **Gather Context Phase** (`Agents::GatherContextExecutor`)
   - Checks conversation history first
   - Analyzes uploaded files (PDFs, images, brand guides)
   - Reviews entity business profile
   - Only asks user conversationally for missing information
   - Stores gathered data in `WorkflowContext`

2. **Goal Execution Phase** (`Agents::GoalExecutor`)
   - Two approaches:
     - **Structured**: Direct data mapping to tool calls (reliable, predictable)
     - **Adaptive**: AI plans tool sequence dynamically (flexible)
   - Uses tools from `Tools::ToolCatalog` (20+ available)
   - Maintains context across tool invocations

3. **Validation Phase** (`Agents::ValidationExecutor`)
   - Runs quality checks on outputs
   - Attempts auto-fixes if validation fails (up to 2 attempts)
   - Reports success/failure with detailed messages

**Template Version Detection**: System detects `template_version: 2` in YAML and routes to V2 engine automatically.

### Persistent Context System

**WorkflowContext Model**: Stores phase data across workflow execution
- Files uploaded by users are moved from `TaskSession` to `WorkflowContext`
- AI can access context via `get_workflow_context` tool
- Prevents repetitive questions by maintaining state

**TaskSession Model**: Tracks user's current task and conversation
- Stores wizard_data, artifacts, current_phase
- Links to WorkflowExecution for history

### Tool Ecosystem

Tools live in `app/services/tools/` and extend `BaseTool`. The `ToolCatalog` singleton auto-discovers and registers all tools.

**Key Tools**:
- `generate_ai_landing_page` - Creates landing pages with AI
- `create_object` / `update_object` / `get_data` - CRUD operations on entities
- `delegate_to_planner_tool` - Recursive workflow invocation
- `list_connections` / `list_operations` / `invoke_operation` - Integration system
- `get_workflow_context` / `manage_task_list` - Context management
- `web_search_tool` - Web search capability

**Tool Definition Pattern**:
```ruby
module Tools
  class YourTool < BaseTool
    def self.definition
      { name: 'tool_name', description: '...', parameters: {...} }
    end

    def execute(args)
      # Implementation
      success_response(message: "...", data: {...})
    end
  end
end
```

### Integration System

AMOS can connect to external APIs (Stripe, HubSpot, Mailgun, custom REST APIs) and orchestrate cross-platform workflows.

**Architecture**:
- `Integration` - Service definition (Stripe, HubSpot, etc.)
- `Connection` - User's specific account with encrypted credentials
- `IntegrationOperation` - Specific API endpoint definition
- `IntegrationLog` - Audit trail of all API calls

**IntegrationApiService**: Handles authentication, rate limiting, request/response transformation

**User Flow**: Users configure connections via UI → AI discovers available operations → AI chains operations across platforms

**Example**: "Email my Stripe customers who upgraded" → Fetch from Stripe API → Filter → Generate emails → Send via Mailgun → Update HubSpot

### Streaming Response System

The chat interface uses **Server-Sent Events (SSE)** for real-time streaming:

**Event Types**:
- `content` - Append message content to chat
- `transient` - Show temporary progress indicators (fade after completion)
- `load_canvas` - Load specialized UI components (landing page editor, dashboards)
- `tool_start` / `tool_end` - Tool execution indicators

**Implementation**: `ScoutController#chat_stream` yields events, front-end listens via EventSource API

## Important Development Patterns

### Creating New Workflow Templates

1. Create YAML file in `app/workflow_templates/your_template_v2.yml`
2. Set `template_version: 2`
3. Define three phases: `gather_context`, `execute_goal`, `validate_result`
4. Add keywords for planner matching
5. System auto-discovers - no registration needed

### Adding New Tools

1. Create file in `app/services/tools/your_tool_tool.rb`
2. Extend `BaseTool` class
3. Define `self.definition` method (name, description, parameters)
4. Implement `execute(args)` method
5. Return `success_response()` or `error_response()`
6. ToolCatalog auto-discovers - no registration needed

### Background Jobs

Uses **SolidQueue** (not Sidekiq). Job files in `app/jobs/`

Common jobs:
- `ProcessCampaignJob` - Send email campaigns
- `GenerateLandingPageImageJob` - AI image generation
- `UpdateConnectionHealthJob` - Check integration health

### Entity Scoping

All data is **entity-scoped** (multi-tenant):
- Controllers include `EntityScoped` concern
- Models belong to `entity`
- Use `current_entity` in controllers
- Filter all queries by entity_id

## Database Schema Notes

**Core Models**:
- `Entity` - Tenant (business/organization)
- `User` - Belongs to entity, authenticated via Devise
- `Campaign` - Email campaigns, belongs to entity
- `Contact` / `ContactGroup` - Many-to-many via join table
- `LandingPage` - AI-generated landing pages
- `EmailTemplate` - Reusable email templates
- `WorkflowExecution` - Tracks workflow runs
- `WorkflowContext` - Persistent phase data (key-value store)

**Integration Models**:
- `Integration` - Service definitions
- `Connection` - User's connected accounts
- `IntegrationOperation` - API endpoint definitions
- `IntegrationLog` - Audit trail

## Key Configuration

**Environment Variables** (see `.env.example`):
- `AWS_REGION`, `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` - Required for Bedrock
- `DATABASE_URL` - PostgreSQL connection
- `MAILGUN_API_KEY` - Email sending (optional)
- `REDIS_URL` - Caching (optional)

**AI Model**: Uses AWS Bedrock Claude Sonnet 4.5 (configured in `BedrockService`)

**Performance Optimization**:
- **Prompt Caching**: Anthropic prompt caching is enabled by default in Scout conversations
- Caches system prompts and tool definitions for 5 minutes
- 10x faster responses for cache hits (~2500ms → ~250ms)
- 90% cost reduction for cached content
- Cross-user cache sharing for maximum efficiency
- See `docs/PROMPT_CACHING_GUIDE.md` for complete details

## Testing Patterns

- Test files mirror app structure: `test/models/`, `test/services/`, `test/controllers/`
- Use fixtures for test data (`test/fixtures/`)
- Agent testing guide: `docs/AGENT_TESTING_GUIDE.md`
- Integration examples: `docs/INTEGRATION_EXAMPLE.md`

## Debugging Workflow Issues

1. Check `WorkflowExecution` record status and metadata
2. Review `WorkflowContext` entries for the execution
3. Enable debug logging: `Rails.logger.level = :debug`
4. Check tool catalog: `Tools::ToolCatalog.instance.all_tools.keys`
5. Review streaming logs in browser console for event stream

## UI Architecture

- **Backend**: Rails 8 with Turbo/Stimulus
- **Frontend**: Bootstrap 5, minimal JavaScript
- **Chat Interface**: Stimulus controller (`app/javascript/controllers/chat_controller.js`)
- **Canvas System**: Dynamic UI loading (landing page editor, campaign dashboard)

## Agent Lightning - RL-Based Agent Optimization

The platform now includes **Agent Lightning integration** for continuous improvement of AI agents using reinforcement learning. This system:

- **Collects execution traces**: Records all LLM calls, tool usage, and workflow execution data automatically
- **Trains on success patterns**: Uses hierarchical RL to identify and reinforce effective behavior
- **Optimizes prompts**: Automatically improves system prompts and instructions based on performance metrics
- **Minimal overhead**: Instrumentation is automatic, non-blocking, and transparent

**Key Components:**
- `LightningStoreService` - Collects and manages training data from agent executions
- `AgentLightningTrainingService` - Orchestrates prompt optimization and RL training
- `RunAgentLightningTrainingJob` - Background job for periodic training (scheduled daily)
- Database models for storing traces, rewards, and training jobs

**Quick Setup:**
1. Run migrations: `rails db:migrate`
2. Configure per entity: `entity.create_agent_lightning_config!(enabled: true, ...)`
3. Training runs automatically via scheduled job or manually via `AgentLightningTrainingService.new(entity).execute_training`

See `docs/AGENT_LIGHTNING_INTEGRATION.md` for comprehensive setup, usage, and configuration guide.

## Documentation Files

- `AGENT_LIGHTNING_INTEGRATION.md` - **NEW**: RL-based agent optimization and prompt improvement
- `WORKFLOW_V2_EXECUTIVE_SUMMARY.md` - V2 architecture overview
- `V2_PURE_IMPLEMENTATION.md` - Implementation details
- `AGENT_ARCHITECTURE.md` - Agent system design
- `INTEGRATION_ARCHITECTURE_V2.md` - Integration system details
- `PROMPT_CACHING_GUIDE.md` - Anthropic prompt caching implementation and optimization
- `UI_UX_STYLE_GUIDE.md` - **MUST READ**: UI/UX best practices, Lucide icon sizing conventions, button styling guidelines
