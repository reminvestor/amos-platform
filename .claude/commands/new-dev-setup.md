# New Developer Setup

Quick command to set up a complete development environment for new developers.

## Usage

```
/new-dev-setup [entity_name]
```

## What It Does

This command chains multiple skills to provide a complete onboarding experience:

1. **Checks application health** - Verifies Docker, database, and services
2. **Prepares development environment** - Sets up entity with full sample data
3. **Runs tests** - Validates everything works
4. **Shows getting started guide** - Provides next steps

## Examples

```bash
# Interactive mode (prompts for entity name)
/new-dev-setup

# With entity name
/new-dev-setup "Training Company"

# Results in:
# - Entity created with subdomain: training-company
# - Admin user: admin@training-company.test / password123
# - 10 contacts, campaign, landing page, templates
# - All tests passing
# - Documentation current
```

## Behind the Scenes

Executes these skills in order:
1. `checking-application-health` - Validate environment
2. `preparing-development-environment` - Full setup with data
3. `running-tests` - Verify functionality
4. `explaining-features` - Show available features

## Implementation

```bash
#!/usr/bin/env bash
# Command: new-dev-setup
# Description: Complete development environment setup for new developers

ENTITY_NAME="${1:-}"

echo "🚀 New Developer Setup"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Step 1: Check health
echo "📋 Step 1/4: Checking application health..."
.claude/skills/checking-application-health/scripts/health-check.sh all

if [ $? -ne 0 ]; then
  echo "❌ Health check failed. Please fix issues and try again."
  exit 1
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Step 2: Prepare environment
echo "🏗️  Step 2/4: Preparing development environment..."
.claude/skills/preparing-development-environment/scripts/prepare-dev-env.sh "$ENTITY_NAME" false false

ENTITY_INFO=$(cat /tmp/new_entity_info.txt 2>/dev/null)

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Step 3: Run tests
echo "🧪 Step 3/4: Running test suite..."
.claude/skills/running-tests/scripts/run-tests.sh quick

if [ $? -ne 0 ]; then
  echo "⚠️  Some tests failed. Review output above."
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Step 4: Show getting started
echo "📚 Step 4/4: Getting Started Guide"
echo ""

cat << 'EOF'
🎉 Development Environment Ready!

Next Steps:
1. Open the application
   http://app.localhost:3000

2. Sign in with your test entity credentials
   (provided in Step 2 output above)

3. Try Scout AI
   Navigate to /scout and try:
   - "Create a landing page for our new product"
   - "Create an email campaign for summer sale"
   - "Show me all my contacts"

4. Explore the codebase
   Key files to review:
   - CLAUDE.md - Project architecture and patterns
   - app/services/tools/ - Scout AI tools
   - app/workflow_templates/ - V2 workflows
   - test/ - Test suite

5. Development workflow
   - Start feature: Use starting-features skill
   - Run tests: Use running-tests skill
   - Before commit: Use finishing-feature-work skill

6. Useful commands
   docker-compose logs -f web       # Watch logs
   docker-compose run --rm web rails console  # Rails console
   docker-compose run --rm web rails test     # Run tests

7. Resources
   - .claude/docs/ - Claude Code documentation
   - .claude/skills/ - Available skills
   - docs/ - Project documentation

Need help? Check:
- .claude/docs/skills-usage-guide.md
- CLAUDE.md for patterns and conventions

Happy coding! 🚀
EOF

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
