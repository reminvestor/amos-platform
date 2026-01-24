# User-Created Tools & Loadouts: Integration Analysis

## Current State

### User-Created Tools (`ToolDefinition`)

**Creation Flow:**
1. User asks Amos to create a tool
2. `CreateToolTool` or `CreateToolDefinitionTool` invokes `Factories::ToolFactory`
3. Factory validates, creates `ToolDefinition` record with `entity_id` and `created_by_id`
4. `Tools::ToolCatalog.refresh_dynamic_tools!` is called to register the new tool

**Current Availability:**
- ✅ Tools are entity-scoped (can't leak across tenants)
- ✅ Tools are refreshed when agents load tools
- ⚠️ **ISSUE**: Custom tools may not surface to Amos unless:
  - RAG/tiered discovery happens to find them
  - They're explicitly assigned to a loadout
  - User explicitly asks for them by name

### User-Created Loadouts (`AgentPlugin`)

**Creation Flow:**
1. User asks Amos to create an agent/loadout
2. `CreateAgentPluginTool` invokes `Factories::AgentFactory`
3. Factory creates `AgentPlugin` record with system prompt, capabilities, and tool assignments
4. Loadout is immediately active

**Current Availability:**
- ✅ Loadouts are entity-scoped
- ✅ Can be assigned specific tools via `AgentTool`
- ⚠️ **ISSUE**: User-created loadouts are NOT automatically considered by `PluginInjectionService`
- ⚠️ **ISSUE**: No way for users to specify when their loadout should be injected

---

## Gaps in the New Plugin Injection Architecture

### Gap 1: Static Plugin Maps

`PluginInjectionService` uses hardcoded maps:
```ruby
CANVAS_PLUGIN_MAP = {
  'landing_page_editor' => 'landing_page_manager',
  'workflow_designer' => 'workflow_architect',
  # ... only system loadouts
}
```

**Problem**: User-created loadouts have no way to be injected automatically.

### Gap 2: No Trigger Registration for Custom Loadouts

Users can create loadouts but can't specify:
- What canvas types trigger them
- What keywords should activate them  
- What capabilities they provide

### Gap 3: Custom Tools Aren't Prioritized

Custom tools exist but aren't given priority in discovery. A user's custom tool should be:
- More visible to that user/entity
- Suggested before similar system tools

---

## Recommended Improvements

### 1. Add User Trigger Configuration to AgentPlugin

Add fields to `AgentPlugin` model:
```ruby
# Migration
add_column :agent_plugins, :trigger_config, :jsonb, default: {}
# Schema:
# {
#   canvas_types: ['my_custom_canvas'],
#   keywords: ['invoice', 'billing', 'payment'],
#   capabilities: ['invoice_generation', 'payment_processing'],
#   priority_boost: 10  # Higher = more likely to be selected
# }
```

### 2. Enhance PluginInjectionService for User Loadouts

```ruby
def select_plugin(canvas_context:, message:, intent:)
  # ... existing logic ...
  
  # NEW: Check user-created loadouts with trigger_config
  if plugin.nil?
    plugin, injection_reason = find_user_loadout_by_triggers(
      canvas: canvas_context[:type],
      message: message
    )
  end
end

def find_user_loadout_by_triggers(canvas:, message:)
  user_loadouts = AgentPlugin.active.for_entity(@entity).where.not(trigger_config: {})
  
  user_loadouts.each do |loadout|
    config = loadout.trigger_config
    
    # Check canvas match
    if config['canvas_types']&.include?(canvas)
      return [loadout, "User loadout canvas: #{canvas}"]
    end
    
    # Check keyword match
    if config['keywords']&.any? { |kw| message.downcase.include?(kw.downcase) }
      return [loadout, "User loadout keyword match"]
    end
  end
  
  [nil, nil]
end
```

### 3. Prioritize Custom Tools in Discovery

In `TieredDiscoveryService` or `ScoutGenericToolsServiceV2`:

```ruby
def get_filtered_tools(...)
  # ... existing logic ...
  
  # ADD: Prioritize entity's custom tools
  custom_tools = ToolDefinition.where(entity_id: entity.id)
                               .pluck(:name)
  
  # Merge custom tools FIRST so they take priority
  all_tools = (custom_tools + other_tools).uniq
end
```

### 4. RAG-Based Loadout Discovery

For complex cases, use semantic search:

```ruby
def discover_loadout_by_capability(task_description)
  # Vector search against loadout descriptions/capabilities
  results = VectorSearchService.search(
    query: task_description,
    collection: 'loadout_capabilities',
    entity_id: @entity.id,
    limit: 3
  )
  
  best_match = results.first
  find_plugin(best_match[:slug]) if best_match
end
```

### 5. Auto-Suggest Loadout Creation

When a user creates a custom tool, suggest:
```
"I've created your 'generate_invoice' tool! Would you like me to create 
a specialized loadout (like 'Invoice Manager') that uses this tool? 
This would let me automatically use it when you mention invoices."
```

---

## Implementation Priority

### Phase 1: Quick Wins (Low effort, high impact)
1. ✅ Add `trigger_config` to `AgentPlugin`
2. ✅ Update `PluginInjectionService` to check user loadouts
3. ✅ Prioritize custom tools in tool loading

### Phase 2: Enhanced Discovery
1. Add RAG-based loadout discovery
2. Auto-detect capabilities from loadout prompts
3. Build loadout suggestion flow

### Phase 3: User Experience
1. UI for managing loadout triggers
2. "My Loadouts" canvas for loadout management
3. Loadout analytics dashboard

---

## Data Model Changes

### AgentPlugin Additions
```ruby
# New columns
:trigger_config  # jsonb - { canvas_types: [], keywords: [], capabilities: [] }
:is_user_created # boolean - Distinguishes from system loadouts
:usage_count     # integer - Track how often injected (for optimization)
```

### ToolDefinition Additions
```ruby
# Already exists but ensure indexed properly
:entity_id       # Already exists
:created_by_id   # Already exists
:is_auto_surface # boolean - Should this tool appear automatically?
```

---

## Summary

The plugin injection architecture is solid, but user-created content needs better integration:

1. **Tools**: Already work but need priority boost for user's own tools
2. **Loadouts**: Need trigger configuration so they can be auto-injected
3. **Discovery**: Both tools and loadouts need better RAG-based discovery

These improvements maintain the simplicity of the plugin injection model while giving users the power to extend Amos with their own specialized capabilities.
