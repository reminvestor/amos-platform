# Complete Feature

End-to-end feature development with mandatory UX review and testing.

## Description

Orchestrates the entire feature development workflow with quality gates built in:
1. Scaffold the feature (models, controllers, routes)
2. Create Scout AI tools (if needed)
3. Create V2 workflow templates (if needed)
4. **🎨 UX review of all new views/components**
5. **🧪 Write comprehensive tests**
6. **🐳 Reload Docker and verify live** ← Manual QA happens here
7. Full pre-commit checks (linting, tests, docs)
8. Create draft PR on GitHub

This command ensures every feature has:
- ✅ Proper Rails structure
- ✅ UX best practices applied
- ✅ Full test coverage
- ✅ Code quality enforcement
- ✅ Ready for code review
- ✅ Live in your development environment for testing

## When to Use

- Building any new feature
- Adding Scout AI capabilities
- Creating new workflows
- Any situation where you want "done done"

## What It Does

### Phase 1: Scaffold
1. Build the Rails feature (`/build-feature`)
2. Creates model, controller, routes, migrations, tests

### Phase 2: AI & Integrations (Interactive)
- Ask: "Does this feature need Scout AI tools?"
  - If yes → `/add-tool` for each tool needed
- Ask: "Does this feature have a V2 workflow?"
  - If yes → `/add-workflow`
- Ask: "Does this need external integrations?"
  - If yes → `/add-integration`

### Phase 3: UX Review (Mandatory)
- Run `/ux` on all new view files
- Run `/ux` on stylesheets
- Review Stimulus controllers if added
- Fix any UX issues found

### Phase 4: Testing (Mandatory)
- Run `/test-feature` to write system tests
- All tests must pass
- Coverage verified

### Phase 5: Reload Docker for Manual Testing
- Restart Rails container to load new code
- Run pending migrations
- Recompile assets if needed
- Verify container is healthy
- Show you the test URL
- Ready for manual verification before committing!

### Phase 6: Final Checks
- Run `/finishing-feature-work`
- Full test suite passes
- RuboCop offenses fixed
- Documentation updated

### Phase 7: Push to GitHub
- Run `/github-push`
- Creates draft PR
- Returns PR URL

## Usage

```bash
/complete-feature "feature name"
```

## Example

```bash
/complete-feature "subscription management"

# You'll be prompted and work through these phases:
# 1. Build the feature - scaffolds models, controllers, routes
# 2. Add Scout tools? → Yes → creates AI tools
# 3. Add workflow? → Yes → creates V2 workflow template
# 4. Add integration? → No
# 5. UX review of all new views and stylesheets
# 6. Write tests with /test-feature
# 7. 🐳 Docker reload - live feature testing in http://app.localhost:3000
#    → You do manual testing here
#    → Verify everything works before committing
# 8. Full checks with /finishing-feature-work
# 9. Push and create draft PR
# ✅ Feature complete, tested live, and ready for review!
```

## Output

You'll get:
- ✅ Complete feature scaffold
- ✅ AI tools (if applicable)
- ✅ Workflow templates (if applicable)
- ✅ UX issues identified and fixed
- ✅ Comprehensive tests written
- ✅ All tests passing
- ✅ Code quality enforced
- ✅ Draft PR with full documentation
- ✅ PR URL for sharing
- ✅ Docker container reloaded with live feature
- ✅ Test URL provided for manual testing

## Time Estimate

- Small feature: 15-20 minutes
- Medium feature (with tools): 25-35 minutes
- Complex feature (with workflow + integrations): 40-50 minutes

## Quality Gates

This command enforces several quality checks:

| Step | Check | Fix |
|------|-------|-----|
| UX Review | Views follow Bootstrap/Rails best practices | Auto-fix or manual review |
| Tests | System tests for happy path and edge cases | Must pass before continuing |
| Linting | RuboCop offenses | Auto-fixed |
| Documentation | README and docs updated | Prompted to update |
| Git | All changes staged and committed | Auto-commit |

## Tips

1. **Have a clear feature idea** before running this command
2. **Answer the interactive prompts honestly** (do you need tools/workflows?)
3. **UX fixes are interactive** - you'll be asked about each issue
4. **Tests are auto-written** but you can enhance them
5. **The resulting PR is DRAFT** - mark ready when you want review

## Related Commands

- `/build-feature` - Just scaffold without full workflow
- `/test-feature` - Just write tests for existing feature
- `/github-push` - Just push without complete checks
- `/check-deployment` - Verify your setup before starting
