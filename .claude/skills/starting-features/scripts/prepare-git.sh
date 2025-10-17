#!/bin/bash
# Prepare Git repository for feature development

set -e

echo "🔍 Checking Git status..."
current_branch=$(git branch --show-current)

if [ "$current_branch" != "main" ]; then
  echo "⚠️  Currently on branch: $current_branch"
  echo "Switching to main..."
  git checkout main || exit 1
fi

echo "📥 Pulling latest from origin/main..."
git pull origin main

echo "✅ Ready on main branch"
echo ""
