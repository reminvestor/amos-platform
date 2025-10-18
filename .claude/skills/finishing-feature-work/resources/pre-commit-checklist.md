# Pre-Commit Checklist

Manual verification steps before committing code.

## Automated Checks

The `finishing-feature-work` skill runs these automatically:

- [ ] All tests pass (`rails test`)
- [ ] RuboCop offenses fixed (`rubocop -a`)
- [ ] Merged branches cleaned up (`git branch -d`)
- [ ] Documentation updated (if tools/workflows/models changed)

## Manual Verification

### Code Quality

- [ ] No `binding.pry` or debugger statements left in code
- [ ] No commented-out code blocks (unless intentionally documented)
- [ ] No `TODO` comments without GitHub issue reference
- [ ] Console.log/puts statements removed (unless intentional logging)
- [ ] No hardcoded credentials or API keys

### Functionality

- [ ] Feature works as expected in browser
- [ ] Edge cases handled (empty states, errors, validations)
- [ ] Works with different entity contexts (multi-tenancy)
- [ ] No breaking changes to existing features
- [ ] Database migrations are reversible (`change` method or `up`/`down`)

### Testing

- [ ] New features have test coverage
- [ ] Edge cases tested
- [ ] Error conditions tested
- [ ] Integration tests pass
- [ ] No flaky tests (run suite 2-3 times to verify)

### Documentation

- [ ] Public APIs documented with comments
- [ ] Complex logic explained with inline comments
- [ ] README updated if setup/usage changed
- [ ] CLAUDE.md updated if architecture changed
- [ ] Workflow templates documented if added

### Git Hygiene

- [ ] Commit message is descriptive
- [ ] Commits are logical and atomic (not "WIP" or "fix fix fix")
- [ ] No merge commits (use rebase)
- [ ] Branch name follows convention (`feature/`, `bugfix/`, `refactor/`)
- [ ] No accidental files committed (`.DS_Store`, `*.log`, etc.)

### Security

- [ ] User input sanitized
- [ ] SQL injection prevented (use parameterized queries)
- [ ] XSS prevented (proper escaping)
- [ ] Authorization checks in place (`current_entity` scoping)
- [ ] Sensitive data not logged

### Performance

- [ ] No N+1 queries (check logs for query patterns)
- [ ] Database indexes on foreign keys
- [ ] Large collections paginated
- [ ] Heavy operations moved to background jobs
- [ ] Caching used where appropriate

## Quick Commands

```bash
# Run tests
docker-compose run --rm web rails test

# Run specific test file
docker-compose run --rm web rails test test/models/campaign_test.rb

# Run specific test
docker-compose run --rm web rails test test/models/campaign_test.rb:23

# Check RuboCop
docker-compose run --rm web bundle exec rubocop

# Fix RuboCop auto-fixable offenses
docker-compose run --rm web bundle exec rubocop -a

# Check for N+1 queries
docker-compose logs web | grep "N+1"

# Check test coverage
docker-compose run --rm web rails test
# Coverage report in coverage/index.html

# Validate migrations
docker-compose run --rm web rails db:migrate:status
```

## Git Commands

```bash
# Check what will be committed
git status
git diff

# Add specific files
git add app/models/campaign.rb

# Commit with message
git commit -m "Add campaign scheduling feature

- Add scheduled_at field to campaigns
- Implement background job for sending
- Add validation for future dates
- Update campaign form with datetime picker

Closes #123"

# Amend last commit (if not pushed)
git commit --amend

# Interactive rebase to clean up commits
git rebase -i HEAD~3
```

## Before Creating PR

- [ ] All checks above passed
- [ ] Branch is up to date with main (`git pull origin main`)
- [ ] No merge conflicts
- [ ] CI/CD pipeline passing (if applicable)
- [ ] Screenshots added to PR description (for UI changes)
- [ ] Breaking changes documented in PR description
- [ ] Reviewers assigned

## PR Description Template

```markdown
## Summary
Brief description of what this PR does

## Changes
- Bullet list of changes
- Organized by type (features, fixes, refactors)

## Testing
How to test these changes:
1. Step by step instructions
2. Expected behavior

## Screenshots
(if applicable)

## Related Issues
Closes #123
Related to #456

## Checklist
- [ ] Tests added/updated
- [ ] Documentation updated
- [ ] No breaking changes (or documented if present)
- [ ] RuboCop passing
```
