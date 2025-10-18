#!/usr/bin/env bash
# Complete pre-commit quality assurance workflow

set -e

SKIP_TESTS="${1:-false}"
SKIP_DOCS="${2:-false}"
SKIP_CLEANUP="${3:-false}"
AUTO_COMMIT="${4:-false}"

TESTS_PASSED=false
RUBOCOP_CLEAN=false
BRANCHES_CLEANED=false
DOCS_UPDATED=false

echo "🚀 Pre-Commit Quality Workflow"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Step 1: Run Tests
if [ "$SKIP_TESTS" != "true" ]; then
  echo "🧪 Step 1: Running Test Suite..."
  echo ""

  if docker-compose run --rm web rails test; then
    echo ""
    echo "✅ All tests passed!"
    TESTS_PASSED=true
  else
    echo ""
    echo "❌ Test failures detected!"
    echo ""
    echo "Fix failing tests before committing."
    echo "Run specific test: rails test <path/to/test_file.rb>:<line_number>"
    exit 1
  fi
else
  echo "⏭️  Step 1: Skipping tests (skip_tests=true)"
  TESTS_PASSED=true
fi

echo ""

# Step 2: Fix RuboCop Offenses
echo "🔍 Step 2: Running RuboCop..."
echo ""

# Run RuboCop with autocorrect
if docker-compose run --rm web bundle exec rubocop -a; then
  echo ""
  echo "✅ RuboCop clean or all offenses auto-fixed!"
  RUBOCOP_CLEAN=true
else
  echo ""
  echo "⚠️  RuboCop offenses require manual fixes"
  echo ""
  echo "Run: docker-compose run --rm web bundle exec rubocop"
  echo "Or fix manually, then run this skill again."
  exit 1
fi

echo ""

# Step 3: Clean Up Branches
if [ "$SKIP_CLEANUP" != "true" ]; then
  echo "🌿 Step 3: Cleaning Up Merged Branches..."
  echo ""

  # Get list of merged branches (excluding main/master and current)
  CURRENT_BRANCH=$(git branch --show-current)
  MERGED_BRANCHES=$(git branch --merged | grep -v "^\*" | grep -v "main" | grep -v "master" | grep -v "develop" | xargs echo)

  if [ -n "$MERGED_BRANCHES" ]; then
    echo "Found merged branches:"
    echo "$MERGED_BRANCHES"
    echo ""
    read -p "Delete these branches? (y/n): " CONFIRM

    if [ "$CONFIRM" = "y" ]; then
      echo "$MERGED_BRANCHES" | xargs -n 1 git branch -d 2>/dev/null || true
      echo "✅ Branches cleaned up!"
      BRANCHES_CLEANED=true
    else
      echo "⏭️  Skipping branch cleanup"
      BRANCHES_CLEANED=true
    fi
  else
    echo "✅ No merged branches to clean up"
    BRANCHES_CLEANED=true
  fi
else
  echo "⏭️  Step 3: Skipping branch cleanup (skip_cleanup=true)"
  BRANCHES_CLEANED=true
fi

echo ""

# Step 4: Update Documentation
if [ "$SKIP_DOCS" != "true" ]; then
  echo "📚 Step 4: Updating Documentation..."
  echo ""

  # Generate tools documentation
  TOOLS_LIST=$(docker-compose run --rm web rails runner '
    require "tools/tool_catalog"

    catalog = Tools::ToolCatalog.instance
    tools = catalog.all_tools.sort_by { |name, _| name }

    tools.each do |name, tool_class|
      definition = tool_class.definition
      puts "### #{definition[:name]}"
      puts ""
      puts definition[:description]
      puts ""
      puts "**File:** `app/services/tools/#{name}.rb`"
      puts ""
      puts "---"
      puts ""
    end
  ' 2>/dev/null)

  mkdir -p docs

  cat > docs/SCOUT_TOOLS.md <<EOF
# Scout AI Tools Reference

Auto-generated documentation for all available Scout AI tools.

**Last Updated:** $(date +"%Y-%m-%d %H:%M")

## Available Tools

$TOOLS_LIST
EOF

  if git diff --quiet docs/; then
    echo "✅ Documentation already up to date"
  else
    echo "✅ Documentation updated!"
    git add docs/
  fi

  DOCS_UPDATED=true
else
  echo "⏭️  Step 4: Skipping documentation update (skip_docs=true)"
  DOCS_UPDATED=true
fi

echo ""

# Step 5: Summary
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [ "$TESTS_PASSED" = true ] && [ "$RUBOCOP_CLEAN" = true ]; then
  echo "✅ Ready to Commit!"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""
  echo "All checks passed:"

  [ "$TESTS_PASSED" = true ] && echo "  ✅ Tests passing"
  [ "$RUBOCOP_CLEAN" = true ] && echo "  ✅ Code style compliant"
  [ "$BRANCHES_CLEANED" = true ] && [ "$SKIP_CLEANUP" != "true" ] && echo "  ✅ Branches cleaned"
  [ "$DOCS_UPDATED" = true ] && [ "$SKIP_DOCS" != "true" ] && echo "  ✅ Documentation current"

  echo ""

  # Check for uncommitted changes
  if ! git diff --quiet; then
    echo "📝 Uncommitted changes detected"
    echo ""
    git status --short
    echo ""

    if [ "$AUTO_COMMIT" = "true" ]; then
      read -p "Commit message: " COMMIT_MSG

      if [ -n "$COMMIT_MSG" ]; then
        git add .
        git commit -m "$COMMIT_MSG

🤖 Generated with Claude Code
Co-Authored-By: Claude <noreply@anthropic.com>"

        echo ""
        echo "✅ Changes committed!"
        echo ""
        echo "Next steps:"
        echo "  git push"
        echo "  Or create PR: gh pr create"
      else
        echo "⏭️  Commit cancelled (no message provided)"
      fi
    else
      echo "Next steps:"
      echo "  git add ."
      echo "  git commit -m \"Your commit message\""
      echo "  git push"
      echo ""
      echo "Or use auto_commit=true to commit automatically"
    fi
  else
    echo "✅ No uncommitted changes"
    echo ""
    echo "You're ready to push:"
    echo "  git push"
  fi
else
  echo "❌ Quality Checks Failed!"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""
  echo "Issues to resolve:"

  [ "$TESTS_PASSED" = false ] && echo "  ❌ Tests failing"
  [ "$RUBOCOP_CLEAN" = false ] && echo "  ❌ RuboCop offenses"

  echo ""
  echo "Fix issues above and run again"
  exit 1
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
