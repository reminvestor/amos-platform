# frozen_string_literal: true

namespace :integrations do
  namespace :quickbooks do
    desc "Analyze QuickBooks operations for duplicates and missing schemas"
    task analyze: :environment do
      puts "=" * 80
      puts "QUICKBOOKS OPERATIONS ANALYSIS"
      puts "=" * 80
      
      qb = Integration.find_by(slug: 'quickbooks')
      unless qb
        puts "❌ QuickBooks integration not found!"
        exit 1
      end
      
      puts "\nIntegration ID: #{qb.id}"
      puts "Total operations: #{qb.integration_operations.count}"
      
      operations = qb.integration_operations.order(:path_template, :http_method)
      
      # Group by path + method to find duplicates
      by_endpoint = operations.group_by { |op| [op.http_method, op.path_template] }
      
      puts "\n" + "-" * 80
      puts "DUPLICATE ENDPOINTS (same path + method):"
      puts "-" * 80
      
      duplicates = by_endpoint.select { |_k, v| v.length > 1 }
      if duplicates.any?
        duplicates.each do |(method, path), ops|
          puts "\n🔴 #{method} #{path}"
          ops.each do |op|
            schema_status = op.request_schema.present? && op.request_schema["properties"].present? ? "✅ Has schema" : "❌ No schema"
            enabled_status = op.is_enabled? ? "enabled" : "disabled"
            puts "   - ID #{op.id}: #{op.operation_id} (#{op.name}) [#{enabled_status}] #{schema_status}"
          end
        end
      else
        puts "   ✅ No duplicate endpoints found"
      end
      
      # Operations missing schemas
      puts "\n" + "-" * 80
      puts "OPERATIONS MISSING REQUEST SCHEMA:"
      puts "-" * 80
      
      missing_schema = operations.select do |op|
        op.request_schema.blank? || op.request_schema["properties"].blank?
      end
      
      if missing_schema.any?
        puts "\n⚠️  #{missing_schema.count} operations have no request schema:"
        missing_schema.each do |op|
          enabled_status = op.is_enabled? ? "enabled" : "disabled"
          puts "   - ID #{op.id}: #{op.operation_id} (#{op.name}) [#{enabled_status}]"
        end
      else
        puts "   ✅ All operations have request schemas"
      end
      
      # Check for common QB mistakes in descriptions
      puts "\n" + "-" * 80
      puts "OPERATIONS WITH POTENTIALLY WRONG DOCUMENTATION:"
      puts "-" * 80
      
      bad_docs = operations.select do |op|
        desc = op.description.to_s.downcase
        # Check for common mistakes
        desc.include?('status') && op.name.to_s.downcase.include?('invoice')
      end
      
      if bad_docs.any?
        puts "\n⚠️  #{bad_docs.count} operations may have incorrect documentation:"
        bad_docs.each do |op|
          puts "   - #{op.operation_id}: mentions 'status' for invoices (QB uses Balance, not Status)"
        end
      end
      
      puts "\n" + "=" * 80
      puts "SUMMARY"
      puts "=" * 80
      puts "Total operations: #{operations.count}"
      puts "Duplicate endpoints: #{duplicates.values.flatten.count}"
      puts "Missing schemas: #{missing_schema.count}"
    end
    
    desc "Add proper QuickBooks schemas to operations"
    task add_schemas: :environment do
      puts "=" * 80
      puts "ADDING QUICKBOOKS OPERATION SCHEMAS"
      puts "=" * 80
      
      qb = Integration.find_by(slug: 'quickbooks')
      unless qb
        puts "❌ QuickBooks integration not found!"
        exit 1
      end
      
      # QuickBooks uses Query Language for most list operations
      # https://developer.intuit.com/app/developer/qbo/docs/learn/explore-the-quickbooks-online-api/data-queries
      #
      # IMPORTANT: QuickBooks Invoice does NOT have a Status field!
      # - Open invoices: Balance > '0'
      # - Paid invoices: Balance = '0'
      # - Use TxnDate for date filtering
      #
      quickbooks_schemas = {
        # Query-based operations (use SQL-like syntax)
        'quickbooks.list_invoices' => {
          'type' => 'object',
          'description' => 'List QuickBooks invoices using Query Language',
          'properties' => {
            'query' => { 
              'type' => 'string', 
              'description' => "SQL-like query. Examples: 'SELECT * FROM Invoice', 'SELECT * FROM Invoice WHERE Balance > \\'0\\'' (open), 'SELECT * FROM Invoice WHERE TxnDate >= \\'2024-01-01\\''. NOTE: Invoice has NO Status field - use Balance for open/paid filtering."
            },
            'limit' => { 
              'type' => 'integer', 
              'description' => 'Max results (use MAXRESULTS in query, e.g., SELECT * FROM Invoice MAXRESULTS 50)',
              'default' => 100
            }
          },
          'examples' => {
            'open_invoices' => "SELECT * FROM Invoice WHERE Balance > '0'",
            'paid_invoices' => "SELECT * FROM Invoice WHERE Balance = '0'",
            'recent_invoices' => "SELECT * FROM Invoice WHERE TxnDate >= '2024-01-01' ORDERBY TxnDate DESC",
            'customer_invoices' => "SELECT * FROM Invoice WHERE CustomerRef = '123'"
          }
        },
        'quickbooks.list_customers' => {
          'type' => 'object',
          'description' => 'List QuickBooks customers using Query Language',
          'properties' => {
            'query' => { 
              'type' => 'string', 
              'description' => "SQL-like query. Examples: 'SELECT * FROM Customer', 'SELECT * FROM Customer WHERE Active = true'"
            },
            'limit' => { 'type' => 'integer', 'description' => 'Max results', 'default' => 100 }
          },
          'examples' => {
            'all_customers' => "SELECT * FROM Customer",
            'active_customers' => "SELECT * FROM Customer WHERE Active = true",
            'by_name' => "SELECT * FROM Customer WHERE DisplayName LIKE 'John%'"
          }
        },
        'quickbooks.list_payments' => {
          'type' => 'object',
          'description' => 'List QuickBooks payments',
          'properties' => {
            'query' => { 
              'type' => 'string', 
              'description' => "SQL-like query. Example: 'SELECT * FROM Payment WHERE TxnDate >= \\'2024-01-01\\''"
            }
          },
          'examples' => {
            'all_payments' => "SELECT * FROM Payment",
            'recent_payments' => "SELECT * FROM Payment WHERE TxnDate >= '2024-01-01'"
          }
        },
        'quickbooks.list_estimates' => {
          'type' => 'object',
          'description' => 'List QuickBooks estimates/quotes',
          'properties' => {
            'query' => { 
              'type' => 'string', 
              'description' => "SQL-like query. Estimate has TxnStatus field: Accepted, Closed, Pending, Rejected"
            }
          },
          'examples' => {
            'pending_estimates' => "SELECT * FROM Estimate WHERE TxnStatus = 'Pending'",
            'accepted_estimates' => "SELECT * FROM Estimate WHERE TxnStatus = 'Accepted'"
          }
        },
        'quickbooks.list_vendors' => {
          'type' => 'object',
          'description' => 'List QuickBooks vendors',
          'properties' => {
            'query' => { 'type' => 'string', 'description' => "SQL-like query" }
          },
          'examples' => {
            'active_vendors' => "SELECT * FROM Vendor WHERE Active = true"
          }
        },
        'quickbooks.list_items' => {
          'type' => 'object',
          'description' => 'List QuickBooks products/services',
          'properties' => {
            'query' => { 'type' => 'string', 'description' => "SQL-like query" }
          },
          'examples' => {
            'all_items' => "SELECT * FROM Item",
            'active_items' => "SELECT * FROM Item WHERE Active = true"
          }
        },
        'quickbooks.list_accounts' => {
          'type' => 'object',
          'description' => 'List QuickBooks chart of accounts',
          'properties' => {
            'query' => { 'type' => 'string', 'description' => "SQL-like query" }
          },
          'examples' => {
            'all_accounts' => "SELECT * FROM Account",
            'expense_accounts' => "SELECT * FROM Account WHERE AccountType = 'Expense'"
          }
        },
        'quickbooks.list_bills' => {
          'type' => 'object',
          'description' => 'List QuickBooks bills (accounts payable)',
          'properties' => {
            'query' => { 
              'type' => 'string', 
              'description' => "SQL-like query. Bill has Balance field for open/paid."
            }
          },
          'examples' => {
            'open_bills' => "SELECT * FROM Bill WHERE Balance > '0'",
            'paid_bills' => "SELECT * FROM Bill WHERE Balance = '0'"
          }
        },
        'quickbooks.get_company_info' => {
          'type' => 'object',
          'description' => 'Get company information',
          'properties' => {}
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
        }
      }
      
      updated_count = 0
      created_count = 0
      
      quickbooks_schemas.each do |operation_id, schema_data|
        op = qb.integration_operations.find_by(operation_id: operation_id)
        
        # Also try without prefix
        short_id = operation_id.split('.').last
        op ||= qb.integration_operations.find_by(operation_id: short_id)
        
        if op
          schema = {
            'type' => schema_data['type'] || 'object',
            'description' => schema_data['description'],
            'properties' => schema_data['properties'] || {}
          }
          
          op.update!(
            request_schema: schema,
            examples: schema_data['examples'] || {},
            is_enabled: true
          )
          puts "✅ Updated: #{operation_id}"
          updated_count += 1
        else
          puts "⚠️  Not found: #{operation_id}"
        end
      end
      
      puts "\n" + "=" * 80
      puts "SCHEMA UPDATE COMPLETE"
      puts "=" * 80
      puts "Operations updated: #{updated_count}"
    end
    
    desc "Clean up duplicate QuickBooks operations"
    task cleanup: :environment do
      puts "=" * 80
      puts "QUICKBOOKS OPERATIONS CLEANUP"
      puts "=" * 80
      
      qb = Integration.find_by(slug: 'quickbooks')
      unless qb
        puts "❌ QuickBooks integration not found!"
        exit 1
      end
      
      operations = qb.integration_operations
      deleted_count = 0
      
      # Group by path + method
      by_endpoint = operations.group_by { |op| [op.http_method, op.path_template] }
      duplicates = by_endpoint.select { |_k, v| v.length > 1 }
      
      duplicates.each do |(method, path), ops|
        puts "\n🔧 Processing: #{method} #{path}"
        
        # Score operations
        scored_ops = ops.map do |op|
          score = 0
          score += 10 if op.is_enabled?
          score += 5 if op.operation_id.start_with?('quickbooks.')
          score += 3 if op.request_schema.present? && op.request_schema["properties"].present?
          score += 2 if op.examples.present? && op.examples.any?
          { op: op, score: score }
        end.sort_by { |x| -x[:score] }
        
        best = scored_ops.first[:op]
        others = scored_ops[1..].map { |x| x[:op] }
        
        puts "   ✅ Keeping: #{best.operation_id} (ID #{best.id})"
        
        others.each do |other|
          puts "   🗑️  Removing: #{other.operation_id} (ID #{other.id})"
          
          # Merge schema if better
          if other.request_schema.present? && other.request_schema["properties"].present?
            if best.request_schema.blank? || best.request_schema["properties"].blank?
              best.update!(request_schema: other.request_schema)
              puts "      ↳ Merged schema"
            end
          end
          
          # Move actions
          if other.integration_actions.any?
            other.integration_actions.update_all(integration_operation_id: best.id)
            puts "      ↳ Moved actions"
          end
          
          other.destroy!
          deleted_count += 1
        end
      end
      
      puts "\n" + "=" * 80
      puts "CLEANUP COMPLETE: #{deleted_count} operations deleted"
      puts "=" * 80
    end
    
    desc "Full QuickBooks cleanup"
    task full_cleanup: [:analyze, :cleanup, :add_schemas] do
      puts "\n🎉 FULL QUICKBOOKS CLEANUP COMPLETE"
    end
  end
end
