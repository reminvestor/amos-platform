# AMOS Project Structure

**Last Updated**: October 16, 2025

This document describes the complete directory structure and organization of the AMOS platform codebase.

---

## 📂 Root Directory Structure

```
agent_marketing/
├── CLAUDE.md                 # Project instructions for Claude Code
├── README.md                 # Project overview and introduction
├── Gemfile                   # Ruby dependencies
├── Gemfile.lock              # Locked Ruby dependency versions
├── package.json              # Node.js dependencies
├── yarn.lock                 # Locked Node dependency versions
├── Rakefile                  # Rake task definitions
├── config.ru                 # Rack configuration for Rails
├── compose.yaml        # Docker multi-container setup
├── Containerfile                # Docker image build instructions
├── requirements.txt          # Python dependencies (Docling, transformers)
├── .env                      # Environment variables (NOT in git)
├── .env.example              # Environment variable template
├── .gitignore                # Git ignore patterns
├── .gitattributes            # Git attributes configuration
├── .ruby-version             # Ruby version specification
├── .node-version             # Node.js version specification
├── .containerignore          # Container build ignore patterns
│
├── 📂 .claude/               # Claude Code configuration
│   ├── 📂 agents/            # Agent-specific instructions
│   └── settings.json         # Claude Code settings
│
├── 📂 app/                   # Rails application code
│   ├── 📂 assets/            # Asset pipeline (CSS, JS)
│   ├── 📂 channels/          # Action Cable channels (WebSockets)
│   ├── 📂 controllers/       # MVC controllers
│   ├── 📂 helpers/           # View helpers
│   ├── 📂 javascript/        # JavaScript (Stimulus controllers)
│   ├── 📂 jobs/              # Background jobs (SolidQueue)
│   ├── 📂 mailers/           # Action Mailer classes
│   ├── 📂 models/            # ActiveRecord models
│   ├── 📂 services/          # Business logic services
│   │   ├── 📂 agents/        # V2 agent system
│   │   ├── 📂 tools/         # Scout tools (20+ tools)
│   │   ├── bedrock_service.rb
│   │   ├── docling_bridge_service.rb
│   │   ├── embedding_cache_service.rb
│   │   ├── rag_store_service.rb
│   │   └── ...
│   └── 📂 views/             # ERB templates
│
├── 📂 bin/                   # Executable scripts
│   ├── bundle                # Bundler wrapper
│   ├── rails                 # Rails CLI
│   ├── rake                  # Rake CLI
│   └── dev                   # Development server (Foreman)
│
├── 📂 config/                # Application configuration
│   ├── 📂 environments/      # Environment-specific configs
│   ├── 📂 initializers/      # Rails initializers
│   ├── 📂 locales/           # I18n translations
│   ├── application.rb        # Main application config
│   ├── database.yml          # Database configuration
│   ├── routes.rb             # Route definitions
│   └── credentials.yml.enc   # Encrypted credentials
│
├── 📂 db/                    # Database files
│   ├── 📂 migrate/           # Database migrations (100+ migrations)
│   ├── schema.rb             # Current database schema
│   └── seeds.rb              # Seed data
│
├── 📂 docs/                  # 📚 Documentation (organized)
│   ├── 📂 architecture/      # Architecture & design documents
│   │   ├── ANALYTICS_ADDON_INTEGRATION_DESIGN.md
│   │   ├── INTEGRATION_BUILDER_IMPLEMENTATION.md
│   │   ├── MULTI_AGENT_ORCHESTRATION_DESIGN.md
│   │   ├── SECURE_INTEGRATION_ARCHITECTURE.md
│   │   └── UNIVERSAL_INTEGRATION_SYSTEM.md
│   │
│   ├── 📂 deployment/        # Deployment & setup guides
│   │   ├── AWS_DEPLOYMENT_STRIPE_WEBHOOKS.md
│   │   ├── DOCKER_SETUP.md
│   │   ├── LAUNCH_READY.md
│   │   └── LOCAL_DEVELOPMENT.md
│   │
│   ├── 📂 guides/            # How-to guides
│   │   ├── ANALYTICS_TESTING_GUIDE.md
│   │   ├── RUN_THIS_MIGRATION.md
│   │   └── SUBSCRIPTION_TRACKING.md
│   │
│   ├── 📂 planning/          # Planning documents
│   │   ├── COMPLETE_DAY_SUMMARY.md
│   │   ├── INTEGRATION_CONSOLIDATION_PLAN.md
│   │   └── UX_IMPROVEMENTS_NEEDED.md
│   │
│   ├── INDEX.md              # Documentation index
│   ├── AGENT_ARCHITECTURE.md # V2 agent system
│   ├── WORKFLOW_V2_EXECUTIVE_SUMMARY.md
│   ├── V2_PURE_IMPLEMENTATION.md
│   ├── INTEGRATION_ARCHITECTURE_V2.md
│   ├── RAG_COMPLETE_SUMMARY.md      # RAG Phase 1-3 summary
│   ├── RAG_ARCHITECTURE.md          # RAG technical docs
│   ├── RAG_PERFORMANCE_BENCHMARKS.md
│   ├── PHASE2_EMBEDDING_OPTIMIZATION.md
│   ├── PHASE3_ENHANCED_METADATA.md
│   ├── REDIS_USAGE_CLARIFICATION.md
│   ├── PGVECTOR_ALTERNATIVE.md
│   └── ... (50+ additional docs)
│
├── 📂 lib/                   # Extended libraries
│   ├── 📂 tasks/             # Rake tasks
│   │   └── rag.rake          # RAG management tasks
│   ├── docling_processor.py  # Python Docling processor
│   └── ... (custom libraries)
│
├── 📂 log/                   # Application logs
│   ├── development.log
│   ├── production.log
│   └── test.log
│
├── 📂 public/                # Static files served directly
│   ├── 📂 assets/            # Compiled assets
│   ├── 404.html
│   ├── 422.html
│   ├── 500.html
│   └── robots.txt
│
├── 📂 scripts/               # 🔧 Utility scripts
│   ├── podman-setup.sh       # Container environment setup (Podman/Docker)
│   └── restore_db.sh         # AWS database restore script
│
├── 📂 test/                  # Test suite
│   ├── 📂 controllers/       # Controller tests
│   ├── 📂 fixtures/          # Test data fixtures
│   ├── 📂 helpers/           # Helper tests
│   ├── 📂 integration/       # Integration tests
│   ├── 📂 models/            # Model tests
│   ├── 📂 services/          # Service tests
│   ├── 📂 system/            # System/feature tests
│   ├── test_helper.rb        # Test configuration
│   └── test_phase3.rb        # Phase 3 RAG feature tests
│
├── 📂 tmp/                   # Temporary files
│   ├── 📂 cache/             # Rails cache
│   ├── 📂 pids/              # Process IDs
│   └── 📂 storage/           # Active Storage temp files
│
└── 📂 vendor/                # Third-party code
    └── 📂 bundle/            # Bundled gems (optional)
```

---

## 🗂️ Key Application Directories

### app/services/ (Business Logic)

```
app/services/
├── 📂 agents/                # V2 Phase-Based Workflow System
│   ├── 📂 memory/            # Agent memory system (Redis DB 1)
│   │   └── agent_memory.rb
│   ├── gather_context_executor.rb
│   ├── goal_executor.rb
│   ├── planner_agent_service.rb
│   ├── validation_executor.rb
│   └── workflow_engine.rb
│
├── 📂 tools/                 # Scout Tools (Tool Catalog)
│   ├── base_tool.rb          # Base tool class
│   ├── create_campaign_tool.rb
│   ├── create_landing_page_tool.rb
│   ├── create_rag_store_tool.rb
│   ├── query_rag_store_tool.rb
│   ├── delegate_to_planner_tool.rb
│   ├── list_connections_tool.rb
│   ├── invoke_operation_tool.rb
│   └── ... (20+ tools total)
│
├── bedrock_service.rb        # AWS Bedrock Claude integration
├── docling_bridge_service.rb # Python Docling interface
├── embedding_cache_service.rb # RAG embedding cache (Redis DB 0)
├── rag_store_service.rb      # RAG core service
├── integration_api_service.rb # External API integration
├── scout_ai.rb               # Legacy Scout (being deprecated)
├── scout_conversation_with_tools_service.rb
└── workflow_execution_service.rb
```

### app/models/ (Data Layer)

```
app/models/
├── user.rb                   # User authentication
├── entity.rb                 # Multi-tenant organization
├── campaign.rb               # Email campaigns
├── contact.rb                # Contact management
├── landing_page.rb           # Landing page builder
├── integration.rb            # Integration definitions
├── connection.rb             # User's connected accounts
├── integration_operation.rb  # API endpoint definitions
├── rag_store.rb              # RAG knowledge base metadata
├── scout_message.rb          # Scout conversation history
├── task_session.rb           # User's current task
├── workflow_execution.rb     # Workflow run history
├── workflow_context.rb       # Persistent workflow data
└── ... (30+ models total)
```

### app/controllers/

```
app/controllers/
├── application_controller.rb # Base controller
├── scout_controller.rb       # Scout chat interface (SSE streaming)
├── campaigns_controller.rb   # Campaign management
├── contacts_controller.rb    # Contact management
├── landing_pages_controller.rb
├── integrations_controller.rb
├── connections_controller.rb
└── ... (15+ controllers)
```

---

## 📄 Important Configuration Files

### Environment Configuration

| File | Purpose |
|------|---------|
| `.env` | Local environment variables (NOT in git) |
| `.env.example` | Environment variable template |
| `config/database.yml` | Database connection settings |
| `config/credentials.yml.enc` | Encrypted Rails credentials |

### Key Environment Variables

```bash
# AWS Bedrock (Scout AI)
AWS_REGION=us-east-1
AWS_ACCESS_KEY_ID=...
AWS_SECRET_ACCESS_KEY=...

# Database
DATABASE_URL=postgresql://...

# Redis (Embedding cache DB 0, Agent memory DB 1)
REDIS_URL=redis://redis:6379/0

# OpenAI (RAG embeddings)
OPENAI_API_KEY=sk-...
OPENAI_EMBEDDING_MODEL=text-embedding-ada-002

# Pinecone (RAG vector storage)
PINECONE_API_KEY=...
PINECONE_REGION=us-east-1

# RAG Configuration
RAG_CHUNKING_STRATEGY=semantic
RAG_CHUNK_SIZE=1000
RAG_CHUNK_OVERLAP=200
RAG_EMBEDDING_CACHE_ENABLED=true
RAG_EMBEDDING_BATCH_SIZE=100
RAG_EXTRACT_PAGE_NUMBERS=true
RAG_EXTRACT_HEADINGS=true
RAG_DETECT_TABLES=true
```

### Docker Configuration

| File | Purpose |
|------|---------|
| `Containerfile` | Rails application image |
| `compose.yaml` | Multi-container setup (web, db, redis) |
| `.containerignore` | Files excluded from container build |

---

## 🗃️ Database Structure

**100+ migrations** spanning core features:

### Core Tables
- `users` - User accounts (Devise)
- `entities` - Multi-tenant organizations
- `entity_users` - Entity membership

### Marketing Tables
- `campaigns` - Email campaigns
- `contacts` - Contact database
- `contact_groups` - Contact segmentation
- `email_deliveries` - Campaign delivery tracking
- `email_sequences` - Automated sequences
- `sequence_steps` - Sequence step definitions
- `sequence_enrollments` - Contact enrollments

### Content Tables
- `landing_pages` - Landing page builder
- `landing_page_versions` - Version history
- `social_posts` - Social media content
- `business_profiles` - Entity business info

### Integration Tables
- `integrations` - Integration definitions (Stripe, HubSpot, etc.)
- `connections` - User's connected accounts
- `integration_operations` - API endpoint definitions
- `integration_logs` - API call audit trail
- `webhook_events` - Incoming webhook data

### Agent/Workflow Tables
- `scout_messages` - Chat conversation history
- `task_sessions` - Current user tasks
- `workflow_executions` - Workflow run history
- `workflow_contexts` - Persistent workflow data (key-value)
- `workflow_variables` - Dynamic workflow variables

### RAG Tables
- `rag_stores` - RAG knowledge base metadata
  - Enhanced with Phase 3 metadata columns
  - Tracks page filtering support, chunk statistics

### Background Jobs
- `solid_queue_*` - SolidQueue job tables

---

## 🐍 Python Dependencies

**requirements.txt** (for RAG system):

```
docling>=2.0.0           # IBM document processor
transformers>=4.30.0     # Semantic chunking (BERT tokenizer)
torch>=2.0.0             # Neural network backend
```

**Installation**:
```bash
pip3 install -r requirements.txt
```

---

## 🔧 Utility Scripts

### scripts/podman-setup.sh
Container environment initialization and validation (supports Podman and Docker).

**Usage**:
```bash
./scripts/podman-setup.sh
```

### scripts/restore_db.sh
Restore PostgreSQL database from backup (AWS production).

**Usage**:
```bash
./scripts/restore_db.sh
```

---

## 📦 Asset Pipeline

### JavaScript (Stimulus)
```
app/javascript/
├── application.js           # Entry point
├── controllers/             # Stimulus controllers
│   ├── chat_controller.js   # Scout chat interface
│   ├── canvas_controller.js # Dynamic canvas loading
│   └── ... (10+ controllers)
└── channels/                # Action Cable channels
```

### CSS (Tailwind + Bootstrap)
```
app/assets/
├── stylesheets/
│   ├── application.css      # Main stylesheet
│   └── custom.css           # Custom styles
└── builds/                  # Compiled assets
```

---

## 🧪 Testing Structure

```
test/
├── controllers/             # Controller tests
├── models/                  # Model tests
├── services/                # Service tests
├── integration/             # Integration tests
├── system/                  # System/E2E tests
├── fixtures/                # Test data
│   ├── users.yml
│   ├── entities.yml
│   ├── campaigns.yml
│   └── ... (30+ fixtures)
├── test_helper.rb           # Test configuration
└── test_phase3.rb           # Phase 3 RAG tests
```

**Running Tests**:
```bash
# All tests
rails test

# Specific test file
rails test test/models/campaign_test.rb

# Agent system tests
rails test:agents
```

---

## 📚 Documentation Organization

See **[docs/INDEX.md](INDEX.md)** for complete documentation index.

**Quick Reference**:
- Architecture: `docs/architecture/`
- Deployment: `docs/deployment/`
- Guides: `docs/guides/`
- Planning: `docs/planning/`

---

## 🔍 Finding Things

### By Feature
- **Agent System**: `app/services/agents/`, `docs/AGENT_ARCHITECTURE.md`
- **RAG System**: `app/services/*rag*.rb`, `lib/docling_processor.py`, `docs/RAG_*.md`
- **Integrations**: `app/services/integration_*.rb`, `docs/INTEGRATION_*.md`
- **Scout Chat**: `app/controllers/scout_controller.rb`, `app/javascript/controllers/chat_controller.js`
- **Workflows**: `app/workflow_templates/*.yml`, `app/services/agents/workflow_engine.rb`
- **Tools**: `app/services/tools/`

### By Task
- **Setup locally**: `docs/deployment/LOCAL_DEVELOPMENT.md`
- **Deploy to production**: `docs/deployment/AWS_DEPLOYMENT_STRIPE_WEBHOOKS.md`
- **Create new tool**: `app/services/tools/base_tool.rb` (base class)
- **Create workflow**: `docs/WORKFLOW_TEMPLATES_GUIDE.md`
- **Test features**: `test/` + `docs/guides/ANALYTICS_TESTING_GUIDE.md`

---

## 🚀 Getting Started

1. **Clone repository**
2. **Install dependencies**: `bundle install && yarn install && pip3 install -r requirements.txt`
3. **Setup database**: `rails db:create db:migrate db:seed`
4. **Configure environment**: Copy `.env.example` to `.env` and fill in values
5. **Start server**: `bin/dev` (runs Rails + asset compilation)
6. **Visit**: `http://localhost:3000`

**See**: [docs/deployment/LOCAL_DEVELOPMENT.md](deployment/LOCAL_DEVELOPMENT.md)

---

## 📊 Project Stats

- **Ruby Version**: 3.2.x
- **Rails Version**: 8.0
- **Node Version**: 20.x
- **Database**: PostgreSQL 16
- **Cache**: Redis 7
- **Background Jobs**: SolidQueue
- **AI Provider**: AWS Bedrock (Claude Sonnet 4.5)
- **Vector DB**: Pinecone
- **Document Processor**: Docling 2.0

**Lines of Code** (approximate):
- Ruby: ~50,000 lines
- JavaScript: ~5,000 lines
- Documentation: ~30,000 lines

---

**Last Updated**: October 16, 2025 (Phase 3 RAG complete)
