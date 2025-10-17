# Claude Code Commands

Commands are quick shortcuts that trigger specific actions or workflows. They're like aliases that make common tasks faster and easier.

---

## How Commands Work

**Definition**: Commands are markdown files in `.claude/commands/` that define quick actions and their aliases.

**When to use**: Just type the command name (or alias) and Claude Code will execute the associated action.

**Key Features**:
- Fast shortcuts for common tasks
- Multiple aliases per command
- Clear descriptions
- Can trigger agents or skills

---

## Available Commands

### 🔧 add-tool
**File**: `add-tool.md`

**Aliases**:
- `add tool`
- `create tool`
- `new tool`

**Description**: Creates a new Scout AI tool following AMOS BaseTool pattern.

**What it does**: Triggers the Tool Builder Agent to guide you through creating a tool.

**Example**:
```
You: "add tool"

Claude Code:
→ Activates Tool Builder Agent
→ Asks about tool purpose and parameters
→ Generates tool class and tests
→ Ensures ToolCatalog auto-discovery
```

**Requirements**:
- None (agent will guide you)

---

### 🌐 add-integration
**File**: `add-integration.md`

**Aliases**:
- `add integration`
- `create integration`
- `connect to [service]`

**Description**: Connects external API or service to AMOS.

**What it does**: Triggers the Integration Connector Agent.

**Example**:
```
You: "add integration"

Claude Code:
→ Activates Integration Connector Agent
→ Asks which service to integrate
→ Reviews API documentation
→ Creates Integration, Connection models
→ Builds API client and tools
```

**Requirements**:
- API documentation URL
- Authentication details (API key, OAuth, etc.)

---

### 🏗️ add-workflow
**File**: `add-workflow.md`

**Aliases**:
- `add workflow`
- `create workflow`
- `new workflow template`

**Description**: Creates a V2 workflow template for Scout.

**What it does**: Triggers the Workflow Architect Agent.

**Example**:
```
You: "add workflow"

Claude Code:
→ Activates Workflow Architect Agent
→ Asks about workflow purpose
→ Designs 3-phase structure
→ Creates YAML template
→ Adds to workflow_templates/ directory
```

**Requirements**:
- Workflow purpose description
- Key steps/phases needed

---

### 🚀 build-feature
**File**: `build-feature.md`

**Aliases**:
- `build feature`
- `implement feature`
- `create feature`

**Description**: Comprehensive feature implementation workflow.

**What it does**: End-to-end feature development including models, services, tools, controllers, views, and tests.

**Workflow**:
1. **Plan**: Understand requirements
2. **Database**: Create migration and models
3. **Service**: Implement business logic
4. **Tool**: Add Scout AI integration
5. **Controller**: Build web interface
6. **Views**: Create UI templates
7. **Tests**: Write unit and system tests
8. **Verify**: Manual testing checklist

**Example**:
```
You: "build feature for managing email templates"

Claude Code:
→ Plans feature architecture
→ Creates migration: create_email_templates
→ Creates model: EmailTemplate (with entity scoping)
→ Creates service: EmailTemplateService
→ Creates tool: email_template_tool
→ Creates controller: EmailTemplatesController
→ Creates views: index, show, _form
→ Writes tests
→ Provides testing checklist
```

**Requirements**:
- Feature description
- Acceptance criteria (optional but recommended)

---

### 🧪 test-feature
**File**: `test-feature.md`

**Aliases**:
- `test feature`
- `test this`
- `run tests`

**Description**: Comprehensive testing workflow for features.

**What it does**: Guides you through writing and running tests.

**Test Types**:
- **Unit Tests**: Models, services, tools
- **Integration Tests**: Multi-component flows
- **System Tests**: Full user flows with Capybara
- **Manual Tests**: UI verification checklist

**Example**:
```
You: "test feature"

Claude Code:
→ Identifies what to test
→ Writes model tests
→ Writes service tests
→ Writes tool tests
→ Writes system tests
→ Runs test suite
→ Provides manual test checklist
```

**Requirements**:
- Feature or file to test

---

## Creating Your Own Command

**Template**:
```markdown
# [Command Name] Command

**Aliases**: `command name`, `alternative name`, `another alias`

**Description**: [What this command does in one sentence]

**What it does**:
[Detailed explanation of what happens when this command is triggered]

**Usage**:
```
[command name]
```

**Requirements**:
- [List any prerequisites]

**Triggers**: [What this activates - agent, skill, or direct action]
```

**Best Practices**:
1. Keep command names short and memorable
2. Provide multiple intuitive aliases
3. Clear description
4. List requirements
5. Show example usage
6. Reference what it triggers (agent/skill/action)

---

## Command Tips

**When to create a command**:
- Frequently repeated task
- Need quick shortcut
- Multiple ways to say the same thing (aliases)

**When NOT to create a command**:
- Complex multi-parameter actions (use skills instead)
- Rarely used tasks
- Already covered by existing command

**Command vs Agent vs Skill**:
- **Command**: Quick trigger, minimal parameters (this file)
- **Agent**: Multi-step guidance, domain expertise (agents.md)
- **Skill**: Parameterized workflows, MCP integration (skills.md)

---

## Common Patterns

**Trigger an Agent**:
```markdown
**Triggers**: This command activates the `[agent-name]` agent which handles...
```

**Trigger a Skill**:
```markdown
**Triggers**: Executes the `skill-name` skill with default parameters.
```

**Direct Action**:
```markdown
**What it does**: Directly executes [action] without additional prompts.
```

---

## Examples by Use Case

**Development Shortcuts**:
- `add-tool` - Create new tool
- `build-feature` - Full feature implementation
- `test-feature` - Comprehensive testing

**Integration Work**:
- `add-integration` - Connect external API
- `add-workflow` - Create workflow template

**Quick Actions**:
- Commands are great for actions you do multiple times per day
- Agents are better for complex guidance
- Skills are better for parameterized workflows

---

## Related Documentation

- [Agents Guide](./agents.md)
- [Skills Guide](./skills.md)
- [Skills Usage Guide](./skills-guide.md)
- [Main README](./../README.md)
