# /workflow Command

Test and debug workflow executions.

## Usage

```
/workflow [template-name or execution-id]
```

## What This Command Does

Invokes the **Running Workflows** skill to:
- ✅ List available workflow templates
- ✅ Execute a specific workflow for testing
- ✅ Debug workflow execution failures
- ✅ Inspect workflow context and phase data
- ✅ Validate workflow YAML syntax
- ✅ Test tool integrations

## Examples

```
# List all workflow templates
/workflow

# Test a specific workflow
/workflow create_landing_page_v2

# Debug a failed execution
/workflow 12345

# Validate workflow YAML
/workflow validate app/workflow_templates/new_workflow.yml
```

## Instructions

Use the Skill tool to invoke the `running-workflows` skill to manage workflow testing and debugging based on the user's request.
