# Analytics Add-On Testing & Integration Guide

**Goal**: Test new analytics features and integrate with existing analytics dashboard

---

## Quick Testing (After Setup)

### Step 1: Run Migrations & Seeds

```bash
# Run migrations
rails db:migrate

# Load sample metrics
rails runner db/seeds/analytics_setup.rb
```

### Step 2: Test Via Chat

**Simple Query**:
```
User: "Show me campaign performance for last 30 days"

Expected:
- AMOS uses query_metric tool
- Returns data
- Creates visualization
```

**Discover Metrics**:
```
User: "What metrics can I analyze?"

Expected:
- AMOS uses list_metrics
- Shows: campaign_performance, email_engagement, contact_growth
```

**Complex Analysis**:
```
User: "Analyze email engagement trends by channel for Q3"

Expected:
- AMOS delegates to planner
- Selects analytics_deep_dive_v2 workflow
- Queries data, creates charts
```

---

## Integrating with Existing Analytics Dashboard

### Current Dashboard
**Location**: `app/views/scout/canvas/_analytics_dashboard.html.erb`

**Shows**:
- Campaign stats (hardcoded)
- Landing page counts (hardcoded)
- Static charts

### Enhanced Dashboard (Powered by New System)

**Add "Custom Report" Button Functionality**:

```javascript
// In _analytics_dashboard.html.erb
function scoutCustomReport() {
  // Instead of dummy function, trigger analytics workflow
  const message = "I want to create a custom analytics report";
  
  if (window.scoutSendMessage) {
    window.scoutSendMessage(message);
  }
}
```

This triggers the **analytics_deep_dive_v2** workflow!

---

## Adding Integration Data to Analytics

### Current Issue:
Analytics only shows AMOS internal data (campaigns, contacts).

### Solution:
Add **Stripe revenue metrics** and other integration data!

### Step 1: Create Integration Data Contracts

```ruby
# In db/seeds/analytics_setup.rb (add this):

DataContract.create!(
  name: 'stripe_customers',
  version: '1.0.0',
  entity_type: 'StripeCustomer',
  schema_definition: {
    entity_id: 'integer',
    customer_id: 'string',
    email: 'string',
    name: 'string',
    created: 'date',
    balance: 'integer',
    currency: 'string'
  },
  privacy_rules: {
    pii_fields: ['email', 'name'],
    tokenization: 'deterministic'
  },
  freshness_slo: '<= 1h',  # Sync hourly
  metadata: {
    source: 'stripe_integration',
    sync_method: 'api_pull'
  }
)

DataContract.create!(
  name: 'stripe_charges',
  version: '1.0.0',
  entity_type: 'StripeCharge',
  schema_definition: {
    entity_id: 'integer',
    charge_id: 'string',
    customer_id: 'string',
    amount: 'integer',
    currency: 'string',
    status: 'enum(succeeded,pending,failed)',
    created: 'date',
    description: 'string'
  },
  privacy_rules: {
    pii_fields: ['customer_id'],
    tokenization: 'deterministic'
  },
  freshness_slo: '<= 1h'
)
```

### Step 2: Create Cross-Platform Metrics

```ruby
MetricDefinition.create!(
  name: 'stripe_revenue',
  version: '1.0.0',
  description: 'Total revenue from Stripe (successful charges)',
  expression: 'SUM(amount) / 100.0',  # Convert cents to dollars
  source: 'stripe_charges',
  time_column: 'created',
  grain_default: 'week',
  dimensions: ['currency', 'status'],
  filters_default: { status: ['succeeded'] },
  quality_rules: ['amount >= 0'],
  owner: 'finance@company.com',
  category: 'revenue',
  metadata: {
    integration: 'stripe',
    unit: 'USD'
  }
)

MetricDefinition.create!(
  name: 'customer_lifetime_value',
  version: '1.0.0',
  description: 'Average customer lifetime value',
  expression: 'AVG(total_spent)',
  source: 'stripe_customers_with_totals',  # Materialized view
  time_column: 'first_purchase_date',
  grain_default: 'month',
  dimensions: ['customer_segment', 'acquisition_channel'],
  filters_default: {},
  quality_rules: [],
  owner: 'growth@company.com',
  category: 'customer'
)
```

### Step 3: Create Data Sync Job

```ruby
# app/jobs/sync_stripe_analytics_job.rb
class SyncStripeAnalyticsJob < ApplicationJob
  queue_as :default
  
  def perform(entity_id)
    entity = Entity.find(entity_id)
    
    # Find Stripe connection
    stripe_conn = entity.connections.joins(:integration)
                        .where(integrations: { slug: 'stripe' })
                        .where(status: :connected)
                        .first
    
    return unless stripe_conn
    
    # Sync customers
    sync_customers(entity, stripe_conn)
    
    # Sync charges
    sync_charges(entity, stripe_conn)
  end
  
  private
  
  def sync_customers(entity, connection)
    # Use execute_integration to get customers
    result = UniversalIntegrationExecutor.execute(
      integration: 'stripe',
      operation: 'list_customers',
      params: { limit: 100 },
      user: entity.users.first,
      entity: entity
    )
    
    return unless result[:success]
    
    # Store in analytics table
    result[:data].each do |customer|
      StripeCustomerAnalytics.upsert({
        entity_id: entity.id,
        customer_id: customer['id'],
        email: customer['email'],
        name: customer['name'],
        created: Time.at(customer['created']),
        balance: customer['balance'],
        currency: customer['currency'] || 'usd',
        synced_at: Time.current
      }, unique_by: [:entity_id, :customer_id])
    end
  end
  
  def sync_charges(entity, connection)
    # Similar pattern for charges
  end
end
```

---

## Enhanced Analytics Dashboard Design

### Section 1: Quick Stats (Keep Current)
```
┌─────────────────────────────────────────────────────┐
│  [Email Stats]  [Campaign Stats]  [Contact Stats]   │
│  (Current hardcoded data - keep this)               │
└─────────────────────────────────────────────────────┘
```

### Section 2: AI-Powered Insights (NEW!)
```
┌─────────────────────────────────────────────────────┐
│  💡 AI Insights                                      │
│  ┌─────────────────────────────────────────────────┐│
│  │ "Email engagement is up 12% this week"          ││
│  │ "Stripe revenue growing 8% month-over-month"    ││
│  │ [Ask for custom analysis →]                     ││
│  └─────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────┘
```

### Section 3: Custom Query Builder (NEW!)
```
┌─────────────────────────────────────────────────────┐
│  📊 Custom Analysis                                  │
│  ┌─────────────────────────────────────────────────┐│
│  │ Ask Amos: [What would you like to analyze?]    ││
│  │                                                  ││
│  │ Quick Links:                                     ││
│  │ • Revenue by channel (last 90 days)             ││
│  │ • Campaign performance comparison                ││
│  │ • Contact growth trends                          ││
│  │ • Stripe customer analysis                       ││
│  └─────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────┘
```

---

## Implementation: Enhanced Analytics Dashboard

**Update**: `app/views/scout/canvas/_analytics_dashboard.html.erb`

**Add after current stats section**:

```erb
<!-- AI-Powered Analytics Section -->
<div class="row mb-4">
  <div class="col-12">
    <div class="card border-0 shadow-sm">
      <div class="card-header bg-gradient-primary text-white">
        <h6 class="mb-0">
          <i class="fas fa-magic me-2"></i>
          AI-Powered Analytics
        </h6>
      </div>
      <div class="card-body">
        <div class="mb-3">
          <label class="form-label fw-bold">Ask Amos to analyze your data:</label>
          <div class="input-group">
            <input type="text" 
                   class="form-control" 
                   id="analyticsQuery" 
                   placeholder="e.g., Show me revenue trends by channel for last quarter">
            <button class="btn btn-primary" onclick="runAnalyticsQuery()">
              <i class="fas fa-chart-line me-1"></i>
              Analyze
            </button>
          </div>
        </div>
        
        <!-- Quick Analysis Templates -->
        <div class="d-flex gap-2 flex-wrap">
          <button class="btn btn-sm btn-outline-primary" onclick="quickAnalysis('campaign_performance')">
            📊 Campaign Performance
          </button>
          <button class="btn btn-sm btn-outline-primary" onclick="quickAnalysis('email_engagement')">
            📧 Email Engagement
          </button>
          <button class="btn btn-sm btn-outline-primary" onclick="quickAnalysis('contact_growth')">
            👥 Contact Growth
          </button>
          <% if current_entity.connections.where(integration: Integration.find_by(slug: 'stripe')).exists? %>
          <button class="btn btn-sm btn-outline-success" onclick="quickAnalysis('stripe_revenue')">
            💰 Stripe Revenue
          </button>
          <% end %>
        </div>
      </div>
    </div>
  </div>
</div>

<script>
function runAnalyticsQuery() {
  const query = document.getElementById('analyticsQuery').value;
  if (query && window.scoutSendMessage) {
    window.scoutSendMessage(query);
  }
}

function quickAnalysis(metric) {
  const queries = {
    'campaign_performance': "Show me campaign performance for the last 90 days",
    'email_engagement': "Analyze email engagement trends over the last quarter",
    'contact_growth': "Show me contact growth trends for the last 6 months",
    'stripe_revenue': "Analyze Stripe revenue by month for the last year"
  };
  
  if (window.scoutSendMessage) {
    window.scoutSendMessage(queries[metric]);
  }
}
</script>
```

---

## Testing Checklist

### Test 1: Discover Metrics
```
In chat: "What metrics can I analyze?"

Expected:
✅ Uses list_metrics tool
✅ Shows: campaign_performance, email_engagement, contact_growth
✅ Displays available dimensions
```

### Test 2: Simple Query
```
In chat: "Show me campaign performance for last 30 days"

Expected:
✅ Uses query_metric tool
✅ Queries campaigns table
✅ Tenant isolation enforced (only user's data)
✅ Returns aggregated data
✅ May create visualization
```

### Test 3: Complex Analysis (Workflow)
```
In chat: "Analyze email engagement trends by channel"

Expected:
✅ Delegates to planner
✅ Selects analytics_deep_dive_v2 workflow
✅ Asks clarifying questions
✅ Queries multiple metrics
✅ Creates visualizations
✅ Shows insights
```

### Test 4: Budget Enforcement
```
In chat: "Show me daily data for the last 5 years"

Expected:
✅ Queries metric
✅ Calculates estimate (5 years = ~1.8M rows)
✅ Exceeds budget (1M row cap)
✅ Returns error: "exceeds budget"
✅ Suggests shorter time period
```

### Test 5: Explain Query
```
In chat: "Explain how you would query revenue by region"

Expected:
✅ Uses explain_query tool
✅ Shows compiled SQL
✅ Shows lineage (which tables)
✅ Shows estimated rows
✅ Does NOT execute
```

---

## Extending to Integration Data

### Add Stripe Metrics

**Create after running setup**:

```ruby
# In rails console or seed file:

# Metric for Stripe data
MetricDefinition.create!(
  name: 'stripe_revenue',
  version: '1.0.0',
  description: 'Revenue from Stripe charges',
  expression: 'SUM(amount) / 100.0',
  source: 'stripe_charges_analytics',  # Synced table
  time_column: 'created_at',
  grain_default: 'month',
  dimensions: ['currency', 'status', 'customer_segment'],
  filters_default: { status: ['succeeded'] },
  owner: 'finance@company.com',
  category: 'revenue',
  metadata: {
    integration: 'stripe',
    requires_sync: true
  }
)
```

**Users can then query**:
```
"Show me Stripe revenue by month for 2025"
```

---

## Production Recommendations

### For Launch (Keep Simple):
1. ✅ Use existing dashboard for quick stats
2. ✅ Add "Ask Amos" query box for custom analysis
3. ✅ Start with AMOS internal metrics (campaigns, contacts)
4. ⏳ Add Stripe metrics post-launch

### Week 2 (Add Integration Sync):
1. Build sync jobs for Stripe data
2. Create analytics tables for external data
3. Add revenue metrics
4. Enable cross-platform analysis

### Week 3+ (Advanced):
1. Real-time dashboards
2. Automated insights
3. Predictive analytics
4. Custom metric builder UI

---

## Current Analytics Dashboard Integration

**Keep Existing** (Top section):
```
📧 Email Campaigns | 🌐 Landing Pages | 👥 Contacts | 📊 Engagement
(Current hardcoded stats - works great)
```

**Add Below** (AI-Powered section):
```
💬 Ask Amos to analyze your data:
[Text input: "What would you like to analyze?"]
[Quick buttons: Campaign Performance | Email Engagement | Contact Growth | Stripe Revenue]

📊 Recent Insights (Auto-generated):
- "Email opens increased 15% this week"
- "Contact growth accelerating (127 new this month)"
- "Revenue trending up 8% month-over-month"
```

---

## Best Testing Approach

### 1. Test Locally First
```bash
# Setup
rails db:migrate
rails runner db/seeds/analytics_setup.rb

# Test in rails console:
result = Analytics::QueryExecutor.execute(
  metric: 'campaign_performance',
  params: {
    start_date: '2025-09-01',
    end_date: '2025-10-15',
    time_grain: 'week'
  },
  entity: Entity.first,
  user: User.first
)

puts result.inspect
```

### 2. Test Via Tools
```bash
# In rails console:
tool = Tools::QueryMetricTool.new(user: User.first, entity: Entity.first)
result = tool.execute({
  metric: 'campaign_performance',
  start_date: '2025-09-01',
  end_date: '2025-10-15',
  time_grain: 'week'
})

puts result.inspect
```

### 3. Test Via Chat
```
Open Scout chat:
"Show me campaign performance for last 30 days"

Watch logs for:
🔧 query_metric tool execution
✅ Results returned
📊 Visualization created (if applicable)
```

### 4. Test Workflow
```
"I want to analyze email engagement trends"

Watch for:
🎯 Delegates to planner
📋 Selects analytics_deep_dive_v2
🔄 Phases execute with progress
✅ Complete with visualizations
```

---

## Quick Win: Enhance Analytics Menu Now

**Update `scoutCustomReport()` function**:

```javascript
// In _analytics_dashboard.html.erb around line 21
function scoutCustomReport() {
  // Open chat with analytics prompt
  if (window.scoutSendMessage) {
    window.scoutSendMessage("I want to create a custom analytics report");
  } else {
    // Fallback: show input modal
    const query = prompt("What would you like to analyze?");
    if (query && window.scoutSendMessage) {
      window.scoutSendMessage(query);
    }
  }
}
```

**Users click "Custom Report"** → Triggers analytics_deep_dive workflow!

---

## Example Queries Users Can Ask

### Internal AMOS Data:
- "Show me campaign performance trends"
- "Which channels have best email engagement?"
- "How many contacts did we add this month?"
- "Compare campaign performance across channels"

### After Adding Stripe Sync:
- "What's our Stripe revenue for Q3?"
- "Show me revenue by customer segment"
- "Compare AMOS email campaigns with Stripe revenue"
- "Which email campaigns drove the most Stripe conversions?"

### Advanced (With Workflow):
- "Analyze our full marketing funnel: emails → clicks → Stripe purchases"
- "Show cohort retention for customers acquired via email campaigns"
- "Forecast revenue based on current email engagement trends"

---

## Security Testing

### Test 1: Tenant Isolation
```ruby
# User A queries metric
result_a = Analytics::QueryExecutor.execute(
  metric: 'campaign_performance',
  params: {...},
  entity: entity_a,
  user: user_a
)

# Should ONLY see entity_a data
result_a[:rows].all? { |r| r['entity_id'] == entity_a.id }
```

### Test 2: Budget Enforcement
```ruby
# Set low budget
quota = TenantQuota.find_by(entity: entity)
quota.update!(row_budget: 1000)

# Query that would exceed
result = Analytics::QueryExecutor.execute(
  metric: 'campaign_performance',
  params: {
    start_date: '2020-01-01',  # 5 years
    end_date: '2025-10-15'
  },
  entity: entity,
  user: user
)

# Should fail with budget error
expect(result[:success]).to be false
expect(result[:error]).to include("exceeds budget")
```

### Test 3: Time Window Cap
```ruby
# Query 1000 days (exceeds 400 cap)
result = Analytics::QueryExecutor.execute(
  metric: 'campaign_performance',
  params: {
    start_date: '2022-01-01',
    end_date: '2025-10-15'
  },
  entity: entity,
  user: user
)

# Should fail
expect(result[:error]).to include("exceeds cap")
```

---

## Monitoring & Observability

### Check Query Logs:
```ruby
# In rails console:
AnalyticsQueryLog.recent.each do |log|
  puts "#{log.metric_name}: #{log.rows_returned} rows in #{log.execution_time_ms}ms"
end
```

### Check Quotas:
```ruby
quota = TenantQuota.find_by(entity: current_entity)
usage = quota.current_usage
puts "Queries: #{usage[:queries_count]}"
puts "Rows scanned: #{usage[:rows_scanned]}"
puts "Usage: #{usage[:usage_percentage]}%"
```

---

## Next Steps

1. **Run setup**: `rails db:migrate && rails runner db/seeds/analytics_setup.rb`
2. **Test simple query**: "Show me campaign performance"
3. **Test workflow**: "Analyze email engagement trends"
4. **Enhance dashboard**: Add AI query box
5. **Add Stripe metrics**: Create sync job (Week 2)

---

**The analytics system is READY to test!** 🎉

All following the same secure, DB-driven patterns as the integration system we built today!

