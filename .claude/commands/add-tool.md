# /add-tool Command

Create a new tool with comprehensive tests for the AMOS workflow system.

## Usage

```
/add-tool [description]
```

## What This Command Does

Delegates to the **tool-builder** agent to:
1. Ask you what the tool should do
2. Define input/output parameters
3. Implement the BaseTool class
4. Write comprehensive unit tests
5. Verify tool registration in ToolCatalog

## Example

```
/add-tool Create a tool to export campaign analytics to CSV
```

## Agent Task

Use the Task tool with subagent_type: "tool-builder"

Provide this prompt:
```
The user wants to create a new tool: [description]

Please:
1. Ask the user what exactly this tool should do
2. Ask what the inputs are (parameters) and what format
3. Ask what the outputs should be
4. Ask which models/databases it interacts with
5. Ask if any external APIs are needed
6. Implement the tool class in app/services/tools/
7. Write comprehensive tests in test/services/tools/
8. Verify it registers in ToolCatalog
9. Test in Rails console if possible

Return a summary of:
- Tool file created
- Test file created
- Parameters defined
- Test results
- Any issues encountered
```
