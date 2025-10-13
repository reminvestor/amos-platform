# Integration Tools - Complete Guide

## Overview

Your system now has **THREE tool ecosystems** that work together seamlessly:

### 1. Internal Data Tools
Work with **your database objects**:
- `get_data` - Read campaigns, contacts, templates, etc.
- `create_object` - Create internal objects
- `update_object` - Update internal objects

### 2. Integration Management Tools
Work with **external API integrations**:
- `invoke_operation` - Call external APIs
- `list_operations` - See available API operations
- `list_connections` - See connected integrations

### 3. Integration Builder Tools ⭐ NEW
**Build new integrations** from scratch:
- `generate_integration_scaffold` - Create integration structure
- `add_integration_endpoint` - Add API endpoints
- `test_integration_endpoint` - Test endpoints
- `query_rag_store` - Query API documentation
- `register_integration_operation` - Register operations manually

## How They Work Together

### Complete Integration Lifecycle

```
┌─────────────────────────────────────────────────────────────┐
│ PHASE 1: BUILD THE INTEGRATION                              │
└─────────────────────────────────────────────────────────────┘

User: "I want to integrate with Stripe"
  ↓
Integration Builder Workflow:
  1. Research API docs (web_search)
  2. Create RAG store (create_rag_store)
  3. Generate scaffold (generate_integration_scaffold)
     → Creates: Service class, Auth module, Error handler
     → Creates: Integration record, Connection record
  4. Generate test endpoint (add_integration_endpoint)
     → Generates: Ruby method in operations.rb
     → Registers: IntegrationOperation record ✨
  5. Test endpoint (test_integration_endpoint)
  
┌─────────────────────────────────────────────────────────────┐
│ PHASE 2: ADD MORE ENDPOINTS                                 │
└─────────────────────────────────────────────────────────────┘

User: "Add a create_subscription endpoint to Stripe"
  ↓
AI uses: add_integration_endpoint
  → Queries RAG store for endpoint details
  → Generates Ruby method
  → Automatically registers as IntegrationOperation ✨
  → Now visible to list_operations!

┌─────────────────────────────────────────────────────────────┐
│ PHASE 3: USE THE INTEGRATION                                │
└─────────────────────────────────────────────────────────────┘

User: "List all Stripe customers"
  ↓
AI uses: list_operations (to discover available operations)
  → Sees: get_customers, create_customer, create_subscription, etc.
  ↓
AI uses: invoke_operation
  → Calls the Stripe API via IntegrationApiService
  → Returns data, displays in canvas
```

## Key Innovation ✨

**`add_integration_endpoint` now AUTOMATICALLY registers operations!**

When you add an endpoint, it:
1. ✅ Generates Ruby code in service file
2. ✅ Registers IntegrationOperation record
3. ✅ Makes it available to `invoke_operation`
4. ✅ Makes it visible to `list_operations`

**This bridges the gap between code generation and the existing integration system!**

## Tool Reference

### Building Integrations

#### `generate_integration_scaffold`
Creates the initial integration structure.

```yaml
Args:
  app_name: "Stripe"
  slug: "stripe"
  auth_type: "bearer_token"  # oauth2, api_key, basic_auth
  base_url: "https://api.stripe.com"
  description: "Payment processing"
  
Creates:
  - Integration record (database)
  - Connection record (database)
  - Service class (code)
  - Auth module (code)
  - Error handler (code)
  - Operations file (code)
```

#### `add_integration_endpoint` ⭐
Adds a new endpoint to an existing integration.

```yaml
Args:
  integration_slug: "stripe"
  endpoint_name: "create_customer"
  http_method: "POST"
  endpoint_path: "/v1/customers"
  parameters:
    email: "string"
    name: "string"
  description: "Create a new customer"
  
Does:
  1. Generates Ruby method in operations.rb
  2. Registers IntegrationOperation (NEW!)
  3. Returns usage examples
  
Result:
  - Code: Ruby method created
  - Database: IntegrationOperation record created
  - Available: Now usable with invoke_operation
```

#### `test_integration_endpoint`
Tests an endpoint by calling it directly.

```yaml
Args:
  integration_slug: "stripe"
  endpoint_name: "create_customer"
  test_params:
    email: "test@example.com"
    name: "Test User"
    
Returns:
  - Response data
  - Response time
  - Status code
  - Troubleshooting tips if failed
```

#### `register_integration_operation`
Manually register an operation (usually auto-handled by add_integration_endpoint).

```yaml
Args:
  integration_slug: "stripe"
  operation_id: "create_customer"
  name: "Create Customer"
  http_method: "POST"
  path_template: "/v1/customers"
  request_schema: {...}
  
Use when:
  - You manually created an endpoint
  - You need to update operation metadata
  - You're migrating existing code
```

#### `query_rag_store`
Query the API documentation knowledge base.

```yaml
Args:
  app_name: "Stripe"
  query: "How do I create a subscription?"
  top_k: 5
  
Returns:
  - Relevant documentation snippets
  - Source URLs
  - Code examples
```

### Using Integrations

#### `list_operations`
See all available operations for an integration.

```yaml
Args:
  integration_slug: "stripe"
  # OR
  connection_id: 123
  
Returns:
  - All registered operations
  - HTTP methods, paths, schemas
  - Includes auto-generated endpoints! ✨
```

#### `invoke_operation`
Execute an integration operation.

```yaml
Args:
  connection_id: 123
  operation_id: "create_customer"  # or operation: "create_customer"
  parameters:
    email: "customer@example.com"
    name: "John Doe"
    
Does:
  1. Finds the IntegrationOperation record
  2. Loads the Connection and credentials
  3. Calls IntegrationApiService
  4. Executes the actual API call
  5. Returns formatted response
  
Works with:
  - Manually defined operations
  - Auto-generated operations ✨
```

#### `list_connections`
See all integration connections.

```yaml
Args: (none required)

Returns:
  - All connections for the user
  - Integration details
  - Connection status
```

## Example Workflows

### Example 1: Build Twilio Integration

```
User: "Build an integration with Twilio to send SMS"

AI Actions:
1. generate_integration_scaffold
   - Creates Twilio integration
   - Sets up bearer_token auth
   
2. add_integration_endpoint
   - endpoint_name: "send_sms"
   - http_method: "POST"
   - endpoint_path: "/2010-04-01/Accounts/{AccountSid}/Messages.json"
   - parameters: {To: "string", From: "string", Body: "string"}
   - ✨ Automatically registers as operation
   
3. test_integration_endpoint
   - Tests with sample data
   
Result: Twilio integration ready to use!

User can now: 
- "Send an SMS to +1234567890"
  → AI uses invoke_operation with send_sms operation
```

### Example 2: Extend Existing Integration

```
User: "Add a webhook endpoint to my Trello integration"

AI Actions:
1. add_integration_endpoint
   - integration_slug: "trello"
   - endpoint_name: "create_webhook"
   - http_method: "POST"
   - endpoint_path: "/1/webhooks"
   - parameters: {callbackURL: "string", idModel: "string"}
   - ✨ Auto-registers operation
   
Result: New endpoint added and registered!

User can now:
- "List all Trello operations"
  → list_operations shows create_webhook ✨
- "Create a webhook for board X"
  → invoke_operation with create_webhook operation
```

### Example 3: Use Generated Integration

```
User: "Get my Stripe customers"

AI Actions:
1. list_connections
   → Finds Stripe connection (id: 123)
   
2. list_operations (integration_slug: "stripe")
   → Sees: get_customers operation (auto-generated ✨)
   
3. invoke_operation
   - connection_id: 123
   - operation: "get_customers"
   - parameters: {limit: 10}
   → Calls Stripe API
   → Returns customer list
   → Displays in canvas
```

## Database Schema

### Integration
```ruby
- name: "Stripe"
- slug: "stripe"
- auth_type: :bearer_token
- api_base_url: "https://api.stripe.com"
- category: "payment"
```

### Connection
```ruby
- integration_id: 1
- entity_id: 1
- status: :connected
- Has many: integration_credentials
```

### IntegrationCredential
```ruby
- connection_id: 1
- credentials: {api_key: "sk_test_..."} # JSON
- auth_method: "bearer"
- status: :active
```

### IntegrationOperation ⭐
```ruby
- integration_id: 1
- operation_id: "create_customer"
- name: "Create Customer"
- http_method: "POST"
- path_template: "/v1/customers"
- request_schema: {...}
- response_schema: {...}
- metadata: {generated_by: "integration_builder"} ✨
```

## Code Structure

### Generated Files

```
app/services/integrations/stripe/
├── stripe_service.rb       # Main service
│   └── request(method, path, params, body)
│
├── stripe_auth.rb          # Authentication
│   └── headers() → auth headers
│
├── error_handler.rb        # Error handling
│   └── handle(error) → formatted error
│
└── operations.rb           # API endpoints
    ├── get_customers()     # ✨ Registered as operation
    ├── create_customer()   # ✨ Registered as operation
    └── create_charge()     # ✨ Registered as operation
```

### Using Generated Code

**Direct usage** (from Ruby code):
```ruby
integration = Integration.find_by(slug: 'stripe')
connection = current_entity.connections.find_by(integration: integration)
service = Integrations::Stripe::StripeService.new(connection)

result = service.create_customer(
  email: 'customer@example.com',
  name: 'John Doe'
)
```

**Via tools** (from AI):
```ruby
# AI can now use invoke_operation!
invoke_operation(
  connection_id: connection.id,
  operation: 'create_customer',
  parameters: {
    email: 'customer@example.com',
    name: 'John Doe'
  }
)
```

## Benefits of This Architecture

✅ **Unified System** - Generated code works with existing tools  
✅ **Discoverable** - All operations visible via list_operations  
✅ **Consistent** - Same interface for all integrations  
✅ **Flexible** - Can use code directly OR via invoke_operation  
✅ **Documented** - Operations have schemas and documentation  
✅ **Tested** - Test endpoints before registering  
✅ **Extensible** - Easy to add more endpoints  

## Migration Path

### For Existing Integrations

If you have existing integration code that isn't registered:

```ruby
# Option 1: Use register_integration_operation tool
register_integration_operation(
  integration_slug: "existing_integration",
  operation_id: "existing_endpoint",
  name: "Existing Endpoint",
  http_method: "GET",
  path_template: "/endpoint/path"
)

# Option 2: Run a migration script
Integration.where(is_custom: true).each do |integration|
  # Parse operations.rb file
  # Register each method as an operation
end
```

## Troubleshooting

### Operation not showing in list_operations?
- Check if IntegrationOperation record exists
- Use register_integration_operation manually
- Verify integration_id is correct

### invoke_operation can't find operation?
- Use list_operations to see available operations
- Check operation_id matches exactly
- Verify connection has active credentials

### Generated code not working?
- Use test_integration_endpoint first
- Check API credentials
- Review error messages
- Query RAG store for API details

---

**Your integration system is now complete and unified!** 🎉

All three tool ecosystems work together seamlessly:
- Build integrations with AI
- Register operations automatically
- Use them with existing tools

