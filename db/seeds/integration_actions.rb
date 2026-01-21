# frozen_string_literal: true

# Seeds pre-built IntegrationAction templates for common integrations
#
# IMPORTANT: This file runs AFTER integrations.rb
# Actions depend on IntegrationOperations existing first.
#
# These are GLOBAL templates (entity_id: nil) that any entity can use.
# The mapping_code has been tested and verified to work correctly.
#
# HOW TO ADD MORE ACTIONS:
# 1. First, ensure the operation exists in integrations.rb
# 2. Add a seed_action call here with matching operation_id
# 3. Write mapping_code that transforms normalized inputs → API params
# 4. Test with sample_input/sample_output

# Safety check: Skip if IntegrationAction table doesn't exist yet
unless ActiveRecord::Base.connection.table_exists?(:integration_actions)
  puts "⏭️  Skipping integration_actions seed - table doesn't exist yet (run migrations first)"
  return
end

puts "🔧 Seeding Integration Actions..."

# Helper to find or create action
def seed_action(integration_slug:, action_name:, operation_id:, **attrs)
  integration = Integration.find_by(slug: integration_slug)
  unless integration
    puts "  ⚠️  Skipping #{action_name}: Integration '#{integration_slug}' not found"
    return
  end

  # Try to find operation by operation_id or by name
  operation = integration.integration_operations.find_by(operation_id: operation_id) ||
              integration.integration_operations.find_by(name: operation_id)
  unless operation
    puts "  ⚠️  Skipping #{action_name}: Operation '#{operation_id}' not found for #{integration_slug}"
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
    mapping_code_version: 1,
    mapping_code_generated_at: Time.current,
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
# These match operations from integrations.rb
# ============================================

seed_action(
  integration_slug: 'stripe',
  action_name: 'create_customer',
  operation_id: 'stripe.create_customer',  # Matches integrations.rb line 134
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
  operation_id: 'stripe.list_customers',  # Matches integrations.rb line 64
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

# ============================================
# HUBSPOT ACTIONS
# These match operations from integrations.rb
# ============================================

seed_action(
  integration_slug: 'hubspot',
  action_name: 'list_contacts',
  operation_id: 'hubspot.list_contacts.v3',  # Matches integrations.rb line 327
  description: 'List HubSpot contacts with optional filters',
  category: 'crm',
  input_schema: [
    { name: 'limit', type: 'integer', required: false, description: 'Max results (1-100)', min: 1, max: 100 },
    { name: 'after', type: 'string', required: false, description: 'Pagination cursor' },
    { name: 'properties', type: 'array', required: false, description: 'Properties to include in response' }
  ],
  sample_input: { limit: 20, properties: ['email', 'firstname', 'lastname'] },
  sample_output: { limit: 20, properties: ['email', 'firstname', 'lastname'] },
  mapping_code: <<~RUBY
    def map(inputs)
      result = { limit: default(inputs[:limit], 10) }
      
      result[:after] = inputs[:after] if present?(inputs[:after])
      result[:properties] = inputs[:properties] if present?(inputs[:properties])
      
      result
    end
  RUBY
)

# ============================================
# SHOPIFY ACTIONS
# Note: Shopify uses versioned operation IDs
# ============================================

seed_action(
  integration_slug: 'shopify',
  action_name: 'list_products',
  operation_id: 'shopify.list_products.v2024-01',  # Matches integrations.rb line 230 (with version)
  description: 'List Shopify products',
  category: 'ecommerce',
  input_schema: [
    { name: 'limit', type: 'integer', required: false, min: 1, max: 250, description: 'Max results (1-250)' },
    { name: 'status', type: 'enum', required: false, values: %w[active archived draft], description: 'Filter by status' },
    { name: 'vendor', type: 'string', required: false, description: 'Filter by vendor' },
    { name: 'product_type', type: 'string', required: false, description: 'Filter by product type' }
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

# ============================================
# SLACK ACTIONS
# ============================================

seed_action(
  integration_slug: 'slack',
  action_name: 'send_webhook_message',
  operation_id: 'slack.post_webhook_message.v1',  # Matches integrations.rb line 443
  description: 'Send a message to Slack via webhook',
  category: 'messaging',
  input_schema: [
    { name: 'message', type: 'string', required: true, description: 'Message text (supports Slack markdown)' },
    { name: 'channel', type: 'string', required: false, description: 'Override default channel' },
    { name: 'blocks', type: 'array', required: false, description: 'Rich message blocks (Block Kit)' }
  ],
  sample_input: { message: 'Hello from AMOS!' },
  sample_output: { text: 'Hello from AMOS!' },
  mapping_code: <<~RUBY
    def map(inputs)
      result = { text: inputs[:message] }
      
      result[:channel] = inputs[:channel] if present?(inputs[:channel])
      result[:blocks] = inputs[:blocks] if present?(inputs[:blocks])
      
      result
    end
  RUBY
)

# ============================================
# GMAIL ACTIONS
# ============================================

seed_action(
  integration_slug: 'gmail',
  action_name: 'list_messages',
  operation_id: 'gmail.list_messages.v1',  # Matches integrations.rb line 548
  description: 'List Gmail messages',
  category: 'email',
  input_schema: [
    { name: 'query', type: 'string', required: false, description: 'Search query (same as Gmail search)' },
    { name: 'limit', type: 'integer', required: false, min: 1, max: 500, description: 'Max results' },
    { name: 'label_ids', type: 'array', required: false, description: 'Filter by label IDs' }
  ],
  sample_input: { query: 'is:unread', limit: 10 },
  sample_output: { q: 'is:unread', maxResults: 10 },
  mapping_code: <<~RUBY
    def map(inputs)
      result = {}
      
      result[:q] = inputs[:query] if present?(inputs[:query])
      result[:maxResults] = default(inputs[:limit], 100)
      result[:labelIds] = inputs[:label_ids] if present?(inputs[:label_ids])
      
      result
    end
  RUBY
)

seed_action(
  integration_slug: 'gmail',
  action_name: 'get_message',
  operation_id: 'gmail.get_message.v1',  # Matches integrations.rb line 585
  description: 'Get a specific Gmail message',
  category: 'email',
  input_schema: [
    { name: 'message_id', type: 'string', required: true, description: 'Gmail message ID' },
    { name: 'format', type: 'enum', required: false, values: %w[minimal full raw metadata], description: 'Response format' }
  ],
  sample_input: { message_id: '123abc', format: 'full' },
  sample_output: { id: '123abc', format: 'full' },
  mapping_code: <<~RUBY
    def map(inputs)
      {
        id: inputs[:message_id],
        format: default(inputs[:format], 'full')
      }
    end
  RUBY
)

# ============================================
# GOOGLE DRIVE ACTIONS
# ============================================

seed_action(
  integration_slug: 'google_drive',
  action_name: 'list_files',
  operation_id: 'google_drive.list_files.v3',  # Matches integrations.rb line 659
  description: 'List files and folders in Google Drive',
  category: 'storage',
  input_schema: [
    { name: 'query', type: 'string', required: false, description: 'Search query' },
    { name: 'limit', type: 'integer', required: false, min: 1, max: 1000, description: 'Max results' },
    { name: 'order_by', type: 'string', required: false, description: 'Sort order (e.g., "modifiedTime desc")' },
    { name: 'fields', type: 'string', required: false, description: 'Fields to include' }
  ],
  sample_input: { limit: 50, order_by: 'modifiedTime desc' },
  sample_output: { pageSize: 50, orderBy: 'modifiedTime desc' },
  mapping_code: <<~RUBY
    def map(inputs)
      result = {}
      
      result[:q] = inputs[:query] if present?(inputs[:query])
      result[:pageSize] = default(inputs[:limit], 100)
      result[:orderBy] = inputs[:order_by] if present?(inputs[:order_by])
      result[:fields] = inputs[:fields] if present?(inputs[:fields])
      
      result
    end
  RUBY
)

seed_action(
  integration_slug: 'google_drive',
  action_name: 'create_folder',
  operation_id: 'google_drive.create_folder.v3',  # Matches integrations.rb line 699
  description: 'Create a new folder in Google Drive',
  category: 'storage',
  input_schema: [
    { name: 'name', type: 'string', required: true, description: 'Folder name' },
    { name: 'parent_folder_id', type: 'string', required: false, description: 'Parent folder ID' }
  ],
  sample_input: { name: 'My New Folder' },
  sample_output: { name: 'My New Folder', mimeType: 'application/vnd.google-apps.folder' },
  mapping_code: <<~RUBY
    def map(inputs)
      result = {
        name: inputs[:name],
        mimeType: 'application/vnd.google-apps.folder'
      }
      
      if present?(inputs[:parent_folder_id])
        result[:parents] = [inputs[:parent_folder_id]]
      end
      
      result
    end
  RUBY
)

# ============================================
# QUICKBOOKS ACTIONS
# ============================================

seed_action(
  integration_slug: 'quickbooks',
  action_name: 'list_customers',
  operation_id: 'quickbooks.list_customers.v3',  # Matches integrations.rb line 868
  description: 'List QuickBooks customers',
  category: 'accounting',
  input_schema: [
    { name: 'limit', type: 'integer', required: false, min: 1, max: 1000, description: 'Max results' },
    { name: 'start_position', type: 'integer', required: false, description: 'Starting position for pagination' },
    { name: 'custom_query', type: 'string', required: false, description: 'Custom SQL-like query' }
  ],
  sample_input: { limit: 100 },
  sample_output: { query: 'SELECT * FROM Customer MAXRESULTS 100', maxResults: 100 },
  mapping_code: <<~RUBY
    def map(inputs)
      limit = default(inputs[:limit], 100)
      start = default(inputs[:start_position], 1)
      
      if present?(inputs[:custom_query])
        query = inputs[:custom_query]
      else
        query = "SELECT * FROM Customer STARTPOSITION \#{start} MAXRESULTS \#{limit}"
      end
      
      { query: query, startPosition: start, maxResults: limit }
    end
  RUBY
)

seed_action(
  integration_slug: 'quickbooks',
  action_name: 'get_company_info',
  operation_id: 'quickbooks.get_company_info.v3',  # Matches integrations.rb line 903
  description: 'Get QuickBooks company information',
  category: 'accounting',
  input_schema: [],  # No inputs needed
  sample_input: {},
  sample_output: {},
  mapping_code: <<~RUBY
    def map(inputs)
      {}  # No parameters needed - companyId is handled by path template
    end
  RUBY
)

puts "✅ Integration Actions seeded!"
puts "   Actions created: #{IntegrationAction.count}"
