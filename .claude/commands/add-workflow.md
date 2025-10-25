# /add-workflow Command

Create a new V2 workflow template with proper three-phase structure.

## Usage

```
/add-workflow [description]
```

## What This Command Does

Uses the **starting-features** skill to:
1. Help you design the workflow phases
2. Create the V2 YAML template structure
3. Define gather_context, execute_goal, and validate_result phases
4. Add workflow keywords for planner matching
5. Identify required tools and integrations

## Examples

```
/add-workflow Create a workflow for generating blog posts from topics
```

```
/add-workflow Build a workflow that creates social media campaigns
```

## Workflow Structure

Creates a V2 workflow template with:
- **template_version: 2** - Ensures V2 engine usage
- **Gather Context Phase** - Data collection strategy
- **Execute Goal Phase** - Structured or adaptive execution
- **Validate Result Phase** - Quality checks and auto-fixes
- **Keywords** - Planner matching phrases

## Implementation

This command uses the starting-features skill which:
- Follows V2 workflow patterns (three-phase structure)
- Creates template in `app/workflow_templates/`
- Auto-discovered by WorkflowEngine
- Provides testing guidance

## Next Steps

After running this command:
1. Test the workflow with the `testing-workflows-manually` skill
2. Run system tests with `running-tests` skill
3. Verify planner matches keywords correctly
4. Use `/quick-commit` to commit your changes

## Uses Skills

- **starting-features** - Workflow template scaffolding and design guidance
