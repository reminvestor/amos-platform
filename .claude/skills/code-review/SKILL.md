# Code Review

Pre-commit review checklist and systematic PR feedback processing.

## Description

This skill provides two complementary review workflows:
1. **Request Review** - Pre-commit checklist to catch issues before pushing
2. **Receive Review** - Process PR feedback systematically and implement changes

**Use this skill when:**
- Before pushing code (request review mode)
- After receiving PR feedback (receive review mode)
- Doing self-review of changes
- Preparing code for team review

## Instructions

### Mode 1: Request Review (Pre-Commit)

**Purpose:** Catch issues before creating PR.

Run this checklist before every push:

#### Code Quality Checklist

```markdown
## Pre-Commit Review Checklist

### 1. Functionality
- [ ] Feature works as specified
- [ ] Edge cases handled
- [ ] Error states handled gracefully
- [ ] No debug code left in (byebug, puts, console.log)

### 2. AMOS Patterns
- [ ] Entity scoping applied where needed
- [ ] `current_entity` used in controllers
- [ ] Fixtures include entity associations
- [ ] Tools extend BaseTool correctly
- [ ] Tool auto-discovery verified

### 3. Security
- [ ] No secrets in code (API keys, passwords)
- [ ] SQL injection prevented (use parameterized queries)
- [ ] XSS prevented (escape user input)
- [ ] Authorization checks present
- [ ] Entity isolation maintained

### 4. Testing
- [ ] New code has tests
- [ ] Tests are meaningful (not just coverage)
- [ ] All tests pass locally
- [ ] Entity scoping tested

### 5. Code Style
- [ ] Rubocop passes
- [ ] Consistent naming conventions
- [ ] No unnecessary comments
- [ ] Methods are focused (single responsibility)

### 6. Performance
- [ ] N+1 queries avoided (use includes/eager_load)
- [ ] Indexes added for foreign keys
- [ ] Background jobs for slow operations
- [ ] No blocking calls in streaming responses

### 7. Documentation
- [ ] Complex logic has comments
- [ ] API changes documented
- [ ] Workflow templates have keywords
```

#### Quick Commands

```bash
# Run before pushing
/rubocop                    # Check style
/run-tests affected         # Run relevant tests
docker-compose exec web rails test  # Full suite
```

### Mode 2: Receive Review (Process Feedback)

**Purpose:** Systematically address PR feedback.

#### Feedback Processing Framework

**Step 1: Categorize Comments**

```markdown
## PR Feedback Categories

### Must Fix (Blocking)
- Security issues
- Breaking functionality
- Data integrity risks
- Missing entity scoping

### Should Fix (Important)
- Performance concerns
- Code clarity improvements
- Missing error handling
- Test coverage gaps

### Consider (Optional)
- Style preferences
- Alternative approaches
- Nice-to-have features
```

**Step 2: Create Action Items**

Convert each comment to a todo:

```markdown
## Feedback from @reviewer

### Comment 1: Missing entity scoping in CampaignService
- **Category:** Must Fix
- **File:** app/services/campaign_service.rb:45
- **Action:** Add entity_id filter to query
- **Status:** [ ] Pending

### Comment 2: Consider caching this API call
- **Category:** Consider
- **File:** app/services/tools/fetch_data_tool.rb:23
- **Action:** Evaluate caching strategy
- **Status:** [ ] Pending
```

**Step 3: Implement Changes**

For each feedback item:
1. Read the commented code
2. Understand the concern
3. Implement the fix (use TDD if adding functionality)
4. Verify the fix
5. Mark as complete

**Step 4: Respond to Comments**

```markdown
## Response Template

### For fixes:
"Fixed in [commit hash]. Added entity scoping filter at line 45."

### For alternative approaches:
"Good point. I went with X because [reason]. Open to changing if you prefer Y."

### For deferred items:
"Created issue #123 to track this. Out of scope for current PR."
```

### AMOS Review Focus Areas

**Entity Scoping Review:**
```ruby
# WRONG - Missing entity scope
Campaign.where(status: 'active')

# RIGHT - Entity scoped
Campaign.where(entity: @entity, status: 'active')
# or
current_entity.campaigns.where(status: 'active')
```

**Tool Review:**
```ruby
# Check these in every tool:
# 1. definition method returns valid schema
# 2. execute uses @entity, @user properly
# 3. Returns success_response or error_response
# 4. Auto-registers in ToolCatalog
```

**Controller Review:**
```ruby
# Every controller should have:
include EntityScoped
before_action :authenticate_user!
# And filter all queries by current_entity
```

### Review Response Template

After addressing feedback:

```markdown
## PR Update Summary

**Changes made:**
- Fixed entity scoping in CampaignService (commit abc123)
- Added nil check in GoalExecutor (commit def456)
- Improved error message in CreateToolTool (commit ghi789)

**Deferred to future PR:**
- Caching optimization (#123)
- Additional test coverage (#124)

**Ready for re-review** ✅
```

## Examples

**Pre-commit self-review:**
```
Use code-review skill mode=request
```

**Process PR feedback:**
```
Use code-review skill mode=receive pr=123
```

**Quick style check:**
```
Use code-review skill mode=quick
```

## Commands Integration

Create corresponding command:

```
/code-review [mode]
```

Where mode is:
- `request` - Pre-commit checklist
- `receive` - Process PR feedback
- `quick` - Fast style check only

## Resources

- [GitHub Push Command](../../commands/github-push.md) - Create PRs
- [Rubocop Command](../../commands/rubocop.md) - Style checking
- [Running Tests](../running-tests/SKILL.md) - Test execution
