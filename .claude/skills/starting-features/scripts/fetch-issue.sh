#!/bin/bash
# Fetch GitHub issue details

set -e

REPO="${1:-NuvolaNetworks/agent_marketing}"
ISSUE_NUM="$2"

if [ -z "$ISSUE_NUM" ]; then
  echo "📋 Fetching open issues from $REPO..."
  echo ""

  # List open issues
  gh issue list \
    --repo "$REPO" \
    --state open \
    --limit 20 \
    --json number,title,labels,assignees,createdAt \
    --template '{{range .}}{{tablerow (printf "#%v" .number) .title (pluck "name" .labels | join ", ") (pluck "login" .assignees | join ", ")}}{{end}}'

  echo ""
  read -p "Which issue would you like to work on? (Enter issue number): " ISSUE_NUM
fi

echo "📖 Fetching details for issue #$ISSUE_NUM..."
echo ""

# Get full issue details
ISSUE_JSON=$(gh issue view "$ISSUE_NUM" \
  --repo "$REPO" \
  --json number,title,body,labels,assignees,milestone)

# Parse and display
ISSUE_TITLE=$(echo "$ISSUE_JSON" | jq -r '.title')
ISSUE_BODY=$(echo "$ISSUE_JSON" | jq -r '.body // ""')
ISSUE_LABELS=$(echo "$ISSUE_JSON" | jq -r '.labels | map(.name) | join(", ")')
ISSUE_ASSIGNEES=$(echo "$ISSUE_JSON" | jq -r '.assignees | map(.login) | join(", ")')

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📌 Issue #$ISSUE_NUM: $ISSUE_TITLE"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "📝 Description:"
echo "$ISSUE_BODY"
echo ""
[ -n "$ISSUE_LABELS" ] && echo "🏷️  Labels: $ISSUE_LABELS"
[ -n "$ISSUE_ASSIGNEES" ] && echo "👤 Assignees: $ISSUE_ASSIGNEES"
echo ""

# Store for use by other scripts
echo "$ISSUE_JSON" > /tmp/github_issue_$ISSUE_NUM.json
echo "$ISSUE_NUM" > /tmp/github_issue_number.txt
echo "$ISSUE_TITLE" > /tmp/github_issue_title.txt
