# Tool Refactoring Guide

## What Changed

The `ScoutGenericToolsService` (nearly 6000 lines!) has been refactored into:

1. **Individual Tool Classes** in `app/services/tools/`
   - Each tool is now its own class inheriting from `BaseTool`
   - Tools define their own metadata, input schema, and execution logic
   - Much easier to maintain and test individual tools

2. **Tool Catalog** (`Tools::ToolCatalog`)
   - Singleton that auto-discovers and registers all tools
   - Handles tool filtering based on agent loadouts
   - Provides tools in Bedrock format

3. **Streamlined Service** (`ScoutGenericToolsServiceV2`)
   - Now only ~300 lines instead of 6000
   - Delegates tool execution to the catalog
   - Properly filters tools based on agent loadout

## Tool Filtering & Agent Loadouts

The system already had `AgentLoadout` infrastructure, but it wasn't being used! Now:

### How It Works

1. **Agent Loadouts** define tool allowlists per agent role:
   ```ruby
   # In AgentLoadout model
   'planner' => {
     tool_allowlist: ['get_schema', 'list_connections'],  # Only 2 tools!
     canvas_allowlist: ['task_progress'],
   },
   'executor' => {
     tool_allowlist: ['get_data', 'create_object', 'invoke_operation', 'generate_ai_landing_page'],
   },
   'analyst' => {
     tool_allowlist: ['aggregate_artifact_data', 'fetch_next_page', 'create_dynamic_visualization'],
   }
   ```

2. **Tool Filtering** happens in `get_filtered_tools`:
   - If an agent loadout is provided, only allowed tools are sent to the LLM
   - This prevents overwhelming the LLM with 30+ tools
   - Different agents get different capabilities

3. **Usage Example**:
   ```ruby
   # Create a planner agent with limited tools
   planner_loadout = AgentLoadout.new(agent_role: 'planner')
   service = ScoutGenericToolsServiceV2.new(user, entity, session_id, agent_loadout: planner_loadout)
   # This agent can only use 'get_schema' and 'list_connections' tools
   ```

## Tool Limits Best Practice

You're right about the 30-tool limit! Current research suggests:
- **10-15 tools** is optimal for accuracy
- **20-30 tools** is the practical maximum
- Beyond 30, LLMs start making more mistakes

With agent loadouts, we can keep each agent under 10 tools, which is ideal.

## Migration Steps

To fully migrate to the new system:

1. **Extract Remaining Tools** (still needed):
   - Analytics tools (aggregate_artifact_data, create_dynamic_visualization)
   - Task management tools (manage_task_list)
   - Integration tools (invoke_operation, list_connections)
   - Form/email tools

2. **Update Controllers**:
   ```ruby
   # Old
   service = ScoutGenericToolsService.new(user, entity, session_id)
   
   # New
   service = ScoutGenericToolsServiceV2.new(user, entity, session_id)
   ```

3. **Add Agent Loadouts** where appropriate:
   ```ruby
   # For workflow steps
   loadout = step.agent_loadout  # Step already has this method
   service = ScoutGenericToolsServiceV2.new(user, entity, session_id, agent_loadout: loadout)
   ```

## Creating New Tools

Super easy now:

```ruby
# app/services/tools/my_new_tool.rb
module Tools
  class MyNewTool < BaseTool
    def self.metadata
      {
        name: 'my_new_tool',
        description: 'Does something cool',
        category: 'custom',
        input_schema: {
          type: 'object',
          properties: {
            param1: { type: 'string' }
          },
          required: ['param1']
        }
      }
    end
    
    def execute(args)
      param1 = get_arg(args, :param1)
      
      # Do the work
      result = do_something_cool(param1)
      
      success_response(data: result)
    end
  end
end
```

The tool is automatically discovered and registered!

## Benefits

1. **Maintainability**: Each tool is ~50-100 lines instead of buried in a 6000-line file
2. **Testability**: Can unit test individual tools
3. **Performance**: LLMs get only relevant tools, improving accuracy
4. **Flexibility**: Easy to add/modify tools without touching core service
5. **Governance**: Agent loadouts control what each agent can do

## Next Steps

1. Continue extracting remaining tools
2. Update production code to use V2 service
3. Add more specific agent loadouts for different contexts
4. Consider dynamic tool loading based on user permissions
