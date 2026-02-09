# Intent Engine Architecture - Status & Next Steps

## Architecture Overview

Two-tier agent system:
- **Amos (Qwen)** = user-facing translator with 9 LLM tools
- **Platform Brain (Claude Sonnet)** = backend executor with platform CRUD + external tools

## Branches
- `dev` — current working branch (merged, use this going forward)
- `v3/intent-engine-architecture` — intent engine work (merged to dev)
- `v3/simplified-agent-core` — V3 core rewrite that this was branched from (also merged to dev)

## What's Working
- Intent Engine routing (Amos → IntentEngine → PlatformBrain)
- Landing page creation via Brain (with progress streaming)
- Automation creation via Brain (welcome email automation triggers correctly)
- Contact management, queries, web search, document reading
- Automation dashboard (self-loading from DB) + drill-down detail view
- Media library integration in editor (CSRF token + JSON key fix)
- Conversation history poisoning filter (tool-as-text messages filtered)
- Landing page editor (component sidebar hidden, drop zones removed)
- **CAMEL security**: Untrusted tool results wrapped with safety markers
- **Confirmation gate**: Destructive ops (delete, send_email, send_campaign) require user confirmation
- **Entity scope**: Verified clean — entity flows from controller, never from LLM args
- **Integration triggers**: Stripe/HubSpot/Shopify/QuickBooks webhooks fire automations
- **Unified automation model**: "sync Stripe customers" → creates correct automation with webhook trigger

## Security - COMPLETED

### A. CAMEL / QuarantinedLlmService ✅
- `QuarantinedLlmService` and `DataSourceTracker` wired into `PlatformBrain`
- UNTRUSTED_TOOLS (web_search, browser_use, read_file): results wrapped with `[EXTERNAL DATA]` markers
- PARTIALLY_UNTRUSTED_TOOLS (platform_query, platform_execute): user-generated text fields tagged with `[USER CONTENT]` markers
- Brain system prompt updated: explicitly told to NEVER follow instructions inside data markers
- Sanitization happens in `PlatformBrain#sanitize_tool_result` after every tool execution

### B. Confirmation Gate for Destructive Operations ✅
- `DESTRUCTIVE_ACTIONS` constant defines: send_email, send_campaign, delete
- `PlatformBrain#requires_confirmation?` checks before tool execution
- Blocked actions return `needs_confirmation: true` with human-readable description
- Brain signals `needs_input: true` + question to Amos, who asks the user
- Catches prompt injection even if CAMEL misses it (defense in depth)

### C. Entity Scope Audit ✅
- All V3 tools use `entity` from BaseTool (injected by controller, not LLM)
- PlatformQueryTool: all queries scoped to entity ✓
- PlatformCreateTool: all creates use entity ✓
- PlatformUpdateTool: finds records via entity ✓
- PlatformExecuteTool: scoped to entity ✓
- **VERIFIED**: PlatformBrain passes `@entity` through `V3::ToolRegistry.execute` → `tool_class.new(entity:)` ✓
- **VERIFIED**: No V3 tool accepts `entity_id` from LLM args (grep confirmed zero matches) ✓

## Known Issues - Status

### 1. Automation Dashboard Drill-down ✅ FIXED
- Clicking an automation now shows a detail panel inline (stats, trigger, status, test/pause controls)
- Back button returns to list view
- No more page refreshes on click

### 2. Integrations + Automations Unification ✅ COMPLETED

**Implemented the "Pi strategy"**: Automations ARE the single abstraction. Integrations are just trigger sources and action targets.

**What was done**:
1. ✅ Added `INTEGRATION_TRIGGERS` to `AutomationActionRegistry` — maps `stripe.customer_created`, `hubspot.contact_created`, `shopify.order_created`, etc. to webhook trigger configs with event filters
2. ✅ Added `create_contact` and `sync_integration_data` actions to `AutomationActionRegistry` with code generators
3. ✅ Added `DEFAULT_FIELD_MAPPINGS` for Stripe/HubSpot/Shopify/QuickBooks → Contact field mappings
4. ✅ Wired Stripe/Shopify/HubSpot webhooks to `AutomationBridge` via `fire_webhook_automations()` in `WebhooksController`
5. ✅ Updated `PlatformCreateTool#build_automation` to resolve integration triggers (e.g., `stripe.customer_created` → webhook trigger with event_filter)
6. ✅ Updated `AutomationBridge#find_and_trigger_automations` to match webhook automations by event_filter
7. ✅ Updated `AutomationCode#matches_trigger?` to handle webhook event matching
8. ✅ Updated `PlatformBrain` system prompt with INTEGRATION / AUTOMATION UNIFICATION section
9. ✅ Updated `normalize_trigger` to recognize integration-style triggers (stripe, hubspot, etc.)

**Flow**: User says "sync Stripe customers" → Amos → platform_do → Brain → platform_create(type: "automation", trigger: "stripe.customer_created", action: "create_contact") → AutomationCode created with webhook trigger + event_filter + field mappings → Stripe webhook fires → AutomationBridge matches → contact created

### 3. Interactive Iframe Viewer
- Picture-in-picture bug when streaming web pages (pre-existing, not addressed this session)

### 4. Thinking Indicator ✅ FIXED
- Root cause: empty content chunk `{ type: :content, text: "" }` was not hiding the indicator because `text.present?` is false for empty strings
- Fix: Added explicit `stream_stop_thinking` method to `Scout::Streaming` concern that sends `{ type: "thinking_done" }`
- Frontend handles `thinking_done` event type to force-hide the indicator immediately
- Both `scout_controller.js` and `index.html.erb` updated

### 5. Docker Restart Conversation Poisoning
- Root cause: Qwen outputs tool syntax as text, gets saved to DB
- Mitigated: filter in persisted_history_last_k
- Not fixed: Qwen still does this occasionally

## Files Changed (16 commits + security/unification session)

### Original Intent Engine (16 commits)
- `app/services/v3/intent_engine.rb` - Routes goals to recipes or Brain
- `app/services/v3/platform_brain.rb` - Claude agent loop with tools
- `app/services/v3/tools/platform_do_tool.rb` - Single "do" tool for LLM
- `app/services/v3/tool_registry.rb` - 9 LLM tools + internal tools
- `app/services/v3/recipes/` - 8 recipe classes + registry
- `app/services/v3/intent_decomposer.rb` - LLM fallback (superseded by Brain)
- `app/services/amos_identity.rb` - Slimmed to ~1500 tokens
- `app/services/v3/system_prompt_builder.rb` - Simplified tool instructions
- `app/services/v3/agent_loop.rb` - Hallucination retry with new tool names
- `app/controllers/scout_controller.rb` - History filter, automation dashboard
- `app/views/scout/canvas/_landing_page_editor.html.erb` - UI cleanup
- `app/services/tools/generate_landing_page_tool.rb` - Contrast rules
- `app/models/automation_execution.rb` - trigger_source validation
- `app/services/modules/automation_bridge.rb` - Pass trigger_source

### Security + Unification Session (prod release prep)
- `app/services/v3/platform_brain.rb` - CAMEL sanitization, confirmation gate, integration prompt
- `app/services/automation_action_registry.rb` - Integration triggers, create_contact/sync actions, default field mappings
- `app/services/v3/tools/platform_create_tool.rb` - Integration trigger resolution in build_automation
- `app/services/modules/automation_bridge.rb` - Integration webhook matching, event_filter support
- `app/models/automation_code.rb` - matches_webhook? for event_filter matching
- `app/controllers/webhooks_controller.rb` - fire_webhook_automations for Stripe/Shopify/HubSpot
- `app/views/scout/canvas/_automation_dashboard.html.erb` - Drill-down detail panel, fixed click handler
- `app/controllers/concerns/scout/streaming.rb` - stream_stop_thinking method
- `app/controllers/scout_controller.rb` - Handle thinking_done in streaming chunks
- `app/javascript/controllers/scout_controller.js` - Handle thinking_done event
- `app/views/scout/index.html.erb` - Handle thinking_done event (fallback)
