# Code Review

Pre-commit review checklist and PR feedback processing.

## Usage

```
/code-review [mode]
```

**Modes:**
- `request` - Pre-commit self-review checklist
- `receive [pr-number]` - Process PR feedback
- `quick` - Fast style check only

## What It Does

### Request Mode (Default)

Runs comprehensive pre-commit checklist:

- **Functionality** - Does it work? Edge cases? Error handling?
- **AMOS Patterns** - Entity scoping, tool patterns, fixtures
- **Security** - No secrets, SQL injection, XSS, authorization
- **Testing** - New tests, meaningful tests, all pass
- **Code Style** - Rubocop, naming, focused methods
- **Performance** - N+1 queries, indexes, background jobs

### Receive Mode

Processes PR feedback systematically:

1. Categorize comments (Must Fix / Should Fix / Consider)
2. Create action items from each comment
3. Implement fixes with TDD
4. Respond to comments with commit references

### Quick Mode

Fast check before small changes:

```bash
/rubocop           # Style
/run-tests affected # Tests
```

## Pre-Commit Checklist

```markdown
## Before Pushing

### Must Check
- [ ] No debug code (byebug, puts, console.log)
- [ ] Entity scoping applied
- [ ] Tests pass
- [ ] Rubocop passes

### Should Check
- [ ] Error handling present
- [ ] No N+1 queries
- [ ] Security review done
```

## Examples

```
/code-review                     # Full pre-commit review
/code-review request             # Same as above
/code-review receive 123         # Process PR #123 feedback
/code-review quick               # Fast style check
```

## Related

- [Code Review Skill](../.claude/skills/code-review/SKILL.md)
- `/rubocop` - Style checking
- `/run-tests` - Test execution
- `/github-push` - Create PRs
