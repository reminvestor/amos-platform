# AI Integration Builder - Complete Guide

## Overview

The AI Integration Builder is an intelligent workflow template that guides users through creating custom integrations with external APIs. It uses a combination of web research, RAG (Retrieval Augmented Generation) knowledge storage, and iterative development to build fully functional integrations.

## Workflow Architecture

The integration builder follows a **9-phase workflow** that progressively builds understanding and generates code:

### Phase 1: Discover Target
**Goal**: Identify which application to integrate with

- Asks user conversationally for the app name
- Captures integration purpose and key features
- Validates and normalizes app name

### Phase 2: Research API
**Goal**: Search web for comprehensive API documentation

- Performs multiple web searches for API docs
- Searches for authentication guides, endpoints, examples
- Returns a **summary to the user** for feedback
- **STOPS and waits** - does not auto-proceed

**Key Behavior**: This phase intentionally pauses to get user feedback before proceeding.

### Phase 3: Gather Feedback
**Goal**: Collect user feedback and additional resources

- Asks for corrections/clarifications
- Accepts additional documentation links
- Accepts uploaded documentation files (PDFs, markdown, etc.)
- Flexible - users can provide as much or little as they want

### Phase 4: Build RAG Store
**Goal**: Create comprehensive knowledge base from all sources

- Combines initial search results
- Includes user-provided links
- Processes uploaded documentation
- Performs additional targeted searches
- Creates RAG store using `create_rag_store` tool
- Indexes all documentation for later querying

### Phase 5: Generate Scaffold
**Goal**: Create integration structure with auth and one test endpoint

- Queries RAG store for authentication details
- Uses `generate_integration_scaffold` to create:
  - Integration model record
  - Connection setup
  - Base service class
  - Authentication module (OAuth2, API Key, etc.)
  - Error handler
  - Operations file
- Generates one simple test endpoint
- Presents code to user with testing instructions

### Phase 6: Test Endpoint
**Goal**: Have user test the integration

- Asks user to test the endpoint
- Guides on providing credentials
- Collects test results and error messages
- Supportive troubleshooting assistance

### Phase 7: Fix Issues
**Goal**: Debug and resolve any problems

- Analyzes test results
- If successful, skips to next phase
- If issues found:
  - Queries RAG store for solutions
  - Identifies root cause
  - Generates fixed code
  - Asks user to test again
- Max 3 attempts with self-healing

### Phase 8: Build Endpoints
**Goal**: Complete the integration with all required endpoints

- Queries RAG store for available endpoints
- Based on user's requirements, identifies endpoints to build
- For each endpoint:
  - Queries RAG for endpoint details
  - Generates code
  - Tests automatically
  - Fixes issues
- Generates comprehensive documentation
- Provides usage guide

### Phase 9: Validation
**Goal**: Ensure integration is complete and documented

- Validates authentication is working
- Checks all endpoints are implemented
- Verifies error handling and rate limiting
- Confirms documentation exists
- Can trigger FixerAgent for final polish

## Tools Used

### 1. `web_search`
Searches the web for API documentation and information.

```yaml
Usage:
  query: "Stripe API documentation"
  num_results: 5
```

### 2. `create_rag_store`
Creates a RAG knowledge base from documentation.

```yaml
Usage:
  app_name: "Stripe"
  documentation: ["https://stripe.com/docs/api", ...]
  search_results: [...]
  user_uploads: [...]
```

### 3. `query_rag_store`
Queries the RAG store for specific information.

```yaml
Usage:
  query: "How does Stripe authentication work?"
  app_name: "Stripe"
  top_k: 5
```

### 4. `generate_integration_scaffold`
Generates the base integration structure.

```yaml
Usage:
  app_name: "Stripe"
  slug: "stripe"
  auth_type: "bearer_token"
  base_url: "https://api.stripe.com"
  description: "Payment processing integration"
```

### 5. `generate_integration_code`
Generates specific endpoint code.

```yaml
Usage:
  integration_slug: "stripe"
  code_type: "endpoint"
  endpoint_name: "create_customer"
  http_method: "POST"
  endpoint_path: "/v1/customers"
  parameters: { email: "string", name: "string" }
```

### 6. `test_integration_endpoint`
Tests an integration endpoint.

```yaml
Usage:
  integration_slug: "stripe"
  endpoint_name: "create_customer"
  test_params: { email: "test@example.com", name: "Test User" }
```

## Generated Code Structure

When the scaffold is generated, it creates this file structure:

```
app/services/integrations/[slug]/
  ├── [slug]_service.rb       # Main service class
  ├── [slug]_auth.rb          # Authentication module
  ├── error_handler.rb        # Error handling
  └── operations.rb           # API endpoint methods
```

### Example: Stripe Integration

```ruby
# app/services/integrations/stripe/stripe_service.rb
module Integrations
  module Stripe
    class StripeService
      def initialize(connection)
        @connection = connection
        @auth = StripeAuth.new(connection)
      end
      
      def base_url
        'https://api.stripe.com'
      end
      
      def request(method, path, params: {}, body: nil, headers: {})
        # Makes authenticated API request
      end
    end
  end
end

# app/services/integrations/stripe/stripe_auth.rb
module Integrations
  module Stripe
    class StripeAuth
      def headers
        {
          'Authorization' => "Bearer #{bearer_token}",
          'Content-Type' => 'application/json'
        }
      end
    end
  end
end

# app/services/integrations/stripe/operations.rb
module Integrations
  module Stripe
    module Operations
      def create_customer(email:, name:)
        request(:post, '/v1/customers', body: { email: email, name: name })
      end
      
      def get_customer(customer_id:)
        request(:get, "/v1/customers/#{customer_id}")
      end
    end
  end
end
```

## Database Models

### Integration
Stores integration definitions (already exists in system).

```ruby
# Fields:
- name: "Stripe"
- slug: "stripe"
- auth_type: :bearer_token
- api_base_url: "https://api.stripe.com"
- category: "payment"
- is_active: true
- is_custom: true
```

### Connection
Links entities to integrations with credentials.

```ruby
# Fields:
- integration_id
- entity_id
- name: "Stripe Connection"
- status: :connected / :disconnected / :limited / :failing
- metadata: { created_by: 'ai_integration_builder' }
```

### IntegrationCredential
Stores encrypted credentials for connections.

```ruby
# Fields:
- connection_id
- credentials: { api_key: "sk_test_...", ... } # JSON
- auth_method: "bearer" / "header" / "basic"
- status: :active / :expired / :revoked
- expires_at
```

### RagStore
Stores RAG knowledge base metadata.

```ruby
# Fields:
- app_name: "Stripe"
- pinecone_index: "amos-integrations-stripe"
- pinecone_namespace: "stripe_1234567890"
- chunk_count: 150
- status: "active" / "building" / "failed"
```

## How to Use

### For Users

1. **Start the workflow**: "I want to integrate with [App Name]"

2. **Review research**: AI presents API documentation summary
   - Provide feedback if needed
   - Upload additional docs if you have them
   - Share specific documentation links

3. **Test the scaffold**: AI generates basic integration
   - Add your API credentials
   - Test the single endpoint
   - Report results

4. **Iterate**: AI fixes issues and builds remaining endpoints
   - Test each endpoint as it's built
   - Provide feedback on functionality

5. **Complete**: Receive full integration with documentation

### For Developers

#### Accessing Generated Integrations

```ruby
# Find the integration
integration = Integration.find_by(slug: 'stripe')

# Get user's connection
connection = current_entity.connections.find_by(integration: integration)

# Initialize service
service = Integrations::Stripe::StripeService.new(connection)

# Use the integration
result = service.create_customer(
  email: 'customer@example.com',
  name: 'John Doe'
)

if result[:success]
  customer = result[:data]
  puts "Customer created: #{customer['id']}"
else
  puts "Error: #{result[:error]}"
end
```

#### Querying RAG Store

```ruby
# Find RAG store for an app
rag_store = RagStore.latest_for_app('stripe')

# Query for information
rag_service = RagStoreService.new
result = rag_service.query_rag_store(
  rag_store.id,
  "How do I create a subscription?",
  top_k: 5
)

result[:results].each do |doc|
  puts doc[:content]
  puts "Source: #{doc[:metadata][:url]}"
end
```

## Key Features

### 🧠 Intelligent Research
- Multi-source web searches
- Automatic documentation discovery
- User feedback incorporation
- Comprehensive knowledge base

### 🔧 Adaptive Code Generation
- Supports OAuth2, API Key, Bearer Token, Basic Auth
- Generates proper error handling
- Creates rate limiting logic
- Follows Ruby/Rails best practices

### 🧪 Iterative Testing
- Tests each endpoint before moving on
- Self-healing on failures
- Detailed troubleshooting guidance
- Maximum 3 fix attempts per issue

### 📚 RAG-Powered Development
- Stores all documentation in Pinecone
- Queries for specific information as needed
- Learns from API docs, examples, and guides
- Provides context-aware code generation

### 🔐 Security Built-In
- Credentials stored in IntegrationCredential model
- Encrypted at rest (Rails encryption)
- Separate from connection metadata
- Proper credential rotation support

## Advanced Configuration

### Custom Authentication

If the generated auth doesn't match the API exactly, you can customize:

```ruby
# Edit: app/services/integrations/[slug]/[slug]_auth.rb

def headers
  {
    'X-Custom-Api-Key' => api_key,
    'X-Custom-Secret' => api_secret,
    'Content-Type' => 'application/json'
  }
end
```

### Rate Limiting

Connections have built-in rate limiting:

```ruby
connection.rate_limit_tier = 'premium' # basic, standard, premium
connection.daily_write_budget = 1000
connection.save!
```

### Error Handling

Custom error handling in error_handler.rb:

```ruby
def self.handle(error)
  case error
  when RestClient::TooManyRequests
    # Custom retry logic
  when CustomApiError
    # Handle API-specific errors
  end
end
```

## Troubleshooting

### Issue: RAG Store Empty
**Cause**: Documentation not indexed properly
**Solution**: Re-run Phase 4 with additional sources

### Issue: Authentication Failing
**Cause**: Incorrect credential format or auth type
**Solution**: Query RAG store for auth details, regenerate auth module

### Issue: Endpoint Not Working
**Cause**: Wrong parameters or HTTP method
**Solution**: Use `query_rag_store` to find correct endpoint spec

### Issue: Connection Status = Failing
**Cause**: High error rate from API
**Solution**: Check integration logs, fix issues, run `connection.test_connection!`

## Future Enhancements

- [ ] Automatic webhook setup
- [ ] OAuth flow automation
- [ ] API versioning support
- [ ] Batch operation generation
- [ ] Pagination handling templates
- [ ] Automatic test suite generation
- [ ] Integration monitoring dashboard
- [ ] Automatic documentation site generation

## Contributing

To add enhancements to the integration builder:

1. Update workflow template: `app/workflow_templates/integration_builder_v2.yml`
2. Add new tools if needed: `app/services/tools/`
3. Extend services: `app/services/integration_*`
4. Update this documentation

## Support

For issues or questions:
- Check logs: `rails console` → `IntegrationLog.last(10)`
- Review RAG store: `RagStore.last.metadata`
- Test connection: `Connection.last.test_connection!`
- Check phase execution: Workflow execution logs

---

**Built with ❤️ using the V2 Phase-Based Workflow Architecture**

