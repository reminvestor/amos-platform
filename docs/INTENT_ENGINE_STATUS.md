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

### 2. Integrations + Automations Unification (Major Design Work)

**Problem**: The platform has two separate systems that confuse both users and the LLM:
- **Automations** (`AutomationCode`) — internal triggers (contact_created, form_submit, schedule)
- **Integration Syncs** (`IntegrationSyncConfig`) — external data syncs (Stripe customers → Contacts)

When user says "when a new Stripe customer is created, create a contact," the Brain doesn't know which system to use. It created an AutomationCode with webhook trigger and create_activity action — which is wrong.

**Design Direction (Pi strategy)**: Automations should be THE single abstraction. An integration is just a trigger source or action target within an automation. The user shouldn't think about "syncs" vs "automations" — they should just say what they want and the platform handles it.

**What exists today**:
- `AutomationCode` model — trigger_type (record_created, form_submit, webhook, schedule, etc.) + code
- `AutomationActionRegistry` — generates code for actions (send_email, update_field, etc.)
- `IntegrationSyncConfig` model — maps external data to internal models
- `AutomationBridge` service — fires automations when records are created/updated
- `AutomationTriggerJob` — background execution of automation code
- `Modules::AutomationBridge` — connects record events to automation triggers
- Webhook infrastructure exists but isn't fully wired for Stripe customer events

**What needs to happen**:
1. Add integration triggers to AutomationActionRegistry (stripe.customer_created → create_contact)
2. Wire Stripe webhooks to the AutomationBridge so they fire automations
3. Add "integration" actions to the registry (pull_stripe_data, sync_hubspot_contacts)
4. Update PlatformBrain system prompt to understand this unified model
5. Ensure PlatformCreateTool's `build_automation` handles integration triggers correctly
6. Build or fix the webhook receiver endpoint for Stripe events
7. Test: user says "sync Stripe customers" → Brain creates correct automation

**Key files**:
- `app/services/automation_action_registry.rb` — action templates
- `app/services/automation_code_executor.rb` — runs automation code
- `app/services/modules/automation_bridge.rb` — event → automation dispatcher
- `app/models/automation_code.rb` — the automation model
- `app/models/integration_sync_config.rb` — the sync model (may be merged into automations)
- `app/jobs/automation_trigger_job.rb` — background execution
- `app/services/v3/tools/platform_create_tool.rb` — build_automation, build_sync methods
- `app/controllers/api/v1/webhooks_controller.rb` — webhook receiver (check if exists)

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
