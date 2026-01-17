# frozen_string_literal: true

# Seeds pre-built IntegrationAction templates for common integrations
#
# These are GLOBAL templates (entity_id: nil) that any entity can use.
# The mapping_code has been tested and verified to work correctly.

puts "🔧 Seeding Integration Actions..."

# Helper to find or create action
def seed_action(integration_slug:, action_name:, operation_id:, **attrs)
  integration = Integration.find_by(slug: integration_slug)
  unless integration
    puts "  ⚠️  Skipping #{action_name}: Integration '#{integration_slug}' not found"
    return
  end

  operation = integration.integration_operations.find_by(operation_id: operation_id) ||
              integration.integration_operations.find_by(name: operation_id)
  unless operation
    puts "  ⚠️  Skipping #{action_name}: Operation '#{operation_id}' not found"
    return
  end

  action = IntegrationAction.find_or_initialize_by(
    integration: integration,
    action_name: action_name
  )

  action.assign_attributes(
    integration_operation: operation,
    entity_id: nil,  # Global template
    **attrs,
    status: :active,
    mapping_code_generated_by: 'seed'
  )

  if action.save
    puts "  ✅ #{integration_slug}.#{action_name}"
  else
    puts "  ❌ #{action_name}: #{action.errors.full_messages.join(', ')}"
  end
end

# ============================================
# STRIPE ACTIONS
# ============================================

seed_action(
  integration_slug: 'stripe',
  action_name: 'create_customer',
  operation_id: 'stripe.create_customer',
  description: 'Create a new Stripe customer',
  category: 'crm',
  input_schema: [
    { name: 'email', type: 'string', required: true, description: 'Customer email address' },
    { name: 'name', type: 'string', required: false, description: 'Customer full name' },
    { name: 'phone', type: 'string', required: false, description: 'Customer phone number' },
    { name: 'description', type: 'string', required: false, description: 'Internal description' },
    { name: 'metadata', type: 'object', required: false, description: 'Custom key-value pairs' }
  ],
  sample_input: { email: 'test@example.com', name: 'John Doe' },
  sample_output: { email: 'test@example.com', name: 'John Doe' },
  mapping_code: <<~RUBY
    def map(inputs)
      result = {}
      
      result[:email] = normalize_email(inputs[:email])
      result[:name] = inputs[:name] if present?(inputs[:name])
      result[:phone] = format_phone(inputs[:phone]) if present?(inputs[:phone])
      result[:description] = inputs[:description] if present?(inputs[:description])
      result[:metadata] = inputs[:metadata] if present?(inputs[:metadata])
      
      result
    end
  RUBY
)

seed_action(
  integration_slug: 'stripe',
  action_name: 'list_customers',
  operation_id: 'stripe.list_customers',
  description: 'List Stripe customers with optional filters',
  category: 'crm',
  input_schema: [
    { name: 'email', type: 'string', required: false, description: 'Filter by email' },
    { name: 'limit', type: 'integer', required: false, description: 'Max results (1-100)', min: 1, max: 100 },
    { name: 'starting_after', type: 'string', required: false, description: 'Cursor for pagination' },
    { name: 'created_after', type: 'string', required: false, description: 'Filter by creation date (ISO8601)' }
  ],
  sample_input: { limit: 10 },
  sample_output: { limit: 10 },
  mapping_code: <<~RUBY
    def map(inputs)
      result = {}
      
      result[:email] = normalize_email(inputs[:email]) if present?(inputs[:email])
      result[:limit] = default(inputs[:limit], 10)
      result[:starting_after] = inputs[:starting_after] if present?(inputs[:starting_after])
      
      if present?(inputs[:created_after])
        date = parse_datetime(inputs[:created_after])
        result[:created] = { gte: to_unix(date) } if date
      end
      
      result
    end
  RUBY
)

seed_action(
  integration_slug: 'stripe',
  action_name: 'create_charge',
  operation_id: 'stripe.create_charge',
  description: 'Create a charge on a payment source',
  category: 'payment',
  input_schema: [
    { name: 'amount', type: 'number', required: true, description: 'Amount in dollars', min: 0.50 },
    { name: 'currency', type: 'string', required: false, description: 'Currency code (default: usd)' },
    { name: 'customer_id', type: 'string', required: false, description: 'Stripe customer ID' },
    { name: 'source', type: 'string', required: false, description: 'Payment source token' },
    { name: 'description', type: 'string', required: false, description: 'Charge description' },
    { name: 'metadata', type: 'object', required: false, description: 'Custom metadata' }
  ],
  sample_input: { amount: 29.99, customer_id: 'cus_123' },
  sample_output: { amount: 2999, currency: 'usd', customer: 'cus_123' },
  mapping_code: <<~RUBY
    def map(inputs)
      {
        amount: to_cents(inputs[:amount]),
        currency: default(downcase(inputs[:currency]), 'usd'),
        customer: inputs[:customer_id],
        source: inputs[:source],
        description: inputs[:description],
        metadata: inputs[:metadata]
      }.compact
    end
  RUBY
)

seed_action(
  integration_slug: 'stripe',
  action_name: 'create_subscription',
  operation_id: 'stripe.create_subscription',
  description: 'Create a subscription for a customer',
  category: 'billing',
  input_schema: [
    { name: 'customer_id', type: 'string', required: true, description: 'Stripe customer ID' },
    { name: 'price_id', type: 'string', required: true, description: 'Stripe price ID' },
    { name: 'quantity', type: 'integer', required: false, description: 'Subscription quantity', min: 1 },
    { name: 'trial_days', type: 'integer', required: false, description: 'Trial period in days' },
    { name: 'metadata', type: 'object', required: false, description: 'Custom metadata' }
  ],
  sample_input: { customer_id: 'cus_123', price_id: 'price_abc' },
  sample_output: { customer: 'cus_123', items: [{ price: 'price_abc' }] },
  mapping_code: <<~RUBY
    def map(inputs)
      result = {
        customer: inputs[:customer_id],
        items: [
          {
            price: inputs[:price_id],
            quantity: default(inputs[:quantity], 1)
          }
        ]
      }
      
      if present?(inputs[:trial_days])
        result[:trial_period_days] = inputs[:trial_days]
      end
      
      result[:metadata] = inputs[:metadata] if present?(inputs[:metadata])
      
      result
    end
  RUBY
)

seed_action(
  integration_slug: 'stripe',
  action_name: 'list_invoices',
  operation_id: 'stripe.list_invoices',
  description: 'List invoices with optional filters',
  category: 'billing',
  input_schema: [
    { name: 'customer_id', type: 'string', required: false, description: 'Filter by customer' },
    { name: 'status', type: 'enum', required: false, values: %w[draft open paid uncollectible void], description: 'Filter by status' },
    { name: 'limit', type: 'integer', required: false, min: 1, max: 100 },
    { name: 'starting_after', type: 'string', required: false }
  ],
  sample_input: { limit: 20, status: 'open' },
  sample_output: { limit: 20, status: 'open' },
  mapping_code: <<~RUBY
    def map(inputs)
      result = { limit: default(inputs[:limit], 10) }
      
      result[:customer] = inputs[:customer_id] if present?(inputs[:customer_id])
      result[:status] = inputs[:status] if present?(inputs[:status])
      result[:starting_after] = inputs[:starting_after] if present?(inputs[:starting_after])
      
      result
    end
  RUBY
)

seed_action(
  integration_slug: 'stripe',
  action_name: 'refund_charge',
  operation_id: 'stripe.create_refund',
  description: 'Refund a charge (full or partial)',
  category: 'payment',
  input_schema: [
    { name: 'charge_id', type: 'string', required: true, description: 'Charge ID to refund' },
    { name: 'amount', type: 'number', required: false, description: 'Partial refund amount in dollars (omit for full refund)' },
    { name: 'reason', type: 'enum', required: false, values: %w[duplicate fraudulent requested_by_customer], description: 'Refund reason' }
  ],
  sample_input: { charge_id: 'ch_123', amount: 10.00, reason: 'requested_by_customer' },
  sample_output: { charge: 'ch_123', amount: 1000, reason: 'requested_by_customer' },
  mapping_code: <<~RUBY
    def map(inputs)
      result = { charge: inputs[:charge_id] }
      
      result[:amount] = to_cents(inputs[:amount]) if present?(inputs[:amount])
      result[:reason] = inputs[:reason] if present?(inputs[:reason])
      
      result
    end
  RUBY
)

# ============================================
# HUBSPOT ACTIONS
# ============================================

seed_action(
  integration_slug: 'hubspot',
  action_name: 'create_contact',
  operation_id: 'hubspot.create_contact',
  description: 'Create a new HubSpot contact',
  category: 'crm',
  input_schema: [
    { name: 'email', type: 'string', required: true, description: 'Contact email' },
    { name: 'first_name', type: 'string', required: false, description: 'First name' },
    { name: 'last_name', type: 'string', required: false, description: 'Last name' },
    { name: 'phone', type: 'string', required: false, description: 'Phone number' },
    { name: 'company', type: 'string', required: false, description: 'Company name' },
    { name: 'lifecycle_stage', type: 'enum', required: false, values: %w[subscriber lead marketingqualifiedlead salesqualifiedlead opportunity customer evangelist other] }
  ],
  sample_input: { email: 'test@example.com', first_name: 'John', last_name: 'Doe' },
  sample_output: { properties: { email: 'test@example.com', firstname: 'John', lastname: 'Doe' } },
  mapping_code: <<~RUBY
    def map(inputs)
      properties = {}
      
      properties[:email] = normalize_email(inputs[:email])
      properties[:firstname] = inputs[:first_name] if present?(inputs[:first_name])
      properties[:lastname] = inputs[:last_name] if present?(inputs[:last_name])
      properties[:phone] = format_phone(inputs[:phone]) if present?(inputs[:phone])
      properties[:company] = inputs[:company] if present?(inputs[:company])
      properties[:lifecyclestage] = inputs[:lifecycle_stage] if present?(inputs[:lifecycle_stage])
      
      { properties: properties }
    end
  RUBY
)

seed_action(
  integration_slug: 'hubspot',
  action_name: 'update_contact',
  operation_id: 'hubspot.update_contact',
  description: 'Update an existing HubSpot contact',
  category: 'crm',
  input_schema: [
    { name: 'contact_id', type: 'string', required: true, description: 'HubSpot contact ID' },
    { name: 'email', type: 'string', required: false },
    { name: 'first_name', type: 'string', required: false },
    { name: 'last_name', type: 'string', required: false },
    { name: 'phone', type: 'string', required: false },
    { name: 'company', type: 'string', required: false },
    { name: 'lifecycle_stage', type: 'enum', required: false, values: %w[subscriber lead marketingqualifiedlead salesqualifiedlead opportunity customer evangelist other] }
  ],
  sample_input: { contact_id: '123', lifecycle_stage: 'customer' },
  sample_output: { id: '123', properties: { lifecyclestage: 'customer' } },
  mapping_code: <<~RUBY
    def map(inputs)
      properties = {}
      
      properties[:email] = normalize_email(inputs[:email]) if present?(inputs[:email])
      properties[:firstname] = inputs[:first_name] if present?(inputs[:first_name])
      properties[:lastname] = inputs[:last_name] if present?(inputs[:last_name])
      properties[:phone] = format_phone(inputs[:phone]) if present?(inputs[:phone])
      properties[:company] = inputs[:company] if present?(inputs[:company])
      properties[:lifecyclestage] = inputs[:lifecycle_stage] if present?(inputs[:lifecycle_stage])
      
      { id: inputs[:contact_id], properties: properties }
    end
  RUBY
)

seed_action(
  integration_slug: 'hubspot',
  action_name: 'search_contacts',
  operation_id: 'hubspot.search_contacts',
  description: 'Search HubSpot contacts',
  category: 'crm',
  input_schema: [
    { name: 'query', type: 'string', required: false, description: 'Search query (email, name, etc.)' },
    { name: 'email', type: 'string', required: false, description: 'Filter by exact email' },
    { name: 'lifecycle_stage', type: 'string', required: false },
    { name: 'limit', type: 'integer', required: false, min: 1, max: 100 }
  ],
  sample_input: { email: 'test@example.com' },
  sample_output: { filterGroups: [{ filters: [{ propertyName: 'email', operator: 'EQ', value: 'test@example.com' }] }] },
  mapping_code: <<~RUBY
    def map(inputs)
      filters = []
      
      if present?(inputs[:email])
        filters << { propertyName: 'email', operator: 'EQ', value: normalize_email(inputs[:email]) }
      end
      
      if present?(inputs[:lifecycle_stage])
        filters << { propertyName: 'lifecyclestage', operator: 'EQ', value: inputs[:lifecycle_stage] }
      end
      
      result = { limit: default(inputs[:limit], 10) }
      
      if filters.any?
        result[:filterGroups] = [{ filters: filters }]
      end
      
      if present?(inputs[:query]) && filters.empty?
        result[:query] = inputs[:query]
      end
      
      result
    end
  RUBY
)

# ============================================
# SLACK ACTIONS
# ============================================

seed_action(
  integration_slug: 'slack',
  action_name: 'send_message',
  operation_id: 'slack.post_message',
  description: 'Send a message to a Slack channel',
  category: 'messaging',
  input_schema: [
    { name: 'channel', type: 'string', required: true, description: 'Channel name or ID (e.g., #general or C12345)' },
    { name: 'message', type: 'string', required: true, description: 'Message text (supports Slack markdown)' },
    { name: 'username', type: 'string', required: false, description: 'Custom bot username' },
    { name: 'icon_emoji', type: 'string', required: false, description: 'Bot icon emoji (e.g., :robot:)' },
    { name: 'thread_ts', type: 'string', required: false, description: 'Thread timestamp for replies' }
  ],
  sample_input: { channel: '#general', message: 'Hello from AMOS!' },
  sample_output: { channel: '#general', text: 'Hello from AMOS!' },
  mapping_code: <<~RUBY
    def map(inputs)
      result = {
        channel: inputs[:channel],
        text: inputs[:message]
      }
      
      result[:username] = inputs[:username] if present?(inputs[:username])
      result[:icon_emoji] = inputs[:icon_emoji] if present?(inputs[:icon_emoji])
      result[:thread_ts] = inputs[:thread_ts] if present?(inputs[:thread_ts])
      
      result
    end
  RUBY
)

# ============================================
# SHOPIFY ACTIONS  
# ============================================

seed_action(
  integration_slug: 'shopify',
  action_name: 'list_products',
  operation_id: 'shopify.list_products',
  description: 'List Shopify products',
  category: 'ecommerce',
  input_schema: [
    { name: 'limit', type: 'integer', required: false, min: 1, max: 250 },
    { name: 'status', type: 'enum', required: false, values: %w[active archived draft] },
    { name: 'vendor', type: 'string', required: false },
    { name: 'product_type', type: 'string', required: false }
  ],
  sample_input: { limit: 50, status: 'active' },
  sample_output: { limit: 50, status: 'active' },
  mapping_code: <<~RUBY
    def map(inputs)
      result = { limit: default(inputs[:limit], 50) }
      
      result[:status] = inputs[:status] if present?(inputs[:status])
      result[:vendor] = inputs[:vendor] if present?(inputs[:vendor])
      result[:product_type] = inputs[:product_type] if present?(inputs[:product_type])
      
      result
    end
  RUBY
)

seed_action(
  integration_slug: 'shopify',
  action_name: 'list_orders',
  operation_id: 'shopify.list_orders',
  description: 'List Shopify orders',
  category: 'ecommerce',
  input_schema: [
    { name: 'limit', type: 'integer', required: false, min: 1, max: 250 },
    { name: 'status', type: 'enum', required: false, values: %w[open closed cancelled any] },
    { name: 'financial_status', type: 'enum', required: false, values: %w[authorized pending paid partially_paid refunded voided partially_refunded any unpaid] },
    { name: 'fulfillment_status', type: 'enum', required: false, values: %w[shipped partial unshipped any unfulfilled] },
    { name: 'created_at_min', type: 'string', required: false, description: 'ISO8601 date' }
  ],
  sample_input: { limit: 50, status: 'open' },
  sample_output: { limit: 50, status: 'open' },
  mapping_code: <<~RUBY
    def map(inputs)
      result = { limit: default(inputs[:limit], 50) }
      
      result[:status] = inputs[:status] if present?(inputs[:status])
      result[:financial_status] = inputs[:financial_status] if present?(inputs[:financial_status])
      result[:fulfillment_status] = inputs[:fulfillment_status] if present?(inputs[:fulfillment_status])
      
      if present?(inputs[:created_at_min])
        date = parse_datetime(inputs[:created_at_min])
        result[:created_at_min] = to_iso8601(date) if date
      end
      
      result
    end
  RUBY
)

puts "✅ Integration Actions seeded!"

