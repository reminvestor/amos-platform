# Finishing Feature Work

Complete pre-commit workflow: tests, linting, and cleanup.

## Description

This skill runs the complete quality assurance workflow before committing feature work. It executes tests, fixes RuboCop offenses, cleans up unused branches, and optionally updates documentation. This is the go-to command before creating a pull request or committing significant changes.

**Use this skill when:**
- Finishing feature development
- Preparing to commit changes
- Before creating a pull request
- After fixing bugs or making updates
- When you want to ensure code quality

## Instructions

### What This Skill Does

Executes a comprehensive QA workflow:

1. **Run Tests** - Verifies code functionality
   - Runs full test suite with `rails test`
   - Shows test results and coverage
   - Fails fast if tests don't pass

2. **Fix RuboCop Offenses** - Ensures code style
   - Runs RuboCop with autocorrect
   - Fixes safe offenses automatically
   - Reports remaining manual fixes needed

3. **Clean Up Branches** - Removes merged branches
   - Lists merged branches
   - Prompts for cleanup confirmation
   - Removes stale local branches

4. **Update Documentation** (optional)
   - Updates tools reference
   - Updates workflow templates docs
   - Updates models documentation

5. **Summary** - Ready to commit checklist
   - Shows what passed/fixed
   - Lists any remaining issues
   - Suggests commit command

### Usage Patterns

**Full Pre-Commit Workflow:**
```
Use finishing-feature-work
```
Runs all steps including documentation update.

**Quick Check (No Docs):**
```
Use finishing-feature-work with skip_docs=true
```
Runs tests, linting, and branch cleanup only.

**Tests and Linting Only:**
```
Use finishing-feature-work with skip_docs=true skip_cleanup=true
```
Just verifies code quality without cleanup.

**Skip Tests (Risky):**
```
Use finishing-feature-work with skip_tests=true
```
Only runs linting and cleanup. Not recommended.

### Parameters

- `skip_tests` - Skip test suite (default: `false`) - NOT RECOMMENDED
- `skip_docs` - Skip documentation updates (default: `false`)
- `skip_cleanup` - Skip branch cleanup (default: `false`)
- `auto_commit` - Automatically commit changes after success (default: `false`)

### Exit Behavior

**Success (Exit 0):**
- All tests passed
- No RuboCop offenses (or all auto-fixed)
- Ready to commit

**Failure (Exit 1):**
- Test failures detected
- RuboCop offenses require manual fixes
- Should not commit until resolved

## Examples

### Complete Pre-Commit Check

```
Use finishing-feature-work
```

Output:
```
🧪 Running Test Suite...
Finished in 12.34s, 56.78 runs/s
123 runs, 456 assertions, 0 failures, 0 errors, 0 skips
✅ All tests passed!

🔍 Running RuboCop...
Inspecting 45 files
...........................................
45 files inspected, 3 offenses detected, 3 offenses autocorrected
✅ RuboCop offenses fixed!

🌿 Cleaning Up Merged Branches...
Found 2 merged branches: feature/old-feature, bugfix/minor-fix
Delete? (y/n): y
✅ Branches cleaned up!

📚 Updating Documentation...
✅ Documentation updated!

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
✅ Ready to Commit!
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

All checks passed:
  ✅ Tests passing
  ✅ Code style compliant
  ✅ Branches cleaned
  ✅ Documentation current

Next steps:
  git add .
  git commit -m "Your commit message"
  git push
```

### Quick Check Before Commit

```
Use finishing-feature-work with skip_docs=true skip_cleanup=true
```

Only runs tests and RuboCop. Fast feedback loop during active development.

### Auto-Commit After Success

```
Use finishing-feature-work with auto_commit=true
```

If all checks pass, automatically stages changes and prompts for commit message.

### Handle Test Failures

When tests fail:
```
❌ Test failures detected:

1) CampaignTest#test_validates_required_fields
   Expected: true
   Actual: false

Fix failing tests before committing.
Run specific test: rails test test/models/campaign_test.rb:42
```

Stops execution and shows which tests need fixing.

### Handle RuboCop Offenses

When manual fixes needed:
```
⚠️  RuboCop offenses require manual fixes:

app/models/campaign.rb:23:5: C: Style/HashSyntax: Use the new Ruby 1.9 hash syntax.

Run: rubocop -a
Or fix manually, then run this skill again.
```

Shows what needs manual attention before proceeding.

## Resources

- [Finish Feature Script](scripts/finish-feature.sh) - Main orchestration script
- [Pre-Commit Checklist](resources/pre-commit-checklist.md) - Manual verification steps
- [Code Quality Standards](resources/code-quality-standards.md) - Project standards reference
