# Scout Integration Architecture

## Vision
Transform Scout from a marketing app into a comprehensive business operations cockpit where AI agents can interact with any external application through a flexible, schema-agnostic integration system.

## Core Principles
1. **Authentication Abstraction**: Separate auth from business logic
2. **Schema Discovery**: Let LLMs figure out APIs dynamically
3. **Universal Tools**: Generic fetch/post tools that work with any authenticated app
4. **Extensibility**: Support both pre-configured and custom integrations

## Data Models

### 1. Integration (App Library)
```ruby
class Integration < ApplicationRecord
  belongs_to :entity, optional: true # nil for global/system integrations
  has_many :integration_credentials
  has_many :integration_endpoints
  
  # Fields:
  # - name: string (e.g., "Stripe", "Shopify", "Custom CRM")
  # - slug: string (e.g., "stripe", "shopify", "custom-crm")
  # - category: string (e.g., "payment", "ecommerce", "crm", "custom")
  # - auth_type: enum [:api_key, :bearer_token, :basic_auth, :oauth2, :custom]
  # - auth_config: jsonb (stores auth method details)
  # - api_base_url: string
  # - documentation_url: string
  # - icon_url: string
  # - description: text
  # - is_active: boolean
  # - is_custom: boolean (user-created vs pre-configured)
  # - metadata: jsonb (rate limits, version info, etc.)
end
```

### 2. IntegrationCredential (User's Auth Data)
```ruby
class IntegrationCredential < ApplicationRecord
  belongs_to :user
  belongs_to :entity
  belongs_to :integration
  
  encrypts :credentials # Rails 7+ encryption
  
  # Fields:
  # - name: string (user-friendly name like "Production API Key")
  # - credentials: jsonb (encrypted) - stores actual auth data
  # - auth_method: string (where to place auth - "header", "query", "body", "bearer")
  # - auth_field_name: string (e.g., "X-API-Key", "api_key", "Authorization")
  # - status: enum [:active, :expired, :revoked]
  # - last_used_at: datetime
  # - expires_at: datetime
  # - test_status: enum [:untested, :working, :failing]
  # - last_test_at: datetime
  # - metadata: jsonb (scopes, permissions, etc.)
end
```

### 3. IntegrationEndpoint (Known Endpoints - Optional)
```ruby
class IntegrationEndpoint < ApplicationRecord
  belongs_to :integration
  
  # Fields:
  # - name: string (e.g., "List Customers")
  # - path: string (e.g., "/v1/customers")
  # - http_method: string
  # - description: text
  # - request_schema: jsonb (optional - for LLM hints)
  # - response_schema: jsonb (optional - for LLM hints)
  # - example_request: jsonb
  # - example_response: jsonb
  # - metadata: jsonb (rate limits, pagination info, etc.)
end
```

### 4. IntegrationLog (Audit Trail)
```ruby
class IntegrationLog < ApplicationRecord
  belongs_to :integration_credential
  belongs_to :user
  belongs_to :scout_message, optional: true
  
  # Fields:
  # - endpoint: string
  # - http_method: string
  # - request_headers: jsonb (sanitized)
  # - request_body: jsonb (sanitized)
  # - response_status: integer
  # - response_headers: jsonb
  # - response_body: jsonb
  # - duration_ms: integer
  # - error_message: text
  # - metadata: jsonb (tool_name, session_id, etc.)
end
```

## Authentication Patterns

### 1. API Key Authentication
```yaml
auth_config:
  type: api_key
  placement: header # or 'query', 'body'
  field_name: X-API-Key
  prefix: "" # optional prefix like "Bearer"
```

### 2. Bearer Token
```yaml
auth_config:
  type: bearer_token
  placement: header
  field_name: Authorization
  prefix: Bearer
```

### 3. OAuth2 (Pre-configured)
```yaml
auth_config:
  type: oauth2
  flow: authorization_code
  client_id: "our_app_client_id"
  client_secret: "encrypted_in_credentials"
  authorize_url: "https://api.example.com/oauth/authorize"
  token_url: "https://api.example.com/oauth/token"
  scopes: ["read", "write"]
  redirect_uri: "https://app.agentmarketing.com/integrations/callback"
```

### 4. OAuth2 (User-configured)
```yaml
auth_config:
  type: oauth2_custom
  flow: authorization_code
  requires_user_app: true
  setup_instructions: "Create an app at https://..."
  required_fields:
    - client_id
    - client_secret
    - redirect_uri
```

## LLM Tools

### 1. fetch_external_data
```ruby
def execute_fetch_external_data(args)
  integration_name = args['integration']
  endpoint = args['endpoint']
  params = args['params'] || {}
  
  # Find credential
  credential = find_active_credential(integration_name)
  
  # Build request with auth
  request = build_authenticated_request(credential, endpoint, params)
  
  # Execute and log
  response = execute_request(request)
  log_integration_activity(credential, request, response)
  
  {
    success: response.success?,
    data: response.parsed_body,
    headers: sanitize_headers(response.headers),
    status: response.status
  }
end
```

### 2. post_external_data
```ruby
def execute_post_external_data(args)
  # Similar to fetch but with POST/PUT/PATCH support
end
```

### 3. discover_api_schema
```ruby
def execute_discover_api_schema(args)
  integration_name = args['integration']
  
  # Try common discovery endpoints
  # - /swagger.json
  # - /openapi.json
  # - /api/v1
  # - Common patterns for the platform
  
  # Return discovered endpoints and schemas
end
```

### 4. test_integration
```ruby
def execute_test_integration(args)
  integration_name = args['integration']
  
  # Perform a simple test request
  # Update credential test_status
end
```

## UI Components

### 1. Integration Library View
```erb
<!-- /app/views/integrations/index.html.erb -->
<div class="integrations-grid">
  <% @integrations.each do |integration| %>
    <div class="integration-card">
      <img src="<%= integration.icon_url %>" />
      <h3><%= integration.name %></h3>
      <p><%= integration.description %></p>
      <% if integration.connected_for?(current_user) %>
        <span class="status-connected">Connected</span>
      <% else %>
        <%= link_to "Connect", new_integration_credential_path(integration) %>
      <% end %>
    </div>
  <% end %>
</div>
```

### 2. OAuth Flow Controller
```ruby
class IntegrationCallbacksController < ApplicationController
  def oauth_callback
    integration = Integration.find_by(slug: params[:integration])
    
    # Exchange code for token
    token_response = exchange_code_for_token(params[:code], integration)
    
    # Store credential
    IntegrationCredential.create!(
      user: current_user,
      entity: current_entity,
      integration: integration,
      credentials: {
        access_token: token_response['access_token'],
        refresh_token: token_response['refresh_token'],
        expires_at: Time.current + token_response['expires_in'].seconds
      }
    )
    
    redirect_to integrations_path, notice: "#{integration.name} connected!"
  end
end
```

## Pre-configured Integrations

### Payment & Finance
- Stripe
- Square
- QuickBooks
- Xero

### E-commerce
- Shopify
- WooCommerce
- BigCommerce

### CRM & Sales
- Salesforce
- HubSpot
- Pipedrive

### Communication
- Slack
- Discord
- Twilio

### Productivity
- Google Workspace
- Microsoft 365
- Notion

### Marketing (extend existing)
- Mailchimp
- SendGrid
- Facebook Ads
- Google Ads

## Security Considerations

1. **Encryption**: All credentials stored with Rails encryption
2. **Scoping**: Credentials scoped to user + entity
3. **Audit Trail**: All API calls logged
4. **Rate Limiting**: Respect and track rate limits
5. **Token Refresh**: Automatic OAuth token refresh
6. **Sanitization**: Remove sensitive data from logs

## LLM Integration Strategy

### System Prompt Addition
```
You have access to external integrations through these tools:
- fetch_external_data: GET data from any connected integration
- post_external_data: POST/PUT/PATCH data to integrations
- discover_api_schema: Explore available endpoints
- test_integration: Verify integration is working

When working with external APIs:
1. Start with discover_api_schema if unsure about endpoints
2. Use your knowledge of common API patterns (REST, pagination, etc.)
3. Handle errors gracefully and suggest fixes
4. Respect rate limits and best practices
```

### Dynamic Schema Learning
The LLM can:
1. Inspect example responses to understand data structure
2. Try common endpoint patterns (/api/v1/resources)
3. Use error messages to correct requests
4. Build a mental model of the API through exploration

## Smart Canvas Integration

### Integration Management Canvas
```ruby
def render_integrations_canvas(data = {})
  integrations = current_entity.integrations.includes(:integration_credentials)
  categories = Integration.distinct.pluck(:category)
  
  {
    canvas_type: 'integrations_manager',
    data: {
      connected_integrations: integrations.map { |i| 
        {
          name: i.name,
          category: i.category,
          status: i.status_for(current_user),
          last_used: i.last_used_at,
          endpoints_discovered: i.discovered_endpoints_count
        }
      },
      available_integrations: Integration.active.count,
      categories: categories,
      recent_activity: IntegrationLog.recent_for(current_entity)
    }
  }
end
```

### API Explorer Canvas
```ruby
def render_api_explorer_canvas(integration_id)
  integration = Integration.find(integration_id)
  credential = integration.credentials_for(current_user)
  
  {
    canvas_type: 'api_explorer',
    data: {
      integration: integration.as_json,
      discovered_endpoints: integration.discovered_endpoints,
      recent_requests: IntegrationLog.where(integration_credential: credential).limit(10),
      test_console: true
    }
  }
end
```

### Integration Analytics Canvas
```ruby
def render_integration_analytics_canvas(data = {})
  {
    canvas_type: 'integration_analytics',
    data: {
      api_usage: calculate_api_usage_stats,
      error_rates: calculate_error_rates,
      popular_endpoints: most_used_endpoints,
      performance_metrics: api_performance_stats
    }
  }
end
```

## Admin Portal

### Admin Dashboard Structure
```
/admin
├── dashboard (overview stats)
├── integrations
│   ├── library (manage pre-configured integrations)
│   ├── credentials (view all user credentials)
│   ├── logs (API activity logs)
│   └── analytics (usage patterns)
├── observability
│   ├── ai_usage (LLM token usage, costs)
│   ├── tool_execution (tool performance)
│   ├── workflows (task session analytics)
│   └── errors (system errors, failures)
├── users
│   ├── activity (user engagement)
│   ├── entities (entity management)
│   └── billing (subscription management)
└── system
    ├── jobs (background job monitoring)
    ├── cache (cache statistics)
    ├── performance (response times)
    └── health (system health checks)
```

### Admin Models & Controllers

```ruby
# app/models/admin_user.rb
class AdminUser < ApplicationRecord
  has_secure_password
  
  enum role: { viewer: 0, editor: 1, super_admin: 2 }
  
  # Audit trail for admin actions
  has_many :admin_activities
end

# app/controllers/admin/base_controller.rb
class Admin::BaseController < ApplicationController
  before_action :authenticate_admin!
  before_action :authorize_admin!
  
  layout 'admin'
  
  private
  
  def authenticate_admin!
    redirect_to root_path unless current_user&.admin?
  end
end

# app/controllers/admin/integrations_controller.rb
class Admin::IntegrationsController < Admin::BaseController
  def index
    @stats = {
      total_integrations: Integration.count,
      active_credentials: IntegrationCredential.active.count,
      api_calls_today: IntegrationLog.today.count,
      error_rate: calculate_error_rate
    }
  end
  
  def library
    @integrations = Integration.includes(:integration_credentials)
  end
  
  def logs
    @logs = IntegrationLog.includes(:integration_credential, :user)
            .order(created_at: :desc)
            .page(params[:page])
  end
end

# app/controllers/admin/observability_controller.rb
class Admin::ObservabilityController < Admin::BaseController
  def ai_usage
    @stats = {
      total_tokens: ObservabilityEvent.ai_tokens_used,
      estimated_cost: ObservabilityEvent.ai_estimated_cost,
      requests_by_model: ObservabilityEvent.group_by_model,
      usage_trend: ObservabilityEvent.daily_usage_trend
    }
  end
  
  def workflows
    @stats = {
      total_sessions: TaskSession.count,
      success_rate: TaskSession.success_rate,
      avg_completion_time: TaskSession.average_completion_time,
      popular_workflows: TaskSession.popular_workflows
    }
  end
end
```

### Admin Views

```erb
<!-- app/views/admin/dashboard/index.html.erb -->
<div class="admin-dashboard">
  <h1>Admin Dashboard</h1>
  
  <div class="stats-grid">
    <div class="stat-card">
      <h3>Integrations</h3>
      <div class="stat-value"><%= @stats[:active_integrations] %></div>
      <div class="stat-label">Active Connections</div>
    </div>
    
    <div class="stat-card">
      <h3>AI Usage</h3>
      <div class="stat-value"><%= number_to_human(@stats[:ai_tokens_today]) %></div>
      <div class="stat-label">Tokens Today</div>
    </div>
    
    <div class="stat-card">
      <h3>API Calls</h3>
      <div class="stat-value"><%= @stats[:api_calls_today] %></div>
      <div class="stat-label">External API Calls</div>
    </div>
    
    <div class="stat-card">
      <h3>Active Users</h3>
      <div class="stat-value"><%= @stats[:active_users_today] %></div>
      <div class="stat-label">Users Today</div>
    </div>
  </div>
  
  <div class="charts-section">
    <div class="chart-container">
      <h3>API Usage Trend</h3>
      <canvas id="api-usage-chart"></canvas>
    </div>
    
    <div class="chart-container">
      <h3>Error Rate</h3>
      <canvas id="error-rate-chart"></canvas>
    </div>
  </div>
</div>
```

### Observability Integration

```ruby
# app/models/observability_event.rb
class ObservabilityEvent < ApplicationRecord
  # Extend existing model with admin-specific scopes
  
  scope :ai_usage, -> { where(event_type: 'ai.completion') }
  scope :tool_execution, -> { where(event_type: 'tool.execution') }
  scope :integration_api, -> { where(event_type: 'integration.api_call') }
  
  def self.ai_tokens_used(period = 1.day)
    ai_usage.where(created_at: period.ago..)
            .sum("(payload->>'total_tokens')::int")
  end
  
  def self.ai_estimated_cost(period = 1.day)
    # Calculate based on model and token usage
    ai_usage.where(created_at: period.ago..).sum do |event|
      tokens = event.payload['total_tokens'].to_i
      model = event.payload['model']
      calculate_cost_for_model(model, tokens)
    end
  end
end
```

## Implementation Phases

### Phase 1: Admin Portal Foundation
- [ ] Create AdminUser model and authentication
- [ ] Build admin layout and navigation
- [ ] Implement basic dashboard
- [ ] Add observability views (AI usage, workflows)
- [ ] Create system health monitoring

### Phase 2: Core Integration Infrastructure
- [ ] Create Integration model and migrations
- [ ] Build IntegrationCredential with encryption
- [ ] Implement basic API key auth
- [ ] Create fetch_external_data tool
- [ ] Add integration UI
- [ ] Build admin integration management

### Phase 3: Smart Canvas Integration
- [ ] Create integration management canvas
- [ ] Build API explorer canvas
- [ ] Add integration analytics canvas
- [ ] Wire up canvas loading in Scout
- [ ] Add LLM tools for canvas manipulation

### Phase 4: OAuth Support
- [ ] Add OAuth2 flow handling
- [ ] Implement token refresh
- [ ] Build callback controller
- [ ] Add pre-configured OAuth apps
- [ ] Create OAuth setup wizard

### Phase 5: LLM Enhancement
- [ ] Add discover_api_schema tool
- [ ] Implement smart error handling
- [ ] Create integration testing tool
- [ ] Add rate limit tracking
- [ ] Build API learning system

### Phase 6: Pre-built Library & Polish
- [ ] Add 10-15 popular integrations
- [ ] Create setup wizards
- [ ] Build integration templates
- [ ] Add webhook support
- [ ] Implement admin analytics dashboards

## Example Usage

```
User: "Pull my latest customers from Stripe"

Scout: *uses fetch_external_data tool*
{
  "integration": "stripe",
  "endpoint": "/v1/customers",
  "params": {
    "limit": 10,
    "created[gte]": "2024-01-01"
  }
}

User: "Create a new product in my Shopify store"

Scout: *uses post_external_data tool*
{
  "integration": "shopify",
  "endpoint": "/admin/api/2024-01/products.json",
  "method": "POST",
  "body": {
    "product": {
      "title": "New Product",
      "body_html": "<p>Great product!</p>",
      "vendor": "Your Store",
      "product_type": "Widget"
    }
  }
}
```

## Benefits

1. **Flexibility**: Works with any API without hard-coding
2. **Scalability**: Easy to add new integrations
3. **User Control**: Custom integrations for unique needs
4. **AI-Powered**: LLM handles schema discovery and adaptation
5. **Unified Interface**: One set of tools for all integrations
