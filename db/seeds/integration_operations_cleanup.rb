# frozen_string_literal: true

# Integration Operations Cleanup Seed
# 
# This seed file:
# 1. AGGRESSIVELY cleans up duplicate operations (by endpoint, not operation_id)
# 2. Adds proper request schemas with correct parameters
# 3. Runs after integrations.rb and integration_actions.rb
#
# Run with: rails db:seed
# Or standalone: rails runner db/seeds/integration_operations_cleanup.rb

puts "=" * 60
puts "🔧 INTEGRATION OPERATIONS CLEANUP"
puts "=" * 60

# Normalize path template to catch duplicates with different param names
# e.g., /v1/customers/{customer_id} and /v1/customers/{id} → /v1/customers/{id}
def normalize_path(path)
  return path unless path
  # Replace any {param_name} with {id} for comparison
  path.gsub(/\{[^}]+\}/, '{id}')
end

# Helper to clean up duplicates by endpoint (method + normalized path)
def cleanup_duplicate_endpoints(integration)
  return 0 unless integration
  
  deleted = 0
  by_endpoint = integration.integration_operations.group_by { |op| [op.http_method, normalize_path(op.path_template)] }
  duplicates = by_endpoint.select { |_k, v| v.count > 1 }
  
  duplicates.each do |(_method, _path), ops|
    # Score each operation - prefer prefixed, with schema, enabled
    best = ops.max_by do |op|
      score = 0
      score += 100 if op.operation_id.start_with?("#{integration.slug}.")  # Prefer prefixed
      score += 50 if op.request_schema.present? && op.request_schema['properties'].present?
      score += 25 if op.is_enabled?
      score += 10 if op.operation_id.exclude?(' ')  # Prefer no spaces
      score
    end
    
    # Delete all but the best
    (ops - [best]).each do |dup|
      puts "   🗑️  Deleting duplicate: #{dup.operation_id} (keeping #{best.operation_id})"
      
      # Reassign any related records to the best operation before deleting
      if defined?(IntegrationLog) && IntegrationLog.table_exists?
        IntegrationLog.where(integration_operation_id: dup.id).update_all(integration_operation_id: best.id)
      end
      if defined?(IntegrationAction) && IntegrationAction.table_exists?
        IntegrationAction.where(integration_operation_id: dup.id).update_all(integration_operation_id: best.id)
      end
      
      dup.destroy!
      deleted += 1
    end
  end
  
  deleted
end

# ============================================================
# STRIPE OPERATIONS
# ============================================================

stripe = Integration.find_by(slug: 'stripe')

if stripe
  puts "\n📦 Stripe Integration"
  
  # FIRST: Clean up duplicates before anything else
  deleted = cleanup_duplicate_endpoints(stripe)
  puts "   Removed #{deleted} duplicate operations" if deleted > 0
  
  # Update integration-level metadata for currency handling
  stripe.update!(metadata: (stripe.metadata || {}).merge({
    'currency_handling' => {
      'amounts_in_cents' => true,
      'divisor' => 100,
      'currency_field' => 'currency',
      'common_currency_fields' => ['amount', 'amount_due', 'amount_paid', 'total', 'subtotal', 'unit_amount', 'fee', 'net'],
      'note' => 'Stripe returns all amounts in smallest currency unit (cents for USD). Divide by 100 for display.'
    }
  }))
  puts "   ✅ Updated integration metadata for currency handling"
  
  # Stripe schemas - based on https://stripe.com/docs/api
  # IMPORTANT: Stripe returns amounts in cents (smallest currency unit)
  # response_formatting tells the display layer how to format fields
  stripe_schemas = {
    'stripe.list_charges' => {
      'type' => 'object',
      'properties' => {
        'limit' => { 'type' => 'integer', 'description' => 'Number of records (1-100)', 'default' => 10 },
        'starting_after' => { 'type' => 'string', 'description' => 'Cursor for pagination (charge ID)' },
        'ending_before' => { 'type' => 'string', 'description' => 'Cursor for pagination (charge ID)' },
        'created' => { 'type' => 'object', 'description' => 'Filter by created date (gte, lte)' },
        'customer' => { 'type' => 'string', 'description' => 'Filter by customer ID' },
        'payment_intent' => { 'type' => 'string', 'description' => 'Filter by payment intent ID' }
      },
      # Mark known-bad parameters
      'deprecated_params' => ['order', 'sort', 'sort_by', 'order_by', 'direction', 'desc', 'asc'],
      # Response formatting hints - tells display layer how to format fields
      'response_formatting' => {
        'currency_fields' => ['amount', 'amount_captured', 'amount_refunded', 'application_fee_amount'],
        'currency_divisor' => 100,
        'currency_field' => 'currency',
        'timestamp_fields' => ['created']
      }
    },
    'stripe.list_customers' => {
      'type' => 'object',
      'properties' => {
        'limit' => { 'type' => 'integer', 'description' => 'Number of records (1-100)', 'default' => 10 },
        'starting_after' => { 'type' => 'string', 'description' => 'Cursor for pagination' },
        'ending_before' => { 'type' => 'string', 'description' => 'Cursor for pagination' },
        'email' => { 'type' => 'string', 'description' => 'Filter by email' },
        'created' => { 'type' => 'object', 'description' => 'Filter by created date' }
      },
      'deprecated_params' => ['order', 'sort', 'sort_by']
    },
    'stripe.list_invoices' => {
      'type' => 'object',
      'properties' => {
        'limit' => { 'type' => 'integer', 'description' => 'Number of records (1-100)', 'default' => 10 },
        'starting_after' => { 'type' => 'string', 'description' => 'Cursor for pagination' },
        'customer' => { 'type' => 'string', 'description' => 'Filter by customer ID' },
        'status' => { 'type' => 'string', 'enum' => ['draft', 'open', 'paid', 'uncollectible', 'void'] },
        'subscription' => { 'type' => 'string', 'description' => 'Filter by subscription ID' }
      },
      'deprecated_params' => ['order', 'sort'],
      'response_formatting' => {
        'currency_fields' => ['amount_due', 'amount_paid', 'amount_remaining', 'subtotal', 'total', 'tax'],
        'currency_divisor' => 100,
        'currency_field' => 'currency',
        'timestamp_fields' => ['created', 'due_date', 'period_start', 'period_end']
      }
    },
    'stripe.list_payment_intents' => {
      'type' => 'object',
      'properties' => {
        'limit' => { 'type' => 'integer', 'description' => 'Number of records (1-100)', 'default' => 10 },
        'starting_after' => { 'type' => 'string', 'description' => 'Cursor for pagination' },
        'customer' => { 'type' => 'string', 'description' => 'Filter by customer ID' },
        'created' => { 'type' => 'object', 'description' => 'Filter by created date' }
      },
      'deprecated_params' => ['order', 'sort'],
      'response_formatting' => {
        'currency_fields' => ['amount', 'amount_capturable', 'amount_received'],
        'currency_divisor' => 100,
        'currency_field' => 'currency',
        'timestamp_fields' => ['created']
      }
    },
    'stripe.list_subscriptions' => {
      'type' => 'object',
      'properties' => {
        'limit' => { 'type' => 'integer', 'description' => 'Number of records (1-100)', 'default' => 10 },
        'starting_after' => { 'type' => 'string', 'description' => 'Cursor for pagination' },
        'customer' => { 'type' => 'string', 'description' => 'Filter by customer ID' },
        'status' => { 'type' => 'string', 'enum' => ['active', 'past_due', 'unpaid', 'canceled', 'incomplete', 'trialing', 'all'] },
        'price' => { 'type' => 'string', 'description' => 'Filter by price ID' }
      },
      'deprecated_params' => ['order', 'sort'],
      'response_formatting' => {
        'currency_fields' => ['items.data[].price.unit_amount'],
        'currency_divisor' => 100,
        'timestamp_fields' => ['created', 'current_period_start', 'current_period_end', 'canceled_at', 'ended_at']
      }
    },
    'stripe.list_products' => {
      'type' => 'object',
      'properties' => {
        'limit' => { 'type' => 'integer', 'description' => 'Number of records (1-100)', 'default' => 10 },
        'starting_after' => { 'type' => 'string', 'description' => 'Cursor for pagination' },
        'active' => { 'type' => 'boolean', 'description' => 'Filter by active status' }
      },
      'deprecated_params' => ['order', 'sort']
    },
    'stripe.list_prices' => {
      'type' => 'object',
      'properties' => {
        'limit' => { 'type' => 'integer', 'description' => 'Number of records (1-100)', 'default' => 10 },
        'starting_after' => { 'type' => 'string', 'description' => 'Cursor for pagination' },
        'product' => { 'type' => 'string', 'description' => 'Filter by product ID' },
        'active' => { 'type' => 'boolean', 'description' => 'Filter by active status' },
        'type' => { 'type' => 'string', 'enum' => ['one_time', 'recurring'] }
      },
      'deprecated_params' => ['order', 'sort'],
      'response_formatting' => {
        'currency_fields' => ['unit_amount', 'unit_amount_decimal'],
        'currency_divisor' => 100,
        'currency_field' => 'currency',
        'timestamp_fields' => ['created']
      }
    },
    'stripe.list_balance_transactions' => {
      'type' => 'object',
      'properties' => {
        'limit' => { 'type' => 'integer', 'description' => 'Number of records (1-100)', 'default' => 10 },
        'starting_after' => { 'type' => 'string', 'description' => 'Cursor for pagination' },
        'type' => { 'type' => 'string', 'description' => 'Filter by transaction type' },
        'payout' => { 'type' => 'string', 'description' => 'Filter by payout ID' }
      },
      'deprecated_params' => ['order', 'sort'],
      'response_formatting' => {
        'currency_fields' => ['amount', 'fee', 'net'],
        'currency_divisor' => 100,
        'currency_field' => 'currency',
        'timestamp_fields' => ['created', 'available_on']
      }
    },
    'stripe.list_payouts' => {
      'type' => 'object',
      'properties' => {
        'limit' => { 'type' => 'integer', 'description' => 'Number of records (1-100)', 'default' => 10 },
        'starting_after' => { 'type' => 'string', 'description' => 'Cursor for pagination' },
        'status' => { 'type' => 'string', 'enum' => ['pending', 'paid', 'failed', 'canceled'] }
      },
      'deprecated_params' => ['order', 'sort'],
      'response_formatting' => {
        'currency_fields' => ['amount'],
        'currency_divisor' => 100,
        'currency_field' => 'currency',
        'timestamp_fields' => ['created', 'arrival_date']
      }
    },
    'stripe.get_balance' => {
      'type' => 'object',
      'properties' => {}
    },
    'stripe.retrieve_balance' => {
      'type' => 'object',
      'properties' => {}
    },
    'stripe.list_payment_methods' => {
      'type' => 'object',
      'properties' => {
        'customer' => { 'type' => 'string', 'description' => 'Customer ID (required)' },
        'type' => { 'type' => 'string', 'description' => 'Payment method type', 'enum' => ['card', 'us_bank_account', 'sepa_debit', 'link'] },
        'limit' => { 'type' => 'integer', 'description' => 'Number of records (1-100)', 'default' => 10 },
        'starting_after' => { 'type' => 'string', 'description' => 'Cursor for pagination' },
        'ending_before' => { 'type' => 'string', 'description' => 'Cursor for pagination' }
      },
      'required' => ['customer'],
      'deprecated_params' => ['order', 'sort']
    }
  }
  
  updated = 0
  stripe_schemas.each do |operation_id, schema|
    # Try to find with full ID or short ID
    op = stripe.integration_operations.find_by(operation_id: operation_id)
    op ||= stripe.integration_operations.find_by(operation_id: operation_id.split('.').last)
    
    if op
      op.update!(request_schema: schema, is_enabled: true)
      puts "   ✅ #{operation_id}"
      updated += 1
    end
  end
  
  puts "   Updated: #{updated} schemas"
else
  puts "\n⚠️  Stripe integration not found"
end

# ============================================================
# QUICKBOOKS OPERATIONS
# ============================================================

qb = Integration.find_by(slug: 'quickbooks')

if qb
  puts "\n📦 QuickBooks Integration"
  
  # FIRST: Clean up duplicates
  deleted = cleanup_duplicate_endpoints(qb)
  puts "   Removed #{deleted} duplicate operations" if deleted > 0
  
  # QuickBooks uses SQL-like Query Language
  # IMPORTANT: Invoice does NOT have a Status field - use Balance for open/paid
  # https://developer.intuit.com/app/developer/qbo/docs/learn/explore-the-quickbooks-online-api/data-queries
  
  qb_schemas = {
    'quickbooks.list_invoices' => {
      'type' => 'object',
      'description' => 'List QuickBooks invoices. NOTE: Use Balance > 0 for open, Balance = 0 for paid. Invoice has NO Status field!',
      'properties' => {
        'query' => { 
          'type' => 'string', 
          'description' => "SQL-like query. Examples: 'SELECT * FROM Invoice', 'SELECT * FROM Invoice WHERE Balance > \\'0\\'' (open invoices). WARNING: Invoice has NO Status field!"
        }
      },
      'deprecated_params' => ['status', 'limit', 'offset', 'page'],
      'examples' => {
        'open_invoices' => "SELECT * FROM Invoice WHERE Balance > '0'",
        'paid_invoices' => "SELECT * FROM Invoice WHERE Balance = '0'",
        'recent' => "SELECT * FROM Invoice WHERE TxnDate >= '2024-01-01' ORDERBY TxnDate DESC",
        'by_customer' => "SELECT * FROM Invoice WHERE CustomerRef = '123'"
      }
    },
    'quickbooks.list_customers' => {
      'type' => 'object',
      'description' => 'List QuickBooks customers using Query Language',
      'properties' => {
        'query' => { 
          'type' => 'string', 
          'description' => "SQL-like query. Example: 'SELECT * FROM Customer WHERE Active = true'"
        }
      },
      'deprecated_params' => ['limit', 'offset', 'page'],
      'examples' => {
        'all' => "SELECT * FROM Customer",
        'active' => "SELECT * FROM Customer WHERE Active = true",
        'by_name' => "SELECT * FROM Customer WHERE DisplayName LIKE 'John%'"
      }
    },
    'quickbooks.list_payments' => {
      'type' => 'object',
      'description' => 'List QuickBooks payments',
      'properties' => {
        'query' => { 'type' => 'string', 'description' => 'SQL-like query' }
      },
      'deprecated_params' => ['limit', 'offset'],
      'examples' => {
        'all' => "SELECT * FROM Payment",
        'recent' => "SELECT * FROM Payment WHERE TxnDate >= '2024-01-01'"
      }
    },
    'quickbooks.list_estimates' => {
      'type' => 'object',
      'description' => 'List QuickBooks estimates. Estimate DOES have TxnStatus: Accepted, Closed, Pending, Rejected',
      'properties' => {
        'query' => { 'type' => 'string', 'description' => 'SQL-like query. TxnStatus is valid for Estimate.' }
      },
      'deprecated_params' => ['limit', 'offset'],
      'examples' => {
        'pending' => "SELECT * FROM Estimate WHERE TxnStatus = 'Pending'",
        'accepted' => "SELECT * FROM Estimate WHERE TxnStatus = 'Accepted'"
      }
    },
    'quickbooks.list_vendors' => {
      'type' => 'object',
      'description' => 'List QuickBooks vendors',
      'properties' => {
        'query' => { 'type' => 'string', 'description' => 'SQL-like query' }
      },
      'deprecated_params' => ['limit', 'offset'],
      'examples' => { 'active' => "SELECT * FROM Vendor WHERE Active = true" }
    },
    'quickbooks.list_items' => {
      'type' => 'object',
      'description' => 'List QuickBooks products/services',
      'properties' => {
        'query' => { 'type' => 'string', 'description' => 'SQL-like query' }
      },
      'deprecated_params' => ['limit', 'offset'],
      'examples' => { 'active' => "SELECT * FROM Item WHERE Active = true" }
    },
    'quickbooks.list_accounts' => {
      'type' => 'object',
      'description' => 'List QuickBooks chart of accounts',
      'properties' => {
        'query' => { 'type' => 'string', 'description' => 'SQL-like query' }
      },
      'deprecated_params' => ['limit', 'offset'],
      'examples' => { 'expense' => "SELECT * FROM Account WHERE AccountType = 'Expense'" }
    },
    'quickbooks.list_bills' => {
      'type' => 'object',
      'description' => 'List QuickBooks bills. Use Balance > 0 for unpaid, Balance = 0 for paid.',
      'properties' => {
        'query' => { 'type' => 'string', 'description' => 'SQL-like query. Use Balance for paid/unpaid status.' }
      },
      'deprecated_params' => ['limit', 'offset', 'status'],
      'examples' => {
        'unpaid' => "SELECT * FROM Bill WHERE Balance > '0'",
        'paid' => "SELECT * FROM Bill WHERE Balance = '0'"
      }
    },
    'quickbooks.profit_and_loss' => {
      'type' => 'object',
      'description' => 'Get Profit and Loss report',
      'properties' => {
        'start_date' => { 'type' => 'string', 'description' => 'Start date (YYYY-MM-DD)', 'format' => 'date' },
        'end_date' => { 'type' => 'string', 'description' => 'End date (YYYY-MM-DD)', 'format' => 'date' },
        'accounting_method' => { 'type' => 'string', 'enum' => ['Cash', 'Accrual'], 'default' => 'Accrual' }
      }
    },
    'quickbooks.balance_sheet' => {
      'type' => 'object',
      'description' => 'Get Balance Sheet report',
      'properties' => {
        'as_of_date' => { 'type' => 'string', 'description' => 'As of date (YYYY-MM-DD)', 'format' => 'date' },
        'accounting_method' => { 'type' => 'string', 'enum' => ['Cash', 'Accrual'], 'default' => 'Accrual' }
      }
    },
    'quickbooks.get_company_info' => {
      'type' => 'object',
      'description' => 'Get company information',
      'properties' => {}
    }
  }
  
  updated = 0
  qb_schemas.each do |operation_id, schema|
    op = qb.integration_operations.find_by(operation_id: operation_id)
    op ||= qb.integration_operations.find_by(operation_id: operation_id.split('.').last)
    
    if op
      op.update!(
        request_schema: schema.except('examples'),
        examples: schema['examples'] || {},
        is_enabled: true
      )
      puts "   ✅ #{operation_id}"
      updated += 1
    end
  end
  
  puts "   Updated: #{updated} schemas"
else
  puts "\n⚠️  QuickBooks integration not found"
end

# ============================================================
# CLEANUP ALL OTHER INTEGRATIONS
# ============================================================

puts "\n🧹 Cleaning up all other integrations..."

total_deleted = 0
Integration.where.not(slug: ['stripe', 'quickbooks']).find_each do |integration|
  deleted = cleanup_duplicate_endpoints(integration)
  if deleted > 0
    puts "   #{integration.name}: removed #{deleted} duplicates"
    total_deleted += deleted
  end
end
puts "   Total removed: #{total_deleted}"

# ============================================================
# SUMMARY
# ============================================================

puts "\n📊 Final Status:"
Integration.find_each do |integration|
  count = integration.integration_operations.count
  with_schema = integration.integration_operations.select { |op| op.request_schema.present? && op.request_schema['properties'].present? }.count
  puts "   #{integration.name}: #{count} operations (#{with_schema} with schemas)"
end

puts "\n" + "=" * 60
puts "✅ INTEGRATION OPERATIONS CLEANUP COMPLETE"
puts "=" * 60
