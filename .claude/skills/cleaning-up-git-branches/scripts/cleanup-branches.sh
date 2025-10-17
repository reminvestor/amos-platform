#!/bin/bash
set -e

# Cleaning Up Git Branches - Delete merged branches
# Usage: cleanup-branches.sh [--scope SCOPE] [--force]

SCOPE="both"
FORCE=false

while [[ $# -gt 0 ]]; do
  case $1 in
    --scope)
      SCOPE="$2"
      shift 2
      ;;
    --force)
      FORCE=true
      shift
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done

echo "🔄 Fetching latest from remote and pruning..."
git fetch --prune
echo "✅ Fetch complete"
echo ""

# Find merged local branches
echo "🔍 Finding merged local branches..."
echo ""

CURRENT=$(git branch --show-current)
MERGED_LOCAL=$(git branch --merged main 2>/dev/null | grep -v "^\*" | grep -v "main" | grep -v "master" | grep -v "develop" | grep -v "$CURRENT" || true)

if [ -z "$MERGED_LOCAL" ] && [ "$SCOPE" != "remote" ]; then
  echo "✅ No merged local branches to clean up"
elif [ -n "$MERGED_LOCAL" ] && [ "$SCOPE" != "remote" ]; then
  echo "Found merged local branches:"
  echo "$MERGED_LOCAL" | while read branch; do
    echo "  - $(echo $branch | xargs)"
  done
  echo ""

  if [ "$FORCE" = false ]; then
    read -p "Delete these local branches? (yes/no): " CONFIRM_LOCAL
  else
    CONFIRM_LOCAL="yes"
  fi

  if [ "$CONFIRM_LOCAL" = "yes" ]; then
    echo "🗑️  Deleting merged local branches..."
    echo "$MERGED_LOCAL" | while read branch; do
      branch=$(echo "$branch" | xargs)
      if [ -n "$branch" ]; then
        echo "  Deleting: $branch"
        git branch -d "$branch" 2>&1 || echo "    ⚠️  Could not delete"
      fi
    done
    echo "✅ Local cleanup complete"
  else
    echo "⏭️  Skipping local branch deletion"
  fi
  echo ""
fi

# Find merged remote branches
if [ "$SCOPE" != "local" ]; then
  echo "🔍 Finding merged remote branches..."
  echo ""

  MERGED_REMOTE=$(git branch -r --merged main | grep "origin/" | grep -v "main" | grep -v "master" | grep -v "develop" | grep -v "HEAD" || true)

  if [ -z "$MERGED_REMOTE" ]; then
    echo "✅ No merged remote branches to clean up"
  else
    echo "Found merged remote branches:"
    echo "$MERGED_REMOTE" | while read branch; do
      BRANCH_NAME=$(echo "$branch" | xargs | sed 's|origin/||')
      echo "  - $BRANCH_NAME"
    done
    echo ""

    if [ "$FORCE" = false ]; then
      echo "⚠️  WARNING: This will delete branches on GitHub!"
      read -p "Delete these remote branches? (yes/no): " CONFIRM_REMOTE
    else
      CONFIRM_REMOTE="yes"
    fi

    if [ "$CONFIRM_REMOTE" = "yes" ]; then
      echo "🗑️  Deleting merged remote branches..."
      echo "$MERGED_REMOTE" | while read branch; do
        branch=$(echo "$branch" | xargs)
        if [ -n "$branch" ]; then
          BRANCH_NAME=$(echo "$branch" | sed 's|origin/||')
          echo "  Deleting: $BRANCH_NAME (remote)"
          git push origin --delete "$BRANCH_NAME" 2>&1 || echo "    ⚠️  Could not delete"
        fi
      done
      echo "✅ Remote cleanup complete"
    else
      echo "⏭️  Skipping remote branch deletion"
    fi
  fi
  echo ""
fi

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📊 Cleanup Summary"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Remaining local branches:"
git branch
echo ""
echo "Remaining remote branches:"
git branch -r | grep "origin/" | grep -v "HEAD"
echo ""
echo "✅ Branch cleanup complete!"
