#!/bin/bash
set -e

# Fixing Pull Requests - Auto-fix common PR issues
# Usage: fix-pr.sh [--pr NUMBER] [--fix-type TYPE]

PR_NUM=""
FIX_TYPE="ask"

while [[ $# -gt 0 ]]; do
  case $1 in
    --pr) PR_NUM="$2"; shift 2 ;;
    --fix-type) FIX_TYPE="$2"; shift 2 ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

# Get PR number
if [ -z "$PR_NUM" ]; then
  CURRENT_BRANCH=$(git branch --show-current)
  echo "🔍 Finding PR for branch: $CURRENT_BRANCH"
  PR_JSON=$(gh pr list --head "$CURRENT_BRANCH" --json number --limit 1)
  PR_NUM=$(echo "$PR_JSON" | jq -r '.[0].number // empty')

  if [ -z "$PR_NUM" ]; then
    echo "❌ No PR found for current branch"
    exit 1
  fi
fi

echo "📋 Analyzing PR #$PR_NUM..."
echo ""

# Get PR status
PR_DATA=$(gh pr view "$PR_NUM" --json mergeable,statusCheckRollup,baseRefName)
MERGEABLE=$(echo "$PR_DATA" | jq -r '.mergeable')
BASE_BRANCH=$(echo "$PR_DATA" | jq -r '.baseRefName')

echo "🔍 PR Status:"
echo "  - Mergeable: $MERGEABLE"
echo "  - Base branch: $BASE_BRANCH"
echo ""

HAS_CONFLICTS=false
[ "$MERGEABLE" = "CONFLICTING" ] && HAS_CONFLICTS=true

FAILING_CHECKS=$(echo "$PR_DATA" | jq -r '.statusCheckRollup[] | select(.conclusion == "FAILURE") | .name' | head -5)

if [ -n "$FAILING_CHECKS" ]; then
  echo "❌ Failing checks:"
  echo "$FAILING_CHECKS" | while read check; do echo "  - $check"; done
  echo ""
fi

# Determine what to fix
if [ "$FIX_TYPE" = "ask" ]; then
  echo "🔧 What would you like to fix?"
  echo "  a) Merge conflicts"
  echo "  b) RuboCop linting"
  echo "  c) Failing tests"
  echo "  d) All of the above"
  read -p "Your choice (a/b/c/d): " CHOICE
  case "$CHOICE" in
    a) FIX_TYPE="conflicts" ;;
    b) FIX_TYPE="lint" ;;
    c) FIX_TYPE="tests" ;;
    d) FIX_TYPE="all" ;;
  esac
fi

# Fix conflicts
if [ "$FIX_TYPE" = "all" ] || [ "$FIX_TYPE" = "conflicts" ]; then
  if [ "$HAS_CONFLICTS" = "true" ]; then
    echo "🔄 Merging $BASE_BRANCH into current branch..."
    git fetch origin "$BASE_BRANCH"

    if git merge "origin/$BASE_BRANCH" --no-edit; then
      echo "✅ Merged successfully"
    else
      echo "⚠️  Merge conflicts - attempting auto-resolution..."

      CONFLICTED=$(git diff --name-only --diff-filter=U)
      echo "$CONFLICTED" | while read file; do
        case "$file" in
          Gemfile.lock|package-lock.json|yarn.lock|db/schema.rb)
            echo "  - $file: Using theirs (will regenerate)"
            git checkout --theirs "$file"
            ;;
          *) echo "  - $file: Manual resolution needed" ;;
        esac
      done

      [ -n "$(echo $CONFLICTED | grep Gemfile.lock)" ] && docker-compose run --rm web bundle install
      [ -n "$(echo $CONFLICTED | grep 'package-lock.json\|yarn.lock')" ] && yarn install

      git add .
      git commit --no-edit || echo "⚠️  Some conflicts require manual resolution"
    fi

    git push
    echo ""
  fi
fi

# Fix linting
if [ "$FIX_TYPE" = "all" ] || [ "$FIX_TYPE" = "lint" ]; then
  echo "🔧 Running RuboCop auto-correct..."
  if docker-compose run --rm web bundle exec rubocop -A; then
    echo "✅ RuboCop fixed"
  fi

  if ! git diff --quiet; then
    git add .
    git commit -m "Fix RuboCop offenses

🤖 Generated with Claude Code"
    git push
  fi
  echo ""
fi

# Run tests
if [ "$FIX_TYPE" = "all" ] || [ "$FIX_TYPE" = "tests" ]; then
  echo "🧪 Running tests..."
  if docker-compose run --rm web rails test; then
    echo "✅ All tests passing"
  else
    echo "❌ Tests failing - review output above"
    echo "Common fixes:"
    echo "  - Run migrations: docker-compose run --rm web rails db:migrate"
    echo "  - Reset DB: docker-compose run --rm web rails db:reset"
  fi
  echo ""
fi

echo "✅ PR fixes complete!"
echo "View PR: $(gh pr view "$PR_NUM" --json url -q .url)"
