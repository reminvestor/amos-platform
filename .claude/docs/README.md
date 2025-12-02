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

Claude Code will recognize these and execute the corresponding skill or command.

---

## 📚 Documentation Files

### [Commands Guide](../commands/README.md)
Quick shortcuts for common development tasks.

**Available Commands**:
- `/add-tool` - Create new Scout AI tool
- `/add-workflow` - Create V2 workflow template
- `/add-integration` - Connect external API
- `/build-feature` - Full feature implementation workflow
- `/test-feature` - Comprehensive testing
- `/quick-commit` - Fast commit workflow
- `/new-dev-setup` - Developer onboarding

**When to use**: Common development tasks and workflows.

---

### [Skills Directory](../skills/)
Reusable, parameterized workflows for development operations.

**Key Skills**:
- `starting-features` - Create features, tools, workflows, integrations
- `testing-tools-manually` - Test Scout AI tools interactively
- `testing-workflows-manually` - Test V2 workflows end-to-end
- `running-tests` - Run automated test suite
- `managing-docker-development` - Docker Compose operations
- `finishing-feature-work` - Pre-commit quality checks

**When to use**: Direct workflow execution with parameters.

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
/add-tool Create a tool to export analytics
```

This uses the `starting-features` skill to guide you through tool creation.

### Using a Skill Directly

**In Claude Code**:
```
Use starting-features skill
```

Or with the Task tool for specific operations.

---

## 📖 What Each Feature Type Does

### Commands = Quick Shortcuts

**Think of commands as convenient shortcuts:**
- Fast triggers for common workflows
- Use skills behind the scenes
- Simplify complex operations
- Remember common patterns

**Example**:
```
You: "/add-tool Create a tool for sending emails"

→ Command uses starting-features skill
→ Guides you through implementation
→ Generates tool class
→ Creates tests
→ Ensures proper AMOS patterns
```

---

### Skills = Reusable Workflows

**Think of skills as reusable, parameterized workflows:**
- Accept parameters for customization
- Execute multi-step processes
- Follow AMOS patterns and conventions
- Can be composed together

**Example**:
```
You: "Use testing-tools-manually with tool_name=send_email_tool"

→ Skill executes:
  1. Loads tool from catalog
  2. Shows tool definition
  3. Prompts for test parameters
  4. Executes tool with context
  5. Shows results
```

---

## 🎯 When to Use What

### Use a Command when you need:
- ✅ Quick shortcut for common tasks
- ✅ Simple, memorable trigger
- ✅ Guided workflow
- ✅ Standard AMOS patterns

**Example**: `/add-integration Shopify` → Sets up Shopify integration

---

### Use a Skill Directly when you need:
- ✅ More control over parameters
- ✅ Compose multiple skills
- ✅ Custom workflow variations
- ✅ Testing and validation

**Example**: `Use testing-tools-manually with tool_name=your_tool` → Test specific tool

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
/add-tool Create a tool to send SMS via Twilio

# Uses starting-features skill to:
# - Guide you through tool design
# - Generate: app/services/tools/send_sms_tool.rb
# - Create: test/services/tools/send_sms_tool_test.rb
# - Verify tool catalog registration
```

---

### Scenario: Adding Integration

```
# In Claude Code:
/add-integration Twilio

# Uses starting-features skill to:
# - Create Integration record
# - Set up Connection authentication
# - Define API operations
# - Build integration tools
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
├── commands/         # Quick command shortcuts
│   ├── README.md
│   ├── add-tool.md
│   ├── add-workflow.md
│   ├── add-integration.md
│   ├── build-feature.md
│   ├── test-feature.md
│   └── ...
│
├── skills/          # Reusable workflows
│   ├── starting-features/
│   ├── testing-tools-manually/
│   ├── testing-workflows-manually/
│   ├── running-tests/
│   ├── managing-docker-development/
│   └── ...
│
└── docs/            # Documentation
    └── README.md (you are here)
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

- **[Commands README](../commands/README.md)** - Complete command reference
- **[Skills Directory](../skills/)** - All available skills
- **[CLAUDE.md](../../CLAUDE.md)** - Project architecture and patterns

---

## 🆘 Getting Help

**In Claude Code, just ask**:
- "How do I create a new tool?"
- "Help me test my workflow"
- "What skills are available?"
- "Show me available commands"

Claude Code will guide you!

---

## 🎓 Learning Path

**Beginner**:
1. Start with **commands** - `/add-tool`, `/test-feature`, etc.
2. Try **managing-docker-development** skill for Docker tasks
3. Use **starting-features** for feature development

**Intermediate**:
4. Use skills directly with parameters
5. Chain multiple skills together
6. Create your own custom commands

**Advanced**:
7. Build custom skills for team workflows
8. Extend existing skills with new capabilities
9. Integrate new tools and patterns

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
/add-tool [description]         # Create new tool
/add-workflow [description]     # Create workflow template
/add-integration [service]      # Connect external API
/build-feature [description]    # Full feature workflow
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
