# Claude Code Agents

Agents are specialized AI assistants that handle specific types of tasks in the AMOS codebase. They have deep knowledge of particular domains and can guide you through complex multi-step workflows.

---

## How Agents Work

**Definition**: Agents are markdown files in `.claude/agents/` that define specialized behaviors, knowledge, and workflows.

**When to use**: Agents are triggered automatically when Claude Code detects that your request matches an agent's specialty, or you can explicitly ask for an agent by name.

**Key Features**:
- Deep domain expertise
- Multi-step workflow guidance
- Context-aware recommendations
- Follow AMOS patterns and conventions

---

## Available Agents

### 🔧 Tool Builder Agent
**File**: `tool-builder.md`

**Purpose**: Guides you through creating new Scout AI tools that follow AMOS patterns.

**When triggered**:
- "create a new tool"
- "add tool for Scout"
- "build a Scout tool"

**What it does**:
1. Asks about tool purpose and parameters
2. Suggests appropriate tool name
3. Generates tool class following `BaseTool` pattern
4. Creates tool tests
5. Ensures auto-discovery by ToolCatalog
6. Validates tool definition format

**Example**:
```
You: "I need to create a tool that sends SMS messages"

Tool Builder Agent:
- Asks about parameters (phone number, message, etc.)
- Suggests name: send_sms_tool
- Generates: app/services/tools/send_sms_tool.rb
- Creates: test/services/tools/send_sms_tool_test.rb
- Shows you how Scout will use it
```

---

### 🌐 Integration Connector Agent
**File**: `integration-connector.md`

**Purpose**: Helps you connect external APIs and services to AMOS.

**When triggered**:
- "add integration"
- "connect to API"
- "integrate with [service]"

**What it does**:
1. Analyzes the external API documentation
2. Creates Integration model definition
3. Sets up Connection authentication
4. Defines IntegrationOperations for API endpoints
5. Builds API client service
6. Creates tools for Scout to use the integration

**Example**:
```
You: "Integrate with Twilio for SMS"

Integration Connector:
- Reviews Twilio API docs
- Creates Integration record for Twilio
- Sets up OAuth2/API key authentication
- Defines operations: send_sms, get_messages, etc.
- Creates TwilioApiService
- Generates tools for Scout
```

---

### 🏗️ Workflow Architect Agent
**File**: `workflow-architect.md`

**Purpose**: Designs and implements V2 workflow templates for Scout.

**When triggered**:
- "create workflow"
- "add workflow template"
- "design workflow for [task]"

**What it does**:
1. Understands the workflow requirements
2. Designs 3-phase structure (gather → execute → validate)
3. Creates YAML template with proper format
4. Defines context sources and required fields
5. Maps data to tool calls
6. Sets up validation rules
7. Adds to workflow_templates/ directory

**Example**:
```
You: "Create a workflow for generating social media posts"

Workflow Architect:
- Designs gather_context phase (brand voice, topic, platform)
- Designs execute_goal phase (generate post, optimize hashtags)
- Designs validate phase (check character limits, tone)
- Creates: app/workflow_templates/social_post_generation_v2.yml
- Shows how PlannerAgent will use it
```

---

### ☁️ Bedrock Integration Specialist Agent
**File**: `bedrock-integration-specialist.md`

**Purpose**: Expert in AWS Bedrock API integration, tool calling, and Claude model usage.

**When triggered**:
- "use Bedrock"
- "Claude API"
- "tool calling with Claude"

**What it does**:
1. Helps structure Bedrock API calls
2. Formats tool definitions for Claude
3. Handles streaming responses
4. Implements tool calling workflows
5. Manages token usage and costs
6. Optimizes prompts for Claude models

**Example**:
```
You: "Add Claude Vision support for analyzing uploaded images"

Bedrock Specialist:
- Extends BedrockService with image support
- Formats base64 image data correctly
- Structures multimodal API calls
- Handles image analysis responses
- Optimizes token usage
```

---

### 🧪 Rails System Test Specialist Agent
**File**: `rails-system-test-specialist.md`

**Purpose**: Guides E2E testing with Capybara and system tests.

**When triggered**:
- "write system test"
- "create E2E test"
- "test user flow"

**What it does**:
1. Designs complete user flow tests
2. Uses Capybara selectors correctly
3. Handles JavaScript interactions
4. Tests Scout AI chat interface
5. Verifies entity isolation
6. Creates comprehensive assertions

**Example**:
```
You: "Test the campaign creation flow"

System Test Specialist:
- Creates: test/system/campaign_creation_test.rb
- Sets up test data (user, entity, contacts)
- Navigates through UI
- Fills forms
- Verifies database changes
- Tests Scout integration
```

---

### 🩹 UI Healer Agent
**File**: `ui-healer.md`

**Purpose**: Fixes UI/UX issues, styling problems, and frontend bugs.

**When triggered**:
- "fix UI bug"
- "styling is broken"
- "layout issue"

**What it does**:
1. Diagnoses UI problems
2. Identifies CSS conflicts
3. Fixes responsive design issues
4. Improves accessibility
5. Ensures Bootstrap 5 compatibility
6. Tests across viewports

**Example**:
```
You: "The sidebar is overlapping content on mobile"

UI Healer:
- Identifies CSS conflict
- Adjusts Bootstrap grid classes
- Adds responsive breakpoints
- Tests on different screen sizes
- Ensures touch-friendly interactions
```

---

## Creating Your Own Agent

**Template**:
```markdown
# [Agent Name] Agent

**Purpose**: [What this agent specializes in]

**Trigger**: When user says [phrases that activate this agent]

---

## Workflow Steps

### Step 1: [First Step Name]

**Actions**:
1. [Action description]
2. [Action description]

**Output**: [What user sees]

---

### Step 2: [Next Step Name]

[Continue workflow...]

---

## Key Principles

1. **[Principle 1]**: [Description]
2. **[Principle 2]**: [Description]

---

## Example Interaction

**User**: "[Example request]"

**Agent**:
```
[Agent response]
```

**User**: "[Follow-up]"

**Agent**: [Agent response]
```

**Best Practices**:
1. Be specific about triggers
2. Define clear workflow steps
3. Include code examples
4. Reference AMOS patterns
5. Show example interactions
6. List key principles
7. Provide error handling guidance

---

## Agent Tips

**When to create an agent**:
- Complex multi-step workflows
- Domain-specific knowledge required
- Repeated similar tasks
- Need to enforce patterns/conventions

**When NOT to create an agent**:
- Simple one-off tasks (use commands instead)
- Already covered by existing agent
- Doesn't need specialized knowledge

**Agent vs Command vs Skill**:
- **Agent**: Multi-step guidance, domain expertise (this file)
- **Command**: Quick shortcuts, simple aliases (commands.md)
- **Skill**: Parameterized workflows, MCP integration (skills.md)

---

## Related Documentation

- [Commands Guide](./commands.md)
- [Skills Guide](./skills.md)
- [Skills Usage Guide](./skills-guide.md)
- [Main README](./../README.md)
