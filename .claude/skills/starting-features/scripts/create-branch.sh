#!/bin/bash
# Create feature branch from issue

set -e

# Load issue data
ISSUE_NUM=$(cat /tmp/github_issue_number.txt 2>/dev/null)
ISSUE_TITLE=$(cat /tmp/github_issue_title.txt 2>/dev/null)

if [ -z "$ISSUE_NUM" ] || [ -z "$ISSUE_TITLE" ]; then
  echo "❌ Issue data not found. Run fetch-issue.sh first."
  exit 1
fi

# Generate branch slug (lowercase, hyphens, max 50 chars)
SLUG=$(echo "$ISSUE_TITLE" | tr '[:upper:]' '[:lower:]' | tr ' ' '-' | sed 's/[^a-z0-9-]//g' | cut -c1-50)
BRANCH_NAME="feature/issue-${ISSUE_NUM}-${SLUG}"

echo "🌿 Creating feature branch: $BRANCH_NAME"
git checkout -b "$BRANCH_NAME"

echo "✅ Created and switched to: $BRANCH_NAME"
echo ""

# Store for later use
echo "$BRANCH_NAME" > /tmp/github_branch_name.txt
