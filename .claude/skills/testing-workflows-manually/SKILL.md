# Testing Workflows Manually

Test AMOS workflow templates end-to-end with Scout AI.

## Description

This skill provides interactive workflow testing capabilities. It allows you to test V2 workflow templates in various modes: manual browser testing, programmatic console testing, or viewing execution logs. The skill handles entity verification, test user setup, and provides sample prompts to trigger workflows.

**Use this skill when:**
- Testing new workflow templates
- Debugging workflow execution issues
- Verifying workflow phases execute correctly
- Validating workflow triggers and keywords

## Instructions

### Test Modes

The skill offers four testing approaches:

**a) Manual Browser Testing**
- Starts the application
- Provides login credentials
- Directs you to Scout chat interface
- Lists example prompts to trigger workflow

**b) Programmatic Testing**
- Creates WorkflowExecution record
- Initializes WorkflowEngine
- Tests engine setup without full execution
- Shows available phases and template structure

**c) View Execution Logs**
- Queries recent WorkflowExecution records
- Shows status, user, and phase information
- Helpful for reviewing past runs

**d) Info Only**
- Displays workflow details
- Shows phases and structure
- No actual testing performed

### Workflow Selection

If no workflow specified, the skill:
1. Lists all `*_v2.yml` templates in `app/workflow_templates/`
2. Prompts for selection
3. Validates template file exists

If workflow name provided as parameter, it:
1. Verifies `app/workflow_templates/{name}_v2.yml` exists
2. Displays workflow metadata
3. Extracts and shows phases

### Entity and User Setup

The skill automatically:
1. Uses provided entity_id or finds first entity
2. Verifies entity exists
3. Gets or creates test user for entity
4. Prepares test environment with credentials

### Example Prompts

Based on workflow name, provides relevant trigger prompts:
- Campaign workflows: "Create a new email campaign"
- Landing page workflows: "Create a landing page for my product"
- Integration workflows: "Connect to Stripe"

### Usage Patterns

**Interactive Selection:**
```
Use testing-workflows-manually
```

**Test Specific Workflow:**
```
Use testing-workflows-manually with workflow=create_campaign
```

**With Specific Entity:**
```
Use testing-workflows-manually with workflow=create_campaign entity_id=1
```

### Parameters

- `workflow` - Workflow template name without `_v2.yml` extension (optional)
- `entity_id` - Entity ID for testing context (optional, defaults to first entity)

## Examples

### List and Select Workflow

```
Use testing-workflows-manually
```

Shows available workflows, prompts for selection, then offers test modes.

### Test Campaign Workflow

```
Use testing-workflows-manually with workflow=create_campaign
```

Loads create_campaign_v2.yml, verifies entity, provides testing options.

### Manual Browser Test

After selecting mode 'a', the skill:
1. Runs `docker-compose up -d`
2. Provides URL: `http://app.localhost:3000`
3. Shows login credentials
4. Lists example prompts to trigger workflow
5. Suggests viewing logs with `docker-compose logs -f web`

### Programmatic Test

Mode 'b' creates WorkflowExecution and initializes engine:
- Shows entity and user details
- Creates execution record
- Loads template YAML
- Tests WorkflowEngine initialization
- Reports available phases

## Resources

- [Test Workflow Script](scripts/test-workflow.sh) - Main workflow testing script
- [Workflow Testing Guide](resources/workflow-testing-guide.md) - Detailed testing procedures
