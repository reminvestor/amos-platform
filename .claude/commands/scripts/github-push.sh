#!/usr/bin/env bash
# Command: github-push
# Description: Stage changes, push to GitHub, create draft PR

set -e  # Exit on error

PR_TITLE="${1:-}"
BASE_BRANCH="main"

echo "🚀 GitHub Push & Draft PR"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Step 1: Check current branch
CURRENT_BRANCH=$(git branch --show-current)

if [ "$CURRENT_BRANCH" = "main" ] || [ "$CURRENT_BRANCH" = "master" ]; then
  echo "❌ Cannot run on main/master branch"
  echo "   Switch to a feature branch first:"
  echo "   git checkout -b feature/my-feature"
  exit 1
fi

echo "📍 Current branch: $CURRENT_BRANCH"
echo ""

# Step 2: Check for changes
if git diff --quiet && git diff --cached --quiet && [ -z "$(git ls-files --others --exclude-standard)" ]; then
  echo "ℹ️  No changes to commit"
  echo ""

  # Check if branch exists on remote
  if git rev-parse --verify "origin/$CURRENT_BRANCH" >/dev/null 2>&1; then
    echo "📤 Branch already pushed. Checking for existing PR..."

    # Check if PR exists
    PR_URL=$(gh pr view --json url --jq .url 2>/dev/null || echo "")

    if [ -n "$PR_URL" ]; then
      echo "✅ PR already exists: $PR_URL"
      exit 0
    else
      echo "Creating PR for existing branch..."
    fi
  else
    echo "Nothing to push. Exiting."
    exit 0
  fi
fi

# Step 3: Show what will be committed
echo "📋 Changes to be committed:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
git status --short | head -20
TOTAL_CHANGES=$(git status --short | wc -l | tr -d ' ')

if [ "$TOTAL_CHANGES" -gt 20 ]; then
  echo "... and $((TOTAL_CHANGES - 20)) more files"
fi

echo ""
echo "Total files changed: $TOTAL_CHANGES"
echo ""

# Step 4: Get PR title if not provided
if [ -z "$PR_TITLE" ]; then
  echo "📝 Enter PR title (or press Enter for auto-generated):"
  read -r PR_TITLE

  if [ -z "$PR_TITLE" ]; then
    # Auto-generate from branch name
    PR_TITLE=$(echo "$CURRENT_BRANCH" | sed 's/[-_]/ /g' | sed 's/\b\(.\)/\u\1/g')
    echo "   Using: $PR_TITLE"
  fi
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Ready to:"
echo "  1. Stage all changes"
echo "  2. Commit: \"$PR_TITLE\""
echo "  3. Push to: origin/$CURRENT_BRANCH"
echo "  4. Create draft PR → $BASE_BRANCH"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
read -p "Continue? [Y/n] " -n 1 -r
echo ""

if [[ ! $REPLY =~ ^[Yy]$ ]] && [[ ! -z $REPLY ]]; then
  echo "Cancelled."
  exit 0
fi

echo ""

# Step 5: Stage all changes
echo "📦 Staging changes..."
git add -A

# Step 6: Create commit
echo "💾 Creating commit..."

COMMIT_MSG="$PR_TITLE

🤖 Generated with Claude Code
Co-Authored-By: Claude <noreply@anthropic.com>"

git commit -m "$COMMIT_MSG"

echo "✅ Committed"
echo ""

# Step 7: Push to remote
echo "📤 Pushing to GitHub..."

# Check if branch exists on remote
if git rev-parse --verify "origin/$CURRENT_BRANCH" >/dev/null 2>&1; then
  echo "   Updating existing branch..."
  git push origin "$CURRENT_BRANCH"
else
  echo "   Creating new remote branch..."
  git push -u origin "$CURRENT_BRANCH"
fi

echo "✅ Pushed to origin/$CURRENT_BRANCH"
echo ""

# Step 8: Create draft PR (or get existing)
echo "📝 Creating draft PR..."

# Check if PR already exists
EXISTING_PR=$(gh pr view --json url --jq .url 2>/dev/null || echo "")

if [ -n "$EXISTING_PR" ]; then
  echo "✅ PR already exists: $EXISTING_PR"
  PR_URL="$EXISTING_PR"
else
  # Get diff stats for PR body
  STATS=$(git diff "$BASE_BRANCH"..."$CURRENT_BRANCH" --stat | tail -1)

  # Create PR body
  PR_BODY="## Summary

Auto-generated from branch: \`$CURRENT_BRANCH\`

## Changes

\`\`\`
$STATS
\`\`\`

## Test Plan

- [ ] Run unit tests: \`rails test\`
- [ ] Check for regressions
- [ ] Manual testing completed

## Notes

This is a draft PR. Mark as ready for review when complete.

---

🤖 Generated with [Claude Code](https://claude.com/claude-code)"

  # Create draft PR
  PR_URL=$(gh pr create \
    --draft \
    --base "$BASE_BRANCH" \
    --title "$PR_TITLE" \
    --body "$PR_BODY" \
    2>&1 | grep -o 'https://.*' || echo "")

  if [ -z "$PR_URL" ]; then
    echo "❌ Failed to create PR"
    echo "   Try manually: gh pr create --draft --base $BASE_BRANCH"
    exit 1
  fi

  echo "✅ Draft PR created"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ Success!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Branch:  $CURRENT_BRANCH"
echo "PR:      $PR_URL"
echo "Status:  Draft"
echo ""
echo "Next steps:"
echo "  • View PR: open $PR_URL"
echo "  • Mark ready: gh pr ready"
echo "  • Add reviewers: gh pr edit --add-reviewer @username"
echo ""
