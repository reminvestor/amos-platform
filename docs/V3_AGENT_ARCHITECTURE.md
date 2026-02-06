# V3 Agent Architecture: Simple Core + Platform Knowledge

> **Key realization**: We already have SkillLibraryService, GuidanceLibrary,
> DynamicContextService, AgentLoadout, and ScoutLoadoutConfiguration.
> V3 is NOT about building new systems — it's about making these the PRIMARY
> mechanism and removing the complex preprocessor/tool-discovery layers
> that sit on top of them and cause failures.

## The Problem

V2 has 157 tools, a regex intent classifier, RAG-based tool discovery, LLM refinement,
a preprocessor pipeline, and multiple layers of context injection. Despite this complexity:

- The agent picks the wrong tool (PDF reading, workflow creation)
- The preprocessor "fast path" drops needed tools
- Adding new capabilities requires modifying regex patterns
- 4,000+ line service files are hard to maintain
- Latency from preprocessing (500-1500ms overhead)

**The core issue: We built complexity to help the model pick tools, but the complexity
itself causes tool selection failures.**

## The Insight (from Pi)

Pi gives the model 4 tools (`read`, `write`, `edit`, `bash`) and it figures out
everything. The model is smarter than our regex classifier. The harness should be
simple; the intelligence should be in the model.

But AMOS is not a coding agent on a local filesystem. It's a multi-tenant SaaS platform.
We need the simplicity of Pi's approach with platform-aware power tools.

## V3 Architecture

### Core Principle: The Platform IS the Agent's Workspace

Instead of 157 specialized tools, the agent has:
1. **Power tools** for direct platform interaction (~10 tools)
2. **Platform skills** — markdown knowledge the model reads on demand
3. **Guardrails** — security, permissions, cost controls
4. **Compaction** — smart context management, not truncation

### Power Tools (~10)

| Tool | Purpose | Equivalent |
|------|---------|------------|
| `platform_query` | Read any platform data (contacts, campaigns, bounties, etc.) | Replaces: get_data, get_schema, list_*, view_* |
| `platform_create` | Create any platform object | Replaces: create_object, create_*, generate_* |
| `platform_update` | Update any platform object | Replaces: update_object, update_* |
| `platform_execute` | Execute platform operations (integrations, automations) | Replaces: execute_integration, generate_automation_code |
| `web_search` | Search the web | Same as current |
| `bash` | Execute commands in sandboxed environment | NEW — Pi-inspired |
| `read_file` | Read uploaded documents, knowledge base | Replaces: read_document, query_document_content |
| `load_canvas` | Show visual content to user | Same as current |
| `ask_user` | Ask user a question | Same as current |
| `discover` | Search platform capabilities, skills, integrations | Replaces: discover_tools, list_tools, list_integrations |

That's 10 tools. The model doesn't need to choose between `create_contact` and
`create_campaign` and `create_landing_page` — it uses `platform_create` with
`{ type: "contact", data: {...} }`. The tool knows how to route internally.

### The `bash` Tool (Sandboxed)

This is the game-changer. The agent can:
- Run `curl` to test APIs
- Run `git` to check code
- Run `jq` to parse JSON
- Execute Ruby scripts for complex platform operations
- Install tools it needs via `apt` or `gem`

**But sandboxed:**
- Runs in a Docker container with read-only filesystem
- No network access to internal services (only public APIs)
- Time-limited (30 second max execution)
- Output truncated to 10KB
- Destructive commands blocked (rm -rf, drop database, etc.)
- Per-user execution isolation

### Platform Skills (Markdown)

Instead of 150 tool definitions, platform knowledge lives in markdown files
that the model reads on demand. Skills are loaded into the system prompt
only when relevant.

```
skills/
  platform/
    contacts.md          # How contacts work, fields, relationships
    campaigns.md         # Campaign types, email sequences, analytics
    landing-pages.md     # Plan → Build workflow, design system
    integrations.md      # How to connect Stripe, QuickBooks, etc.
    workflows.md         # Automation triggers, actions, conditions
    modules.md           # Custom app builder, schema design
    bounties.md          # Bounty system, token economics
    eap.md               # External Agent Protocol
  recipes/
    lead-capture.md      # Complete recipe: LP → Form → Contact → Email
    email-campaign.md    # Recipe: Create and send email campaign
    data-import.md       # Recipe: Import from CSV/API
    integration-setup.md # Recipe: Connect a new integration
  context/
    current-state.md     # Auto-generated: what's deployed, active, etc.
    recent-changes.md    # Auto-generated: what changed recently
```

When a user says "create a workflow for lead capture", the model:
1. Uses `discover` to find the `lead-capture.md` recipe
2. Uses `read_file` to read it
3. Follows the instructions, using `platform_create` and `platform_execute`
4. If it needs to build something new, it builds it and the knowledge persists

### Platform Knowledge Growth

This is the key insight from the user: **once the agent builds something,
it should know about it next time.**

When the agent creates a new integration:
1. It builds it using `platform_create` and `platform_execute`
2. On success, it writes a skill file: `skills/integrations/stripe-setup.md`
3. Next time someone asks about Stripe, the agent reads that skill
4. The agent improves the skill over time with new learnings

This is **organic platform intelligence** — the agent gets smarter by working.

### Guardrails

Security and safety don't go away — they get simpler:

```
guardrails/
  permissions.rb     # Entity isolation, role-based access
  cost_controls.rb   # Token limits, rate limiting
  bash_sandbox.rb    # Docker execution, blocked commands
  policy_rules.rb    # Confirmation for destructive ops
  audit_log.rb       # Every tool call logged
```

Key rules:
- Every `platform_*` call is scoped to the current entity
- `bash` runs in an isolated Docker container
- Destructive operations require user confirmation
- All tool calls are logged for audit
- Token/cost limits enforced before LLM call

### Agent Loop (Simple)

```
┌─────────────────────────────────────────────────────────┐
│                     AGENT LOOP (v3)                      │
│                                                          │
│  1. Build system prompt                                  │
│     - Core identity (who is AMOS)                        │
│     - User context (name, role, entity)                  │
│     - Active skills (loaded based on canvas/context)     │
│     - Platform state summary (auto-generated)            │
│                                                          │
│  2. Send to LLM with 10 power tools                     │
│                                                          │
│  3. Execute tool calls                                   │
│     - Apply guardrails (permissions, sandbox)             │
│     - Log for audit                                      │
│     - Return results                                     │
│                                                          │
│  4. If more tool calls → go to 2                         │
│     If done → return response                            │
│                                                          │
│  5. Compact if context too long                          │
│     - Summarize old turns                                │
│     - Preserve recent context + key facts                │
│                                                          │
└─────────────────────────────────────────────────────────┘
```

No preprocessor. No intent classifier. No RAG tool discovery. No LLM refinement.
The model has 10 tools and platform skills. It figures out the rest.

### Conversation Compaction

When context exceeds ~80% of the model's window:
1. Take the oldest 60% of messages
2. Ask the LLM to summarize key facts, decisions, and state
3. Replace those messages with the summary
4. Continue with the summary + recent 40%

This is better than truncation because:
- No information loss (facts are preserved in summary)
- The model knows what it discussed earlier
- Sessions can run indefinitely

### Migration Path (Incremental)

We don't have to rewrite everything at once:

**Phase 1: Power Tools** (this branch)
- Build `platform_query`, `platform_create`, `platform_update`, `platform_execute`
- Build sandboxed `bash` tool
- Build `discover` tool that searches skills
- Keep old tools as fallback

**Phase 2: Simple Agent Loop**
- New `AgentLoopV3` service that uses only power tools
- Runs alongside V2 (feature flag)
- No preprocessor, no intent classifier
- Direct system prompt → LLM → tools → repeat

**Phase 3: Platform Skills**
- Convert platform knowledge to markdown skills
- Auto-generate `current-state.md` and `recent-changes.md`
- Skill growth: agent writes new skills on success

**Phase 4: Compaction**
- Implement conversation summarization
- Replace context truncation
- Add session branching

**Phase 5: Deprecate V2**
- Remove preprocessor, intent classifier, RAG discovery
- Remove 150 specialized tools
- V3 becomes the default

### What We Keep

- Canvas system (load_canvas, visual builders)
- Authentication and entity isolation
- Billing and token economics
- EAP (External Agent Protocol)
- GitHub webhooks and bounty pipeline
- Solana programs
- All the domain models (Contact, Campaign, etc.)

### What We Already Have (USE, don't rebuild)

- **SkillLibraryService** — discovers skills from integrations, canvas, keywords, custom uploads
- **GuidanceLibrary** — task-specific expertise injection with detect_task_type
- **DynamicContextService** — computes context on-the-fly based on canvas + message
- **AgentLoadout** — bounded capabilities per role with budgets and confirmations
- **ScoutLoadoutConfiguration** — per-entity tool tiers (core/configurable)
- **UserSkill model** — custom uploaded skills per entity
- **LoadoutOptimizationService** — tracks which tools are actually used
- **Learning system** — ScoutLearning, TaskExperience, SemanticAdvantage

V3 promotes these from "layers on top of V2" to "the primary mechanism."

### What We Simplify/Remove

- UnifiedPreprocessorService → replace with DynamicContextService (already exists)
- 150 specialized tool classes → consolidate into ~10 power tools
- Regex intent classifier → model decides, GuidanceLibrary provides context
- Fast path logic → remove entirely
- RAG tool discovery → `discover` tool (model searches when needed)
- SmartRequestRouter → remove
- TieredDiscoveryService → remove (model uses `discover` on demand)

### Expected Outcomes

1. **Fewer tool selection failures** — 10 tools, no wrong choices
2. **Lower latency** — no preprocessing overhead
3. **Easier to extend** — add a skill file, not a Ruby class
4. **Platform knowledge grows** — agent learns from its work
5. **Simpler codebase** — agent loop under 500 lines
6. **Better for EAP** — external agents use same simple tool set
