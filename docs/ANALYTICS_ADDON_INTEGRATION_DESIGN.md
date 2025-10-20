# Analytics Add-On Integration Design

**Goal**: Integrate deterministic analytics module into AMOS architecture  
**Approach**: Separate service with clean API boundaries  
**Priority**: Post-launch (Week 2-3)

---

## How It Fits with Current AMOS Architecture

### Perfect Alignment with Today's Work

The analytics add-on follows **THE EXACT SAME PATTERN** we just built for integrations:

**Integration System** (Built Today):
- External APIs → IntegrationOperation (DB schema)
- UniversalIntegrationExecutor (safe interpreter)
- No arbitrary code execution ✅

**Analytics Add-On** (Proposed):
- Data contracts → Metrics (DB schema)
- AnalyticsQueryExecutor (safe interpreter)
- No arbitrary SQL execution ✅

**SAME PHILOSOPHY**: Schema-driven, DB-only, secure execution!

---

## Architecture Integration Points

### Layer 1: Analytics Service (Separate Module)

```
app/services/analytics/
├── landing_layer.rb          # Ingest contracted data
├── conform_layer.rb          # Normalize to ontology
├── serve_layer.rb            # Pre-aggregated metrics
├── query_executor.rb         # Safe metric query execution
├── contract_validator.rb     # Validate data contracts
└── catalog_service.rb        # Discover datasets/metrics

app/models/
├── data_contract.rb          # Versioned contracts
├── metric_definition.rb      # Metric specs
├── analytics_query_log.rb    # Audit trail
└── tenant_quota.rb           # Budgets & limits
```

**Key**: Self-contained module, no core AMOS changes!

### Layer 2: Tools for Agents

Following the pattern from today (execute_integration, list_operations, etc.):

```ruby
# Analytics tools (mirror integration tools)
Tools::AnalyticsTools:
  - query_metric          # Like execute_integration
  - list_metrics          # Like list_operations
  - validate_data         # Like test_integration_endpoint
  - explain_query         # New - show lineage
```

### Layer 3: Agent Integration

**AMOS Main Chat Agent**:
```ruby
'main_chat' => {
  tool_allowlist: [
    # Existing tools...
    'query_metric',        # Simple metric queries
    'list_metrics',        # Discover analytics
    'delegate_to_analyst'  # Complex analysis workflows
  ]
}
```

**AnalystAgent** (via workflows):
```yaml
# analytics_deep_dive_v2.yml workflow
phases:
  - type: gather_context
    goal: Understand analysis question
    
  - type: execute_goal
    allowed_tools: [query_metric, explain_query, list_metrics]
    goal: Query relevant metrics
    
  - type: execute_goal
    allowed_tools: [create_dynamic_visualization, aggregate_artifact_data]
    goal: Create visualizations
    
  - type: validate_result
    goal: Verify insights are accurate
```

---

## Integration Pattern (Mirrors Integration System)

### Current Integration System:
```
User: "List Stripe customers"
  ↓
AMOS: execute_integration(integration: "stripe", operation: "list_customers")
  ↓
UniversalIntegrationExecutor:
  - Finds IntegrationOperation (DB schema)
  - Builds HTTP request from schema
  - Executes safely via IntegrationApiService
  ↓
Returns data
```

### New Analytics System:
```
User: "Show me revenue by channel"
  ↓
AMOS: query_metric(metric: "revenue", group_by: ["channel"])
  ↓
AnalyticsQueryExecutor:
  - Finds MetricDefinition (DB schema)
  - Builds safe query from schema
  - Enforces tenant isolation, budgets
  - Executes via warehouse connector
  ↓
Returns aggregated data
```

**SAME PATTERN**: Schema → Safe executor → Results

---

## Database Schema (Mirrors Integration Tables)

### Integration System Tables:
```ruby
integrations           # API definitions
integration_operations # Endpoint definitions
connections           # User connections
integration_logs      # Audit trail
```

### Analytics System Tables (Proposed):
```ruby
data_contracts        # Contract definitions
metric_definitions    # Metric definitions
analytics_connections # Warehouse connections
analytics_query_logs  # Audit trail (execution cards)
tenant_quotas        # Row budgets, time caps
```

**SAME STRUCTURE**: Metadata in DB, safe execution!

---

## Tools Implementation (Following Today's Pattern)

### 1. QueryMetricTool (Like ExecuteIntegrationTool)

```ruby
module Tools
  class QueryMetricTool < BaseTool
    def self.metadata
      {
        name: 'query_metric',
        description: 'Query business metrics with automatic filtering and aggregation',
        category: 'analytics',
        input_schema: {
          type: 'object',
          properties: {
            metric: { type: 'string', description: 'Metric name (e.g., "revenue", "orders")' },
            start_date: { type: 'string', description: 'Start date (YYYY-MM-DD)' },
            end_date: { type: 'string', description: 'End date (YYYY-MM-DD)' },
            time_grain: { type: 'string', enum: ['day', 'week', 'month'] },
            group_by: { type: 'array', description: 'Dimensions to group by' },
            where: { type: 'object', description: 'Filters' },
            limit: { type: 'integer', default: 10000 }
          },
          required: ['metric', 'start_date', 'end_date']
        }
      }
    end
    
    def execute(args)
      # Similar to UniversalIntegrationExecutor pattern
      result = Analytics::QueryExecutor.execute(
        metric: args[:metric],
        params: args,
        entity: @entity,  # Tenant isolation
        user: @user       # Audit trail
      )
      
      # Returns standardized response
      if result[:success]
        success_response(
          data: result[:rows],
          stats: result[:stats],
          metric: args[:metric]
        )
      else
        error_response(result[:error])
      end
    end
  end
end
```

### 2. ListMetricsTool (Like ListOperationsTool)

```ruby
module Tools
  class ListMetricsTool < BaseTool
    def execute(args)
      # Discover available metrics
      catalog = Analytics::CatalogService.get_catalog(entity: @entity)
      
      success_response(
        metrics: catalog[:metrics],
        datasets: catalog[:datasets],
        dimensions: catalog[:dimensions]
      )
    end
  end
end
```

### 3. ExplainQueryTool (New)

```ruby
module Tools
  class ExplainQueryTool < BaseTool
    def execute(args)
      # Show query lineage without executing
      explanation = Analytics::QueryExecutor.explain(
        metric: args[:metric],
        params: args,
        entity: @entity
      )
      
      success_response(
        compiled_query: explanation[:sql],
        lineage: explanation[:lineage],
        estimate_rows: explanation[:estimate_rows]
      )
    end
  end
end
```

---

## Workflow Integration

### New Analytics Workflow Template

```yaml
# app/workflow_templates/analytics_deep_dive_v2.yml
template_version: 2
name: "AI-Powered Analytics Deep Dive"
slug: "analytics_deep_dive_v2"
description: "Analyze business metrics with AI guidance"

phases:
  - id: "understand_question"
    type: "gather_context"
    goal: "Understand what metrics user wants to analyze"
    required_fields:
      - key: "analysis_question"
        prompt: "What would you like to analyze?"
      - key: "time_period"
        prompt: "What time period?"
      - key: "dimensions"
        prompt: "Break down by what? (region, channel, etc.)"
  
  - id: "discover_metrics"
    type: "execute_goal"
    allowed_tools: [list_metrics, explain_query]
    goal: "Find relevant metrics for the question"
  
  - id: "query_data"
    type: "execute_goal"
    allowed_tools: [query_metric]
    goal: "Query metrics safely with budgets enforced"
  
  - id: "visualize"
    type: "execute_goal"
    allowed_tools: [create_dynamic_visualization, aggregate_artifact_data]
    goal: "Create visualizations and insights"
  
  - id: "validation"
    type: "validate_result"
    goal: "Verify data quality and insights accuracy"
```

**Fits perfectly with V2 workflow system!**

---

## Agent Orchestration

### AMOS Delegation Pattern (Same as Today)

```
User: "Show me revenue trends by channel for last 90 days"
  ↓
AMOS analyzes: Complex analysis (multi-step)
  ↓
Uses: delegate_to_planner
  ↓
PlannerAgent: Selects analytics_deep_dive_v2 workflow
  ↓
Workflow executes with GoalExecutor:
  Phase 1: GoalExecutor with [list_metrics]
  Phase 2: GoalExecutor with [query_metric]
  Phase 3: GoalExecutor with [create_dynamic_visualization]
  ↓
Results displayed
```

**SAME PATTERN as integration builder we built today!**

---

## Security Mapping to AMOS

### Multi-Tenancy
```ruby
# Already exists in AMOS:
@entity = current_entity  # Tenant scope

# Analytics enforces:
Analytics::QueryExecutor.execute(
  metric: "revenue",
  entity: @entity,  # Automatic tenant filtering
  user: current_user
)
```

### Row-Level Security (RLS)
```ruby
# In Analytics::QueryExecutor
def build_query(metric, params, entity)
  sql = metric.base_query
  sql += " WHERE tenant_id = ?"  # Always inject
  sql += " AND #{parse_filters(params[:where])}"
  
  # Execute with params (no string interpolation!)
  warehouse.execute(sql, [entity.id, ...])
end
```

### Audit Trail
```ruby
# After every query:
AnalyticsQueryLog.create!(
  entity: entity,
  user: user,
  metric: "revenue",
  query_hash: Digest::SHA256.hexdigest(query),
  params: params,
  rows_returned: result.count,
  execution_time_ms: duration
)
```

---

## Implementation Approach

### Phase 1: Core Analytics Module (Week 1-2)
**Build the analytics engine**:
1. Data models (DataContract, MetricDefinition, etc.)
2. Landing/Conform/Serve layers
3. QueryExecutor (safe, tenant-isolated)
4. CatalogService
5. ContractValidator

**Deliverable**: Standalone module with API endpoints

### Phase 2: Tool Integration (Week 2)
**Connect to AMOS agent system**:
1. Create QueryMetricTool
2. Create ListMetricsTool
3. Create ExplainQueryTool
4. Add to tool catalog
5. Update agent loadouts

**Deliverable**: Agents can query metrics

### Phase 3: Workflows (Week 3)
**Build analytics workflows**:
1. analytics_deep_dive_v2.yml
2. cohort_analysis_v2.yml
3. revenue_forecasting_v2.yml

**Deliverable**: Complex analysis via workflows

### Phase 4: Visualization (Week 3-4)
**Enhanced viz for analytics**:
1. Time series charts
2. Cohort retention grids
3. Funnel visualizations
4. Trend indicators

**Deliverable**: Rich visual analytics

---

## Key Design Decisions

### 1. **Separate Service** ✅
- `app/services/analytics/` module
- Own controllers (`AnalyticsController`)
- Own API endpoints
- Doesn't touch AMOS core

### 2. **DB-Driven Schemas** ✅
- MetricDefinition (JSON schema)
- DataContract (validation rules)
- No arbitrary SQL from agents
- **Same as integration system!**

### 3. **Tool-Based Access** ✅
- Agents use tools (query_metric, list_metrics)
- Tools enforce budgets, RLS
- Logged in AnalyticsQueryLog
- **Same as execute_integration!**

### 4. **Workflow-Driven Analysis** ✅
- Complex analysis via workflows
- Phase executors with scoped tools
- GoalExecutor becomes "Analytics Specialist"
- **Same as integration_builder!**

---

## Architecture Diagram

```
┌──────────────────────────────────────────────────────────┐
│ AMOS Main Chat Agent                                     │
│ Tools: query_metric, list_metrics, delegate_to_planner  │
└────────────────┬─────────────────────────────────────────┘
                 │
    Simple Query │
                 ↓
┌────────────────────────────────────────────────────────────┐
│ QueryMetricTool                                            │
└────────────────┬───────────────────────────────────────────┘
                 │
                 ↓
┌────────────────────────────────────────────────────────────┐
│ Analytics::QueryExecutor (Safe Interpreter)                │
│ - Finds MetricDefinition (DB)                             │
│ - Enforces tenant isolation                               │
│ - Checks budgets & time caps                              │
│ - Builds safe query from schema                           │
│ - Executes via warehouse connector                        │
└────────────────┬───────────────────────────────────────────┘
                 │
                 ↓
┌────────────────────────────────────────────────────────────┐
│ Warehouse / Data Store                                     │
│ - Pre-aggregated metrics (Serve layer)                    │
│ - Tenant-isolated                                          │
│ - Returns rows                                             │
└────────────────────────────────────────────────────────────┘
```

**This mirrors UniversalIntegrationExecutor perfectly!**

---

## Tool Distribution (Following Today's Pattern)

### AMOS Main Chat (Add 3 analytics tools):
```ruby
'main_chat' => {
  tool_allowlist: [
    # Existing 13 tools...
    'query_metric',      # Simple metric queries
    'list_metrics',      # Discover analytics
    'explain_query'      # Understand queries
  ]
}
# Total: 16 tools (still reasonable)
```

### Analytics Workflow Phases:
```yaml
- type: execute_goal
  allowed_tools: [query_metric, list_metrics, explain_query]
  # GoalExecutor becomes "Analytics Specialist"
```

**Follows established agent scoping pattern!**

---

## Database Schema Design

### Following Integration System Pattern

**Integration System**:
```ruby
Integration           # API definition
IntegrationOperation  # Endpoint schema
Connection           # User connection
IntegrationLog       # Audit
```

**Analytics System** (Proposed):
```ruby
DataContract         # Contract definition
  - name: "orders"
  - version: "1.2.0"
  - schema: {...}    # JSON
  - privacy: {...}   # PII rules

MetricDefinition     # Metric schema
  - name: "revenue"
  - version: "2.0.0"
  - expression: "sum(revenue_net_cents)/100.0"
  - dimensions: ["region", "channel"]
  - grain_default: "week"

AnalyticsConnection  # Warehouse connection
  - entity_id
  - connection_type: "postgres|bigquery|snowflake"
  - credentials: {...} # Encrypted

TenantQuota         # Budget limits
  - entity_id
  - row_budget: 1000000
  - window_days_cap: 400
  - qps_limit: 10

AnalyticsQueryLog   # Execution cards
  - entity_id
  - user_id
  - metric: "revenue"
  - query_hash
  - params: {...}
  - rows_returned
  - execution_time_ms
```

**Clean, mirrors proven architecture!**

---

## Implementation Roadmap

### Week 1: Core Module
- [ ] Create Analytics module structure
- [ ] Implement QueryExecutor (safe SQL builder)
- [ ] Create DB models (DataContract, MetricDefinition, etc.)
- [ ] Build CatalogService
- [ ] Implement tenant isolation & RLS

### Week 2: Tool Integration  
- [ ] Create QueryMetricTool
- [ ] Create ListMetricsTool
- [ ] Create ExplainQueryTool
- [ ] Register in ToolCatalog
- [ ] Add to agent loadouts

### Week 3: Workflows
- [ ] Create analytics_deep_dive_v2.yml
- [ ] Create cohort_analysis_v2.yml
- [ ] Test with GoalExecutor
- [ ] Verify budgets enforced

### Week 4: Visualization
- [ ] Enhanced time series viz
- [ ] Cohort grids
- [ ] Trend analysis
- [ ] Integration with existing create_dynamic_visualization

---

## API Endpoint Mapping

### Analytics Module Endpoints:
```ruby
# app/controllers/analytics_controller.rb
POST   /api/analytics/contracts/validate
GET    /api/analytics/catalog
POST   /api/analytics/metrics/query
POST   /api/analytics/metrics/explain
POST   /api/analytics/admin/quotas
POST   /api/analytics/events/audit
```

### Tool → Endpoint Mapping:
```
query_metric    → POST /api/analytics/metrics/query
list_metrics    → GET  /api/analytics/catalog
explain_query   → POST /api/analytics/metrics/explain
validate_data   → POST /api/analytics/contracts/validate
```

---

## Security Integration

### Existing AMOS Security:
- Entity-scoped (multi-tenant) ✅
- IntegrationCredential encryption ✅
- IntegrationLog audit trail ✅
- Connection rate limits ✅

### Analytics Security (Same Pattern):
- Entity-scoped queries (RLS) ✅
- AnalyticsConnection encryption ✅
- AnalyticsQueryLog audit trail ✅
- TenantQuota budgets ✅

**Reuse existing patterns!**

---

## Example User Flows

### Simple Query:
```
User: "What's my revenue this month?"
  ↓
AMOS: query_metric(
  metric: "revenue",
  start_date: "2025-10-01",
  end_date: "2025-10-31",
  time_grain: "month"
)
  ↓
Analytics::QueryExecutor:
  - Validates metric exists
  - Checks tenant quota
  - Builds safe query
  - Enforces RLS (tenant_id filter)
  - Executes
  ↓
Returns: { revenue: $125,450 }
  ↓
AMOS: "Your revenue this month is $125,450"
```

### Complex Analysis:
```
User: "Analyze revenue trends by channel over last 6 months and forecast next quarter"
  ↓
AMOS: delegate_to_planner (complex multi-step)
  ↓
Planner: Creates custom workflow or uses analytics_deep_dive_v2
  ↓
Workflow phases:
  1. GatherContextExecutor: Clarifies question
  2. GoalExecutor with [query_metric, list_metrics]:
     - Queries revenue by channel
     - Gets historical trends
  3. GoalExecutor with [create_dynamic_visualization]:
     - Creates trend chart
     - Adds forecasting model
  4. ValidationExecutor: Checks data quality
  ↓
Results displayed with viz
```

---

## Integration with Existing Features

### Works With:
✅ **Integration System** - Can join Stripe revenue with analytics  
✅ **Workflows** - Analytics workflows like landing_page_creation  
✅ **Agent System** - Uses same GoalExecutor pattern  
✅ **Tools** - Follows same tool structure  
✅ **Visualization** - Uses create_dynamic_visualization  

### Extends:
✅ **aggregate_artifact_data** - Can work with analytics results  
✅ **create_dynamic_visualization** - Enhanced with analytics  
✅ **Canvas system** - New analytics_dashboard canvas  

---

## Key Advantages

### 1. **Consistent Architecture**
- Same as integration system (proven today!)
- Schema-driven (secure)
- Tool-based (discoverable)
- Workflow-enabled (complex tasks)

### 2. **Secure by Design**
- No arbitrary SQL
- Tenant isolation enforced
- Budget limits
- Full audit trail

### 3. **Agent-Friendly**
- Simple tools for simple queries
- Workflows for complex analysis
- Explainable (lineage tracking)
- Discoverable (catalog)

### 4. **Production-Safe**
- Separate module
- No AMOS core changes
- Can version independently
- Can disable if needed

---

## Recommendation

**Build this as Module #2** after launch:

**Timeline**:
- Week 1 post-launch: Core analytics module
- Week 2: Tool integration
- Week 3: Workflows
- Week 4: Polish & visualization

**Approach**:
- Follow **exact same patterns** as integration system
- DB-driven schemas (no code generation)
- Tool-based access (safe executors)
- Workflow-enabled (complex analysis)

**Result**: Production-grade analytics that fits perfectly with AMOS architecture!

---

**Next Steps**:

1. Launch AMOS with current features ✅
2. Week 2: Start analytics module (following integration pattern)
3. Reuse all the architecture patterns from today
4. 4-week implementation following this design

**Thoughts?** This design reuses everything we built today - same patterns, same security model, clean integration.

