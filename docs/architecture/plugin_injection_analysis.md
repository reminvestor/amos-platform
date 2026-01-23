# Plugin Injection Architecture Analysis

## Executive Summary

**The Question:** Instead of delegating tasks to separate agents, should we inject agent plugins directly into Amos, giving him their capabilities in a single conversation turn?

**My Opinion: YES, with a hybrid approach.** The current delegation architecture is over-engineered for most use cases. Plugin injection would simplify 80% of interactions while preserving delegation for complex scenarios.

---

## Current Architecture (Agent Delegation)

```
User → Amos → "I should delegate this"
         ↓
    delegate_to_agent tool
         ↓
    AgentPluginExecution created
         ↓
    AgentPluginExecutionJob queued
         ↓
    StandardPluginExecutor runs
         ↓
    Bedrock conversation (separate from Amos)
         ↓
    Response saved to HubMessage/ScoutMessage
         ↓
User sees response
```

### What an AgentPlugin Actually Is

```ruby
AgentPlugin = {
  system_prompt: "You are a Landing Page Manager...",  # Just text
  agent_tools: ["edit_landing_page_section", ...],    # Just tool names
  configuration: { canvas_on_completion: "..." },      # Just config
  ai_model: nil,                                       # Usually nil (inherit default)
}
```

**Key Insight:** An agent is literally just a **prompt + tools**. The same model (Qwen/Claude) runs both Amos and agents. There's no architectural reason they need separate conversations.

### Current Flow Overhead

| Step | Latency | Notes |
|------|---------|-------|
| Amos decides to delegate | ~1-3s | LLM call |
| Create AgentPluginExecution | ~50ms | DB write |
| Queue job | ~100ms | Redis/SolidQueue |
| Job picks up | ~100-500ms | Worker polling |
| StandardPluginExecutor builds context | ~200ms | Tool loading, RAG |
| Agent Bedrock call | ~2-5s | Separate LLM call |
| Response broadcast | ~100ms | ActionCable |
| **Total** | **4-10s** | **For what could be 2-4s** |

---

## Proposed Architecture (Plugin Injection)

```
User → Amos (with injected plugin capabilities)
         ↓
    Single Bedrock call with:
    - Amos core identity
    - Injected plugin prompt
    - Merged tool set
         ↓
User sees response
```

### How It Would Work

1. **During preprocessing** (already parallel):
   - Detect relevant plugin based on:
     - Canvas context (landing_page_editor → Landing Page Manager)
     - Intent classification (CRM keywords → CRM Agent)
     - Explicit mention ("ask the analytics agent")
     - Tool requirements

2. **Inject the plugin**:
   ```ruby
   amos_system_prompt = AmosIdentity.full_identity + "\n\n" +
     "## CURRENT SPECIALIZATION: #{plugin.name}\n" +
     plugin.system_prompt
   
   amos_tools = ESSENTIAL_TOOLS + plugin.assigned_tools
   ```

3. **Single LLM call** handles everything

### Benefits

| Benefit | Impact |
|---------|--------|
| **50% faster responses** | Eliminate second LLM call |
| **Simpler code** | Remove 500+ lines in StandardPluginExecutor |
| **Full context** | Plugin has complete conversation history |
| **Unified experience** | Always Amos, no persona switching |
| **Cheaper** | One LLM call vs two |
| **Better debugging** | Single conversation thread |

---

## Comparison

| Aspect | Agent Delegation | Plugin Injection |
|--------|-----------------|------------------|
| Latency | 4-10s | 2-4s |
| LLM calls | 2 | 1 |
| Conversation context | Partial (passed) | Full |
| System prompt size | Separate | Larger (but manageable) |
| Tool count | Separate | Merged |
| Code complexity | High | Low |
| User experience | Switching personas | Consistent Amos |
| Debugging | Separate logs | Single thread |
| Cost per interaction | ~2x | 1x |

---

## Concerns and Mitigations

### 1. System Prompt Bloat
**Concern:** Injecting multiple plugin prompts could explode the system prompt.

**Mitigation:** 
- Only inject ONE plugin at a time (most relevant)
- Plugin prompts should be concise (<500 tokens)
- Use tiered injection: core capabilities always, specialized on demand

### 2. Tool Overload
**Concern:** Too many tools might confuse the model.

**Mitigation:**
- Current Amos already handles 60+ tools successfully
- Plugin tools are typically 5-15 additional tools
- Keep total under 128 (Bedrock limit)

### 3. Loss of Specialization
**Concern:** Agent-specific model settings (temperature, max_tokens).

**Mitigation:**
- Most agents use default settings anyway
- Could support per-plugin inference overrides
- For truly specialized needs, keep delegation as an option

### 4. User Expectations
**Concern:** Some users want to "talk to the specialist".

**Mitigation:**
- Amos can announce when using specialized capabilities
- Hub DM threads can remain for explicit agent conversations
- Hybrid approach supports both modes

---

## Recommended Hybrid Approach

### Mode 1: Plugin Injection (Default)
For 80% of interactions:
```
User: "Change the hero background to #ece3de"
[Preprocessor detects: canvas=landing_page_editor, inject=Landing Page Manager]
Amos (with Landing Page Manager capabilities): *executes edit directly*
```

### Mode 2: Agent Delegation (Explicit)
For complex multi-turn tasks or explicit requests:
```
User: "I want to work with the CRM agent on a campaign"
Amos: "I'll connect you with the CRM Agent in a dedicated thread..."
[Opens Hub DM thread with CRM Agent]
```

---

## Implementation Plan

### Phase 1: Plugin Injection Infrastructure
1. Add `PluginInjectionService` to handle:
   - Plugin selection based on context
   - Prompt merging
   - Tool set merging
   
2. Modify `UnifiedPreprocessorService`:
   - Add `selected_plugin` to output
   - Pre-compute injected prompt

3. Modify `ScoutGenericToolsServiceV2`:
   - Accept injected plugin
   - Merge plugin prompt with Amos identity
   - Merge plugin tools with core tools

### Phase 2: Smart Plugin Selection
1. Canvas-based injection (automatic):
   - `landing_page_editor` → Landing Page Manager
   - `integrations_manager` → Integration specialist
   - `workflow_designer` → Workflow Architect

2. Intent-based injection:
   - CRM keywords → CRM Agent capabilities
   - Analytics requests → Analytics capabilities

3. Explicit opt-in:
   - "Use the landing page manager" → Inject that plugin

### Phase 3: Deprecate Heavy Delegation
1. Keep `delegate_to_agent` for:
   - Explicit user requests
   - Multi-agent collaboration
   - Long-running tasks

2. Remove for:
   - Simple tool execution
   - Single-turn requests
   - Context-aware tasks

---

## Code Impact

### Files to Modify
- `UnifiedPreprocessorService` - Add plugin selection
- `ScoutGenericToolsServiceV2` - Accept injected plugin
- `AmosIdentity` - Support specialization blocks

### Files to Simplify (Later)
- `StandardPluginExecutor` - Used less frequently
- `delegate_to_agent_tool` - Simplified use cases
- `AgentPluginExecution` - Fewer records created

### Files Unchanged
- `AgentPlugin` model - Still defines plugins
- `ToolCatalog` - Still serves tools
- `Hub` system - Still available for explicit agent conversations

---

## Metrics to Track

1. **Response latency** - Should decrease by 40-60%
2. **User satisfaction** - Should stay same or improve
3. **Cost per conversation** - Should decrease by ~40%
4. **Delegation rate** - Should decrease (sign of success)
5. **Plugin injection hits** - Track which plugins are used

---

## Conclusion

The current agent delegation architecture was built assuming agents are fundamentally different entities. But they're not - they're just prompts and tools running on the same model.

Plugin injection simplifies the common case while preserving flexibility for complex scenarios. It's faster, cheaper, and provides a more unified user experience.

**Recommendation: Implement the hybrid approach, starting with Phase 1.**

---

## Next Steps

1. [ ] Implement `PluginInjectionService`
2. [ ] Add canvas-based injection rules
3. [ ] Modify `ScoutGenericToolsServiceV2` to accept injected plugins
4. [ ] Test with Landing Page Manager (most common use case)
5. [ ] Measure latency improvement
6. [ ] Roll out to other plugins
