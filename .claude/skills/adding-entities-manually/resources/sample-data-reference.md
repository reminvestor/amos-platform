# Sample Data Reference

Reference for sample data created with entities.

## Data Levels

### None
- **Entity only**
- **Admin user only**
- No additional data

**Use when:**
- Manual data entry needed
- Testing specific scenarios
- Minimal setup required

### Minimal (Default)
Creates basic sample data for testing:

**Contacts:** 3 test contacts
```ruby
contact1@example.com - Test Contact 1
contact2@example.com - Test Contact 2
contact3@example.com - Test Contact 3
```

**Contact Groups:** 1 group
```ruby
"Test Group" - Empty group ready for contacts
```

**Email Templates:** 1 welcome template
```ruby
Name: "Welcome Email"
Subject: "Welcome to {{company_name}}"
Body: "Hello {{first_name}}, welcome!"
```

**Use when:**
- Basic workflow testing
- Simple feature development
- Quick entity setup

### Full
Creates comprehensive sample data:

**Contacts:** 10 total (3 + 7 additional)
```ruby
contact1-3@example.com - Basic test contacts
user1-7@example.com - Faker-generated names
```

**Contact Groups:** 1 group
```ruby
"All Contacts" - For organizing contacts
```

**Email Templates:** 1 template
```ruby
"Welcome Email" - Same as minimal
```

**Campaigns:** 1 draft campaign
```ruby
Name: "Product Launch Campaign"
Status: draft
Email Template: Welcome Email
```

**Landing Pages:** 1 sample page
```ruby
Name: "Product Landing Page"
Slug: product
Content:
  Headline: "Our Amazing Product"
  Subheadline: "The best solution for your needs"
  Sections: []
```

**Business Profile:** Configured settings
```ruby
Industry: Technology
Description: A test company for development
Website: https://example.com
```

**Use when:**
- Comprehensive testing
- Demonstrating features
- Training/onboarding
- Full workflow validation

## Data Structure

### Entity

```ruby
Entity.create!(
  name: "Entity Name",
  subdomain: "entity-name",  # Parameterized from name
  settings: {}
)
```

**Fields:**
- `name` - Display name
- `subdomain` - URL identifier (lowercase, hyphenated)
- `settings` - JSONB field for configuration

### Admin User

```ruby
User.create!(
  entity: entity,
  email: "admin@{subdomain}.test",
  password: "password123",
  password_confirmation: "password123",
  first_name: "Admin",
  last_name: "User"
)
```

**Credentials:**
- Email: `admin@{subdomain}.test`
- Password: `password123` (consistent across all test entities)

### Contacts

**Minimal:**
```ruby
{
  email: "contact#{i}@example.com",
  first_name: "Test",
  last_name: "Contact #{i}"
}
```

**Full (additional):**
```ruby
{
  email: "user#{i}@example.com",
  first_name: Faker::Name.first_name,  # Random
  last_name: Faker::Name.last_name      # Random
}
```

### Contact Groups

```ruby
ContactGroup.create!(
  entity: entity,
  name: "Test Group"  # or "All Contacts" for full
)
```

### Email Templates

```ruby
EmailTemplate.create!(
  entity: entity,
  name: "Welcome Email",
  subject: "Welcome to {{company_name}}",
  body: "Hello {{first_name}}, welcome!"
)
```

**Template Variables:**
- `{{company_name}}` - Entity name
- `{{first_name}}` - Contact first name
- `{{last_name}}` - Contact last name

### Campaigns (Full Only)

```ruby
Campaign.create!(
  entity: entity,
  name: "Product Launch Campaign",
  status: "draft",
  email_template: entity.email_templates.first
)
```

**Status Values:**
- `draft` - Not yet sent
- `active` - Currently sending
- `paused` - Temporarily stopped
- `completed` - Finished sending

### Landing Pages (Full Only)

```ruby
LandingPage.create!(
  entity: entity,
  name: "Product Landing Page",
  slug: "product",
  content: {
    headline: "Our Amazing Product",
    subheadline: "The best solution for your needs",
    sections: []
  }
)
```

**Content Structure:**
- `headline` - Main heading text
- `subheadline` - Secondary heading
- `sections` - Array of content sections (empty by default)

**URL:** `http://{subdomain}.localhost:3000/pages/product`

### Business Profile (Full Only)

```ruby
entity.update!(
  settings: {
    business_profile: {
      industry: "Technology",
      description: "A test company for development",
      website: "https://example.com"
    }
  }
)
```

## Access Information

After entity creation:

**Main Application:**
```
URL: http://{subdomain}.localhost:3000
```

**Scout AI Chat:**
```
URL: http://{subdomain}.localhost:3000/scout
```

**Admin Login:**
```
Email: admin@{subdomain}.test
Password: password123
```

## Data Summary Output

After creation, the script shows:

```
Data Summary:
  Users: 1
  Contacts: 3 (or 10)
  Contact Groups: 1
  Email Templates: 1
  Campaigns: 0 (or 1)
  Landing Pages: 0 (or 1)
```

## Customization

### Adding More Contacts

```ruby
10.times do |i|
  Contact.create!(
    entity: entity,
    email: "contact#{i}@example.com",
    first_name: Faker::Name.first_name,
    last_name: Faker::Name.last_name,
    # Optional fields:
    phone: Faker::PhoneNumber.phone_number,
    company: Faker::Company.name,
    tags: ['customer', 'vip']
  )
end
```

### Adding Email Templates

```ruby
[
  {
    name: 'Welcome Email',
    subject: 'Welcome to {{company_name}}!',
    body: 'Hello {{first_name}}, thanks for joining us!'
  },
  {
    name: 'Newsletter',
    subject: 'Monthly Newsletter - {{month}}',
    body: 'Check out what\'s new this month...'
  },
  {
    name: 'Promotion',
    subject: 'Special Offer: {{discount}}% Off!',
    body: 'Hi {{first_name}}, we have a special deal for you...'
  }
].each do |template_data|
  EmailTemplate.create!(entity: entity, **template_data)
end
```

### Adding Campaigns

```ruby
['New Product Launch', 'Monthly Newsletter', 'Customer Survey'].each do |campaign_name|
  Campaign.create!(
    entity: entity,
    name: campaign_name,
    status: 'draft',
    email_template: entity.email_templates.sample
  )
end
```

### Adding Landing Pages

```ruby
[
  { name: 'Homepage', slug: 'home', headline: 'Welcome to Our Platform' },
  { name: 'Pricing', slug: 'pricing', headline: 'Choose Your Plan' },
  { name: 'Contact', slug: 'contact', headline: 'Get in Touch' }
].each do |page_data|
  LandingPage.create!(
    entity: entity,
    content: {
      headline: page_data[:headline],
      subheadline: 'Learn more about our services',
      sections: []
    },
    **page_data
  )
end
```

## Testing with Sample Data

### Scout AI Workflows

With full sample data, you can test:

```
# Campaign workflows
"Send my Product Launch campaign to all contacts"

# Landing page workflows
"Update the Product Landing Page headline"

# Contact workflows
"Show me all my contacts"

# Template workflows
"Create a new email template for promotions"
```

### Feature Development

Sample data provides:
- Existing records to query
- Associations to test
- Entity-scoped data
- Realistic content for UI

### Demo/Presentation

Full sample data creates a realistic environment:
- Multiple contacts with names
- Draft campaign ready to send
- Landing page to showcase
- Business profile populated

## Cleanup

To remove test entity and all associated data:

```ruby
entity = Entity.find_by(name: 'Test Entity')
entity.destroy  # Cascades to all associated records if dependent: :destroy
```

Or via SQL:

```sql
DELETE FROM entities WHERE name = 'Test Entity';
-- All associated records deleted via foreign key constraints
```

## Resources

- [Entity Model](../../../app/models/entity.rb)
- [Contact Model](../../../app/models/contact.rb)
- [Campaign Model](../../../app/models/campaign.rb)
- [Faker Gem](https://github.com/faker-ruby/faker) for random data generation
