#!/bin/bash
# Execute predefined skill workflows

set -e

WORKFLOW="${1:-pre-commit}"
shift

echo "🔄 Running workflow: $WORKFLOW"
echo ""

case "$WORKFLOW" in
  feature-start)
    echo "📋 Feature Start Workflow"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "This workflow will:"
    echo "  1. Prepare git repository"
    echo "  2. Fetch GitHub issue"
    echo "  3. Create feature branch"
    echo "  4. Generate implementation plan"
    echo ""
    echo "⚠️  Manual step: Use 'starting-features' skill"
    echo "    Claude Code will guide you through the process"
    ;;

  pre-commit)
    echo "✅ Pre-Commit Quality Checks"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    echo "Step 1/3: Fixing RuboCop offenses..."
    ./.claude/skills/fixing-rubocop-offenses-skill/scripts/fix-rubocop.sh . false false

    echo ""
    echo "Step 2/3: Running affected tests..."
    ./.claude/skills/running-tests-skill/scripts/run-affected-tests.sh

    echo ""
    echo "Step 3/3: Checking application health..."
    docker-compose ps | grep -q "Up" && echo "✅ Services running" || echo "⚠️  Services not running"

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "✅ Pre-commit checks complete!"
    ;;

  pre-deploy)
    echo "🚀 Pre-Deployment Validation"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    echo "Step 1/4: Running full test suite..."
    COVERAGE=true ./.claude/skills/running-tests-skill/scripts/run-all-tests.sh

    echo ""
    echo "Step 2/4: Fixing RuboCop offenses..."
    ./.claude/skills/fixing-rubocop-offenses-skill/scripts/fix-rubocop.sh . false false

    echo ""
    echo "Step 3/4: Checking application health..."
    docker-compose ps

    echo ""
    echo "Step 4/4: Verifying database status..."
    docker-compose exec web rails db:migrate:status | tail -5

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "✅ Pre-deployment validation complete!"
    ;;

  dev-reset)
    echo "🔄 Development Environment Reset"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "⚠️  WARNING: This will DELETE all local data!"
    echo ""
    read -p "Type 'yes' to confirm: " confirm

    if [ "$confirm" != "yes" ]; then
      echo "Cancelled."
      exit 1
    fi

    echo ""
    echo "Step 1/4: Stopping services..."
    docker-compose down

    echo ""
    echo "Step 2/4: Cleaning Docker resources..."
    docker-compose down -v
    docker system prune -f

    echo ""
    echo "Step 3/4: Recreating database..."
    docker-compose up -d db
    sleep 5
    docker-compose run --rm web rails db:drop db:create db:migrate db:seed

    echo ""
    echo "Step 4/4: Starting all services..."
    docker-compose up -d
    sleep 5
    docker-compose ps

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "✅ Development environment reset complete!"
    echo "📍 Rails app: http://localhost:3000"
    ;;

  quality-check)
    echo "📊 Code Quality Audit"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    echo "Step 1/3: RuboCop analysis..."
    docker-compose run --rm web bundle exec rubocop --format progress || true

    echo ""
    echo "Step 2/3: Running tests with coverage..."
    COVERAGE=true ./.claude/skills/running-tests-skill/scripts/run-all-tests.sh || true

    echo ""
    echo "Step 3/3: Checking test coverage..."
    if [ -f coverage/index.html ]; then
      echo "✅ Coverage report available: coverage/index.html"
      echo "   Open with: open coverage/index.html"
    else
      echo "⚠️  No coverage report found"
    fi

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "📊 Quality audit complete!"
    ;;

  quick-pr)
    echo "🚀 Quick PR Creation"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    BRANCH=$(git branch --show-current)
    if [ "$BRANCH" = "main" ]; then
      echo "❌ Cannot create PR from main branch"
      exit 1
    fi

    echo "Step 1/5: Fixing RuboCop..."
    ./.claude/skills/fixing-rubocop-offenses-skill/scripts/fix-rubocop.sh . false true

    echo ""
    echo "Step 2/5: Running affected tests..."
    ./.claude/skills/running-tests-skill/scripts/run-affected-tests.sh

    echo ""
    echo "Step 3/5: Checking for uncommitted changes..."
    if ! git diff --quiet; then
      echo "⚠️  Uncommitted changes found. Please commit manually."
      exit 1
    fi

    echo ""
    echo "Step 4/5: Pushing branch..."
    git push -u origin "$BRANCH"

    echo ""
    echo "Step 5/5: Creating PR..."
    echo "⚠️  Manual step: Use GitHub CLI or web interface to create PR"
    echo "    gh pr create --fill"

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "✅ Ready for PR creation!"
    ;;

  *)
    echo "❌ Unknown workflow: $WORKFLOW"
    echo ""
    echo "Available workflows:"
    echo "  - feature-start    : Start new feature from GitHub issue"
    echo "  - pre-commit       : Quality checks before committing"
    echo "  - pre-deploy       : Deployment readiness validation"
    echo "  - dev-reset        : Reset development environment"
    echo "  - quality-check    : Comprehensive code quality audit"
    echo "  - quick-pr         : Fast PR creation workflow"
    exit 1
    ;;
esac
