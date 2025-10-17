# Claude Code Skills Guide

Quick reference for using AMOS development skills in Claude Code.

---

## 🐳 docker-dev - Docker Development Skill

**Purpose**: Manage Docker Compose development environment (Rails, Postgres, Redis)

### Basic Operations

```bash
# Start all services
docker-dev start

# Stop all services
docker-dev stop

# Restart all services
docker-dev restart

# Rebuild everything (fresh start)
docker-dev rebuild

# Show container status
docker-dev ps

# Clean up (remove containers and volumes)
docker-dev clean
```

### Development Tools

```bash
# Open Rails console
docker-dev console

# Open bash shell in web container
docker-dev shell

# View logs (all services)
docker-dev logs

# View Rails logs only
docker-dev logs service=web

# View Redis logs
docker-dev logs service=redis

# View database logs
docker-dev logs service=db
```

### Database Operations

```bash
# Run migrations (default)
docker-dev db
docker-dev db db_action=migrate

# Rollback last migration
docker-dev db db_action=rollback

# Seed database
docker-dev db db_action=seed

# Reset database (drop, create, migrate, seed)
docker-dev db db_action=reset

# Drop database (with confirmation)
docker-dev db db_action=drop
```

### Testing

```bash
# Run all tests
docker-dev test

# Run model tests only
docker-dev test test_path=model

# Run controller tests only
docker-dev test test_path=controller

# Run system tests only
docker-dev test test_path=system

# Run specific test file
docker-dev test test_path=test/models/user_test.rb
```

### RAG Operations

```bash
# Check RAG system health
docker-dev rag
docker-dev rag rag_action=health

# Verify Docling and API keys installed
docker-dev rag rag_action=verify

# Seed system RAG stores (Stripe, HubSpot docs)
docker-dev rag rag_action=seed

# List all RAG stores
docker-dev rag rag_action=list

# Test RAG functionality
docker-dev rag rag_action=test
```

### Common Workflows

**Daily Startup:**
```bash
docker-dev start
docker-dev logs service=web
```

**After Pulling Code:**
```bash
docker-dev restart
docker-dev db
docker-dev test
```

**Fresh Rebuild:**
```bash
docker-dev clean
docker-dev rebuild
docker-dev db db_action=reset
```

**Debugging:**
```bash
docker-dev logs service=web
docker-dev console
docker-dev shell
```

---

## 🚀 start-feature - Backlog Workflow Skill

**Purpose**: Create feature branch from Azure DevOps backlog with implementation plan

### Prerequisites

**1. Configure Azure DevOps MCP** in `.claude/.mcp.json`:
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

**2. Get Azure DevOps Personal Access Token:**
- Go to https://dev.azure.com/{your-org}/_usersSettings/tokens
- Create new token with Work Items (Read & Write) scope
- Copy token and add to .mcp.json

**3. Restart Claude Code** after configuring MCP

### Basic Usage

**Interactive Mode (Recommended):**
```bash
start-feature
```

This will:
1. Switch to main branch and pull latest
2. Show you list of backlog items assigned to you
3. Ask which one you want to work on
4. Create feature branch
5. Ask about testing preferences
6. Generate detailed implementation plan

**Example Output:**
```
📋 Available Work Items:

1. [User Story #1234] Add RAG document upload UI
   Priority: 1 | State: Active | Assigned: Ryan

2. [Bug #1235] Fix Scout chat scroll position
   Priority: 2 | State: New | Unassigned

3. [Task #1236] Update workflow documentation
   Priority: 3 | State: Active | Assigned: Ryan

Which work item would you like to work on? (Enter number or ID)
```

You type: `1`

```
✅ Created and switched to branch: feature/work-item-1234-add-rag-document-upload-ui

🧪 What testing would you like to include?

a) Unit tests only
b) E2E/System tests only
c) Both unit and E2E tests
d) No tests (implementation only)

Your choice (a/b/c/d):
```

You type: `c`

Then it generates a comprehensive implementation plan!

### Advanced Usage

**Skip Interactive Selection:**
```bash
# If you already know the work item ID
start-feature work_item_id=1234
```

**Specify Testing Upfront:**
```bash
# Unit tests only
start-feature tests=unit

# E2E tests only
start-feature tests=e2e

# Both unit and E2E
start-feature tests=both

# No tests
start-feature tests=none
```

**Different Project:**
```bash
start-feature project=my-other-project
```

**Combine Parameters:**
```bash
start-feature work_item_id=1234 tests=both
```

### What You Get

The skill generates a **detailed implementation plan** including:

**📋 Work Item Summary**
- ID, type, priority, branch name

**🎯 Objective**
- Clear description of what needs to be done

**✅ Acceptance Criteria**
- Checklist from Azure DevOps work item

**🏗️ Implementation Phases**
Each phase includes:
- Specific file paths
- Whether to create/modify/delete
- Actual code examples
- Reason for each change

Example phases:
- Phase 1: Database Schema (migrations, models)
- Phase 2: Service Layer (business logic)
- Phase 3: Tool Integration (Scout AI)
- Phase 4: Controller & Routes (web interface)
- Phase 5: Views (UI templates)

**🧪 Testing Strategy**
Based on your preference:
- Unit test file locations
- Specific test cases to write
- E2E test scenarios
- Manual testing checklist

**📦 Files to Create/Modify**
Complete list of all files affected

**⚠️ Considerations**
- Entity isolation requirements
- Database migrations needed
- Edge cases to handle
- Dependencies to consider

**🔄 Implementation Steps**
High-level roadmap with actual commands

### After Getting the Plan

The skill will ask:
```
🚀 Ready to Start?

Options:
- Type "yes" or "start" to begin implementation
- Type "change [section]" to revise part of the plan
- Type "more detail on [topic]" to expand a section
```

Then you can:
- Ask me to implement it step by step
- Implement it yourself using the plan as a guide
- Ask for more details on specific parts
- Request changes to the plan

### Example Workflow

**Full Example:**
```bash
# 1. Start feature workflow
start-feature

# (Select work item #1234)
# (Choose "both" for testing)
# (Review implementation plan)
# (Type "yes" to proceed)

# 2. Now I help you implement:
# - Create migration
docker-dev db db_action=migrate

# - Write code files
# - Create tests
docker-dev test

# - Manual testing
docker-dev console

# 3. Commit and push
git add .
git commit -m "Implement #1234: Feature name"
git push -u origin feature/work-item-1234-feature-name
```

---

## 💡 Pro Tips

### docker-dev

**Combine with watch mode:**
```bash
# In one terminal
docker-dev start

# In another terminal
docker-dev logs service=web
```

**Quick reset for fresh state:**
```bash
docker-dev clean && docker-dev rebuild && docker-dev db db_action=reset
```

**Debug database issues:**
```bash
docker-dev shell
# Inside container:
rails dbconsole
```

### start-feature

**Work on backlog items efficiently:**
1. Run `start-feature` Monday morning
2. Pick your top priority item
3. Get implementation plan
4. Execute throughout the day
5. Repeat for next item

**Use testing preferences wisely:**
- `unit` - Fast feedback, TDD approach
- `e2e` - Critical user flows only
- `both` - Important features (recommended)
- `none` - Quick fixes, experiments

**Branch naming is automatic:**
- Format: `feature/work-item-{id}-{slug}`
- Example: `feature/work-item-1234-add-rag-upload-ui`
- Slug is auto-generated from work item title

**Plan is your blueprint:**
- Don't skip reading it
- Ask for clarification on unclear parts
- Use it as checklist during implementation
- It references actual AMOS patterns

---

## 🔗 Combined Workflow Example

**Complete feature development cycle:**

```bash
# 1. Start Docker environment
docker-dev start

# 2. Start feature from backlog
start-feature

# (Interactive: Select work item, choose testing)
# (Review plan, approve)

# 3. Implement Phase 1 (Database)
# - Create migration file
docker-dev db db_action=migrate

# 4. Implement Phase 2 (Models, Services, Tools)
# - Write code files

# 5. Run tests
docker-dev test

# 6. Test manually
docker-dev console

# 7. Check in Scout UI
# - Visit http://localhost:3000
# - Test the feature

# 8. Commit
git add .
git commit -m "Implement #1234: Feature name"
git push -u origin <branch-name>

# 9. Create PR (if needed)
gh pr create --title "..." --body "..."
```

---

## 🛠️ Troubleshooting

### docker-dev Issues

**Container won't start:**
```bash
docker-dev clean
docker-dev rebuild
```

**Database connection refused:**
```bash
docker-dev ps  # Check if db is running
docker-dev restart service=db
docker-dev logs service=db  # Check for errors
```

**Redis errors:**
```bash
docker-dev restart service=redis
docker-dev logs service=redis
```

### start-feature Issues

**"Azure DevOps MCP not configured":**
- Add MCP to `.claude/.mcp.json` (see Prerequisites)
- Restart Claude Code

**"No backlog items found":**
- Check project name is correct
- Verify work items exist in Azure DevOps
- Check work item states (New, Active)
- Try: `start-feature work_item_id=1234` if you know the ID

**"Git working directory not clean":**
```bash
git status
git stash  # or commit changes
start-feature  # try again
```

**"Not on main branch":**
- The skill will automatically switch to main
- Or manually: `git checkout main`

---

## 📚 More Resources

- [RAG Docker Setup](./RAG_DOCKER_SETUP.md) - RAG-specific Docker guide
- [AMOS Workflow Deep Dive](./AMOS_WORKFLOW_SYSTEM_DEEP_DIVE.md) - Architecture details
- [CLAUDE.md](../CLAUDE.md) - AMOS development patterns

---

**Happy coding!** 🚀

Need help? Just ask me:
- "How do I use docker-dev?"
- "Show me start-feature examples"
- "Help me debug Docker issues"
