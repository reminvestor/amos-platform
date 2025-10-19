# Adding Entities Manually

Create test entities with sample data for development.

## Description

This skill quickly sets up test entities (tenants) with admin users and optional sample data. It's designed for development and testing, creating entities with contacts, campaigns, landing pages, and other resources. The skill handles subdomain generation, user creation with credentials, and provides access URLs.

**Use this skill when:**
- Setting up new development environment
- Creating test data for feature development
- Preparing entities for workflow testing
- Demonstrating the application with sample data

## Instructions

### Entity Creation Process

The skill follows these steps:

1. **Gather Entity Details**
   - Entity name (prompts if not provided)
   - Data level: `minimal`, `full`, or `none`
   - Optional custom subdomain

2. **Create Entity**
   - Generates subdomain from name
   - Creates entity record with settings
   - Returns entity ID for subsequent steps

3. **Create Admin User**
   - Email: `admin@{subdomain}.test`
   - Password: `password123`
   - First name: Admin, Last name: User

4. **Add Sample Data** (if requested)
   - Minimal: 3 contacts, 1 group, 1 email template
   - Full: Above + 7 more contacts, campaign, landing page, business profile

### Data Levels

**none** - Entity and admin user only
- Empty entity ready for manual data entry
- Fastest setup

**minimal** (default) - Basic sample data
- 3 test contacts
- 1 contact group
- 1 email template
- Good for basic workflow testing

**full** - Complete sample dataset
- 10 total contacts (with Faker names)
- Product launch campaign (draft status)
- Landing page with sample content
- Business profile settings
- Ideal for comprehensive testing

### Usage Patterns

**Interactive Mode:**
```
Use adding-entities-manually
```
Prompts for entity name and uses minimal data.

**Named Entity:**
```
Use adding-entities-manually with name='Acme Corp'
```

**With Full Data:**
```
Use adding-entities-manually with name='Acme Corp' with_data=full
```

**No Sample Data:**
```
Use adding-entities-manually with name='Acme Corp' with_data=none
```

**Custom Subdomain:**
```
Use adding-entities-manually with name='Acme Corp' domain=acme
```

### Parameters

- `name` - Entity name (optional, prompts if not provided)
- `with_data` - Sample data level: `minimal`, `full`, or `none` (default: `minimal`)
- `domain` - Custom subdomain (optional, auto-generated from name if not provided)

### Access Information

After creation, the skill provides:
- Entity ID and subdomain
- Admin credentials (email and password)
- Access URLs for main app and Scout AI
- Data summary (counts of users, contacts, campaigns, etc.)

## Examples

### Quick Setup with Defaults

```
Use adding-entities-manually
```

Prompts for name, creates entity with minimal sample data, shows access info.

### Full-Featured Entity

```
Use adding-entities-manually with name='Tech Startup' with_data=full
```

Creates entity with:
- Name: Tech Startup
- Subdomain: tech-startup
- Admin: admin@tech-startup.test / password123
- 10 contacts, campaign, landing page, business profile

Access at: `http://tech-startup.localhost:3000`

### Empty Entity for Custom Setup

```
Use adding-entities-manually with name='Custom Corp' with_data=none
```

Creates entity and admin user only, no sample data. Ready for manual configuration.

### Next Steps After Creation

The skill suggests:
- Start app: `docker-dev start`
- Sign in with provided credentials
- Test Scout AI workflows
- Use `testing-tools` skill to verify tools

## Resources

- [Add Entity Script](scripts/add-entity.sh) - Main entity creation script
- [Sample Data Reference](resources/sample-data-reference.md) - Details on generated data
