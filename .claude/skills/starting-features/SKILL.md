# Starting Features

Interactive GitHub Issues workflow that creates feature branches with comprehensive implementation plans.

## Description

This skill automates the entire feature development workflow by fetching GitHub issues, creating properly named feature branches, and generating detailed implementation plans tailored to the AMOS codebase. It follows Rails 8 + Scout AI patterns including entity scoping, tool integration, and proper testing strategies.

**Use this skill when:**
- Starting work on a GitHub issue
- Creating a feature branch with implementation plan
- Needing a structured approach to feature development
- Working with the AMOS Rails application

The skill handles:
- Git repository preparation (switch to main, pull latest)
- Interactive or direct issue selection from GitHub
- Feature branch creation with standardized naming
- Comprehensive implementation plan generation
- Testing strategy selection (unit, E2E, both, or none)
- AMOS-specific patterns (entity scoping, Scout tools, workflows)

## Instructions

### Workflow Overview

1. **Prepare Repository** - Ensure clean state on main branch
2. **Select Issue** - Interactive list or direct issue number
3. **Create Branch** - Auto-named as `feature/issue-{number}-{slug}`
4. **Generate Plan** - Comprehensive implementation roadmap
5. **Begin Development** - Step-by-step guidance

### Issue Selection

The skill supports two modes:

**Interactive Mode** (default):
- Lists up to 20 open issues from the repository
- Shows issue number, title, labels, and assignees
- Prompts for issue number selection

**Direct Mode** (with issue_number parameter):
- Skips listing, goes straight to specified issue
- Faster for known issue numbers

### Feature Branch Naming

Branches are automatically named following this pattern:
```
feature/issue-{number}-{slug}
```

Where:
- `{number}` = GitHub issue number
- `{slug}` = Issue title converted to lowercase, spaces to hyphens, max 50 chars

**Example**: Issue #42 "Add user authentication" → `feature/issue-42-add-user-authentication`

### Implementation Plan Structure

The generated plan includes:

**1. Issue Details**
- Issue number, labels, branch name, repository

**2. Database Schema (Phase 1)**
- Migration file creation
- Schema changes with examples
- Index recommendations
- Migration command

**3. Model Layer (Phase 2)**
- Model file with entity scoping pattern
- Validations and associations
- Scopes for entity filtering

**4. Service Layer (Phase 3)**
- Service class for business logic
- Entity-scoped operations
- Error handling

**5. Tool Integration (Phase 4)**
- Scout AI tool creation
- BaseTool extension pattern
- Auto-discovery via ToolCatalog

**6. Controller & Routes (Phase 5)**
- Routes configuration
- Controller with EntityScoped concern
- Authentication requirements

**7. Views (Phase 6)**
- View files needed
- Form partials
- Entity-scoped queries

**8. Testing Strategy**
- Unit tests (models, services, tools)
- E2E/System tests
- Manual testing checklist

**9. Files Summary**
- New files to create
- Files to modify
- Database changes

**10. Implementation Steps**
- Sequential execution steps
- Commands to run
- Verification steps

### Testing Preferences

Choose one of four testing strategies:

**a) Unit tests only** - Fast, focused testing
- Model tests (validations, scopes)
- Service tests (business logic)
- Tool tests (Scout integration)

**b) E2E/System tests only** - Full user flow testing
- Complete feature workflows
- Scout integration testing
- Entity isolation verification

**c) Both** - Comprehensive coverage
- All unit tests
- All E2E tests
- Manual testing checklist

**d) None** - Implementation only
- Skip test file creation
- Focus on core functionality

### AMOS-Specific Patterns

The plan follows these AMOS conventions:

**Entity Scoping** (Multi-tenant):
```ruby
belongs_to :entity
scope :accessible_by, ->(user) { where(entity_id: user.entity_id) }
```

**Controller Pattern**:
```ruby
class FeaturesController < ApplicationController
  include EntityScoped
  before_action :authenticate_user!
end
```

**Tool Pattern** (Scout AI):
```ruby
module Tools
  class FeatureTool < BaseTool
    def self.definition
      { name: 'tool_name', description: '...', parameters: {...} }
    end

    def execute(args)
      # Use @user, @entity, @workflow_execution
      success_response(message: "Done!", data: {...})
    end
  end
end
```

### Repository Configuration

**Default**: `NuvolaNetworks/agent_marketing`

Override with `repo` parameter:
```
Use starting-features with repo=owner/different-repo
```

## Examples

### Interactive Mode

```
Use starting-features skill
```

**Flow**:
1. Lists open issues
2. Prompts for issue number
3. Asks about testing preference
4. Creates branch and generates plan

### Direct Issue

```
Use starting-features with issue_number=42
```

**Flow**:
1. Fetches issue #42 directly
2. Asks about testing preference
3. Creates branch and generates plan

### With Testing Preference

```
Use starting-features with issue_number=42 tests=both
```

**Flow**:
1. Fetches issue #42
2. Skips testing prompt (uses "both")
3. Creates branch and generates plan

### Different Repository

```
Use starting-features with repo=acme/project issue_number=10
```

**Flow**:
1. Uses acme/project repository
2. Fetches issue #10
3. Continues normally

## Resources

- [Git Preparation Script](scripts/prepare-git.sh) - Repository setup
- [Issue Fetching Script](scripts/fetch-issue.sh) - GitHub issue retrieval
- [Branch Creation Script](scripts/create-branch.sh) - Feature branch creation
- [Plan Template](resources/implementation-plan-template.md) - Full plan structure
- [AMOS Patterns Reference](resources/amos-patterns.md) - Entity scoping, tools, etc.
