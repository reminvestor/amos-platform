# Claude Code Documentation

Complete guide to using agents, commands, and skills in Claude Code for AMOS development.

---

## ⚠️ Important: How to Use These Features

**These are Claude Code features, NOT bash commands!**

You use them **inside Claude Code** (the chat interface), not in your terminal.

### ❌ Wrong Way (Terminal):
```bash
# This won't work!
$ docker-dev start
bash: docker-dev: command not found
```

### ✅ Correct Way (Claude Code):
```
# In Claude Code chat, just type:
docker-dev start

# Or:
start-feature

# Or:
add tool
```

Claude Code will recognize these and execute the corresponding skill/command/agent.

---

## 📚 Documentation Files

### [Agents Guide](./agents.md)
Learn about specialized AI assistants that handle complex multi-step workflows.

**Available Agents**:
- `tool-builder` - Creates new Scout AI tools
- `integration-connector` - Connects external APIs
- `workflow-architect` - Designs V2 workflow templates
- `bedrock-integration-specialist` - AWS Bedrock expert
- `rails-system-test-specialist` - E2E testing guide
- `ui-healer` - Fixes UI/UX issues

**When to use**: Complex tasks needing domain expertise and guidance.

---

### [Commands Guide](./commands.md)
Quick shortcuts for common tasks.

**Available Commands**:
- `add-tool` - Create new tool
- `add-integration` - Connect external API
- `add-workflow` - Create workflow template
- `build-feature` - Full feature implementation
- `test-feature` - Comprehensive testing

**When to use**: Simple shortcuts and triggers.

---

### [Skills Guide](./skills.md)
Parameterized workflows with MCP integration.

**Available Skills**:
- `docker-dev` - Docker Compose management
- `start-feature` - Azure DevOps backlog workflow

**When to use**: Workflows needing parameters or MCP tools.

---

### [Skills Usage Guide](./skills-guide.md)
Complete examples and workflows for using docker-dev and start-feature skills.

**Includes**:
- All docker-dev operations
- start-feature walkthrough
- Common workflows
- Troubleshooting

---

## 🚀 Quick Start

### Using a Skill

**In Claude Code chat**:
```
docker-dev start
```

Claude Code will execute the skill and show you the output.

**With parameters**:
```
docker-dev logs service=web
```

**Interactive**:
```
start-feature
```

### Using a Command

**In Claude Code chat**:
```
add tool
```

This triggers the Tool Builder agent to guide you.

### Using an Agent

Agents activate automatically when Claude Code detects your task matches their expertise.

**Or explicitly**:
```
I need help from the workflow-architect agent
```

---

## 📖 What Each Feature Type Does

### Agents = Domain Experts

**Think of agents as specialized consultants:**
- Deep knowledge of specific domains
- Guide you through complex workflows
- Make recommendations based on AMOS patterns
- Handle multi-step processes

**Example**:
```
You: "I need to create a tool for sending emails"

→ Tool Builder Agent activates
→ Asks about parameters
→ Generates tool class
→ Creates tests
→ Ensures proper patterns
```

---

### Commands = Quick Shortcuts

**Think of commands as aliases or shortcuts:**
- Fast triggers for common tasks
- No parameters needed
- Can activate agents or skills
- Multiple aliases

**Example**:
```
You: "add integration"

→ Command triggers Integration Connector agent
→ Agent guides you through setup
```

---

### Skills = Parameterized Workflows

**Think of skills as reusable scripts:**
- Accept parameters
- Call MCP tools (Azure DevOps, GitHub, etc.)
- Execute bash commands
- Multi-step automation

**Example**:
```
You: "docker-dev db db_action=migrate"

→ Skill executes:
  1. Checks Docker services
  2. Runs migration in container
  3. Shows results
```

---

## 🎯 When to Use What

### Use an Agent when you need:
- ✅ Guidance through complex process
- ✅ Domain-specific expertise
- ✅ Recommendations based on best practices
- ✅ Multi-turn conversation
- ✅ Help making decisions

**Example**: "How do I integrate with Stripe?" → Integration Connector Agent

---

### Use a Command when you need:
- ✅ Quick shortcut
- ✅ Simple trigger
- ✅ No parameters
- ✅ Common task

**Example**: "add tool" → Triggers Tool Builder Agent

---

### Use a Skill when you need:
- ✅ Parameterized workflow
- ✅ Call MCP tools
- ✅ Automated multi-step process
- ✅ Reusable operation

**Example**: "start-feature work_item_id=1234" → Creates branch from Azure DevOps

---

## 💡 Examples by Scenario

### Scenario: Daily Development Workflow

**Morning startup**:
```
# In Claude Code:
docker-dev start
docker-dev logs service=web
```

**Pick work item**:
```
start-feature
# (Interactive: Select item, choose testing)
```

**Implement feature**:
```
# Agent guides you through implementation
# Run migrations:
docker-dev db

# Run tests:
docker-dev test
```

---

### Scenario: Creating New Tool

```
# In Claude Code:
add tool

# Agent asks questions:
Agent: "What should the tool do?"
You: "Send SMS messages via Twilio"

Agent: "What parameters does it need?"
You: "phone_number, message"

# Agent generates:
# - app/services/tools/send_sms_tool.rb
# - test/services/tools/send_sms_tool_test.rb
```

---

### Scenario: Adding Integration

```
# In Claude Code:
add integration

Agent: "Which service?"
You: "Twilio"

Agent: "API documentation URL?"
You: "https://www.twilio.com/docs/..."

# Agent creates:
# - Integration model definition
# - Connection authentication
# - API operations
# - Client service
# - Tools for Scout
```

---

### Scenario: Docker Troubleshooting

```
# Check status:
docker-dev ps

# View logs:
docker-dev logs service=web

# Restart:
docker-dev restart

# Fresh rebuild:
docker-dev clean
docker-dev rebuild
```

---

## 📁 File Structure

```
.claude/
├── agents/           # Specialized AI assistants
│   ├── tool-builder.md
│   ├── integration-connector.md
│   ├── workflow-architect.md
│   └── ...
│
├── commands/         # Quick shortcuts
│   ├── add-tool.md
│   ├── add-integration.md
│   ├── build-feature.md
│   └── ...
│
├── skills/          # Parameterized workflows
│   ├── docker-dev.yaml
│   └── start-feature.yaml
│
└── docs/            # This documentation
    ├── README.md (you are here)
    ├── agents.md
    ├── commands.md
    ├── skills.md
    └── skills-guide.md
```

---

## 🔧 Configuration

### Azure DevOps MCP (for start-feature skill)

Edit `.claude/.mcp.json`:
```json
{
  "mcpServers": {
    "azure_devops": {
      "type": "stdio",
      "command": "npx",
      "args": ["-y", "@azure/devops-mcp"],
      "env": {
        "AZURE_DEVOPS_ORG": "your-org-name",
        "AZURE_DEVOPS_PAT": "your-personal-access-token"
      }
    }
  }
}
```

**Restart Claude Code** after adding MCP servers.

---

## 📚 Further Reading

- **[agents.md](./agents.md)** - Detailed agent documentation
- **[commands.md](./commands.md)** - Complete command reference
- **[skills.md](./skills.md)** - Skill creation and usage
- **[skills-guide.md](./skills-guide.md)** - docker-dev and start-feature examples

---

## 🆘 Getting Help

**In Claude Code, just ask**:
- "How do I use docker-dev?"
- "Show me start-feature examples"
- "What agents are available?"
- "Help me create a new tool"

Claude Code will guide you!

---

## 🎓 Learning Path

**Beginner**:
1. Start with **commands** - simple shortcuts
2. Try **docker-dev** skill for daily Docker tasks
3. Use **start-feature** for backlog items

**Intermediate**:
4. Work with **agents** for feature development
5. Create your own **commands**
6. Customize **skills** with parameters

**Advanced**:
7. Create custom **agents** for team workflows
8. Build complex **skills** with MCP integration
9. Integrate new MCP servers

---

## ✅ Cheat Sheet

**Docker Operations**:
```
docker-dev start           # Start services
docker-dev console         # Rails console
docker-dev db              # Run migrations
docker-dev test            # Run tests
docker-dev logs service=web # View logs
```

**Feature Development**:
```
start-feature              # Interactive backlog selection
add tool                   # Create new tool
add integration           # Connect external API
build-feature             # Full feature workflow
```

**Testing**:
```
docker-dev test test_path=model      # Model tests
docker-dev test test_path=system     # E2E tests
test-feature                         # Comprehensive testing
```

---

**Happy coding!** 🚀

Remember: Use these **in Claude Code chat**, not your terminal!
