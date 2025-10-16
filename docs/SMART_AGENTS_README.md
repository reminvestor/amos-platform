# Smart Agents, Tools, and Canvas Governance (High-Level)

## Goals
- Minimize LLM context while maximizing capability and reliability
- Enforce least-privilege tool and data access per agent/task
- Stream results quickly via prebuilt or dynamic canvases without dumping raw payloads into chat

## Current System (brief)
- Orchestration: `ScoutGenericToolsService`, native Bedrock tool calling, SSE to frontend
- Workflows: `WorkflowEngine`, `TaskSession`, `TaskEvent`
- Tools: `ToolRunner`, `ToolRegistry`, integrations via `IntegrationApiService`
- UI: `scout_controller.js` streams `tool_*`, `intermediate_message`, `load_canvas`; canvases via `ScoutController#load_canvas`

## Target Architecture
- Memory layers:
  - Session Summary: short rolling summary + user/entity profile
  - Task Memory: per-`TaskSession` DAG, step state, references to artifacts
  - Artifacts Store: datasets/aggregates saved with metadata (schema, count, sample, storage_ref)
- Minimal context packing:
  - Build LLM prompts from: session summary + task summary + current step brief + tool contracts + artifact summaries (no bulk rows)
  - Refer to data by `artifact_id`; request samples/aggregates via tools
- Multi-agent roles:
  - Planner: turns user intent into a DAG with explicit data needs/outputs (artifacts)
  - Executor: runs tools, normalizes inputs, returns artifacts not inline payloads
  - Analyst: computes aggregates/comparisons via server-side aggregation tools
  - Verifier: checks plan completeness/quality, triggers fill-gaps steps
  - Guard: policy/rate-limit/redaction/circuit-breaker

## Plan Compiler → Agent Loadout (bounds & governance)
- For every plan (DAG) the Planner also emits an Agent Loadout per step:
  - agent_role: planner | executor | analyst | verifier
  - tool_allowlist: exact tool names and versions the step may call
  - canvas_allowlist: which canvases can be loaded (or none)
  - data_scopes:
    - read: list of artifact_ids and allowed fields/aggregations
    - write: artifact namespaces the step can create/update
  - budgets: token, time, and max_tool_calls (e.g., 20); retry policy; rate-limit tier
  - confirmations: whether two-phase write is required for this step
  - prompts: compact, role-specific instructions + context recipe (artifact summaries only)

- The loadout is persisted on the step in `TaskSession` and referenced during execution.

## Execution Enforcement (runtime)
- ToolRunner validates on each call:
  - step_id matches active step and agent_role
  - tool is in step.tool_allowlist
  - resource policy via PolicyEngine (connection/integration/operation allowlists)
  - data scope: artifact access by ID; deny raw payload injection to LLM
- Context Assembler builds the minimal context from the step’s loadout and artifact summaries.
- Canvas Governance at runtime:
  - Only canvases in step.canvas_allowlist may be loaded; otherwise ignored
  - Default is none for Planner/Verifier; Analyst may use dynamic_canvas/analytics_dashboard; Executor only when configuring integrations
- Streaming guards:
  - Intermediate messages must be summary-only; PII redacted; no raw arrays

## Escalation & Handoff
- Verifier can request a constrained re-plan: adds missing capabilities/scopes to specific steps.
- Planner updates the DAG and emits revised loadouts; TaskSession records the diff and rationale.

## Observability (enforced bounds)
- Each tool call log includes: agent_role, step_id, allowed_tool, policy_decision, data_scope_used, artifact_ids, denial_reasons.
- Per-step metrics: tokens, duration, retries, rate-limit events.

## Smart Tool Management
- Tool allowlists per agent and per step
- Contract-first: strict JSON Schemas; input alias normalization (operation vs operation_id, params vs parameters)
- Idempotency and pagination helpers; `fetch_next_page(artifact_id)` tracked in tool cache
- Two-phase writes for mutating ops; dry-run + confirm

## Canvas Governance
- Agent → Canvas matrix:
  - Planner: task_progress only
  - Executor: integrations_manager (when configuring) and dynamic_canvas (for quick tables) as needed
  - Analyst: dynamic_canvas, analytics_dashboard
  - Verifier: task_progress status only
- Dynamic Canvas consumes `artifact_id` + render spec (table/chart); never raw dumps in chat

## Observability & Safety
- Correlation IDs across tools, artifacts, canvases, and tasks
- Policy engine checks (resource, scope); redaction of PII from streamed messages
- Rate-limit/backoff in `IntegrationApiService`; structured logging in `IntegrationLog`

## Prompt & Autonomy Guards
- System prompts enforce: "Do not include raw records; use artifacts and aggregation tools"
- Planner prompt: prefer server-side aggregation; page only when required
- Executor/Analyst prompts: minimal, contract-focused; reject oversize inputs

## Phased Rollout (no-code outline)
1. Artifact-first results: normalize `invoke_operation` to return artifacts and stream dynamic canvas summaries
2. Aggregation tools: group_by_time/top_k/pivot/stats; pagination manager and tool cache
3. Multi-agent activation: Planner/Executor/Analyst/Verifier roles bound to `TaskSession`
4. Canvas governance: render by artifact_id; chart presets; export controls
5. Observability & safety hardening: quotas, alerts, policy rules, redaction

## Success Criteria
- Lower token usage per turn; faster end-to-end runs
- No bulk payloads in chat; repeatable analyses via artifact IDs
- Clear, chronological task progress; deterministic tool behavior and UI
