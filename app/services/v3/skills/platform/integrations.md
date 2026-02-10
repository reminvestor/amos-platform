# Integrations

## Overview
Integrations connect external services (Stripe, HubSpot, Mailgun, etc.) to the platform.

## How Integrations Work
1. Each Integration has a slug (e.g., "stripe", "hubspot")
2. Users create Connections (linking their credentials)
3. Connections have IntegrationActions (available operations)
4. AMOS executes actions through the platform_execute tool

## Common Operations

### List connected integrations
Use the platform_query tool with type: "integrations"

### Execute an integration action
First check available actions using the discover tool with query: "stripe actions"

Then use the platform_execute tool with action: "integration", integration: "stripe", operation: "list_customers", inputs: { limit: 10 }

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
- Always use the discover tool or the platform_query tool with type="integrations" first to check what's connected
- Integration credentials are securely stored — AMOS never sees raw API keys
- Each entity has its own connections (multi-tenant isolation)
- If an integration isn't connected, guide the user to connect it in the Integrations Manager
