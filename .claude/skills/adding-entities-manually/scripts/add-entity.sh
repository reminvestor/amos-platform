#!/usr/bin/env bash
# Create test entity with sample data

set -e

ENTITY_NAME="$1"
WITH_DATA="${2:-minimal}"
DOMAIN="$3"

echo "📝 Create New Entity"
echo ""

# Prompt for name if not provided
if [ -z "$ENTITY_NAME" ]; then
  read -p "Entity name: " ENTITY_NAME
fi

if [ -z "$ENTITY_NAME" ]; then
  echo "❌ Entity name is required"
  exit 1
fi

echo "Creating entity: $ENTITY_NAME"
echo "Sample data: $WITH_DATA"
echo ""

# Create entity
echo "🏢 Creating entity: $ENTITY_NAME"
echo ""

RESULT=$(docker-compose run --rm web rails runner "
  entity = Entity.create!(
    name: '$ENTITY_NAME',
    subdomain: '$ENTITY_NAME'.parameterize,
    settings: {}
  )

  puts \"ENTITY_ID=#{entity.id}\"
  puts \"SUBDOMAIN=#{entity.subdomain}\"
  puts \"Entity created: #{entity.name} (ID: #{entity.id})\"
" 2>/dev/null)

echo "$RESULT"
echo ""

ENTITY_ID=$(echo "$RESULT" | grep "ENTITY_ID=" | cut -d'=' -f2)
SUBDOMAIN=$(echo "$RESULT" | grep "SUBDOMAIN=" | cut -d'=' -f2)

# Create admin user
echo "👤 Creating admin user..."
echo ""

docker-compose run --rm web rails runner "
  entity = Entity.find($ENTITY_ID)

  user = User.create!(
    entity: entity,
    email: 'admin@#{entity.subdomain}.test',
    password: 'password123',
    password_confirmation: 'password123',
    first_name: 'Admin',
    last_name: 'User'
  )

  puts \"User created: #{user.email}\"
  puts \"Password: password123\"
" 2>/dev/null

echo ""

# Add minimal sample data
if [ "$WITH_DATA" = "minimal" ] || [ "$WITH_DATA" = "full" ]; then
  echo "📦 Adding minimal sample data..."
  echo ""

  docker-compose run --rm web rails runner "
    entity = Entity.find($ENTITY_ID)
    user = entity.users.first

    # Create a few contacts
    3.times do |i|
      Contact.create!(
        entity: entity,
        email: \"contact#{i+1}@example.com\",
        first_name: \"Test\",
        last_name: \"Contact #{i+1}\"
      )
    end
    puts \"Created 3 contacts\"

    # Create a contact group
    group = ContactGroup.create!(
      entity: entity,
      name: 'Test Group'
    )
    puts \"Created contact group: #{group.name}\"

    # Create an email template
    template = EmailTemplate.create!(
      entity: entity,
      name: 'Welcome Email',
      subject: 'Welcome to {{company_name}}',
      body: 'Hello {{first_name}}, welcome!'
    )
    puts \"Created email template: #{template.name}\"
  " 2>/dev/null

  echo ""
fi

# Add full sample data
if [ "$WITH_DATA" = "full" ]; then
  echo "📦 Adding full sample data..."
  echo ""

  docker-compose run --rm web rails runner "
    entity = Entity.find($ENTITY_ID)
    user = entity.users.first

    # More contacts
    7.times do |i|
      Contact.create!(
        entity: entity,
        email: \"user#{i+1}@example.com\",
        first_name: Faker::Name.first_name,
        last_name: Faker::Name.last_name
      )
    end
    puts \"Created 7 additional contacts\"

    # Campaign
    campaign = Campaign.create!(
      entity: entity,
      name: 'Product Launch Campaign',
      status: 'draft',
      email_template: entity.email_templates.first
    )
    puts \"Created campaign: #{campaign.name}\"

    # Landing page
    landing_page = LandingPage.create!(
      entity: entity,
      name: 'Product Landing Page',
      slug: 'product',
      content: {
        headline: 'Our Amazing Product',
        subheadline: 'The best solution for your needs',
        sections: []
      }
    )
    puts \"Created landing page: #{landing_page.name}\"

    # Business profile
    entity.update!(
      settings: {
        business_profile: {
          industry: 'Technology',
          description: 'A test company for development',
          website: 'https://example.com'
        }
      }
    )
    puts \"Updated business profile\"
  " 2>/dev/null

  echo ""
fi

# Summary
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ Entity Created Successfully!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Entity Details:"
echo "  Name: $ENTITY_NAME"
echo "  ID: $ENTITY_ID"
echo "  Subdomain: $SUBDOMAIN"
echo ""
echo "Admin User:"
echo "  Email: admin@${SUBDOMAIN}.test"
echo "  Password: password123"
echo ""
echo "Access:"
echo "  URL: http://${SUBDOMAIN}.localhost:3000"
echo "  Scout AI: http://${SUBDOMAIN}.localhost:3000/scout"
echo ""

# Show data summary
docker-compose run --rm web rails runner "
  entity = Entity.find($ENTITY_ID)

  puts 'Data Summary:'
  puts \"  Users: #{entity.users.count}\"
  puts \"  Contacts: #{entity.contacts.count}\" if defined?(Contact)
  puts \"  Contact Groups: #{entity.contact_groups.count}\" if defined?(ContactGroup)
  puts \"  Email Templates: #{entity.email_templates.count}\" if defined?(EmailTemplate)
  puts \"  Campaigns: #{entity.campaigns.count}\" if defined?(Campaign)
  puts \"  Landing Pages: #{entity.landing_pages.count}\" if defined?(LandingPage)
" 2>/dev/null

echo ""
echo "Next Steps:"
echo "  - Start app: docker-dev start"
echo "  - Sign in with admin credentials above"
echo "  - Test Scout AI workflows"
echo "  - Test tools: Use testing-tools"
echo ""
