# Integration System Example

This document demonstrates how integrations work in our system - everything is data-driven, no hard-coding required!

## Example: Adding a Custom CRM Integration

Let's say a user wants to integrate their custom CRM system. Here's how they would do it:

### 1. Create the Integration (via UI or rake task)

```ruby
# This is what happens when a user fills out the custom integration form
integration = Integration.create!(
  name: "Acme CRM",
  slug: "acme_crm",
  category: "crm",
  description: "Our company's custom CRM system",
  auth_type: "api_key",
  api_base_url: "https://crm.acme.com/api/v2",
  allowed_hosts: ["crm.acme.com"],
  documentation_url: "https://docs.acme.com/api",
  is_active: true,
  is_verified: false,  # Custom integrations start unverified
  auth_config: {
    auth_method: "header",
    auth_field_name: "X-ACME-API-Key",
    test_endpoint: "/api/v2/users?limit=1",
    setup_instructions: "Get your API key from Settings > API Access in Acme CRM"
  }
)
```

### 2. Add Operations (via UI)

Users can add operations through the web interface:

```ruby
# List Contacts operation
integration.integration_operations.create!(
  operation_id: "acme_crm.list_contacts.v2",
  name: "List Contacts",
  description: "Get a list of contacts from Acme CRM",
  http_method: "GET",
  path_template: "/api/v2/contacts",
  pagination_strategy: "page",
  is_idempotent: true,
  requires_confirmation: false,
  max_limit: 100,
  request_schema: {
    type: "object",
    properties: {
      page: { type: "integer", default: 1 },
      per_page: { type: "integer", default: 20, maximum: 100 },
      search: { type: "string" },
      tags: { type: "array", items: { type: "string" } }
    }
  },
  response_schema: {
    type: "object",
    properties: {
      data: { type: "array" },
      page: { type: "integer" },
      total_pages: { type: "integer" }
    }
  }
)

# Create Contact operation
integration.integration_operations.create!(
  operation_id: "acme_crm.create_contact.v2",
  name: "Create Contact",
  description: "Create a new contact in Acme CRM",
  http_method: "POST",
  path_template: "/api/v2/contacts",
  is_idempotent: false,
  requires_confirmation: true,  # Requires dry-run confirmation
  request_schema: {
    type: "object",
    required: ["email", "name"],
    properties: {
      email: { type: "string", format: "email" },
      name: { type: "string" },
      phone: { type: "string" },
      company: { type: "string" },
      tags: { type: "array", items: { type: "string" } }
    }
  }
)
```

### 3. User Connects the Integration

```ruby
# User creates a connection with their credentials
connection = Connection.create!(
  entity: current_entity,
  integration: integration,
  name: "Acme CRM - Production",
  status: "connected",
  settings: {
    environment: "production"
  },
  rate_limit_tier: "standard",
  daily_write_budget: 1000
)

# User adds their credentials (encrypted)
credential = IntegrationCredential.create!(
  connection: connection,
  name: "Production API Key",
  auth_method: "header",
  auth_field_name: "X-ACME-API-Key",
  credentials: {
    api_key: "acme_1234567890abcdef"  # Automatically encrypted
  },
  status: "active"
)
```

### 4. Using the Integration with Scout AI

Now users can interact with their custom CRM through Scout:

**User:** "Show me my contacts from Acme CRM"

**Scout uses the `list_connections` tool:**
```json
{
  "tool": "list_connections",
  "args": {
    "category": "crm"
  }
}
```

**Response:**
```json
{
  "connections": [
    {
      "id": 123,
      "name": "Acme CRM - Production",
      "integration": {
        "name": "Acme CRM",
        "slug": "acme_crm"
      },
      "status": "connected"
    }
  ]
}
```

**Scout then uses `invoke_operation`:**
```json
{
  "tool": "invoke_operation",
  "args": {
    "connection_id": 123,
    "operation_id": "acme_crm.list_contacts.v2",
    "params": {
      "per_page": 20,
      "page": 1
    }
  }
}
```

### 5. The Magic: Everything is Data-Driven

The `IntegrationApiService` handles the request using only database information:

1. **Builds the URL:** Combines `api_base_url` + `path_template`
   - `https://crm.acme.com/api/v2` + `/api/v2/contacts`

2. **Adds Authentication:** Uses `auth_config` to build headers
   - Adds header: `X-ACME-API-Key: acme_1234567890abcdef`

3. **Validates Request:** Checks against `request_schema`
   - Ensures `per_page` doesn't exceed 100

4. **Executes with Policy:** Checks rate limits and permissions
   - Verifies within daily budget of 1000 writes

5. **Logs Everything:** Creates audit trail in `IntegrationLog`

## Key Points

1. **No Code Changes Required:** Everything needed for an integration is stored in the database
2. **User Empowerment:** Users can add their own custom APIs
3. **Policy Control:** Rate limits, budgets, and permissions all data-driven
4. **Schema Validation:** JSON Schema ensures data quality
5. **Full Audit Trail:** Every API call is logged

## Sharing Integrations

Users can export and share their custom integrations:

```bash
# Export an integration
rake integrations:export[acme_crm]

# Creates acme_crm_integration.json that others can import
rake integrations:import[acme_crm_integration.json]
```

This makes it easy for:
- Companies to share integrations internally
- Communities to share integrations for popular services
- Vendors to provide official integration definitions
