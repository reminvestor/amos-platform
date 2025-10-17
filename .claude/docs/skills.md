# Claude Code Skills

Skills are parameterized workflows that combine multiple steps into a single, reusable command. They can accept parameters, call MCP tools, and execute complex sequences of actions.

---

## How Skills Work

**Definition**: Skills are YAML files in `.claude/skills/` that define workflows with parameters, steps, and outputs.

**When to use**: Skills are perfect for:
- Workflows that need parameters
- Integration with MCP tools (Azure DevOps, GitHub, etc.)
- Multi-step automated tasks
- Reusable complex operations

**Key Features**:
- Accept parameters
- Call MCP tools
- Execute bash commands
- Conditional logic
- Store and reuse outputs
- Interactive prompts

---

## YAML Skill Structure

```yaml
name: skill-name
description: What this skill does
version: "1.0"

parameters:
  param_name:
    description: "Parameter description"
    type: string
    required: true
    default: "default_value"

steps:
  - name: Step Name
    run: |
      # Bash commands
      echo "Doing something"

  - name: MCP Tool Call
    mcp: server_name
    tool: tool_name
    parameters:
      param: "${{ parameters.param_name }}"
    store_as: result_var

  - name: Conditional Step
    condition: "${{ parameters.param == 'value' }}"
    run: |
      # Only runs if condition is true

examples:
  - description: "Example usage"
    command: "Use skill-name with param_name=value"
```

---

## Available Skills

### 🐳 docker-dev
**File**: `docker-dev.yaml`

**Purpose**: Manage AMOS Docker Compose development environment.

**Parameters**:
- `action`: What to do (start, stop, restart, rebuild, logs, console, db, shell, ps, clean, test, rag)
- `service`: Which service (web, db, redis, all)
- `db_action`: Database operation (migrate, rollback, seed, reset, drop)
- `rag_action`: RAG operation (health, verify, seed, list, test)
- `test_path`: Test path (all, model, controller, system, or specific file)

**Examples**:
```bash
# Start all services
docker-dev start

# View Rails logs
docker-dev logs service=web

# Open Rails console
docker-dev console

# Run migrations
docker-dev db db_action=migrate

# Run tests
docker-dev test test_path=model

# Check RAG health
docker-dev rag rag_action=health
```

**Common Operations**:
- `start` - Start all Docker services
- `stop` - Stop all services
- `restart` - Restart services
- `rebuild` - Rebuild and restart
- `console` - Open Rails console
- `db` - Database operations
- `test` - Run tests
- `rag` - RAG operations
- `logs` - View service logs
- `shell` - Open bash shell
- `ps` - Show container status
- `clean` - Clean up Docker resources

**See**: [Skills Usage Guide](./skills-guide.md) for complete examples

---

### 🚀 start-feature
**File**: `start-feature.yaml`

**Purpose**: Create feature branch from Azure DevOps backlog with implementation plan.

**Parameters**:
- `project`: Azure DevOps project name (default: "agent_marketing")
- `work_item_id`: Specific work item ID (skip interactive selection)
- `tests`: Testing preference (unit, e2e, both, none, ask)

**Workflow**:
1. Prepares Git (checkout main, pull latest)
2. Lists Azure DevOps backlog items via MCP
3. Prompts user to select work item (unless work_item_id provided)
4. Fetches full work item details
5. Creates feature branch (`feature/work-item-{id}-{slug}`)
6. Asks about testing preferences (unless tests specified)
7. Generates detailed implementation plan

**Examples**:
```bash
# Interactive mode (recommended)
start-feature

# Specific work item
start-feature work_item_id=1234

# With testing preference
start-feature tests=both
start-feature tests=unit
start-feature tests=none

# Combine parameters
start-feature work_item_id=1234 tests=both
```

**Requirements**:
- Azure DevOps MCP configured in `.claude/.mcp.json`
- Clean Git working directory
- On main branch (or will switch automatically)

**MCP Tools Used**:
- `mcp__azure_devops__list_work_items`
- `mcp__azure_devops__get_work_item`

**See**: [Skills Usage Guide](./skills-guide.md) for complete workflow

---

## Creating Your Own Skill

### Basic Skill Template

```yaml
name: my-skill
description: Description of what this skill does
version: "1.0"

parameters:
  required_param:
    description: "A required parameter"
    type: string
    required: true

  optional_param:
    description: "An optional parameter"
    type: string
    default: "default_value"

steps:
  - name: First Step
    run: |
      echo "Starting skill..."
      echo "Param value: ${{ parameters.required_param }}"

  - name: Second Step
    run: |
      # Multi-line bash commands
      if [ "${{ parameters.optional_param }}" = "special" ]; then
        echo "Special handling"
      else
        echo "Normal handling"
      fi

examples:
  - description: "Basic usage"
    command: "Use my-skill with required_param=value"

  - description: "With optional parameter"
    command: "Use my-skill with required_param=value and optional_param=custom"
```

### Skill with MCP Integration

```yaml
name: github-pr-skill
description: Create GitHub PR from current branch
version: "1.0"

parameters:
  title:
    description: "PR title"
    type: string
    required: true

  base:
    description: "Base branch"
    type: string
    default: "main"

steps:
  - name: Get Current Branch
    run: |
      CURRENT_BRANCH=$(git branch --show-current)
      echo "CURRENT_BRANCH=$CURRENT_BRANCH" >> $GITHUB_ENV

  - name: Create PR
    mcp: github
    tool: create_pull_request
    parameters:
      title: "${{ parameters.title }}"
      head: "${{ env.CURRENT_BRANCH }}"
      base: "${{ parameters.base }}"
    store_as: pr_result

  - name: Show PR URL
    run: |
      echo "✅ PR created: ${{ pr_result.url }}"

examples:
  - description: "Create PR"
    command: "Use github-pr-skill with title='Add new feature'"
```

### Skill with Interactive Prompts

```yaml
name: deploy-app
description: Deploy application with environment selection
version: "1.0"

parameters:
  environment:
    description: "Target environment (will ask if not provided)"
    type: string
    default: "ask"

steps:
  - name: Prompt for Environment
    condition: "${{ parameters.environment == 'ask' }}"
    prompt: "Which environment? (staging/production)"
    store_as: selected_env

  - name: Determine Environment
    run: |
      if [ "${{ parameters.environment }}" = "ask" ]; then
        ENV="${{ selected_env }}"
      else
        ENV="${{ parameters.environment }}"
      fi
      echo "DEPLOY_ENV=$ENV" >> $GITHUB_ENV

  - name: Deploy
    run: |
      echo "Deploying to $DEPLOY_ENV..."
      # Deployment commands here

examples:
  - description: "Interactive deployment"
    command: "Use deploy-app"

  - description: "Direct deployment"
    command: "Use deploy-app with environment=staging"
```

---

## Skill Features

### Parameters

**Types**:
- `string` - Text value
- `number` - Numeric value
- `boolean` - true/false

**Properties**:
- `description` - What the parameter is for
- `required` - Whether it's mandatory
- `default` - Default value if not provided
- `enum` - List of allowed values

**Example**:
```yaml
parameters:
  log_level:
    description: "Logging verbosity"
    type: string
    required: false
    default: "info"
    enum: ["debug", "info", "warn", "error"]
```

### Steps

**Types of steps**:

**1. Bash Command**:
```yaml
- name: Run Commands
  run: |
    echo "Running commands"
    ls -la
```

**2. MCP Tool Call**:
```yaml
- name: Call MCP Tool
  mcp: server_name
  tool: tool_name
  parameters:
    param1: "value"
    param2: "${{ parameters.user_param }}"
  store_as: result
```

**3. Conditional Step**:
```yaml
- name: Conditional Action
  condition: "${{ parameters.flag == 'true' }}"
  run: |
    echo "Flag is true"
```

**4. Interactive Prompt**:
```yaml
- name: Ask User
  prompt: "What is your name?"
  store_as: user_name
```

### Variable Substitution

**Access parameters**:
```yaml
${{ parameters.param_name }}
```

**Access stored values**:
```yaml
${{ variable_name }}
```

**Access environment variables**:
```yaml
${{ env.VAR_NAME }}
```

**Example**:
```yaml
steps:
  - name: Get Data
    mcp: api
    tool: fetch
    store_as: api_result

  - name: Use Data
    run: |
      echo "Result: ${{ api_result.data }}"
      echo "Param: ${{ parameters.user_param }}"
```

---

## MCP Integration

Skills can call MCP (Model Context Protocol) tools to integrate with external services.

### Available MCP Servers

**Azure DevOps** (configured for start-feature):
```yaml
mcp: azure_devops
tool: list_work_items
parameters:
  project: "project_name"
  state: "Active,New"
```

**GitHub**:
```yaml
mcp: github
tool: create_issue
parameters:
  title: "Issue title"
  body: "Issue description"
```

**Custom MCP**:
Add to `.claude/.mcp.json`:
```json
{
  "mcpServers": {
    "my_service": {
      "type": "stdio",
      "command": "npx",
      "args": ["-y", "@my/mcp-package"],
      "env": {
        "API_KEY": "your-key"
      }
    }
  }
}
```

Then use in skill:
```yaml
mcp: my_service
tool: tool_name
```

---

## Best Practices

**1. Clear Parameters**:
```yaml
# Good
parameters:
  work_item_id:
    description: "Azure DevOps work item ID (e.g., 1234)"
    type: string
    required: false

# Not as good
parameters:
  id:
    type: string
```

**2. Helpful Examples**:
```yaml
examples:
  - description: "Complete example with all options"
    command: "Use skill-name with param1=value and param2=value"

  - description: "Minimal example"
    command: "Use skill-name with param1=value"

  - description: "Advanced use case"
    command: "Use skill-name with param1=special-value and param2=custom"
```

**3. Error Handling**:
```yaml
steps:
  - name: Check Prerequisites
    run: |
      if [ ! -f ".env" ]; then
        echo "❌ Error: .env file not found"
        exit 1
      fi
```

**4. Clear Output**:
```yaml
steps:
  - name: Show Progress
    run: |
      echo "🚀 Starting process..."
      echo "📊 Step 1 of 3"
      # ... work ...
      echo "✅ Complete!"
```

---

## Testing Skills

**Test locally**:
```bash
# Use the skill
skill-name param=value

# Check output
# Verify expected behavior
```

**Debug**:
- Add `echo` statements to show variables
- Use `set -x` for verbose bash output
- Check MCP tool responses
- Verify parameter substitution

---

## Skill vs Agent vs Command

**Use a Skill when**:
- Need parameters
- Call MCP tools
- Automate multi-step process
- Want reusable workflow

**Use an Agent when**:
- Need domain expertise
- Complex decision-making
- Multi-turn conversation
- Guidance and recommendations

**Use a Command when**:
- Simple trigger
- No parameters needed
- Just need shortcut/alias
- Activate agent or skill

---

## Related Documentation

- [Agents Guide](./agents.md)
- [Commands Guide](./commands.md)
- [Skills Usage Guide](./skills-guide.md) - Complete examples for docker-dev and start-feature
- [Main README](./../README.md)
