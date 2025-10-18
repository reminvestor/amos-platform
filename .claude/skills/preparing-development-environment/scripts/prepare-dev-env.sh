#!/usr/bin/env bash
# Complete development environment setup

set -e

ENTITY_NAME="$1"
SKIP_ENTITY="${2:-false}"
SKIP_DOCS="${3:-false}"

echo "🚀 Development Environment Setup"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Step 1: Health Check
echo "📋 Step 1/5: Health Check"
echo ""

if ! docker ps >/dev/null 2>&1; then
  echo "❌ Docker is not running"
  echo "   Please start Docker and try again"
  exit 1
fi

if ! docker-compose ps | grep -q "Up"; then
  echo "⚠️  Application containers not running"
  echo "   Starting containers..."
  docker-compose up -d
  echo "   Waiting for containers to be ready..."
  sleep 5
fi

echo "✅ Docker containers running"

# Check database connectivity
if ! docker-compose run --rm web rails runner "ActiveRecord::Base.connection.execute('SELECT 1')" >/dev/null 2>&1; then
  echo "❌ Database connection failed"
  echo "   Run: docker-compose run --rm web rails db:create"
  exit 1
fi

echo "✅ Database connectivity verified"
echo ""

# Step 2: Database Setup
echo "📊 Step 2/5: Database Setup"
echo ""

echo "Running migrations..."
docker-compose run --rm web rails db:migrate 2>/dev/null

echo "✅ Database migrations complete"
echo ""

# Step 3: Create Test Entity (optional)
ENTITY_ID=""
SUBDOMAIN=""

if [ "$SKIP_ENTITY" != "true" ]; then
  echo "🏢 Step 3/5: Test Entity Creation"
  echo ""

  if [ -z "$ENTITY_NAME" ]; then
    read -p "Enter entity name (or press Enter to skip): " ENTITY_NAME
  fi

  if [ -n "$ENTITY_NAME" ]; then
    echo "Creating entity: $ENTITY_NAME"
    echo ""

    # Create entity with full sample data
    RESULT=$(docker-compose run --rm web rails runner "
      entity = Entity.create!(
        name: '$ENTITY_NAME',
        subdomain: '$ENTITY_NAME'.parameterize,
        settings: {}
      )

      puts \"ENTITY_ID=#{entity.id}\"
      puts \"SUBDOMAIN=#{entity.subdomain}\"

      # Create admin user
      user = User.create!(
        entity: entity,
        email: 'admin@#{entity.subdomain}.test',
        password: 'password123',
        password_confirmation: 'password123',
        first_name: 'Admin',
        last_name: 'User'
      )

      # Create contacts
      10.times do |i|
        Contact.create!(
          entity: entity,
          email: \"contact#{i+1}@example.com\",
          first_name: \"Test\",
          last_name: \"Contact #{i+1}\"
        )
      end

      # Create contact group
      ContactGroup.create!(
        entity: entity,
        name: 'All Contacts'
      )

      # Create email template
      EmailTemplate.create!(
        entity: entity,
        name: 'Welcome Email',
        subject: 'Welcome to {{company_name}}',
        body: 'Hello {{first_name}}, welcome!'
      )

      # Create campaign
      Campaign.create!(
        entity: entity,
        name: 'Product Launch',
        status: 'draft',
        email_template: entity.email_templates.first
      )

      # Create landing page
      LandingPage.create!(
        entity: entity,
        name: 'Homepage',
        slug: 'home',
        content: {
          headline: 'Welcome to Our Platform',
          subheadline: 'The best solution for your needs',
          sections: []
        }
      )

      # Update business profile
      entity.update!(
        settings: {
          business_profile: {
            industry: 'Technology',
            description: 'A test company for development',
            website: 'https://example.com'
          }
        }
      )

      puts \"Created entity with full sample data\"
    " 2>/dev/null)

    ENTITY_ID=$(echo "$RESULT" | grep "ENTITY_ID=" | cut -d'=' -f2)
    SUBDOMAIN=$(echo "$RESULT" | grep "SUBDOMAIN=" | cut -d'=' -f2)

    echo "✅ Entity created: $ENTITY_NAME (ID: $ENTITY_ID)"
    echo ""
  else
    echo "⏭️  Skipping entity creation"
    echo ""
  fi
else
  echo "⏭️  Step 3/5: Skipping entity creation (skip_entity=true)"
  echo ""
fi

# Step 4: Update Documentation (optional)
if [ "$SKIP_DOCS" != "true" ]; then
  echo "📚 Step 4/5: Documentation Update"
  echo ""

  # Generate tools documentation
  echo "Updating tools reference..."
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

## Adding New Tools

1. Create file in \`app/services/tools/your_tool_tool.rb\`
2. Extend \`BaseTool\` class
3. Define \`self.definition\` method
4. Implement \`execute(args)\` method
5. ToolCatalog auto-discovers - no registration needed
EOF

  echo "✅ Documentation updated"
  echo ""
else
  echo "⏭️  Step 4/5: Skipping documentation update (skip_docs=true)"
  echo ""
fi

# Step 5: Summary
echo "✅ Step 5/5: Summary"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🎉 Development Environment Ready!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

if [ -n "$SUBDOMAIN" ]; then
  echo "🏢 Test Entity:"
  echo "   Name: $ENTITY_NAME"
  echo "   ID: $ENTITY_ID"
  echo "   Subdomain: $SUBDOMAIN"
  echo ""
  echo "👤 Admin User:"
  echo "   Email: admin@${SUBDOMAIN}.test"
  echo "   Password: password123"
  echo ""
  echo "🌐 Access URLs:"
  echo "   Main App: http://${SUBDOMAIN}.localhost:3000"
  echo "   Scout AI: http://${SUBDOMAIN}.localhost:3000/scout"
  echo ""

  # Show data summary
  docker-compose run --rm web rails runner "
    entity = Entity.find($ENTITY_ID)

    puts '📦 Sample Data:'
    puts \"   Users: #{entity.users.count}\"
    puts \"   Contacts: #{entity.contacts.count}\"
    puts \"   Contact Groups: #{entity.contact_groups.count}\"
    puts \"   Email Templates: #{entity.email_templates.count}\"
    puts \"   Campaigns: #{entity.campaigns.count}\"
    puts \"   Landing Pages: #{entity.landing_pages.count}\"
  " 2>/dev/null

  echo ""
fi

echo "📝 Next Steps:"
echo "   1. Visit http://${SUBDOMAIN:-app}.localhost:3000"

if [ -n "$SUBDOMAIN" ]; then
  echo "   2. Sign in with admin@${SUBDOMAIN}.test / password123"
  echo "   3. Go to Scout AI chat"
  echo "   4. Try: \"Create a landing page for our new product\""
fi

echo ""
echo "🔧 Useful Commands:"
echo "   - Test workflows: Use testing-workflows"
echo "   - Test tools: Use testing-tools"
echo "   - View logs: docker-compose logs -f web"
echo "   - Rails console: docker-compose run --rm web rails console"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
