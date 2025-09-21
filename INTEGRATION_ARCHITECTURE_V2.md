# Scout Integration Architecture V2

*Enhanced with security, reliability, and AI-specific features based on feedback*

## Core Improvements

### 1. Security Enhancements

#### 1.1 Connection Resource
Instead of directly storing credentials on integrations, introduce a `Connection` model:

```ruby
class Connection < ApplicationRecord
  belongs_to :entity
  belongs_to :integration
  has_many :integration_credentials
  has_many :integration_logs
  
  # Rate limiting and budget controls
  integer :daily_write_budget
  string :rate_limit_tier # basic, standard, premium
  
  # Access control
  jsonb :allowed_operations # whitelist specific operations
  jsonb :scopes_granted # OAuth scopes actually granted
  jsonb :scopes_requested # OAuth scopes we asked for
end
```

#### 1.2 Host Allowlists & Path Templates
Prevent SSRF and enforce API boundaries:

```ruby
class Integration < ApplicationRecord
  # Define allowed hosts (with wildcard support)
  jsonb :allowed_hosts # ["api.stripe.com", "*.googleapis.com"]
  
  def host_allowed?(url)
    uri = URI.parse(url)
    allowed_hosts.any? { |pattern| File.fnmatch(pattern, uri.host) }
  end
end
```

#### 1.3 Policy Engine
Gate every tool call through policy checks:

```ruby
class PolicyEngine
  def self.check(connection, operation, agent_role)
    rules = PolicyRule.active.for_entity(connection.entity)
    
    # Check operation whitelist
    return false unless connection.allowed_operations.include?(operation.id)
    
    # Check rate limits
    return false unless connection.within_rate_limit?
    
    # Check daily budget for writes
    if operation.write_operation?
      return false unless connection.within_daily_budget?
    end
    
    # Check time-based rules
    rules.each do |rule|
      return false unless rule.allows?(operation, agent_role)
    end
    
    true
  end
end
```

#### 1.4 Two-Phase Writes
Critical operations require explicit confirmation:

```ruby
# Phase 1: Dry run
result = dry_run_operation(
  connection_id: 123,
  operation_id: "stripe.create_invoice",
  body: {...}
)
# Returns: {token: "confirm_xyz", preview: {...}, expires_at: ...}

# Phase 2: Confirm
result = confirm_operation(token: "confirm_xyz")
```

#### 1.5 Data Redaction
Log bodies with sensitive data masked:

```ruby
class IntegrationLog < ApplicationRecord
  before_save :redact_sensitive_data
  
  private
  
  def redact_sensitive_data
    self.request_body = redact_fields(request_body, operation.sensitive_fields)
    self.response_body = redact_fields(response_body, operation.sensitive_response_fields)
  end
end
```

### 2. Reliability Improvements

#### 2.1 Typed Operations
Each operation has a full contract:

```ruby
class IntegrationOperation < ApplicationRecord
  belongs_to :integration
  
  # JSON Schema for request/response
  jsonb :request_schema
  jsonb :response_schema
  jsonb :error_schema
  
  # Versioning
  string :api_version
  datetime :deprecated_at
  string :migration_guide
  
  # Execution hints
  boolean :is_idempotent
  integer :max_retries
  integer :timeout_seconds
  string :pagination_strategy # cursor, page, offset
end
```

#### 2.2 Contract Validation
Validate all inputs/outputs:

```ruby
class ToolRunner
  def execute_operation(connection, operation, params)
    # Validate inputs
    errors = JSONSchemer.schema(operation.request_schema).validate(params)
    raise InvalidInput.new(errors) if errors.any?
    
    # Execute
    response = IntegrationAPIService.call(connection, operation, params)
    
    # Validate output
    if response.success?
      errors = JSONSchemer.schema(operation.response_schema).validate(response.body)
      raise InvalidResponse.new(errors) if errors.any?
    end
    
    response
  end
end
```

#### 2.3 Correlation IDs
Track requests across the system:

```ruby
class IntegrationAPIService
  def call(connection, operation, params)
    correlation_id = "op_#{SecureRandom.hex(8)}"
    
    # Add to headers
    headers['X-Correlation-ID'] = correlation_id
    headers['X-Scout-Request-ID'] = correlation_id
    
    # Log with correlation
    IntegrationLog.create!(
      connection: connection,
      operation: operation,
      correlation_id: correlation_id,
      scout_message_id: Current.scout_message_id
    )
  end
end
```

#### 2.4 Rate Limiting & Circuit Breakers
Respect API limits and fail fast:

```ruby
class RateLimiter
  def check_and_increment(connection, operation)
    key = "rate:#{connection.id}:#{operation.id}"
    
    # Check rate limit
    current = Redis.current.get(key).to_i
    limit = operation.rate_limit || connection.rate_limit
    
    if current >= limit
      raise RateLimitExceeded.new(
        retry_after: Redis.current.ttl(key)
      )
    end
    
    # Increment with expiry
    Redis.current.multi do |r|
      r.incr(key)
      r.expire(key, operation.rate_window || 3600)
    end
  end
end
```

#### 2.5 Idempotency & Retries
Handle failures gracefully:

```ruby
class IntegrationAPIService
  def call_with_retries(connection, operation, params)
    idempotency_key = params[:idempotency_key] || generate_key(params)
    
    # Check if already executed
    if operation.is_idempotent && previous = find_by_idempotency_key(idempotency_key)
      return previous.response
    end
    
    # Execute with retries
    retries = 0
    begin
      response = execute(connection, operation, params)
      store_idempotent_result(idempotency_key, response) if operation.is_idempotent
      response
    rescue RetryableError => e
      retries += 1
      if retries <= operation.max_retries
        sleep(backoff_time(retries))
        retry
      else
        raise
      end
    end
  end
end
```

### 3. Smarter AI Integration

#### 3.1 Multi-Agent Pattern
Separate concerns for better reasoning:

```yaml
agents:
  planner:
    role: "Understand user intent and plan approach"
    capabilities:
      - Decompose complex requests
      - Identify required integrations
      - Determine operation sequence
      
  executor:
    role: "Execute operations safely"
    capabilities:
      - Validate permissions
      - Run operations
      - Handle pagination
      - Manage transactions
      
  verifier:
    role: "Validate results and side effects"
    capabilities:
      - Check operation success
      - Verify data integrity
      - Detect anomalies
      - Suggest corrections
```

#### 3.2 Documentation RAG
Help AI understand APIs:

```ruby
class IntegrationDocumentationService
  def index_documentation(integration)
    # Parse OpenAPI/Swagger specs
    spec = fetch_openapi_spec(integration)
    
    # Extract and embed
    operations = spec['paths'].flat_map do |path, methods|
      methods.map do |method, details|
        {
          operation_id: "#{integration.slug}.#{details['operationId']}",
          description: details['description'],
          parameters: details['parameters'],
          examples: details['examples'],
          embedding: generate_embedding(details)
        }
      end
    end
    
    # Store in vector DB
    VectorStore.upsert(operations)
  end
end
```

#### 3.3 Bounded Tool Calls
Prevent infinite loops:

```ruby
class ScoutGenericToolsService
  MAX_TOOL_CALLS = 20
  MAX_DEPTH = 5
  
  def process_with_tools(message, depth = 0)
    return error_response("Max depth reached") if depth > MAX_DEPTH
    
    tool_calls = 0
    while response = get_ai_response(message)
      break unless response.has_tool_call?
      
      tool_calls += 1
      return error_response("Max tool calls reached") if tool_calls > MAX_TOOL_CALLS
      
      # Execute tool
      result = execute_tool(response.tool_call)
      
      # Add to context
      message.add_tool_result(result)
    end
    
    response
  end
end
```

#### 3.4 Policy-Aware AI
Integrate policies into prompts:

```ruby
class PolicyAwarePromptBuilder
  def build_system_prompt(user, context)
    policies = PolicyRule.active.for_entity(user.entity)
    
    <<~PROMPT
      You are Scout, an AI assistant with access to external integrations.
      
      Current policies:
      #{policies.map(&:description).join("\n")}
      
      Available connections:
      #{user.entity.connections.active.map(&:summary).join("\n")}
      
      IMPORTANT: Always verify operations are allowed before attempting them.
      Use dry_run for write operations and ask for confirmation.
    PROMPT
  end
end
```

### 4. Better Observability

#### 4.1 Per-Tenant Encryption
Encrypt sensitive logs per customer:

```ruby
class IntegrationLog < ApplicationRecord
  # Encrypt response bodies with per-entity key
  encrypts :response_body, key_provider: :entity_key_provider
  
  def entity_key_provider
    EntityKeyProvider.new(connection.entity)
  end
end
```

#### 4.2 Masked Logging
Show enough to debug without exposing PII:

```ruby
class MaskedLogger
  SENSITIVE_PATTERNS = {
    ssn: /\d{3}-\d{2}-\d{4}/,
    email: /[\w._%+-]+@[\w.-]+\.[A-Z]{2,}/i,
    api_key: /sk_[a-zA-Z0-9]{32}/
  }
  
  def log(level, message, data = {})
    masked_data = deep_mask(data)
    Rails.logger.send(level, message, masked_data)
  end
end
```

#### 4.3 Cost Tracking
Monitor API usage costs:

```ruby
class UsageTracker
  def track_operation(connection, operation, response)
    usage = IntegrationUsage.find_or_create_by(
      entity: connection.entity,
      integration: connection.integration,
      operation: operation,
      date: Date.current
    )
    
    usage.increment!(:call_count)
    usage.increment!(:token_count, response.headers['X-Tokens-Used'].to_i)
    usage.increment!(:estimated_cost_cents, calculate_cost(operation, response))
  end
end
```

#### 4.4 Correlation & Tracing
Full request lifecycle visibility:

```ruby
class TracingMiddleware
  def call(env)
    # Extract or generate trace ID
    trace_id = env['HTTP_X_TRACE_ID'] || SecureRandom.uuid
    
    # Set in thread context
    Current.trace_id = trace_id
    
    # Add to response
    status, headers, body = @app.call(env)
    headers['X-Trace-ID'] = trace_id
    
    [status, headers, body]
  end
end
```

### 5. Production Features

#### 5.1 Webhooks
First-class webhook support:

```ruby
class WebhookSubscription < ApplicationRecord
  belongs_to :connection
  belongs_to :integration_operation
  
  string :endpoint_url
  string :signing_secret
  jsonb :events # ["invoice.created", "invoice.paid"]
  jsonb :filters # {"customer_id": "cus_123"}
  
  enum status: [:active, :paused, :failed]
end

class WebhookProcessor
  def process(webhook_event)
    subscription = find_subscription(webhook_event)
    return unless subscription&.active?
    
    # Verify signature
    verify_signature!(webhook_event, subscription)
    
    # Create scout message for processing
    ScoutMessage.create!(
      role: 'webhook',
      content: "Webhook received: #{webhook_event.type}",
      metadata: {
        webhook_id: webhook_event.id,
        subscription_id: subscription.id,
        payload: webhook_event.data
      }
    )
  end
end
```

#### 5.2 Pagination Handling
Standardized pagination across providers:

```ruby
class PaginationHandler
  STRATEGIES = {
    cursor: CursorPagination,
    page: PagePagination,
    offset: OffsetPagination,
    token: TokenPagination,
    link_header: LinkHeaderPagination
  }
  
  def paginate(connection, operation, params)
    strategy = STRATEGIES[operation.pagination_strategy]
    results = []
    
    loop do
      response = execute_operation(connection, operation, params)
      results.concat(response.data)
      
      break unless next_params = strategy.next_page_params(response)
      params.merge!(next_params)
      
      # Respect rate limits
      sleep_if_needed(connection)
    end
    
    results
  end
end
```

#### 5.3 Caching Strategy
Reduce API calls for read-heavy workloads:

```ruby
class CachedIntegrationService
  def get_with_cache(connection, operation, params)
    return direct_call(connection, operation, params) unless operation.cacheable?
    
    cache_key = generate_cache_key(connection, operation, params)
    
    Rails.cache.fetch(cache_key, expires_in: operation.cache_ttl) do
      direct_call(connection, operation, params)
    end
  end
  
  private
  
  def generate_cache_key(connection, operation, params)
    [
      'integration',
      connection.id,
      operation.id,
      Digest::SHA256.hexdigest(params.to_json)
    ].join(':')
  end
end
```

#### 5.4 Backoff & Jitter
Handle rate limits gracefully:

```ruby
class BackoffStrategy
  def wait_time(attempt, base_delay = 1)
    # Exponential backoff with jitter
    max_delay = [base_delay * (2 ** attempt), 300].min
    jitter = rand(0..max_delay * 0.1)
    max_delay + jitter
  end
  
  def handle_rate_limit(response)
    # Respect Retry-After header
    if retry_after = response.headers['Retry-After']
      return retry_after.to_i
    end
    
    # Or use exponential backoff
    wait_time(1)
  end
end
```

### 6. Data Model Nits

#### 6.1 Standardized Fields
Common fields across integration models:

```ruby
module IntegrationConcerns
  extend ActiveSupport::Concern
  
  included do
    # Audit fields
    string :created_by_type # User, AdminUser, System
    integer :created_by_id
    string :correlation_id
    
    # Soft delete
    datetime :deleted_at
    
    # Metadata
    jsonb :metadata
    jsonb :tags
  end
end
```

#### 6.2 Connection States
More granular connection health:

```ruby
class Connection < ApplicationRecord
  enum status: {
    disconnected: 0,
    connected: 1,
    degraded: 2,     # Partial failures
    rate_limited: 3, # Temporary throttling
    suspended: 4,    # Admin action
    expired: 5       # Credentials expired
  }
  
  # Health tracking
  datetime :last_successful_call_at
  datetime :last_failed_call_at
  integer :consecutive_failures
  jsonb :last_error
end
```

### 7. Example Implementation

```ruby
# Integration definition
stripe = Integration.create!(
  name: "Stripe",
  slug: "stripe",
  auth_type: "bearer_token",
  api_base_url: "https://api.stripe.com",
  allowed_hosts: ["api.stripe.com"],
  documentation_url: "https://stripe.com/docs/api"
)

# Operation definition
stripe.operations.create!(
  operation_id: "stripe.create_invoice.v2020-08-27",
  name: "Create Invoice",
  http_method: "POST",
  path_template: "/v1/invoices",
  request_schema: {
    type: "object",
    required: ["customer"],
    properties: {
      customer: { type: "string" },
      auto_advance: { type: "boolean" }
    }
  },
  is_idempotent: true,
  requires_confirmation: true,
  rate_limit: 100,
  rate_window: 3600
)

# Policy rule
PolicyRule.create!(
  entity: current_user.entity,
  resource_type: "Operation",
  resource_id: "stripe.create_invoice.*",
  agent_role: marketing,
  action: read,
  conditions: {
    type: allow_list,
    operations: 
      - stripe.list_customers.*
      - stripe.get_customer.*
  },
  max_daily_calls: 1000,
  requires_confirmation: false
)

# Usage by LLM
User: "Get my recent Stripe customers"
Planner: Check available connections and operations
Executor: invoke_operation(
  connection_id: "conn_123",
  operation_id: "stripe.list_customers.v2020-08-27",
  params: {limit: 50, created: {gte: "2025-01-01"}}
)
Verifier: Validate response matches schema
```

## Dynamic Configuration Management

### Purpose
Allow runtime configuration of integrations without code changes, enabling flexibility and adaptability.

### Key Features

1. **Permission Model**:
   - Admin-only for verified global integrations
   - User-editable for custom integrations  
   - Full audit trail for all changes
   - Role-based access control

2. **Configurable Elements**:
   - API base URLs (environment switching)
   - Authentication settings (OAuth URLs, scopes, tokens)
   - Rate limit adjustments
   - Custom headers and parameters
   - Operation endpoints and paths
   - Request/response schemas
   - Pagination strategies

3. **LLM Tool**: `configure_integration`
   ```ruby
   {
     name: "configure_integration",
     description: "Update integration settings dynamically",
     params: {
       connection_id: "Connection to configure",
       updates: {
         api_base_url: "New base URL",
         auth_config: "OAuth settings",
         rate_limits: "Custom limits",
         custom_headers: "Additional headers"
       },
       operation_updates: [
         {
           operation_id: "Operation to update",
           path_template: "New endpoint path",
           request_schema: "Updated schema"
         }
       ]
     }
   }
   ```

4. **Real-World Use Cases**:
   - **Environment Switching**: Move between sandbox/production
   - **API Version Updates**: Handle vendor API upgrades
   - **Custom Authentication**: Add tenant-specific headers
   - **Rate Limit Tuning**: Adjust for account tiers
   - **Endpoint Fixes**: Handle API changes without deployment
   - **Schema Evolution**: Update as APIs evolve

5. **Safety Features**:
   - Automatic connection testing after changes
   - Configuration validation before save
   - Rollback capability with versioning
   - Host allowlist enforcement
   - Change impact analysis
   - Dry-run mode for testing

6. **Example Scenarios**:
   ```
   User: "My Stripe API is returning 404 errors for customer endpoints"
   Scout: "I'll check your Stripe configuration... I see the issue. 
          Stripe recently updated their API. Let me update the endpoint 
          from /v1/customers to /v2/customers and test it."
   
   User: "Switch my QuickBooks to production mode"
   Scout: "I'll update your QuickBooks connection from sandbox to production.
          This will change the base URL and I'll test the connection to 
          ensure everything works correctly."
   ```

7. **Implementation Details**:
   - Changes stored in Integration/Connection models
   - Configuration versioning in metadata
   - Automatic cache invalidation
   - Real-time connection health updates
   - Integration with PolicyEngine for permission checks

8. **Configuration Versioning**:
   ```ruby
   class ConfigurationVersion < ApplicationRecord
     belongs_to :integration
     belongs_to :changed_by, polymorphic: true
     
     jsonb :previous_config
     jsonb :new_config
     jsonb :changes_made
     string :change_reason
     
     # Rollback support
     def rollback!
       integration.update!(previous_config)
       create_rollback_version!
     end
   end
   ```

9. **Smart Configuration Suggestions**:
   ```ruby
   class ConfigurationAdvisor
     def suggest_fixes(connection, error)
       case error
       when /404.*endpoint/i
         suggest_endpoint_update(connection, error)
       when /401.*unauthorized/i
         suggest_auth_update(connection)
       when /429.*rate limit/i
         suggest_rate_limit_adjustment(connection)
       end
     end
   end
   ```

This dynamic configuration system makes Scout's integration platform truly adaptable, allowing both admins and users to handle API changes, environment switches, and custom requirements without code deployments!