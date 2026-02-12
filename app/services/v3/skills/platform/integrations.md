# Integrations

## Overview
Integrations connect external services (Stripe, HubSpot, Neon CRM, Mailgun, etc.) to the platform.

## How Integrations Work
1. Each Integration has a slug (e.g., "stripe", "hubspot")
2. Users create Connections (linking their credentials via the secure UI — NEVER through chat)
3. Connections have IntegrationActions (available operations)
4. AMOS executes actions through the platform_execute tool

## ⚠️ CRITICAL SECURITY RULE

**NEVER ask users for API keys, tokens, passwords, client secrets, or any credentials in chat.**

Credentials are entered ONLY through the Integrations canvas UI (integration_connect canvas).
- Do NOT ask the user to paste credentials in chat
- Do NOT claim the chat is "encrypted" or "secure" as justification
- Do NOT say "you can paste them here securely"
- If a user voluntarily pastes credentials, tell them to delete the message and use the Integrations panel instead

## Setting Up a NEW Integration (Step-by-Step Flow)

When a user asks to connect/set up/integrate with a service:

### Step 1: Research the API
Use web_search to find:
- Official API documentation URL
- Base URL (e.g., "https://api.neoncrm.com/v2")
- Authentication type (api_key, bearer_token, oauth2, basic_auth)
- A test endpoint to verify the connection (e.g., "/accounts", "/me", "/ping")
- Common useful endpoints/operations

### Step 2: Get user feedback (optional)
Ask the user if they have specific requirements, but do NOT ask for credentials.
Good: "I found the Neon CRM v2 API. It uses API key authentication. Shall I set it up with the standard endpoints?"
BAD: "Can you provide your API key?"

### Step 3: Build the integration shell
Use platform_create to create the integration with all the researched info:

**API Key example:**
```
platform_create(type: "integration", data: {
  name: "Neon CRM",
  base_url: "https://api.neoncrm.com/v2",
  documentation_url: "https://developer.neoncrm.com",
  auth_type: "api_key",
  category: "crm",
  description: "Nonprofit CRM for donor and membership management",
  test_endpoint: "/accounts",
  auth_placement: "header",
  auth_header_name: "Authorization",
  operations: [
    { name: "list_accounts", method: "GET", path: "/accounts", description: "List all accounts" },
    { name: "get_account", method: "GET", path: "/accounts/{id}", description: "Get account by ID" }
  ]
})
```

**Basic Auth example** (uses HTTP Basic — two fields shown in UI):
By default basic_auth creates "Username" and "Password" fields. For custom labels/placeholders, pass explicit auth_configs:
```
platform_create(type: "integration", data: {
  name: "Neon CRM v2",
  base_url: "https://api.neoncrm.com/v2",
  auth_type: "basic_auth",
  category: "crm",
  description: "Nonprofit CRM — uses HTTP Basic Auth with Org ID as username, API Key as password",
  test_endpoint: "/accounts",
  auth_configs: [
    { key: "organization_id", value: "{organization_id}", placement: "header" },
    { key: "api_key", value: "{api_key}", placement: "header" }
  ],
  operations: [
    { name: "list_accounts", method: "GET", path: "/accounts", description: "List all accounts" }
  ]
})
```
The UI will show "Organization Id" and "Api Key" input fields. Credentials are Base64-encoded into the Authorization header automatically.

### Step 4: Direct user to the canvas for credentials
After the integration is created, the Integrations canvas opens automatically.
Tell the user: "I've set up the [Name] integration! You can now enter your API credentials in the Integrations panel that just opened. Once connected, I can help you pull data and set up automations."

### Step 5: Test and use
Once connected, test with: platform_execute(action: "integration", integration: "slug", operation: "test_endpoint")

## Using Existing Integrations

### List connected integrations
Use the platform_query tool with type: "integrations"

### Execute an integration action
First check available actions:
platform_query(type: "integration_actions", integration: "stripe")

Then execute:
platform_execute(action: "integration", integration: "stripe", operation: "list_customers", inputs: { limit: 10 })

### Common Stripe actions
- `list_customers`: inputs: { limit: 10 }
- `create_customer`: inputs: { email: "...", name: "..." }
- `get_customer`: inputs: { customer_id: "cus_xxx" }
- `list_charges`: inputs: { limit: 10 }
- `create_charge`: inputs: { amount: 1000, currency: "usd", customer: "cus_xxx" }

### Common Mailgun actions
- `send_email`: inputs: { to: "...", subject: "...", text: "..." }
- `list_domains`: inputs: {}

## Important Notes
- Always use platform_query with type="integrations" first to check what's connected
- Integration credentials are securely stored and entered through the UI — AMOS never sees raw API keys
- Each entity has its own connections (multi-tenant isolation)
- If an integration isn't connected, guide the user to the Integrations canvas to enter credentials
- Auth types: api_key, bearer_token, basic_auth, oauth2, oauth2_custom, no_auth
- Auth placement: header (default), query_param, body
