# Workflows & Automations

## Overview
Workflows are visual automations that respond to triggers and execute actions. They power everything from lead nurturing to data sync between systems.

## Key Concepts
- **Trigger**: What starts the workflow (form submission, schedule, event, webhook, manual)
- **Action**: What the workflow does (send email, update record, call API, etc.)
- **Condition**: Branch logic (if/else based on data)
- **Delay**: Wait steps (wait 1 day, wait until condition)

## Database Models
- `Workflow` — The automation definition
- `WorkflowStep` — Individual nodes in the flow
- `WorkflowExecution` — Run history
- `AutomationRecipe` — Pre-built workflow templates

## Key Fields
- `name`: Workflow identifier
- `status`: draft, active, paused, archived
- `trigger_type`: form_submission, schedule, event, webhook, manual
- `trigger_config`: JSON with trigger-specific settings
- `steps`: Array of WorkflowStep references

## Canvases
- `workflow_designer` — Visual drag-drop builder for creating/editing workflows
- `automation_dashboard` — Overview of all automations and their status

## Common Operations

### Query workflows
```
platform_query(type: "workflows", filters: { status: "active" })
platform_query(type: "automation_recipes", search: "lead")
```

### Create a workflow
```
platform_create(type: "workflow", data: {
  name: "Welcome Email Sequence",
  trigger_type: "form_submission",
  trigger_config: { form_id: 123 },
  status: "draft"
})
```

### Open workflow designer
```
load_canvas(canvas_name: "workflow_designer")
load_canvas(canvas_name: "workflow_designer", canvas_data: { workflow_id: 42 })
```

## Trigger Types
| Type | Description | Config |
|------|-------------|--------|
| form_submission | Form is submitted | `{ form_id: X }` |
| schedule | Cron schedule | `{ cron: "0 9 * * *" }` |
| event | System event | `{ event_type: "contact.created" }` |
| webhook | External HTTP call | `{ path: "/trigger/abc" }` |
| manual | User-triggered | `{}` |

## Action Types
- `send_email` — Send email using template
- `update_record` — Update a contact or other object
- `create_record` — Create a new object
- `call_integration` — Execute integration action
- `call_webhook` — HTTP request to external URL
- `enroll_sequence` — Add to email sequence
- `add_to_group` — Add contact to group
- `slack_notify` — Send Slack message
- `delay` — Wait before next step

## Pre-built Recipes
Automation recipes are templates. Query them with:
```
platform_query(type: "automation_recipes")
```

Instantiate a recipe into a workflow with:
```
platform_execute(operation: "instantiate_recipe", params: { recipe_id: 5 })
```

## Tips
- Start with a clear trigger — what event starts this?
- Keep workflows focused — one purpose per workflow
- Test with draft status before activating
- Monitor executions in automation_dashboard
