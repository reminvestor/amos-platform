# Quick Commit

Fast pre-commit workflow for small changes.

## Usage

```
/quick-commit [message]
```

## What It Does

Lightweight pre-commit check for quick iterations:

1. **Runs tests** - Quick mode (changed files only)
2. **Fixes RuboCop** - Auto-correct safe offenses
3. **Commits changes** - With provided message
4. **Shows summary** - What was committed

## Examples

```bash
# Interactive (prompts for message)
/quick-commit

# With message
/quick-commit "Fix campaign validation bug"

# Results in:
# - Tests passing for changed files
# - Code style fixed
# - Changes committed with message
# - Ready to push
```

## vs. finishing-feature-work

**Use quick-commit when:**
- Small bug fix
- Minor change
- Quick iteration during development
- Don't need full test suite

**Use finishing-feature-work when:**
- Feature complete
- Before creating PR
- Major changes
- Need full test coverage

## Behind the Scenes

Executes:
1. `running-tests` (quick mode) - Only changed files
2. `fixing-rubocop-offenses` - Auto-fix code style
3. `making-quick-commits` - Commit with message

## Implementation

```bash
#!/usr/bin/env bash
# Command: quick-commit
# Description: Fast pre-commit workflow for small changes

COMMIT_MESSAGE="${1:-}"

echo "⚡ Quick Commit"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Check for uncommitted changes
if git diff --quiet && git diff --staged --quiet; then
  echo "✅ No changes to commit"
  exit 0
fi

# Step 1: Quick tests
echo "🧪 Running quick tests..."
.claude/skills/running-tests/scripts/run-tests.sh quick

if [ $? -ne 0 ]; then
  echo ""
  echo "❌ Tests failed. Fix issues before committing."
  exit 1
fi

echo ""

# Step 2: Fix RuboCop
echo "🔍 Fixing code style..."
.claude/skills/fixing-rubocop-offenses/scripts/fix-rubocop.sh . false false

echo ""

# Step 3: Commit
if [ -z "$COMMIT_MESSAGE" ]; then
  echo "📝 Enter commit message:"
  read -r COMMIT_MESSAGE
fi

if [ -z "$COMMIT_MESSAGE" ]; then
  echo "❌ Commit message required"
  exit 1
fi

git add .

git commit -m "$COMMIT_MESSAGE

🤖 Generated with Claude Code
Co-Authored-By: Claude <noreply@anthropic.com>"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ Committed!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
git log -1 --oneline
echo ""
echo "Next: git push"
