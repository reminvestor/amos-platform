# Testing Tools Manually

Test Scout AI tools interactively with custom parameters.

## Description

This skill provides interactive testing for Scout AI tools. It allows you to execute tools with custom or example parameters, view source code, inspect JSON definitions, and see execution results. The skill handles tool catalog loading, entity/user context setup, and WorkflowExecution creation.

**Use this skill when:**
- Developing new Scout AI tools
- Debugging tool execution issues
- Validating tool parameters and responses
- Learning how tools work by inspection

## Instructions

### Test Modes

The skill offers four testing modes:

**a) Interactive Mode**
- Prompts for JSON parameters
- You provide exact parameter values
- Executes tool with your input
- Shows full result including success/error status

**b) Example Mode**
- Auto-generates example parameters from tool definition
- Uses sensible defaults (strings, integers, booleans)
- Quick test without manual parameter entry
- Good for initial tool validation

**c) View Source Code**
- Finds tool file in `app/services/tools/`
- Displays complete Ruby source
- Helpful for understanding implementation

**d) Show JSON Definition**
- Displays tool's Bedrock-compatible JSON schema
- Shows parameters, types, descriptions
- Matches what AI sees when calling tools

### Tool Selection

If no tool specified:
1. Lists all tools from ToolCatalog
2. Shows tool names and descriptions
3. Prompts for selection

If tool name provided:
1. Validates tool exists in catalog
2. Loads tool definition
3. Shows parameters and requirements

### Environment Setup

The skill automatically:
1. Finds or uses provided entity_id
2. Gets first user for that entity
3. Creates WorkflowExecution for context
4. Initializes tool instance with proper context

This ensures tools have all required context (entity, user, execution) for testing.

### Tool Definition Display

Shows structured information:
- Tool name
- Description
- Parameters with types
- Required vs optional indicators
- File location

### Usage Patterns

**Interactive Selection:**
```
Use testing-tools-manually
```

**Test Specific Tool:**
```
Use testing-tools-manually with tool_name=create_campaign_tool
```

**With Specific Entity:**
```
Use testing-tools-manually with tool_name=create_campaign_tool entity_id=1
```

### Parameters

- `tool_name` - Tool name to test (e.g., `create_campaign_tool`) (optional)
- `entity_id` - Entity ID for testing context (optional, defaults to first entity)

## Examples

### List and Test a Tool

```
Use testing-tools-manually
```

Shows available tools:
```
  - create_campaign_tool
    Description: Create a new email campaign

  - generate_landing_page_tool
    Description: Generate an AI landing page

  ...

Total tools: 23
```

Then prompts for selection and test mode.

### Test Campaign Tool with Custom Params

```
Use testing-tools-manually with tool_name=create_campaign_tool
```

Mode 'a' (Interactive):
```
📝 Enter tool parameters as JSON:

Example: {"name": "Test Campaign", "subject": "Hello"}

JSON parameters: {"name": "Summer Sale", "subject": "50% Off Everything!"}
```

Executes tool and shows result:
```
Result:
{
  "success": true,
  "message": "Campaign created successfully",
  "data": {
    "campaign_id": 42,
    "name": "Summer Sale"
  }
}

✅ Tool executed successfully!
```

### Quick Test with Example Parameters

Mode 'b' auto-generates parameters:
```
Example Parameters:
{
  "name": "Test Value",
  "subject": "Test Value",
  "recipients": []
}

Executing tool...

Result:
{
  "success": true,
  ...
}
```

### View Tool Implementation

Mode 'c' displays source:
```
File: app/services/tools/create_campaign_tool.rb
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
module Tools
  class CreateCampaignTool < BaseTool
    def self.definition
      ...
    end

    def execute(args)
      ...
    end
  end
end
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

### Inspect JSON Definition

Mode 'd' shows Bedrock schema:
```
{
  "name": "create_campaign_tool",
  "description": "Create a new email campaign",
  "parameters": {
    "type": "object",
    "properties": {
      "name": {
        "type": "string",
        "description": "Campaign name"
      },
      ...
    },
    "required": ["name", "subject"]
  }
}
```

## Resources

- [Test Tool Script](scripts/test-tool.sh) - Main tool testing script
- [Tool Development Guide](resources/tool-development-guide.md) - Creating new tools
