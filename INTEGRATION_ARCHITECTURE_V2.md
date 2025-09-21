# Scout Integration Architecture V2
*Incorporating security, reliability, and governance improvements*

## Vision
Transform Scout from a marketing app into a comprehensive business operations cockpit where AI agents can **safely and reliably** interact with any external application through a typed, policy-controlled integration system.

## Core Principles (Updated)
1. **Bounded Flexibility**: Schema-agnostic doesn't mean unbounded - enforce contracts
2. **Policy-First**: Every API call goes through policy checks
3. **Two-Phase Writes**: Plan → Dry-run → Confirm for safety
4. **Typed Operations**: Move from freeform endpoints to versioned operations
5. **Trust but Verify**: LLMs propose, policies dispose

## Enhanced Data Models

### 1. Integration (App Catalog)
```ruby
class Integration < ApplicationRecord
  has_many :connections
  has_many :integration_operations
  has_many :integration_docs
  
  validates :name, :slug, presence: true, uniqueness: true
  
  # Fields:
  # - name: string (unique)
  # - slug: string (unique, indexed)
  # - category: string
  # - auth_type: enum [:api_key, :bearer_token, :basic_auth, :oauth2, :oauth2_custom]
  # - auth_config: jsonb
  # - api_base_url: string
  # - allowed_hosts: jsonb (array of allowed hostnames)
  # - documentation_url: string
  # - icon_url: string
  # - description: text
  # - is_active: boolean
  # - is_verified: boolean (has been security reviewed)
  # - metadata: jsonb (rate limits, version info)
  
  # Indexes:
  # - unique index on name
  # - unique index on slug
end
```

### 2. Connection (Per-Entity Install)
```ruby
class Connection < ApplicationRecord
  belongs_to :entity
  belongs_to :integration
  has_many :integration_credentials
  has_many :connection_operations
  has_many :integration_logs
  has_many :webhook_subscriptions
  
  # Fields:
  # - name: string (user-friendly)
  # - status: enum [:disconnected, :connected, :limited, :failing]
  # - settings: jsonb (account_id, region, environment)
  # - allowed_operations: jsonb (operation_ids this connection can use)
  # - rate_limit_tier: string
  # - daily_write_budget: integer
  # - scopes_granted: jsonb (actual OAuth scopes)
  # - scopes_requested: jsonb (what we asked for)
  # - last_health_check: datetime
  # - metadata: jsonb
  
  # Policy helpers
  def can_execute?(operation_id, agent_role)
    PolicyEngine.check(self, operation_id, agent_role)
  end
  
  def within_rate_limit?
    RateLimiter.check(self)
  end
end
```

### 3. IntegrationCredential (Secrets)
```ruby
class IntegrationCredential < ApplicationRecord
  belongs_to :connection
  
  encrypts :credentials # Envelope encryption with per-tenant key
  
  # Fields:
  # - name: string
  # - credentials: jsonb (encrypted)
  # - auth_method: string
  # - auth_field_name: string
  # - token_type: string (for OAuth)
  # - expires_at: datetime
  # - rotates_at: datetime
  # - rotated_at: datetime
  # - last_refresh_at: datetime
  # - last_refresh_error: text
  # - status: enum [:active, :expired, :revoked, :rotating]
  # - metadata: jsonb
  
  # Indexes:
  # - composite unique (connection_id, name)
end
```

### 4. IntegrationOperation (Typed Operations)
```ruby
class IntegrationOperation < ApplicationRecord
  belongs_to :integration
  
  # Fields:
  # - operation_id: string (e.g., "stripe.list_customers.v2020-08-27")
  # - name: string
  # - description: text
  # - http_method: string
  # - path_template: string (e.g., "/v1/customers/{id}")
  # - request_schema: jsonb (JSON Schema)
  # - response_schema: jsonb (JSON Schema)
  # - pagination_strategy: enum [:cursor, :page, :offset, :none]
  # - is_idempotent: boolean
  # - requires_confirmation: boolean
  # - max_limit: integer
  # - documentation: text
  # - examples: jsonb
  # - version: string
  # - deprecated_at: datetime
end
```

### 5. IntegrationLog (Enhanced Audit)
```ruby
class IntegrationLog < ApplicationRecord
  belongs_to :connection
  belongs_to :user
  belongs_to :scout_message, optional: true
  belongs_to :integration_operation, optional: true
  
  # Fields:
  # - correlation_id: string (indexed)
  # - operation_id: string
  # - endpoint: string
  # - http_method: string
  # - request_headers: jsonb (masked)
  # - request_body: jsonb (redacted)
  # - response_status: integer
  # - response_headers: jsonb
  # - response_body_encrypted: binary (per-tenant encryption)
  # - duration_ms: integer
  # - rate_limit_remaining: integer
  # - rate_limit_reset_at: datetime
  # - error_message: text
  # - retry_count: integer
  # - idempotency_key: string
  # - dry_run: boolean
  # - metadata: jsonb
end
```

### 6. WebhookSubscription
```ruby
class WebhookSubscription < ApplicationRecord
  belongs_to :connection
  has_many :inbound_events
  
  # Fields:
  # - event_types: jsonb
  # - webhook_url: string
  # - signing_secret: string (encrypted)
  # - status: enum [:active, :paused, :failing]
  # - last_delivery_at: datetime
  # - consecutive_failures: integer
  # - metadata: jsonb
end
```

### 7. PolicyRule
```ruby
class PolicyRule < ApplicationRecord
  belongs_to :entity, optional: true # nil for global rules
  
  # Fields:
  # - name: string
  # - resource_type: string (Connection, Operation, etc)
  # - resource_id: string
  # - agent_role: string
  # - action: string (read, write, etc)
  # - conditions: jsonb (OPA/Rego-style rules)
  # - max_daily_calls: integer
  # - max_write_calls: integer
  # - requires_confirmation: boolean
  # - is_active: boolean
end
```

## Enhanced LLM Tools

### 1. list_connections
```ruby
def execute_list_connections(args)
  connections = current_entity.connections.active
  
  connections.map do |conn|
    {
      id: conn.id,
      name: conn.name,
      integration: conn.integration.name,
      status: conn.status,
      allowed_operations: conn.allowed_operations
    }
  end
end
```

### 2. describe_connection
```ruby
def execute_describe_connection(args)
  connection = Connection.find(args['connection_id'])
  
  {
    id: connection.id,
    name: connection.name,
    integration: connection.integration.name,
    operations: connection.available_operations.map do |op|
      {
        operation_id: op.operation_id,
        name: op.name,
        description: op.description,
        request_schema: op.request_schema,
        requires_confirmation: op.requires_confirmation
      }
    end,
    rate_limit_status: connection.rate_limit_status,
    daily_budget_remaining: connection.daily_budget_remaining
  }
end
```

### 3. invoke_operation
```ruby
def execute_invoke_operation(args)
  connection = Connection.find(args['connection_id'])
  operation = IntegrationOperation.find_by!(operation_id: args['operation_id'])
  
  # Policy check
  unless connection.can_execute?(operation.operation_id, current_agent_role)
    return { error: "Operation not allowed by policy" }
  end
  
  # Schema validation
  validator = JSONSchemer.schema(operation.request_schema)
  unless validator.valid?(args['params'])
    return { error: "Invalid parameters", validation_errors: validator.validate(args['params']).to_a }
  end
  
  # Rate limit check
  unless connection.within_rate_limit?
    return { error: "Rate limit exceeded", retry_after: connection.rate_limit_reset_at }
  end
  
  # Execute with correlation ID
  correlation_id = SecureRandom.uuid
  response = execute_api_call(connection, operation, args['params'], correlation_id)
  
  # Handle pagination
  if response.headers['X-Next-Cursor']
    response[:next_cursor] = response.headers['X-Next-Cursor']
  end
  
  response
end
```

### 4. dry_run_operation
```ruby
def execute_dry_run_operation(args)
  connection = Connection.find(args['connection_id'])
  operation = IntegrationOperation.find_by!(operation_id: args['operation_id'])
  
  # Simulate the request
  simulated_request = build_request(connection, operation, args['params'])
  
  # Estimate impact
  impact = estimate_operation_impact(operation, args['params'])
  
  # Generate confirmation token
  confirmation_token = generate_confirmation_token({
    connection_id: connection.id,
    operation_id: operation.operation_id,
    params: args['params'],
    expires_at: 5.minutes.from_now
  })
  
  {
    dry_run: true,
    confirmation_token: confirmation_token,
    simulated_request: {
      method: simulated_request[:method],
      url: simulated_request[:url],
      headers: mask_sensitive_headers(simulated_request[:headers]),
      body: redact_sensitive_fields(simulated_request[:body])
    },
    estimated_impact: impact,
    requires_confirmation: operation.requires_confirmation
  }
end
```

### 5. confirm_operation
```ruby
def execute_confirm_operation(args)
  token_data = verify_confirmation_token(args['token'])
  return { error: "Invalid or expired token" } unless token_data
  
  # Execute the pre-validated operation
  execute_invoke_operation(token_data)
end
```

### 6. discover_api_with_docs
```ruby
def execute_discover_api_with_docs(args)
  integration = Integration.find_by!(slug: args['integration'])
  
  # Try to fetch OpenAPI/Swagger spec
  spec = fetch_api_specification(integration)
  
  # Index documentation with RAG
  if integration.documentation_url
    doc_embeddings = generate_doc_embeddings(integration.documentation_url)
    store_in_vector_db(integration, doc_embeddings)
  end
  
  # Parse and store operations
  if spec
    operations = parse_openapi_spec(spec)
    operations.each do |op_data|
      IntegrationOperation.find_or_create_by(
        integration: integration,
        operation_id: op_data[:operation_id]
      ) do |op|
        op.update!(op_data)
      end
    end
  end
  
  {
    discovered_operations: operations.count,
    documentation_indexed: doc_embeddings.present?,
    spec_version: spec&.dig('info', 'version')
  }
end
```

## Policy Engine

```ruby
class PolicyEngine
  def self.check(connection, operation_id, agent_role)
    rules = PolicyRule.where(
      resource_type: 'Connection',
      resource_id: [connection.id, nil], # specific or global
      agent_role: [agent_role, nil]
    ).active
    
    rules.all? do |rule|
      evaluate_conditions(rule.conditions, {
        connection: connection,
        operation_id: operation_id,
        agent_role: agent_role,
        time: Time.current
      })
    end
  end
  
  private
  
  def self.evaluate_conditions(conditions, context)
    # Simple rule evaluation, could use OPA for complex cases
    case conditions['type']
    when 'allow_list'
      conditions['operations'].include?(context[:operation_id])
    when 'time_window'
      Time.current.between?(
        Time.parse(conditions['start']),
        Time.parse(conditions['end'])
      )
    when 'budget_check'
      context[:connection].daily_budget_remaining > 0
    else
      true
    end
  end
end
```

## Multi-Agent Pattern

```ruby
class IntegrationPlannerAgent < BaseAgent
  def plan_integration_task(user_request)
    # 1. Understand request
    connections = execute_list_connections
    
    # 2. Find relevant operations
    relevant_ops = connections.flat_map do |conn|
      ops = execute_describe_connection(connection_id: conn[:id])
      ops[:operations].select { |op| relevant_to_request?(op, user_request) }
    end
    
    # 3. Create execution plan
    {
      steps: build_execution_steps(relevant_ops, user_request),
      estimated_calls: count_api_calls(steps),
      requires_confirmation: steps.any? { |s| s[:requires_confirmation] }
    }
  end
end

class IntegrationExecutorAgent < BaseAgent
  def execute_plan(plan)
    results = []
    
    plan[:steps].each do |step|
      # Dry run if needed
      if step[:requires_confirmation]
        dry_run = execute_dry_run_operation(step)
        
        # Get confirmation
        confirmed = request_confirmation(dry_run)
        next unless confirmed
        
        result = execute_confirm_operation(token: dry_run[:confirmation_token])
      else
        result = execute_invoke_operation(step)
      end
      
      results << result
      
      # Handle pagination
      while result[:next_cursor]
        result = execute_invoke_operation(
          step.merge(cursor: result[:next_cursor])
        )
        results << result
      end
    end
    
    results
  end
end

class IntegrationVerifierAgent < BaseAgent
  def verify_results(results, expectations)
    results.map do |result|
      {
        success: validate_against_schema(result),
        business_rules: check_business_rules(result, expectations),
        recommendations: suggest_improvements(result)
      }
    end
  end
end
```

## Security & Compliance

### Host Allowlist
```ruby
class ApiRequestBuilder
  ALLOWED_HOSTS = {
    'stripe' => ['api.stripe.com'],
    'shopify' => ['*.myshopify.com', 'admin.shopify.com'],
    'custom' => [] # Must be explicitly configured
  }
  
  def build_url(connection, path)
    uri = URI.join(connection.integration.api_base_url, path)
    
    # Verify host is allowed
    unless host_allowed?(connection.integration.slug, uri.host)
      raise SecurityError, "Host not allowed: #{uri.host}"
    end
    
    uri.to_s
  end
end
```

### Data Redaction
```ruby
module DataRedaction
  SENSITIVE_FIELDS = %w[
    password secret token key
    ssn sin tax_id
    card_number cvv
    bank_account routing_number
  ]
  
  def self.redact_response(data, schema = nil)
    return data unless data.is_a?(Hash) || data.is_a?(Array)
    
    if data.is_a?(Array)
      return data.map { |item| redact_response(item, schema) }
    end
    
    data.transform_values do |value|
      if should_redact?(key, value, schema)
        '[REDACTED]'
      elsif value.is_a?(Hash) || value.is_a?(Array)
        redact_response(value, nested_schema(schema, key))
      else
        value
      end
    end
  end
end
```

## Implementation Phases (Updated)

### Phase 1: Admin Portal Foundation
- [ ] Create admin authentication and layout
- [ ] Build observability dashboards
- [ ] Add cost tracking for AI usage
- [ ] Implement system health monitoring

### Phase 2: Core Integration Infrastructure
- [ ] Create Integration, Connection, Credential models
- [ ] Build encrypted credential storage
- [ ] Implement host allowlist and path templates
- [ ] Add basic API key authentication
- [ ] Create connection UI

### Phase 2.5: Safety & Contracts
- [ ] Implement PolicyEngine with basic rules
- [ ] Add IntegrationOperation model
- [ ] Build schema validation
- [ ] Create typed tool wrappers
- [ ] Add correlation ID tracking

### Phase 3: Smart Canvas & Tools
- [ ] Build list_connections, describe_connection tools
- [ ] Implement invoke_operation with policy checks
- [ ] Add dry_run and confirm_operation flow
- [ ] Create integration management canvas
- [ ] Build API explorer with dry-run UI

### Phase 4: OAuth & Advanced Auth
- [ ] OAuth2 flow with PKCE
- [ ] Token refresh automation
- [ ] Dynamic client registration
- [ ] Scope management UI

### Phase 5: Intelligence Layer
- [ ] Documentation RAG system
- [ ] Multi-agent orchestration
- [ ] Smart retry with backoff
- [ ] Error learning system

### Phase 6: Production Readiness
- [ ] Webhook subscriptions
- [ ] Event-driven workflows
- [ ] Rate limit management
- [ ] Circuit breakers
- [ ] Contract testing suite

## Example: Secure Stripe Integration

```yaml
# Integration definition
stripe:
  name: Stripe
  auth_type: bearer_token
  api_base_url: https://api.stripe.com
  allowed_hosts: [api.stripe.com]
  
# Operation definition
stripe.list_customers.v2020-08-27:
  name: List Customers
  path_template: /v1/customers
  method: GET
  request_schema:
    type: object
    properties:
      limit: 
        type: integer
        minimum: 1
        maximum: 100
      starting_after:
        type: string
      created:
        type: object
        properties:
          gte: {type: string, format: date-time}
          lte: {type: string, format: date-time}
  pagination_strategy: cursor
  max_limit: 100

# Policy rule
marketing_agent_stripe_read:
  agent_role: marketing
  action: read
  conditions:
    type: allow_list
    operations: 
      - stripe.list_customers.*
      - stripe.get_customer.*
  max_daily_calls: 1000
  requires_confirmation: false

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
