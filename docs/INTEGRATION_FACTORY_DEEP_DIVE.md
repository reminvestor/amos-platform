# Integration Factory Deep Dive

## Executive Summary

The integration system has more infrastructure than initially thought. The ETL/iPaaS architecture with deterministic code execution already exists for **data syncing**. The gap is in making **API operations** equally deterministic for Amos.

**What Exists:**
- ✅ `IntegrationAgentGenerator` - Creates trained expert agents with RAG knowledge
- ✅ `IntegrationSyncConfig` - Recipe for syncing data between systems  
- ✅ `EtlPipelineService` - Full Extract-Transform-Load pipeline
- ✅ `TransformCodeExecutor` - Sandboxed execution of AI-generated Ruby code
- ✅ `TransformContext` - 30+ safe helpers for data transformation
- ✅ `GenerateTransformCodeTool` - AI generates Ruby code, tests it, saves it

**What's Now Built (IntegrationAction Layer):**
- ✅ **IntegrationAction model** - Pre-defined, tested operation templates
- ✅ **ActionCodeExecutor** - Sandboxed execution mirroring TransformCodeExecutor
- ✅ **ActionContext** - 40+ helpers including API-specific formatting
- ✅ **execute_integration_action tool** - Normalized interface for Amos
- ✅ **generate_action_mapping tool** - AI generates mapping code
- ✅ **Pre-built action library** - Stripe, HubSpot, Gmail, Google Drive, QuickBooks, Slack, Shopify

**Still TODO:**
- ⏳ **Design mode for actions** - Visual builder in Design Space
- ⏳ **Response normalization** - Currently optional, could be default

---

## Current Architecture (What Exists)

### Integration Agent Pipeline

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    INTEGRATION SETUP FLOW                                │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  1. CREATE INTEGRATION                                                   │
│     ├── IntegrationFactory validates & creates                          │
│     ├── OauthConfiguration for auth                                     │
│     └── IntegrationOperations for endpoints                             │
│                                                                          │
│  2. CREATE AGENT (IntegrationAgentGenerator)                            │
│     ├── AgentFactory.create() with system prompt                        │
│     ├── Loads INTEGRATION_KNOWLEDGE for known integrations              │
│     ├── seed_knowledge_base() - adds API docs to RAG                    │
│     └── setup_learning() - energy state + decision boundary             │
│                                                                          │
│  3. TRAIN AGENT                                                          │
│     ├── Upload API docs to RAG store                                    │
│     ├── Agent learns from interactions                                  │
│     └── Improves over time with AgentLearningService                    │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

### ETL Pipeline (Already Deterministic!)

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    ETL SYNC FLOW (NO AI AT RUNTIME)                      │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  IntegrationSyncConfig                                                   │
│  ├── resource_type: 'customers'                                         │
│  ├── target_type: 'Contact'                                             │
│  ├── field_mappings: { 'email' => 'email', 'name' => 'full_name' }     │
│  ├── transform_code: <AI-GENERATED RUBY>                                │
│  └── sync_mode: 'incremental'                                           │
│                                                                          │
│                          ▼                                               │
│                                                                          │
│  EtlPipelineService.run!                                                 │
│  ├── EXTRACT: UniversalIntegrationExecutor.execute(operation, params)   │
│  ├── TRANSFORM: TransformCodeExecutor.transform(record) ← Pure Ruby!   │
│  └── LOAD: upsert_record() to internal model                            │
│                                                                          │
│                          ▼                                               │
│                                                                          │
│  TransformSandbox (5s timeout, 1MB limit)                               │
│  ├── TransformContext provides safe helpers                             │
│  └── No AI calls - just Ruby execution                                  │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

### TransformContext Helpers (Already Exists)

| Category | Helpers |
|----------|---------|
| **Navigation** | `get(path)`, `record[]` |
| **Strings** | `titleize`, `downcase`, `upcase`, `strip`, `slugify`, `truncate`, `format(template)` |
| **Numbers** | `to_cents`, `to_dollars`, `round` |
| **Dates** | `parse_date`, `parse_datetime`, `from_unix`, `to_unix`, `today`, `now` |
| **Arrays** | `first`, `last`, `join`, `split` |
| **Conditionals** | `present?`, `blank?`, `default(val, fallback)` |
| **Lookups** | `lookup_contact_by_email`, `lookup_user_by_email` |
| **Mapping** | `map_value`, `build_hash`, `merge` |

---

## The Gap: Ad-hoc API Operations

### Current Problem

When Amos wants to execute an operation (not a sync), the flow is:

```
User: "Place a limit order on Coinbase for 0.001 BTC at $50,000"
                    ▼
Amos: execute_integration(
  integration: "coinbase",
  operation: "create_order",    ← Which operation? 
  params: {
    product_id: "BTC-USD",      ← Or is it 'symbol'? 'pair'?
    side: "buy",                ← Or "BUY"?
    size: "0.001",              ← Or 'quantity'? 'amount'?
    price: "50000"              ← String or number? Cents?
  }
)
                    ▼
UniversalIntegrationExecutor
                    ▼
API call... might work, might not
```

**The problem**: Amos has to figure out the API-specific parameter names, types, and formats every time.

---

## Solution: IntegrationAction Layer

### The Pattern (Mirrors Existing ETL)

Just like `TransformCodeExecutor` runs AI-generated code for transformations, we need `ActionCodeExecutor` for parameter mapping:

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    NEW: ACTION EXECUTION FLOW                            │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  User: "Place a limit order for 0.001 BTC at $50,000"                   │
│                          ▼                                               │
│                                                                          │
│  Amos calls: execute_integration_action(                                │
│    integration: "coinbase",                                              │
│    action: "place_limit_order",     ← Normalized action name            │
│    inputs: {                                                             │
│      symbol: "BTC/USD",             ← Normalized format                 │
│      side: "buy",                   ← Always lowercase                  │
│      quantity: 0.001,               ← Always a number                   │
│      price: 50000.00                ← Always in dollars                 │
│    }                                                                     │
│  )                                                                       │
│                          ▼                                               │
│                                                                          │
│  IntegrationAction (database record)                                     │
│  ├── action_name: 'place_limit_order'                                   │
│  ├── integration_operation_id: 123 (create_order)                       │
│  ├── input_schema: [symbol, side, quantity, price]                      │
│  └── mapping_code: <AI-GENERATED RUBY>                                  │
│                          ▼                                               │
│                                                                          │
│  ActionCodeExecutor.execute(inputs)                                     │
│  ├── ActionSandbox (mirrors TransformSandbox)                           │
│  ├── ActionContext (extends TransformContext with more helpers)         │
│  └── Returns: { product_id: "BTC-USD", side: "BUY", size: "0.001", ... }│
│                          ▼                                               │
│                                                                          │
│  UniversalIntegrationExecutor.execute(operation, mapped_params)         │
│                          ▼                                               │
│                                                                          │
│  API Response                                                            │
│                          ▼                                               │
│                                                                          │
│  Response normalization (optional mapping_code for response)            │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## Implementation Plan

### Phase 1: Core Models & Executor (Leverage Existing Code)

```ruby
# db/migrate/xxx_create_integration_actions.rb
create_table :integration_actions do |t|
  t.references :integration, null: false, foreign_key: true
  t.references :integration_operation, null: false, foreign_key: true
  t.references :entity, foreign_key: true  # nil = global template
  
  t.string :action_name, null: false      # "place_limit_order"
  t.string :slug, null: false             # "coinbase.place_limit_order"
  t.text :description
  
  # Input schema (what Amos provides)
  t.jsonb :input_schema, default: []      # [{name, type, required, description}]
  
  # AI-generated Ruby code for mapping inputs → API params
  t.text :mapping_code
  t.string :mapping_code_version
  t.datetime :mapping_code_generated_at
  
  # Optional: AI-generated Ruby code for normalizing response
  t.text :response_mapping_code
  
  # Sample data for testing
  t.jsonb :sample_input, default: {}
  t.jsonb :sample_output, default: {}
  t.jsonb :sample_response, default: {}
  
  t.integer :status, default: 0           # draft, testing, active, deprecated
  t.integer :usage_count, default: 0
  t.integer :success_count, default: 0
  t.integer :error_count, default: 0
  
  t.timestamps
end

add_index :integration_actions, [:integration_id, :action_name], unique: true
add_index :integration_actions, :slug, unique: true
```

### Phase 2: ActionCodeExecutor (Copy TransformCodeExecutor Pattern)

```ruby
# app/services/integrations/action_code_executor.rb
module Integrations
  class ActionCodeExecutor
    # Mirrors TransformCodeExecutor exactly
    # Uses ActionSandbox and ActionContext
    
    def map_inputs(inputs)
      # Run mapping_code to convert normalized inputs → API params
    end
    
    def normalize_response(response)
      # Run response_mapping_code to normalize API response
    end
  end
  
  class ActionContext < TransformContext
    # Extends TransformContext with integration-specific helpers
    
    # Trading helpers
    def normalize_trading_pair(pair, format: :hyphen)
      # "BTC/USD" → "BTC-USD" or "BTCUSD"
    end
    
    # API format helpers
    def to_api_enum(value, mapping)
      # "buy" → "BUY" based on mapping
    end
    
    def to_api_decimal(value, precision: 8)
      # 0.001 → "0.00100000"
    end
  end
end
```

### Phase 3: New Tool - execute_integration_action

```ruby
module Tools
  class ExecuteIntegrationActionTool < BaseTool
    def execute(args)
      action = IntegrationAction.find_by!(
        integration: find_integration(args['integration']),
        action_name: args['action']
      )
      
      # Validate inputs against schema
      validation = validate_inputs(args['inputs'], action.input_schema)
      return error_response(validation[:errors]) unless validation[:valid]
      
      # Map inputs to API params using AI-generated code
      executor = Integrations::ActionCodeExecutor.new(action)
      mapped = executor.map_inputs(args['inputs'])
      
      # Execute the underlying operation
      result = UniversalIntegrationExecutor.execute(
        integration: action.integration,
        operation: action.integration_operation.operation_id,
        params: mapped[:params],
        user: @user,
        entity: @entity
      )
      
      # Normalize response if mapping exists
      if result[:success] && action.response_mapping_code.present?
        result[:data] = executor.normalize_response(result[:data])
      end
      
      result
    end
  end
end
```

### Phase 4: AI-Assisted Action Creation

```ruby
module Tools
  class GenerateActionMappingTool < BaseTool
    # Mirrors GenerateTransformCodeTool
    
    def execute(args)
      # Query RAG store for API documentation
      docs = query_integration_docs(args['integration'], args['action'])
      
      # Generate mapping code using AI
      code = generate_mapping_code(
        action_name: args['action'],
        input_schema: args['input_schema'],
        api_docs: docs,
        sample_api_params: args['sample_params']
      )
      
      # Test the code
      test_result = test_mapping_code(code, args['sample_input'])
      
      # Save to IntegrationAction
      save_action(args['integration_id'], code, test_result)
    end
  end
end
```

### Phase 5: Pre-built Action Library

Create actions for common operations across major integrations:

| Integration | Actions |
|-------------|---------|
| **Stripe** | `create_customer`, `charge_card`, `create_subscription`, `list_invoices`, `refund_charge` |
| **HubSpot** | `create_contact`, `update_deal`, `add_note`, `list_companies`, `search_contacts` |
| **Shopify** | `create_order`, `update_product`, `list_customers`, `adjust_inventory` |
| **QuickBooks** | `create_invoice`, `record_payment`, `get_balance`, `list_transactions` |
| **Coinbase** | `place_limit_order`, `place_market_order`, `get_balance`, `list_trades`, `cancel_order` |
| **Slack** | `send_message`, `create_channel`, `add_reaction`, `upload_file` |
| **Gmail** | `send_email`, `search_emails`, `add_label`, `create_draft` |
| **Twilio** | `send_sms`, `make_call`, `lookup_phone`, `get_messages` |

### Phase 6: Design Mode Integration

Add to Design Space:
- Action builder canvas
- API docs loader
- Test panel
- Visual mapping editor

---

## Relationship to Existing Components

| Existing Component | New Component | Relationship |
|--------------------|---------------|--------------|
| `TransformCodeExecutor` | `ActionCodeExecutor` | Same pattern, different purpose |
| `TransformContext` | `ActionContext` | Extends with API-specific helpers |
| `TransformSandbox` | `ActionSandbox` | Same sandbox, different code |
| `GenerateTransformCodeTool` | `GenerateActionMappingTool` | Same pattern |
| `IntegrationSyncConfig` | `IntegrationAction` | Sync vs. ad-hoc operations |
| `EtlPipelineService` | `ActionExecutionService` | Batch vs. single operation |

---

## Migration Path

1. **Existing `execute_integration` calls continue to work** - No breaking changes
2. **New `execute_integration_action` is opt-in** - Gradually migrate operations
3. **Integration agents get updated prompts** - Prefer actions when available
4. **Fallback to raw operations** - If no action template exists

---

## Benefits

| Before | After |
|--------|-------|
| Amos guesses at parameter names | Normalized input schema |
| Amos guesses at formats | AI-generated mapping code |
| Inconsistent error handling | Structured validation |
| No learning from failures | Action success/error tracking |
| Every call is ad-hoc | Pre-tested action templates |
| Design mode limited to sync | Full action builder |

---

## Implementation Priority

### Week 1: Foundation
- [ ] Create `IntegrationAction` model
- [ ] Create `IntegrationActionExecution` model (audit)
- [ ] Port `TransformCodeExecutor` → `ActionCodeExecutor`
- [ ] Create `ActionContext` with extended helpers
- [ ] Create `execute_integration_action` tool
- [ ] Write tests

### Week 2: AI Generation
- [ ] Create `GenerateActionMappingTool`
- [ ] Integrate with RAG store for API docs
- [ ] Add test execution
- [ ] Add response normalization

### Week 3: Pre-built Library
- [ ] Create 5+ actions for Stripe
- [ ] Create 5+ actions for HubSpot
- [ ] Create 5+ actions for Shopify
- [ ] Seed as templates

### Week 4: Design Mode
- [ ] Action builder canvas
- [ ] Visual schema editor
- [ ] Test panel
- [ ] Integration with Frontend Design Expert

---

## Migration from Existing Setup

### Relationship to Existing Components

```
EXISTING (db/seeds/integrations.rb)           NEW (db/seeds/integration_actions.rb)
─────────────────────────────────────        ───────────────────────────────────────

┌─────────────────┐                          ┌─────────────────────┐
│   Integration   │                          │  IntegrationAction  │
│   (Stripe)      │◄──────────────┐          │  (list_customers)   │
└─────────────────┘               │          └─────────────────────┘
        │                         │                    │
        │ 1:many                  │ belongs_to         │ belongs_to
        ▼                         │                    ▼
┌────────────────────────┐        └────────┌────────────────────────┐
│  IntegrationOperation  │◄────────────────│  IntegrationOperation  │
│  (stripe.list_customers)                 │  (the underlying op)   │
└────────────────────────┘                 └────────────────────────┘
```

### Nothing is Replaced

- **`execute_integration` tool** continues to work exactly as before
- **Operations** are still the foundation
- **Actions** are an optional layer ON TOP of operations

### Migration Path

1. **Run migrations:** `rails db:migrate`
2. **Run seeds:** Seeds load in order:
   - `integrations.rb` creates Integration + IntegrationOperation records
   - `integration_actions.rb` creates IntegrationAction records that reference operations
3. **Gradual adoption:** Update agent prompts to prefer `execute_integration_action` when an action exists
4. **Fallback:** If no action exists, `execute_integration` still works

### How to Add Missing Operations

Some actions need operations that don't exist yet. Add them to `integrations.rb`:

```ruby
# Example: Add stripe.create_charge
stripe.integration_operations.find_or_create_by!(
  operation_id: 'stripe.create_charge'
) do |op|
  op.name = 'Create Charge'
  op.description = 'Create a charge on a payment source'
  op.http_method = 'POST'
  op.path_template = '/v1/charges'
  op.is_idempotent = false
  op.requires_confirmation = true
  op.request_schema = {
    type: 'object',
    required: ['amount', 'currency'],
    properties: {
      amount: { type: 'integer', description: 'Amount in cents' },
      currency: { type: 'string', description: 'Three-letter currency code' },
      customer: { type: 'string' },
      source: { type: 'string' }
    }
  }
end
```

Then add the action in `integration_actions.rb`:

```ruby
seed_action(
  integration_slug: 'stripe',
  action_name: 'create_charge',
  operation_id: 'stripe.create_charge',
  input_schema: [
    { name: 'amount', type: 'number', required: true, description: 'Amount in DOLLARS' },
    { name: 'currency', type: 'string', required: false },
    { name: 'customer_id', type: 'string', required: false }
  ],
  mapping_code: <<~RUBY
    def map(inputs)
      {
        amount: to_cents(inputs[:amount]),  # Convert dollars → cents
        currency: default(inputs[:currency], 'usd'),
        customer: inputs[:customer_id]
      }.compact
    end
  RUBY
)
```

---

## Questions Resolved

1. **Should actions be entity-specific or global?**
   → Both: Global templates (entity_id: nil) + entity customizations

2. **How do we handle auth?**
   → Auth is connection-level, actions reference connections when executed

3. **What about webhooks?**
   → Future: WebhookAction for inbound, separate from outbound actions

4. **How do we version actions?**
   → `mapping_code_version` + `status` (draft → testing → active → deprecated)

5. **Why trading/crypto examples?**
   → Just used as clear illustration of the problem. Focus is on Stripe, HubSpot, etc.
