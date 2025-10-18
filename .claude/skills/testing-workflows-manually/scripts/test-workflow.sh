#!/usr/bin/env bash
# Test AMOS workflow templates end-to-end

set -e

WORKFLOW="$1"
ENTITY_ID="$2"

echo "📋 AMOS Workflow Testing"
echo ""

# List workflows if none specified
if [ -z "$WORKFLOW" ]; then
  echo "Available workflow templates:"
  echo ""

  TEMPLATES=$(find app/workflow_templates -name "*_v2.yml" -type f)

  if [ -z "$TEMPLATES" ]; then
    echo "❌ No V2 workflow templates found"
    exit 1
  fi

  echo "$TEMPLATES" | while read template; do
    BASENAME=$(basename "$template" _v2.yml)
    echo "  - $BASENAME"
  done

  echo ""
  read -p "Which workflow would you like to test? " WORKFLOW
fi

# Validate template exists
TEMPLATE_FILE="app/workflow_templates/${WORKFLOW}_v2.yml"

if [ ! -f "$TEMPLATE_FILE" ]; then
  echo "❌ Workflow template not found: $TEMPLATE_FILE"
  exit 1
fi

echo "📖 Loading workflow: $WORKFLOW"
echo "   File: $TEMPLATE_FILE"
echo ""

# Display workflow details
echo "Workflow Details:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
cat "$TEMPLATE_FILE" | grep -E "^name:|^description:|^template_version:" | sed 's/^/  /'
echo ""

# Extract phases
echo "Phases:"
cat "$TEMPLATE_FILE" | grep -E "^  - name:" | sed 's/  - name:/  -/'
echo ""

# Verify entity
echo "🏢 Checking entities..."
echo ""

if [ -z "$ENTITY_ID" ]; then
  # Get first entity
  ENTITY_ID=$(docker-compose run --rm web rails runner "puts Entity.first&.id" 2>/dev/null | tail -1)

  if [ -z "$ENTITY_ID" ] || [ "$ENTITY_ID" = "nil" ]; then
    echo "❌ No entities found in database"
    echo ""
    echo "Create an entity first:"
    echo "  docker-compose run --rm web rails runner \"Entity.create!(name: 'Test Entity')\""
    exit 1
  fi
fi

# Verify entity exists
ENTITY_NAME=$(docker-compose run --rm web rails runner "puts Entity.find($ENTITY_ID).name" 2>/dev/null | tail -1)

if [ -z "$ENTITY_NAME" ]; then
  echo "❌ Entity not found: $ENTITY_ID"
  exit 1
fi

echo "✅ Testing with entity:"
echo "   ID: $ENTITY_ID"
echo "   Name: $ENTITY_NAME"
echo ""

# Get or create test user
echo "🔧 Preparing test environment..."
echo ""

USER_EMAIL=$(docker-compose run --rm web rails runner "
  entity = Entity.find($ENTITY_ID)
  user = entity.users.first || entity.users.create!(
    email: 'test@example.com',
    password: 'password123',
    password_confirmation: 'password123'
  )
  puts user.email
" 2>/dev/null | tail -1)

echo "✅ Test user: $USER_EMAIL"
echo ""

# Generate test prompts
echo "💬 Workflow Test Prompt"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "To test this workflow, you'll need to interact with Scout AI."
echo ""
echo "Example prompts to trigger this workflow:"
echo ""

# Generate sample prompts based on workflow name
case "$WORKFLOW" in
  *campaign*)
    echo "  - \"Create a new email campaign for my customers\""
    echo "  - \"I want to send a newsletter about our new product\""
    ;;
  *landing*)
    echo "  - \"Create a landing page for my product\""
    echo "  - \"Build a landing page with a contact form\""
    ;;
  *integration*)
    echo "  - \"Connect to Stripe\""
    echo "  - \"Set up an integration with HubSpot\""
    ;;
  *)
    echo "  - Check app/workflow_templates/${WORKFLOW}_v2.yml for keywords"
    ;;
esac

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Test mode selection
echo "🧪 Test Mode Options:"
echo ""
echo "  a) Start app and test manually in browser"
echo "  b) Run programmatic test via Rails console"
echo "  c) View workflow execution logs"
echo "  d) Skip testing (just show info)"
echo ""
read -p "Your choice (a/b/c/d): " TEST_MODE

case "$TEST_MODE" in
  a)
    echo ""
    echo "🚀 Starting application..."
    echo ""

    docker-compose up -d

    echo "✅ Application started!"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "📝 Test Instructions:"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "1. Open: http://app.localhost:3000"
    echo "2. Sign in with: $USER_EMAIL / password123"
    echo "3. Go to Scout chat interface"
    echo "4. Enter a prompt to trigger the workflow (see examples above)"
    echo "5. Observe workflow execution through phases"
    echo ""
    echo "View logs in real-time:"
    echo "  docker-compose logs -f web"
    echo ""
    ;;

  b)
    echo ""
    echo "🔬 Running programmatic workflow test..."
    echo ""

    docker-compose run --rm web rails runner "
      # Get user and entity
      entity = Entity.find($ENTITY_ID)
      user = entity.users.first

      puts \"Testing workflow: $WORKFLOW\"
      puts \"Entity: #{entity.name}\"
      puts \"User: #{user.email}\"
      puts \"\"

      # Create workflow execution
      execution = WorkflowExecution.create!(
        entity: entity,
        user: user,
        template_name: '$WORKFLOW',
        status: 'in_progress',
        metadata: {}
      )

      puts \"Created WorkflowExecution ##{execution.id}\"
      puts \"\"

      # Load workflow template
      template_path = Rails.root.join(\"app/workflow_templates/${WORKFLOW}_v2.yml\")
      template = YAML.load_file(template_path)

      puts \"Template loaded: #{template['name']}\"
      puts \"Phases: #{template['phases']&.map { |p| p['name'] }&.join(', ')}\"
      puts \"\"

      # Test workflow engine initialization
      begin
        engine = Agents::WorkflowEngine.new(
          user: user,
          entity: entity,
          workflow_execution: execution,
          template_name: '$WORKFLOW'
        )

        puts \"✅ Workflow engine initialized\"
        puts \"   Available phases: #{engine.instance_variable_get(:@template)['phases']&.size}\"
      rescue => e
        puts \"❌ Error initializing workflow: #{e.message}\"
        puts e.backtrace.first(5)
      end

      puts \"\"
      puts \"To run full workflow:\"
      puts \"  - Use Scout chat interface\"
      puts \"  - Or call: engine.execute_workflow(user_message: 'test message')\"
    "
    ;;

  c)
    echo ""
    echo "📊 Recent workflow executions for: $WORKFLOW"
    echo ""

    docker-compose run --rm web rails runner "
      executions = WorkflowExecution
        .where(template_name: '$WORKFLOW', entity_id: $ENTITY_ID)
        .order(created_at: :desc)
        .limit(10)

      if executions.empty?
        puts 'No executions found for this workflow'
      else
        executions.each do |exec|
          puts \"##{exec.id} - #{exec.status} - #{exec.created_at.strftime('%Y-%m-%d %H:%M')}\"
          puts \"  User: #{exec.user&.email}\"
          puts \"  Phases: #{exec.metadata&.dig('current_phase') || 'N/A'}\"
          puts \"\"
        end
      end
    "
    ;;

  d)
    echo ""
    echo "ℹ️  Info mode - no testing performed"
    ;;

  *)
    echo "Invalid choice"
    exit 1
    ;;
esac

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ Workflow test session complete"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Resources:"
echo "  - Workflow file: app/workflow_templates/${WORKFLOW}_v2.yml"
echo "  - Execution logs: WorkflowExecution table"
echo "  - Context data: WorkflowContext table"
echo ""
