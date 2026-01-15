# Git Conventional Commits

Auto-generate consistent, meaningful commit messages following the Conventional Commits specification.

## Description

This skill ensures all commits follow the [Conventional Commits](https://www.conventionalcommits.org/) specification, making git history readable, enabling automated changelogs, and improving team communication.

**Use this skill when:**
- Committing code changes
- Want consistent commit message format
- Need meaningful git history
- Preparing for release notes

## Instructions

### Commit Message Format

```
<type>(<scope>): <description>

[optional body]

[optional footer]
```

### Types

| Type | When to Use | Example |
|------|-------------|---------|
| `feat` | New feature | `feat(tools): add subscription management tool` |
| `fix` | Bug fix | `fix(workflow): handle nil context in executor` |
| `docs` | Documentation only | `docs(readme): update API examples` |
| `style` | Formatting, no code change | `style: fix rubocop offenses` |
| `refactor` | Code change without fix/feature | `refactor(service): extract email sending logic` |
| `test` | Adding/updating tests | `test(tools): add entity scoping tests` |
| `chore` | Maintenance, deps, config | `chore(deps): update rails to 8.0.1` |
| `perf` | Performance improvement | `perf(query): add index for entity lookups` |
| `ci` | CI/CD changes | `ci: add staging deployment workflow` |

### Scopes (AMOS-Specific)

Common scopes for this project:

| Scope | Area |
|-------|------|
| `tools` | Scout AI tools |
| `workflow` | V2 workflow system |
| `agent` | Agent/executor services |
| `model` | Database models |
| `api` | API endpoints |
| `ui` | Views and frontend |
| `docker` | Container configuration |
| `integration` | External API integrations |
| `voice` | Voice assistant system |
| `mobile` | Flutter mobile app |

### Writing Good Descriptions

**Rules:**
1. Use imperative mood ("add" not "added" or "adds")
2. Don't capitalize first letter
3. No period at the end
4. Max 50 characters
5. Describe *what* and *why*, not *how*

**Good Examples:**
```
feat(tools): add landing page generation tool
fix(workflow): prevent duplicate phase execution
refactor(agent): simplify context gathering logic
test(model): add entity scoping validation tests
```

**Bad Examples:**
```
Fixed bug                           # Not descriptive
Added new feature for subscriptions # Too vague, wrong tense
feat: stuff                         # Meaningless
Updated files                       # What files? Why?
```

### When to Use Body

Add a body for:
- Breaking changes
- Complex changes needing explanation
- References to issues

```
feat(api): add webhook endpoint for Stripe events

Adds POST /webhooks/stripe to receive payment events.
Processes subscription updates and failed payments.

Closes #123
```

### Breaking Changes

Use `!` after type or `BREAKING CHANGE:` in footer:

```
feat(api)!: change auth from cookies to bearer tokens

BREAKING CHANGE: All API endpoints now require Authorization header.
Cookie-based auth is removed.

Migration: Update client code to include Bearer token.
```

### Auto-Generation Rules

When analyzing changes to generate commits:

1. **Read the diff** - Understand what changed
2. **Identify the type** - Feature, fix, refactor, etc.
3. **Find the scope** - Which area of the codebase
4. **Write description** - What and why in 50 chars
5. **Add body if needed** - For complex changes

### Commit Frequency

**Commit often, commit small:**

```
# Good - Atomic commits
git commit -m "feat(model): add Subscription model"
git commit -m "feat(model): add entity scoping to Subscription"
git commit -m "test(model): add Subscription validation tests"

# Bad - Monolithic commit
git commit -m "add subscription feature"
```

### Integration with Workflow

Use with other commands:

```bash
# After completing a task
git add .
git commit -m "feat(tools): add create_subscription tool"

# Push with PR
/github-push "Add subscription management"
```

## Examples

**New feature:**
```
Use git-conventional-commits skill for "added new landing page tool"
→ feat(tools): add landing page generation tool
```

**Bug fix:**
```
Use git-conventional-commits skill for "fixed entity scoping bug"
→ fix(model): add missing entity scope to Campaign
```

**Multiple files:**
```
Use git-conventional-commits skill
→ Analyzes diff, generates appropriate message
```

## Quick Reference

```
feat     → New feature
fix      → Bug fix
docs     → Documentation
style    → Formatting
refactor → Code restructure
test     → Tests
chore    → Maintenance
perf     → Performance
ci       → CI/CD
```

## Resources

- [Conventional Commits Spec](https://www.conventionalcommits.org/)
- [GitHub Push Command](../../commands/github-push.md)
- [Complete Feature Command](../../commands/complete-feature.md)
