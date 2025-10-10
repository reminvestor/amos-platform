# /add-workflow Command

Create a new V2 workflow template with proper three-phase structure.

## Usage

```
/add-workflow [description]
```

## What This Command Does

Delegates to the **workflow-architect** agent to:
1. Ask you about required vs optional data
2. Determine execution strategy (structured vs adaptive)
3. Design validation criteria
4. Create the YAML workflow template
5. Identify any missing tools needed

## Example

```
/add-workflow Create a workflow for generating blog posts from topics
```

## Agent Task

Use the Task tool with subagent_type: "workflow-architect"

Provide this prompt:
```
The user wants to create a new V2 workflow: [description]

Please:
1. Ask the user what data needs to be gathered (required vs optional fields)
2. Ask what the primary goal/outcome should be
3. Ask if execution should be structured or adaptive
4. Ask what validation criteria define success
5. Design the three-phase workflow template
6. Create the file in app/workflow_templates/
7. Report what tools are needed for execution

Return a summary of:
- Template file created
- Execution strategy chosen
- Tools required (existing vs new)
- Any integration needs identified
```
