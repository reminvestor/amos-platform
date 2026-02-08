# Intent Engine Architecture - Status & Next Steps

## Architecture Overview

Two-tier agent system:
- **Amos (Qwen)** = user-facing translator with 9 LLM tools
- **Platform Brain (Claude Sonnet)** = backend executor with platform CRUD + external tools

## Current Branch: `v3/intent-engine-architecture` (merged to dev)

## What's Working
- Intent Engine routing (Amos → IntentEngine → PlatformBrain)
- Landing page creation via Brain (with progress streaming)
- Automation creation via Brain (welcome email automation triggers correctly)
- Contact management, queries, web search, document reading
- Automation dashboard (self-loading from DB)
- Media library integration in editor (CSRF token + JSON key fix)
- Conversation history poisoning filter (tool-as-text messages filtered)
- Landing page editor (component sidebar hidden, drop zones removed)

## Security - MUST DO BEFORE PROD

### A. CAMEL / QuarantinedLlmService
- File exists: `app/services/quarantined_llm_service.rb`
- **NOT WIRED IN** - never used anywhere
- Needs to be integrated into PlatformBrain for goals involving external/untrusted data
- Key scenarios: email content, document content, web scraping, integration data
- The quarantined LLM extracts data WITHOUT tool access, preventing embedded instructions

### B. Confirmation Gate for Destructive Operations
- PlatformBrain should flag destructive ops (send_email, delete, export_data)
- Brain returns `needs_confirmation: true` with a description
- Amos asks the user to confirm before the Brain proceeds
- This catches prompt injection even if CAMEL misses it

### C. Entity Scope Audit
- All V3 tools use `entity` from BaseTool (injected by controller, not LLM)
- PlatformQueryTool: all queries scoped to entity ✓
- PlatformCreateTool: all creates use entity ✓
- PlatformUpdateTool: finds records via entity ✓
- PlatformExecuteTool: scoped to entity ✓
- **Need to verify**: PlatformBrain passes correct entity through to tool execution
- **Need to verify**: No tool accepts entity_id as a user-supplied parameter

## Known Issues - Fix Before Prod

### 1. Automation Dashboard Drill-down
- Clicking an automation in the dashboard refreshes instead of showing detail
- Need: automation detail view canvas or modal

### 2. Integrations as Subset of Automations
- User asked: "create automation when new Stripe customer → create contact"
- Brain created wrong type (AutomationCode with webhook trigger, create_activity action)
- Should use: IntegrationSyncConfig (type: "sync") for this pattern
- **Design decision**: Unify integrations and automations under one concept
- The Pi strategy: automations ARE the abstraction, integrations are just triggers/actions

### 3. Interactive Iframe Viewer
- Picture-in-picture bug when streaming web pages (pre-existing)

### 4. Thinking Indicator
- Still sometimes appears during Brain execution despite fix

### 5. Docker Restart Conversation Poisoning
- Root cause: Qwen outputs tool syntax as text, gets saved to DB
- Mitigated: filter in persisted_history_last_k
- Not fixed: Qwen still does this occasionally

## Files Changed (16 commits)
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
