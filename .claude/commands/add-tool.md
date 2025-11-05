# /add-tool Command

Create a new Scout AI tool for the AMOS workflow system.

## Usage

```
/add-tool [description]
```

## What This Command Does

Uses the **starting-features** skill to:
1. Help you design the tool's functionality
2. Create the tool class extending BaseTool
3. Implement tool definition and execute method
4. Write comprehensive unit tests
5. Verify auto-registration in ToolCatalog

## Examples

```
/add-tool Create a tool to export campaign analytics to CSV
```

```
/add-tool Build a tool that generates social media posts from blog content
```

## Implementation

This command uses the starting-features skill which:
- Follows AMOS patterns (entity scoping, tool catalog)
- Generates proper file structure in `app/services/tools/`
- Creates corresponding test files in `test/services/tools/`
- Ensures tool auto-discovery works correctly

## Next Steps

After running this command:
1. Test the tool manually with the `testing-tools-manually` skill
2. Run tests with `running-tests` skill
3. Use `/quick-commit` to commit your changes

## Uses Skills

- **starting-features** - Tool scaffolding and implementation guidance
