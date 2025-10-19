#!/bin/bash
set -e

# Making Quick Commits - Smart commit message generation
# Usage: quick-commit.sh [message] [push]
# Examples:
#   quick-commit.sh                              # AI-generated message with push
#   quick-commit.sh "Fix bug"                    # Custom message with push
#   quick-commit.sh "" false                     # AI-generated without push
#   quick-commit.sh "Update model" false         # Custom message without push

CUSTOM_MESSAGE="$1"
PUSH="${2:-true}"

echo "🔍 Checking git status..."
echo ""

# Check for changes
if ! git diff --quiet --cached; then
  echo "✅ Staged changes found"
  HAS_STAGED=true
else
  HAS_STAGED=false
fi

if ! git diff --quiet; then
  echo "📝 Unstaged changes found"
  HAS_UNSTAGED=true
else
  HAS_UNSTAGED=false
fi

if [ "$HAS_STAGED" = "false" ] && [ "$HAS_UNSTAGED" = "false" ]; then
  echo "❌ No changes to commit"
  exit 1
fi

echo ""
git status --short
echo ""

# Handle mixed staged/unstaged changes
if [ "$HAS_STAGED" = "false" ] && [ "$HAS_UNSTAGED" = "true" ]; then
  echo "📦 Staging all changes..."
  git add .
elif [ "$HAS_STAGED" = "true" ] && [ "$HAS_UNSTAGED" = "true" ]; then
  echo "⚠️  You have both staged and unstaged changes."
  echo ""
  echo "Staged files:"
  git diff --cached --name-only
  echo ""
  echo "Unstaged files:"
  git diff --name-only
  echo ""
  read -p "Stage all changes? (y/n): " STAGE_ALL
  if [ "$STAGE_ALL" = "y" ] || [ "$STAGE_ALL" = "yes" ]; then
    echo "📦 Staging all changes..."
    git add .
  fi
  echo ""
fi

# Generate commit message if not provided
if [ -z "$CUSTOM_MESSAGE" ]; then
  echo "🔍 Analyzing changes for commit message..."
  echo ""

  # Get diff stats
  STATS=$(git diff --cached --stat)
  echo "Changes:"
  echo "$STATS"
  echo ""

  # Get changed files
  CHANGED_FILES=$(git diff --cached --name-only)

  # Categorize changes
  NEW_FILES=$(git diff --cached --diff-filter=A --name-only | wc -l | tr -d ' ')
  MODIFIED_FILES=$(git diff --cached --diff-filter=M --name-only | wc -l | tr -d ' ')
  DELETED_FILES=$(git diff --cached --diff-filter=D --name-only | wc -l | tr -d ' ')

  echo "Summary:"
  echo "  - New files: $NEW_FILES"
  echo "  - Modified files: $MODIFIED_FILES"
  echo "  - Deleted files: $DELETED_FILES"
  echo ""

  # Determine commit type based on file patterns
  if echo "$CHANGED_FILES" | grep -q "^db/migrate/"; then
    TYPE="Add"
    SCOPE="database migration"
  elif echo "$CHANGED_FILES" | grep -q "^app/models/"; then
    TYPE="Update"
    SCOPE="models"
    # Get first model for context
    FIRST_FILE=$(echo "$CHANGED_FILES" | grep "^app/models/" | head -1)
    FILE_BASE=$(basename "$FIRST_FILE" .rb)
    SCOPE="$FILE_BASE model"
  elif echo "$CHANGED_FILES" | grep -q "^app/services/tools/"; then
    TYPE="Update"
    SCOPE="Scout tools"
    # Get first tool for context
    FIRST_FILE=$(echo "$CHANGED_FILES" | grep "^app/services/tools/" | head -1)
    FILE_BASE=$(basename "$FIRST_FILE" .rb)
    SCOPE="${FILE_BASE/_tool/} tool"
  elif echo "$CHANGED_FILES" | grep -q "^app/services/"; then
    TYPE="Update"
    SCOPE="services"
  elif echo "$CHANGED_FILES" | grep -q "^app/controllers/"; then
    TYPE="Update"
    SCOPE="controllers"
    # Get first controller for context
    FIRST_FILE=$(echo "$CHANGED_FILES" | grep "^app/controllers/" | head -1)
    FILE_BASE=$(basename "$FIRST_FILE" .rb)
    SCOPE="${FILE_BASE/_controller/} controller"
  elif echo "$CHANGED_FILES" | grep -q "^app/views/"; then
    TYPE="Update"
    SCOPE="views"
  elif echo "$CHANGED_FILES" | grep -q "^config/routes.rb"; then
    TYPE="Update"
    SCOPE="routes"
  elif echo "$CHANGED_FILES" | grep -q "^test/"; then
    TYPE="Add"
    SCOPE="tests"
  elif echo "$CHANGED_FILES" | grep -q "^docs/\|\.md$"; then
    TYPE="Update"
    SCOPE="documentation"
  elif echo "$CHANGED_FILES" | grep -q "^Gemfile\|^package.json"; then
    TYPE="Update"
    SCOPE="dependencies"
  elif [ "$NEW_FILES" -gt "0" ]; then
    TYPE="Add"
    SCOPE="new files"
  elif [ "$DELETED_FILES" -gt "0" ]; then
    TYPE="Remove"
    SCOPE="files"
  else
    TYPE="Update"
    SCOPE="code"
  fi

  SUGGESTED_MSG="$TYPE $SCOPE"

  echo "💡 Suggested commit message:"
  echo "   $SUGGESTED_MSG"
  echo ""

  read -p "Use suggested message? (y/n or enter custom): " USER_INPUT
  if [ -z "$USER_INPUT" ] || [ "$USER_INPUT" = "y" ] || [ "$USER_INPUT" = "yes" ]; then
    MESSAGE="$SUGGESTED_MSG"
  else
    MESSAGE="$USER_INPUT"
  fi
else
  MESSAGE="$CUSTOM_MESSAGE"
fi

echo "📝 Creating commit..."
echo "   Message: $MESSAGE"
echo ""

# Create commit with Claude attribution
git commit -m "$MESSAGE

🤖 Generated with Claude Code"

echo "✅ Commit created!"
echo ""

# Show commit
git log -1 --oneline
echo ""

# Push if requested
if [ "$PUSH" = "true" ]; then
  CURRENT_BRANCH=$(git branch --show-current)

  echo "📤 Pushing to origin/$CURRENT_BRANCH..."

  # Check if branch has upstream
  if git rev-parse --abbrev-ref --symbolic-full-name @{u} >/dev/null 2>&1; then
    git push
  else
    echo "Setting upstream branch..."
    git push -u origin "$CURRENT_BRANCH"
  fi

  echo "✅ Pushed successfully!"
fi
