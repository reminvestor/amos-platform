# AMOS - Automated Management Operating System

> **AI-Powered Business Automation Platform**  
> Natural language workflows, intelligent agents, universal integrations, and voice interaction

---

## 🚀 What is AMOS?

**AMOS** is an AI-first business automation platform where you accomplish complex tasks through natural conversation. No forms to fill out. No complicated workflows to configure. Just tell AMOS what you need, and it intelligently orchestrates the work through a sophisticated multi-agent system.

### The Vision

AMOS transforms business automation from:
- ❌ **Manual form-filling** → ✅ **Natural conversation**
- ❌ **Rigid workflows** → ✅ **Intelligent adaptation**
- ❌ **Static integrations** → ✅ **AI-created connectors**
- ❌ **Single-purpose tools** → ✅ **Self-evolving agent ecosystem**

---

## ✨ Core Capabilities

### 🤖 Scout - Conversational AI Interface
Scout is the primary AI assistant that handles all user interactions:
- **Natural Language Processing**: Understand complex requests in plain English
- **Context-Aware**: Remembers conversations, uploaded files, and business profile
- **Tool Orchestration**: Accesses 60+ tools for data, integrations, and workflows
- **Real-Time Streaming**: See progress as Scout works via Server-Sent Events
- **Smart Delegation**: Knows when to hand off to specialized agents

### 🧠 Multi-Agent System
AMOS features a sophisticated agent architecture with 11 specialized agents:

| Agent | Role | Purpose |
|-------|------|---------|
| **Scout** | main_chat | Primary user interface, tool orchestration |
| **Agent Architect** | architect | Creates and modifies AI agents |
| **Tool Builder** | engineer | Builds custom tools (HTTP APIs & Ruby code) |
| **Integration Architect** | architect | Creates API integrations via research-test-build workflow |
| **AI Landing Page Creator** | executor | Generates conversion-optimized landing pages |
| **Email Sequence Architect** | executor | Designs multi-email drip campaigns |
| **Campaign Optimizer** | analyst | Analyzes and improves campaign performance |
| **Sales Email Generator** | executor | Creates personalized sales emails |
| **Content Quality Analyzer** | verifier | Evaluates content quality and SEO |
| **Customer Journey Mapper** | analyst | Maps customer touchpoints and friction |
| **Web Research Agent** | researcher | Performs web searches via Serper API |

### 🏭 Factory System (Agent, Tool & Integration Creation)
AMOS can create its own capabilities through three factory services:

#### Agent Factory (`Factories::AgentFactory`)
- **Schema Validation**: Ensures agents have proper structure
- **Prompt Validation**: Checks system prompts for required sections (role, objective, constraints)
- **Capability Validation**: Verifies input/output contracts
- **Tool Validation**: Confirms assigned tools exist
- **Test Execution**: Runs a test prompt before deployment
- **Ownership Tracking**: Associates agents with their creator (`user_id`)

#### Tool Factory (`Factories::ToolFactory`)
- **Two Execution Types**: `ruby_code` or `http_request`
- **Security Scanning**: Blocks dangerous patterns (eval, system, file writes)
- **Parameter Schema Validation**: Ensures proper JSON Schema format
- **API Config Validation**: For HTTP tools, validates URLs, methods, headers
- **Automatic Catalog Refresh**: New tools immediately available

#### Integration Factory (`Factories::IntegrationFactory`)
- **Staged Creation Pipeline**:
  1. **Foundation**: Create basic integration (name, base URL, description)
  2. **Configure Auth**: Set authentication type and parameters
  3. **Test Auth**: Verify credentials work with the API
  4. **Add Operations**: Define API endpoints
- **Flexible Auth Support**: API Key, Bearer Token, Basic Auth, OAuth2, Custom
- **Auth Placement**: Header, Query Parameter, or URL Path
- **Connection Management**: Entity-scoped connections with credentials

### 🔌 Universal Integration Platform
Connect to any REST API without code changes:

**Pre-Built Integrations:**
- 💳 **Stripe** - Payments, subscriptions, customers
- 🎯 **HubSpot** - CRM, contacts, deals
- ✉️ **AWS SES** - Transactional email with tracking
- 📋 **Trello** - Boards, lists, cards
- 🔧 **Any REST API** - User-configurable

**Integration Features:**
- **Dynamic Operation Discovery**: Agents find and use API endpoints
- **Secure Credential Storage**: Encrypted with rotation support
- **Policy Engine**: Role-based operation permissions
- **Audit Logging**: Every API call tracked
- **Rate Limiting**: Automatic throttling and retry

### 🛠️ Tool Ecosystem (60+ Tools)

**Data Management:**
- `create_object`, `get_data`, `update_object` - CRUD operations
- `get_schema` - Discover available data types
- `query_metric`, `list_metrics` - Analytics queries

**Agent & Automation:**
- `delegate_to_agent` - Hand off to specialized agents
- `invoke_agent_plugin` - Execute agent plugins
- `list_available_agents` - Discover agents by capability
- `create_agent`, `update_agent` - Agent management
- `create_tool`, `update_tool` - Tool management

**Integration Tools:**
- `list_connections`, `list_operations` - Discover integrations
- `invoke_operation`, `execute_integration` - Call APIs
- `create_integration_foundation` - Start new integration
- `configure_integration_auth` - Set up authentication
- `test_integration_auth` - Verify credentials
- `add_integration_operations` - Define endpoints
- `research_api` - Structured API research

**Content & Documents:**
- `generate_ai_landing_page` - Create landing pages
- `update_landing_page` - Modify existing pages
- `read_document`, `query_document_content` - Document analysis
- `query_rag_store` - Semantic search over documents
- `create_rag_store` - Create knowledge bases

**Communication:**
- `ask_user` - Request user input mid-workflow
- `web_search` - Search the internet via Serper API
- `search_history`, `retrieve_history` - Conversation memory

**Visualization:**
- `create_dynamic_visualization` - Generate charts and dashboards
- `load_canvas` - Display rich UI components

### 📊 Canvas System (25 UI Components)
Dynamic UI components that Scout can load:

| Canvas | Purpose |
|--------|---------|
| `dynamic_canvas` | Flexible markdown/HTML display |
| `analytics_dashboard` | Metrics and charts |
| `landing_page_editor` | Visual page builder |
| `integrations_manager` | Connection management |
| `campaign_viewer` | Email campaign details |
| `contact_viewer` | Contact profiles |
| `document_viewer` | Document display |
| `task_progress` | Workflow status |
| `parallel_tasks` | Multi-task monitoring |

### 🎙️ Voice Interface
Full voice interaction support:
- **Voice Input**: Web Speech API, WebSocket streaming
- **Voice Output**: AWS Polly, ElevenLabs TTS
- **Real-Time Processing**: Sub-second response times
- **Session Management**: Persistent voice sessions
- **Connection Optimization**: Automatic retry and health monitoring

### 📚 RAG (Retrieval-Augmented Generation)
Semantic search across all knowledge:
- **Document Chunking**: Intelligent text segmentation
- **Vector Embeddings**: pgvector-powered similarity search
- **Multi-Source Search**: Documents, conversations, integrations
- **Hybrid Queries**: Combine semantic and keyword search
- **Knowledge Stores**: Entity-scoped document collections

---

## 🏗️ Architecture

### System Flow

```
┌─────────────────────────────────────────────────────────────┐
│                    User Request (Chat/Voice)                 │
└─────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────┐
│                  ScoutGenericToolsServiceV2                  │
│  • Builds context-aware system prompt                        │
│  • Filters tools by agent loadout                            │
│  • Streams responses via ActionCable                         │
│  • Executes tool calls and continuations                     │
└─────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────┐
│                      BedrockService                          │
│  • Claude Sonnet 4.5 via AWS Bedrock                         │
│  • Streaming with tool use                                   │
│  • Prompt caching for efficiency                             │
│  • Rate limiting and fallback                                │
└─────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────┐
│                     Tool Execution                           │
│  ┌──────────┐  ┌──────────┐  ┌──────────────┐               │
│  │ Data     │  │ Agent    │  │ Integration  │               │
│  │ Tools    │  │ Plugins  │  │ Operations   │               │
│  └──────────┘  └──────────┘  └──────────────┘               │
└─────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────┐
│                    Canvas/Response                           │
│  • Dynamic UI components                                     │
│  • Streamed text responses                                   │
│  • Structured data displays                                  │
└─────────────────────────────────────────────────────────────┘
```

### Agent Plugin Execution

```
┌─────────────────────────────────────────────────────────────┐
│                   Agent Plugin Invocation                    │
└─────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────┐
│                 StandardPluginExecutor                       │
│  • Loads agent configuration                                 │
│  • Builds role-specific system prompt                        │
│  • Performs runtime tool discovery (RAG)                     │
│  • Executes tool loop (max 15 turns)                         │
│  • Broadcasts progress via ActionCable                       │
└─────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────┐
│              AgentPluginExecutionJob (Background)            │
│  • Async execution via SolidQueue                            │
│  • Status tracking (pending → running → completed)           │
│  • Canvas output on completion                               │
│  • Error handling and retry                                  │
└─────────────────────────────────────────────────────────────┘
```

### Integration Execution

```
┌─────────────────────────────────────────────────────────────┐
│                  invoke_operation Tool                       │
└─────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────┐
│              UniversalIntegrationExecutor                    │
│  • Resolves connection and credentials                       │
│  • Checks policy permissions                                 │
│  • Builds authenticated request                              │
└─────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────┐
│                 IntegrationApiService                        │
│  • Constructs URL from path template                         │
│  • Applies auth headers/params from AuthConfig               │
│  • Handles pagination strategies                             │
│  • Logs request/response                                     │
└─────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────┐
│                    External API                              │
│  Stripe, HubSpot, Trello, Custom APIs...                     │
└─────────────────────────────────────────────────────────────┘
```

---

## 📁 Project Structure

```
app/
├── channels/
│   ├── scout_channel.rb          # Real-time chat streaming
│   ├── voice_channel.rb          # Voice session WebSocket
│   └── amos_channel.rb           # Legacy chat channel
├── controllers/
│   ├── scout_controller.rb       # Main chat API
│   ├── integrations_controller.rb # Integration management
│   ├── agent_plugins_controller.rb
│   └── admin/                    # Admin panel
├── jobs/
│   ├── agent_plugin_execution_job.rb  # Async agent execution
│   ├── voice_agent_job.rb        # Voice processing
│   └── rag/                      # Document processing pipeline
├── models/
│   ├── agent_plugin.rb           # AI agent definitions
│   ├── tool_definition.rb        # Custom tool definitions
│   ├── integration.rb            # API integration blueprints
│   ├── connection.rb             # Entity-integration links
│   ├── integration_credential.rb # Encrypted API credentials
│   ├── integration_operation.rb  # API endpoint definitions
│   ├── oauth_configuration.rb    # OAuth settings
│   ├── auth_config.rb            # Flexible auth parameters
│   └── agent_loadout.rb          # Role-based tool permissions
├── services/
│   ├── scout_generic_tools_service_v2.rb  # Main Scout service
│   ├── bedrock_service.rb        # AWS Bedrock Claude API
│   ├── factories/
│   │   ├── agent_factory.rb      # Agent creation/validation
│   │   ├── tool_factory.rb       # Tool creation/validation
│   │   └── integration_factory.rb # Integration creation
│   ├── agents/
│   │   ├── standard_plugin_executor.rb  # Agent execution engine
│   │   ├── gather_context_executor.rb
│   │   ├── goal_executor.rb
│   │   └── validation_executor.rb
│   ├── tools/                    # 60+ tool implementations
│   │   ├── base_tool.rb
│   │   ├── tool_catalog.rb       # Tool registry
│   │   ├── create_agent_tool.rb
│   │   ├── create_tool_tool.rb
│   │   ├── create_integration_foundation_tool.rb
│   │   └── ... (60+ tools)
│   ├── integration_api_service.rb  # API execution
│   ├── universal_integration_executor.rb
│   ├── policy_engine.rb          # Permission enforcement
│   ├── security_check_service.rb # Tool security scanning
│   ├── rag_service.rb            # Semantic search
│   ├── embedding_service.rb      # Vector embeddings
│   └── voice_agent_service.rb    # Voice processing
├── views/
│   └── scout/canvas/             # 25 canvas partials
└── workflow_templates/           # YAML workflow definitions
```

---

## 🚦 Getting Started

### Prerequisites
- Ruby 3.4+
- Rails 8.0+
- PostgreSQL 14+ with pgvector extension
- AWS Account (for Bedrock Claude, SES, S3)
- Node.js & Yarn
- Redis (for ActionCable)

### Installation

```bash
# Clone the repository
git clone [repository-url]
cd agent_marketing

# Install dependencies
bundle install
yarn install

# Setup database
rails db:create db:migrate db:seed

# Configure environment
cp .env.example .env
# Add your AWS credentials and other keys

# Start the server
bin/dev
```

### Demo Login Credentials

After running `db:seed`:

| Email | Password | Role |
|-------|----------|------|
| admin@demo.com | password123 | Admin (full access) |
| marketer@demo.com | password123 | Marketer |
| viewer@demo.com | password123 | Viewer (read-only) |

### Environment Variables

```bash
# AWS Bedrock (Required)
AWS_REGION=us-east-1
AWS_ACCESS_KEY_ID=your_key
AWS_SECRET_ACCESS_KEY=your_secret
BEDROCK_DEFAULT_MODEL=claude-sonnet-4-5

# AWS SES (Email)
SES_REGION=us-east-1
MAILER_SENDER=noreply@yourdomain.com

# Database
DATABASE_URL=postgresql://localhost/amos_development

# Redis (ActionCable)
REDIS_URL=redis://localhost:6379

# Serper API (Web Search)
SERPER_API_KEY=your_key

# Voice (Optional)
ELEVENLABS_API_KEY=your_key
DEEPGRAM_API_KEY=your_key
```

### Docker

```bash
# Start all services
docker compose up -d

# View logs
docker compose logs -f web

# Reset passwords
docker compose exec web rails dev:reset_passwords

# Run seeds
docker compose exec web rails db:seed
```

---

## 📖 Usage Examples

### Creating an Agent

```
You: Create an agent that summarizes PDF documents

AMOS: I'll delegate this to the Agent Architect...

Agent Architect: I'll create a Document Summarizer agent for you.
      
      📋 Agent Blueprint:
      • Name: Document Summarizer
      • Role: executor
      • Tools: read_document, query_rag_store
      
      🧪 Running test...
      ✅ Agent created successfully!
      
      You can now ask: "Summarize the Q4 report"
```

### Creating a Custom Tool

```
You: Create a tool that fetches weather data from OpenWeatherMap

AMOS: I'll have the Tool Builder create that...

Tool Builder: Creating weather_lookup tool:
      
      📦 Tool Configuration:
      • Type: http_request
      • Endpoint: api.openweathermap.org/data/2.5/weather
      • Auth: Query parameter (appid)
      
      🔒 Security scan: PASS
      ✅ Tool created and available!
```

### Creating an Integration

```
You: Connect to the Notion API

AMOS: I'll have the Integration Architect set this up...

Integration Architect: Let me research the Notion API...
      
      📚 Research Complete:
      • Base URL: https://api.notion.com/v1
      • Auth: Bearer token in header
      • Version header required
      
      🔧 Creating integration foundation...
      🔐 Configuring authentication...
      
      Please provide your Notion API key:

You: [provides key]

Integration Architect: 
      ✅ Connection tested successfully!
      
      📋 Adding operations:
      • list_databases
      • query_database
      • create_page
      
      Integration ready! You can now ask:
      "List my Notion databases"
```

### Cross-Platform Automation

```
You: Email my Stripe customers who upgraded this week

AMOS: 🔧 Connecting to Stripe...
      📊 Found 12 customers who upgraded
      
      🔧 Creating personalized emails...
      ✅ 12 emails sent via AWS SES!
      
      Open rates will be tracked automatically.
```

---

## 🔐 Security

### AI Safety
- **Agent Loadouts**: Role-based tool allowlists
- **Security Scanning**: Tools checked for dangerous patterns
- **Input Validation**: All tool parameters validated
- **HTML Sanitization**: AI-generated content sanitized

### Data Privacy
- **Entity Scoping**: Data isolated per organization
- **Encrypted Credentials**: Integration secrets encrypted at rest
- **Audit Logging**: All operations logged
- **GDPR Compliance**: Contact management features

### API Security
- **Policy Engine**: Operation-level permissions
- **Rate Limiting**: Per-connection throttling
- **Credential Rotation**: Automatic token refresh
- **SSRF Prevention**: Internal URL blocking

---

## 📈 Roadmap

### Current (V2.5) ✅
- ✅ Multi-agent system with 11 specialized agents
- ✅ Factory system (Agent, Tool, Integration)
- ✅ 60+ AI-accessible tools
- ✅ Universal integration platform
- ✅ Staged integration creation workflow
- ✅ Voice input/output
- ✅ RAG with vector search
- ✅ 25 canvas components
- ✅ Real-time streaming

### Coming Soon (V3.0) 🚀
- 🔄 Visual workflow builder
- 🔄 Integration marketplace
- 🔄 Webhook automation triggers
- 🔄 Multi-agent collaboration
- 🔄 Proactive recommendations

### Future (V4.0) 🎯
- 🎯 100+ pre-built integrations
- 🎯 Team collaboration features
- 🎯 White-label options
- 🎯 Mobile apps

---

## 🛠️ Development

### Key Technologies

**Backend:**
- Ruby on Rails 8.0
- PostgreSQL with pgvector
- AWS Bedrock (Claude Sonnet 4.5)
- AWS SES (Email)
- SolidQueue (Background jobs)
- ActionCable (WebSocket)

**Frontend:**
- Bootstrap 5
- Stimulus.js
- Turbo
- Server-Sent Events

### Running Tests

```bash
rails test
rails test test/services/factories/agent_factory_test.rb
```

### Adding a New Tool

1. Create `app/services/tools/your_tool_tool.rb`:

```ruby
module Tools
  class YourToolTool < BaseTool
    def name
      'your_tool'
    end

    def description
      'What this tool does'
    end

    def parameters
      {
        type: 'object',
        properties: {
          param1: { type: 'string', description: 'Parameter description' }
        },
        required: ['param1']
      }
    end

    def execute(args)
      # Your logic here
      success_response(message: "Done!", data: { result: 'value' })
    rescue => e
      error_response("Error: #{e.message}")
    end
  end
end
```

2. Tools are auto-discovered by `ToolCatalog`

### Adding a New Agent

Use the Agent Architect or seed directly:

```ruby
# db/seeds/agent_plugins.rb
seed_agent(
  "your_agent_slug",
  {
    name: "Your Agent Name",
    role: "executor",  # executor, planner, analyst, verifier, architect, engineer
    description: "What this agent does",
    system_prompt: { prompt: "Your system prompt..." },
    configuration: { custom_settings: true }
  },
  [
    { capability_name: "your_capability", contract_schema: { inputs: [], outputs: [] } }
  ],
  [
    { tool_name: "tool1", required: true },
    { tool_name: "tool2", required: false }
  ]
)
```

---

## 🐛 Troubleshooting

### Common Issues

**AMOS not responding:**
```bash
# Check AWS Bedrock credentials
aws bedrock list-foundation-models --region us-east-1

# Check ActionCable connection
tail -f log/development.log | grep ActionCable
```

**Agent execution fails:**
```ruby
# Check execution status
AgentPluginExecution.last.status
AgentPluginExecution.last.result

# Check agent tools
AgentPlugin.find_by(slug: 'agent_slug').agent_tools.pluck(:tool_name)
```

**Integration not working:**
```ruby
# Check connection status
Connection.last.status

# Check credentials
Connection.last.active_credential.present?

# Test manually
IntegrationApiService.new(integration, credential).test_connection
```

---

## 📞 Support

- **Issues**: [GitHub Issues](repository-issues-url)
- **Email**: support@amoslabs.ai
- **Documentation**: [Full Docs](docs-url)

---

## 📄 License

[Your License Here]

---

## 🙏 Acknowledgments

Built with:
- **AWS Bedrock** - Claude AI foundation
- **Ruby on Rails** - Web framework
- **Bootstrap** - UI framework
- **pgvector** - Vector similarity search
- **The Open Source Community**

---

**AMOS** - Making business automation as simple as having a conversation. 🚀

*Version 2.5 - November 2025*
