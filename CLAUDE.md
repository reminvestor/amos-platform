# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

### Development (Podman - Recommended)
```bash
# Start all services (Rails, PostgreSQL, Redis, LocalStack, SolidQueue)
podman compose up -d

# View logs
bin/podman-logs web

# Run Rails console in container
podman compose exec web rails console

# Run database operations in container
podman compose exec web rails db:migrate
podman compose exec web rails db:seed

# Restart web service after code changes (if needed)
podman compose restart web
```

### Development (Local - Alternative)
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

**AI Model**: Uses AWS Bedrock Claude Sonnet 4.6 (configured in `BedrockService`)

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

## Voice Assistant System

The application includes a sophisticated voice-to-text transcription system with intelligent fallback capabilities, health monitoring, error recovery, and performance optimization.

**Speech-to-Text Providers**:
1. **Primary**: Eleven Labs Scribe v2 Realtime
   - Ultra-low latency (~150ms)
   - 90+ language support
   - Superior accuracy across accents and tones
   - Technical vocabulary and proper noun recognition
   - WebSocket-based real-time streaming

2. **Fallback**: Deepgram (automatic failover)
   - Active fallback if Eleven Labs unavailable
   - Seamless provider switching with user notification
   - Comprehensive logging for monitoring

**Core Services**:
- `ElevenLabsTranscriptionService` - Credential and config management
- `VoiceProviderHealthService` - Health monitoring and status tracking
- `VoiceConnectionRetryService` - Error recovery with exponential backoff and circuit breaker
- `VoiceMetricsService` - Usage analytics, performance tracking, comparative analysis
- `VoiceConnectionOptimizer` - Performance optimization (caching, prewarming, pooling)

**Controllers**:
- `Api::Voice::VoiceSessionsController` - Session and credential endpoints
- `Api::Voice::HealthController` - Health monitoring and analytics endpoints

**Key Features**:
- Pre-initialized credentials for instant mic activation
- Automatic provider fallback with intelligent retry logic (exponential backoff)
- Circuit breaker pattern to prevent cascading failures
- 16-bit PCM audio at 16kHz (telephony quality)
- Voice Activity Detection (VAD)
- Partial and final transcript handling
- Multi-language configuration and keyword boosting
- Real-time health monitoring
- Comprehensive metrics and analytics
- Performance optimization (credential caching, connection pre-warming)

**Health Monitoring Endpoints**:
- `GET /api/voice/health/status` - Overall system health
- `GET /api/voice/health/providers` - Provider-specific status and metrics
- `GET /api/voice/health/metrics?days=7` - Usage and performance analytics
- `GET /api/voice/health/optimization` - Optimization recommendations
- `POST /api/voice/health/prewarm` - Manual connection pre-warming

**Configuration**:
- `ELEVEN_LABS_API_KEY` - Required for primary provider
- `DEEPGRAM_API_KEY` - For fallback provider (optional but recommended)
- See `.env.example` for full voice configuration

**Monitoring & Debugging**:
- Health endpoint: `/api/voice/health/status`
- Metrics dashboard: `/api/voice/health/metrics`
- Optimization guide: `/api/voice/health/optimization`
- Browser console for provider logs
- Format: `📊 Session used STT provider: Eleven Labs Scribe v2` or `Deepgram (fallback)`

**Documentation**:
- `docs/VOICE_SYSTEM_MONITORING.md` - Complete guide to monitoring, optimization, and troubleshooting

## UI Architecture

- **Backend**: Rails 8 with Turbo/Stimulus
- **Frontend**: Bootstrap 5, minimal JavaScript
- **Chat Interface**: Stimulus controller (`app/javascript/controllers/chat_controller.js`)
- **Canvas System**: Dynamic UI loading (landing page editor, campaign dashboard)
- **Voice Input**: WebSocket-based real-time transcription (`app/javascript/controllers/voice_assistant_controller.js`)

## Flutter Mobile App

The mobile app (`flutter_mobile/`) is a Flutter-based iOS/Android client that connects to the Rails API running in containers.

### Prerequisites
- Containers must be running (`podman compose up -d`)
- Rails API available at `http://localhost:3000`

### Running the Mobile App
```bash
cd flutter_mobile
flutter pub get

# Run on iOS Simulator (connects to containerized Rails API)
flutter run -d "iPhone 16 Pro" --dart-define=API_BASE_URL=http://localhost:3000

# Run on Android Emulator (use 10.0.2.2 for localhost from emulator)
flutter run -d emulator --dart-define=API_BASE_URL=http://10.0.2.2:3000

# Run on physical device (use your machine's IP)
flutter run --dart-define=API_BASE_URL=http://192.168.x.x:3000
```

### Development Workflow
1. Start services: `podman compose up -d`
2. Verify API is running: `curl http://localhost:3000/api/auth/me`
3. Run Flutter app with API_BASE_URL pointing to container
4. Changes to Rails code auto-reload in container
5. Flutter hot-reload works as normal (`r` in terminal)

### Mobile Authentication Architecture

**CRITICAL: All services must use ApiClient for authentication consistency.**

**Token Storage Strategy**:
- **In-memory cache** (`ApiClient.instance._cachedToken`) - Primary, most reliable
- **flutter_secure_storage** - Persistence for app restart (can be unreliable on iOS simulator)
- After login, `AuthService` sets the token via `ApiClient.instance.setAuthToken(token)`

**ApiClient Singleton Pattern**:
```dart
// CORRECT - all services should use this pattern:
final ApiClient _api = ApiClient();  // Returns singleton via factory constructor

// Token is automatically added via Dio interceptor
final response = await _api.get('/api/v1/agents');
```

**Services needing own Dio** (for SSE streaming, file uploads, WebSockets):
```dart
// Use getAuthToken() to access the cached token
final token = await ApiClient.instance.getAuthToken();
if (token == null) throw Exception('Not authenticated');

// Then use with custom Dio instance
final response = await _dio.post(url, options: Options(
  headers: {'Authorization': 'Bearer $token'},
));
```

**Key Files**:
- `lib/services/api_client.dart` - Central HTTP client with auth interceptor
- `lib/services/auth_service.dart` - Login/logout/MFA handling
- `lib/providers/auth_provider.dart` - Riverpod auth state management
- `lib/services/storage_service.dart` - Secure storage wrapper

**Authentication Flow**:
1. User logs in via `AuthService.login(email, password)`
2. Server returns `api_key` token
3. Token is stored: `ApiClient.instance.setAuthToken(token)` (caches in memory + writes to storage)
4. All subsequent requests use interceptor to add `Authorization: Bearer <token>` header
5. 401 errors with valid token clear the cached token (invalid/expired)
6. 401 errors without token do NOT clear cache (prevents cascade failures)

**API Endpoints Used by Mobile**:
- `POST /api/auth/login` - Login (returns api_key)
- `POST /api/auth/logout` - Logout
- `GET /api/auth/me` - Check auth status
- `POST /mfa/verify` - MFA code verification
- `GET /api/v1/agents` - List agents
- `GET /api/v1/campaigns` - List campaigns
- `GET /api/v1/tasks` - List tasks
- `POST /amos/chat_stream` - SSE chat endpoint (also available as `/scout/chat_stream`)
- `POST /amos/new_session` - Create new chat session
- `GET /amos/questions/pending` - Agent questions queue
- `POST /amos/questions/:id/answer` - Answer agent question
- `POST /amos/questions/:id/skip` - Skip agent question
- `POST /amos/upload_files` - File uploads
- `GET /amos/document-status/:asset_id` - Document indexing status

Note: Both `/amos/` and `/scout/` endpoints are supported. Mobile uses `/amos/`, web app uses `/scout/`.

**Rails API Authentication**:
```ruby
# API controllers use authenticate_api_user! (via api_key)
def authenticate_api_user!
  token = request.headers["Authorization"]&.gsub(/^Bearer /, "")
  @current_user = User.find_by(api_key: token)
  render json: { error: "Unauthorized" }, status: :unauthorized unless @current_user
end

# Amos controllers support both web (Devise) and mobile (api_key)
def authenticate_user_or_api!
  token = request.headers["Authorization"]&.gsub(/^Bearer /, "")
  if token.present?
    @current_user = User.find_by(api_key: token)
    render json: { error: "Invalid token" }, status: :unauthorized unless @current_user
  else
    authenticate_user!  # Devise web auth
  end
end
```

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
- `VOICE_SYSTEM_MONITORING.md` - Voice system health, monitoring, analytics, and optimization
