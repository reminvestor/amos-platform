# frozen_string_literal: true

namespace :integrations do
  namespace :stripe do
    desc "Analyze Stripe operations for duplicates and missing schemas"
    task analyze: :environment do
      puts "=" * 80
      puts "STRIPE OPERATIONS ANALYSIS"
      puts "=" * 80
      
      stripe = Integration.find_by(slug: 'stripe')
      unless stripe
        puts "❌ Stripe integration not found!"
        exit 1
      end
      
      puts "\nIntegration ID: #{stripe.id}"
      puts "Total operations: #{stripe.integration_operations.count}"
      
      operations = stripe.integration_operations.order(:path_template, :http_method)
      
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
            if op.request_schema.present? && op.request_schema["properties"].present?
              puts "     Properties: #{op.request_schema['properties'].keys.join(', ')}"
            end
          end
        end
      else
        puts "   ✅ No duplicate endpoints found"
      end
      
      # Find similar operation names (potential duplicates)
      puts "\n" + "-" * 80
      puts "SIMILAR OPERATION NAMES:"
      puts "-" * 80
      
      by_normalized_name = operations.group_by do |op|
        # Normalize: lowercase, remove prefix, remove underscores/dashes
        op.operation_id.to_s.downcase
          .gsub(/^stripe[\._]/, '')
          .gsub(/[_\-\.\s]/, '')
      end
      
      similar = by_normalized_name.select { |_k, v| v.length > 1 }
      if similar.any?
        similar.each do |normalized, ops|
          puts "\n🟡 Similar: #{normalized}"
          ops.each do |op|
            schema_status = op.request_schema.present? && op.request_schema["properties"].present? ? "✅ Has schema" : "❌ No schema"
            enabled_status = op.is_enabled? ? "enabled" : "disabled"
            puts "   - ID #{op.id}: #{op.operation_id} (#{op.name}) [#{enabled_status}] #{schema_status}"
          end
        end
      else
        puts "   ✅ No similar operation names found"
      end
      
      # Operations with missing or empty schemas
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
          puts "     Path: #{op.http_method} #{op.path_template}"
        end
      else
        puts "   ✅ All operations have request schemas"
      end
      
      # Summary
      puts "\n" + "=" * 80
      puts "SUMMARY"
      puts "=" * 80
      puts "Total operations: #{operations.count}"
      puts "Duplicate endpoints: #{duplicates.values.flatten.count} operations in #{duplicates.count} groups"
      puts "Similar names: #{similar.values.flatten.count} operations in #{similar.count} groups"
      puts "Missing schemas: #{missing_schema.count}"
      puts "\nRun `rails integrations:stripe:cleanup` to fix issues"
    end
    
    desc "Clean up duplicate Stripe operations (keeps best version)"
    task cleanup: :environment do
      puts "=" * 80
      puts "STRIPE OPERATIONS CLEANUP"
      puts "=" * 80
      
      stripe = Integration.find_by(slug: 'stripe')
      unless stripe
        puts "❌ Stripe integration not found!"
        exit 1
      end
      
      operations = stripe.integration_operations
      deleted_count = 0
      merged_count = 0
      
      # 1. Find duplicates by endpoint (path + method)
      by_endpoint = operations.group_by { |op| [op.http_method, op.path_template] }
      duplicates = by_endpoint.select { |_k, v| v.length > 1 }
      
      puts "\n📋 Processing #{duplicates.count} duplicate endpoint groups..."
      
      duplicates.each do |(method, path), ops|
        puts "\n🔧 Processing: #{method} #{path}"
        
        # Score each operation
        scored_ops = ops.map do |op|
          score = 0
          score += 10 if op.is_enabled?
          score += 5 if op.operation_id.start_with?('stripe.')
          score += 3 if op.request_schema.present? && op.request_schema["properties"].present?
          score += op.request_schema["properties"]&.keys&.length.to_i
          score += 2 if op.description.present? && op.description.length > 50
          score += 1 if op.examples.present? && op.examples.any?
          
          { op: op, score: score }
        end.sort_by { |x| -x[:score] }
        
        best = scored_ops.first[:op]
        others = scored_ops[1..].map { |x| x[:op] }
        
        puts "   ✅ Keeping: #{best.operation_id} (ID #{best.id}, score: #{scored_ops.first[:score]})"
        
        # Merge any better schema data from others into best
        others.each do |other|
          puts "   🗑️  Removing: #{other.operation_id} (ID #{other.id}, score: #{scored_ops.find { |x| x[:op] == other }[:score]})"
          
          # If other has a better schema, merge it
          if other.request_schema.present? && other.request_schema["properties"].present?
            if best.request_schema.blank? || best.request_schema["properties"].blank?
              best.update!(request_schema: other.request_schema)
              puts "      ↳ Merged schema from deleted operation"
              merged_count += 1
            elsif other.request_schema["properties"].keys.length > (best.request_schema["properties"]&.keys&.length || 0)
              # Merge missing properties
              merged_props = best.request_schema["properties"].merge(other.request_schema["properties"])
              best.request_schema["properties"] = merged_props
              best.save!
              puts "      ↳ Merged additional properties: #{(other.request_schema['properties'].keys - best.request_schema['properties'].keys).join(', ')}"
              merged_count += 1
            end
          end
          
          # Move any integration_actions to the best operation
          if other.integration_actions.any?
            moved = other.integration_actions.update_all(integration_operation_id: best.id)
            puts "      ↳ Moved #{moved} integration actions to kept operation"
          end
          
          # Delete the duplicate
          other.destroy!
          deleted_count += 1
        end
      end
      
      # 2. Find similar names (potential duplicates with different paths)
      puts "\n" + "-" * 80
      puts "📋 Checking similar operation names..."
      
      operations.reload
      by_normalized = operations.group_by do |op|
        op.operation_id.to_s.downcase
          .gsub(/^stripe[\._]/, '')
          .gsub(/[_\-\.\s]/, '')
      end
      
      similar = by_normalized.select { |_k, v| v.length > 1 }
      
      similar.each do |normalized, ops|
        # Only consider them duplicates if they have the same HTTP method
        by_method = ops.group_by(&:http_method)
        by_method.each do |method, method_ops|
          next if method_ops.length < 2
          
          puts "\n🟡 Similar: #{normalized} (#{method})"
          
          # If one is prefixed with "stripe." and one isn't, prefer the prefixed one
          prefixed = method_ops.find { |op| op.operation_id.start_with?('stripe.') }
          unprefixed = method_ops.find { |op| !op.operation_id.start_with?('stripe.') }
          
          if prefixed && unprefixed && prefixed.path_template == unprefixed.path_template
            puts "   ✅ Keeping: #{prefixed.operation_id} (ID #{prefixed.id})"
            puts "   🗑️  Removing: #{unprefixed.operation_id} (ID #{unprefixed.id})"
            
            # Merge schema if needed
            if unprefixed.request_schema.present? && unprefixed.request_schema["properties"].present?
              if prefixed.request_schema.blank? || prefixed.request_schema["properties"].blank?
                prefixed.update!(request_schema: unprefixed.request_schema)
                puts "      ↳ Merged schema from deleted operation"
                merged_count += 1
              end
            end
            
            # Move actions
            if unprefixed.integration_actions.any?
              moved = unprefixed.integration_actions.update_all(integration_operation_id: prefixed.id)
              puts "      ↳ Moved #{moved} integration actions"
            end
            
            unprefixed.destroy!
            deleted_count += 1
          else
            puts "   ⚠️  Paths differ - manual review needed:"
            method_ops.each do |op|
              puts "      - #{op.operation_id}: #{op.path_template}"
            end
          end
        end
      end
      
      # 3. Disable operations without schemas (they cause AI confusion)
      puts "\n" + "-" * 80
      puts "📋 Checking for operations missing request schemas..."
      
      operations.reload
      missing_schema = operations.where(is_enabled: true).select do |op|
        op.request_schema.blank? || op.request_schema["properties"].blank?
      end
      
      if missing_schema.any?
        puts "\n⚠️  Disabling #{missing_schema.count} operations without request schemas:"
        missing_schema.each do |op|
          puts "   - Disabling: #{op.operation_id} (ID #{op.id})"
          op.update!(is_enabled: false)
        end
      end
      
      # Summary
      puts "\n" + "=" * 80
      puts "CLEANUP COMPLETE"
      puts "=" * 80
      puts "Operations deleted: #{deleted_count}"
      puts "Schemas merged: #{merged_count}"
      puts "Operations disabled (no schema): #{missing_schema.count}"
      puts "\nRemaining Stripe operations: #{stripe.integration_operations.reload.count}"
      puts "Enabled operations: #{stripe.integration_operations.enabled.count}"
    end
    
    desc "Add missing schemas to common Stripe operations"
    task add_schemas: :environment do
      puts "=" * 80
      puts "ADDING STRIPE OPERATION SCHEMAS"
      puts "=" * 80
      
      stripe = Integration.find_by(slug: 'stripe')
      unless stripe
        puts "❌ Stripe integration not found!"
        exit 1
      end
      
      # Common Stripe operation schemas
      # Based on Stripe API docs: https://stripe.com/docs/api
      common_schemas = {
        'stripe.list_charges' => {
          'type' => 'object',
          'properties' => {
            'limit' => { 'type' => 'integer', 'description' => 'Number of records (1-100)', 'default' => 10 },
            'starting_after' => { 'type' => 'string', 'description' => 'Cursor for pagination (charge ID)' },
            'ending_before' => { 'type' => 'string', 'description' => 'Cursor for pagination (charge ID)' },
            'created' => { 'type' => 'object', 'description' => 'Filter by created date', 'properties' => {
              'gte' => { 'type' => 'integer', 'description' => 'Minimum timestamp' },
              'lte' => { 'type' => 'integer', 'description' => 'Maximum timestamp' }
            }},
            'customer' => { 'type' => 'string', 'description' => 'Filter by customer ID' },
            'payment_intent' => { 'type' => 'string', 'description' => 'Filter by payment intent ID' }
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
          }
        },
        'stripe.list_invoices' => {
          'type' => 'object',
          'properties' => {
            'limit' => { 'type' => 'integer', 'description' => 'Number of records (1-100)', 'default' => 10 },
            'starting_after' => { 'type' => 'string', 'description' => 'Cursor for pagination' },
            'customer' => { 'type' => 'string', 'description' => 'Filter by customer ID' },
            'status' => { 'type' => 'string', 'enum' => ['draft', 'open', 'paid', 'uncollectible', 'void'] },
            'subscription' => { 'type' => 'string', 'description' => 'Filter by subscription ID' }
          }
        },
        'stripe.list_payment_intents' => {
          'type' => 'object',
          'properties' => {
            'limit' => { 'type' => 'integer', 'description' => 'Number of records (1-100)', 'default' => 10 },
            'starting_after' => { 'type' => 'string', 'description' => 'Cursor for pagination' },
            'customer' => { 'type' => 'string', 'description' => 'Filter by customer ID' },
            'created' => { 'type' => 'object', 'description' => 'Filter by created date' }
          }
        },
        'stripe.list_subscriptions' => {
          'type' => 'object',
          'properties' => {
            'limit' => { 'type' => 'integer', 'description' => 'Number of records (1-100)', 'default' => 10 },
            'starting_after' => { 'type' => 'string', 'description' => 'Cursor for pagination' },
            'customer' => { 'type' => 'string', 'description' => 'Filter by customer ID' },
            'status' => { 'type' => 'string', 'enum' => ['active', 'past_due', 'unpaid', 'canceled', 'incomplete', 'incomplete_expired', 'trialing', 'all', 'ended'] },
            'price' => { 'type' => 'string', 'description' => 'Filter by price ID' }
          }
        },
        'stripe.list_products' => {
          'type' => 'object',
          'properties' => {
            'limit' => { 'type' => 'integer', 'description' => 'Number of records (1-100)', 'default' => 10 },
            'starting_after' => { 'type' => 'string', 'description' => 'Cursor for pagination' },
            'active' => { 'type' => 'boolean', 'description' => 'Filter by active status' },
            'type' => { 'type' => 'string', 'enum' => ['good', 'service'] }
          }
        },
        'stripe.list_prices' => {
          'type' => 'object',
          'properties' => {
            'limit' => { 'type' => 'integer', 'description' => 'Number of records (1-100)', 'default' => 10 },
            'starting_after' => { 'type' => 'string', 'description' => 'Cursor for pagination' },
            'product' => { 'type' => 'string', 'description' => 'Filter by product ID' },
            'active' => { 'type' => 'boolean', 'description' => 'Filter by active status' },
            'type' => { 'type' => 'string', 'enum' => ['one_time', 'recurring'] }
          }
        },
        'stripe.list_balance_transactions' => {
          'type' => 'object',
          'properties' => {
            'limit' => { 'type' => 'integer', 'description' => 'Number of records (1-100)', 'default' => 10 },
            'starting_after' => { 'type' => 'string', 'description' => 'Cursor for pagination' },
            'type' => { 'type' => 'string', 'description' => 'Filter by transaction type' },
            'payout' => { 'type' => 'string', 'description' => 'Filter by payout ID' },
            'source' => { 'type' => 'string', 'description' => 'Filter by source ID' }
          }
        },
        'stripe.list_payouts' => {
          'type' => 'object',
          'properties' => {
            'limit' => { 'type' => 'integer', 'description' => 'Number of records (1-100)', 'default' => 10 },
            'starting_after' => { 'type' => 'string', 'description' => 'Cursor for pagination' },
            'status' => { 'type' => 'string', 'enum' => ['pending', 'paid', 'failed', 'canceled'] },
            'destination' => { 'type' => 'string', 'description' => 'Filter by destination' }
          }
        },
        'stripe.get_balance' => {
          'type' => 'object',
          'properties' => {}
        }
      }
      
      updated_count = 0
      
      common_schemas.each do |operation_id, schema|
        op = stripe.integration_operations.find_by(operation_id: operation_id)
        
        if op
          if op.request_schema.blank? || op.request_schema["properties"].blank?
            op.update!(request_schema: schema, is_enabled: true)
            puts "✅ Updated: #{operation_id}"
            updated_count += 1
          else
            puts "⏭️  Already has schema: #{operation_id}"
          end
        else
          puts "⚠️  Not found: #{operation_id}"
        end
      end
      
      puts "\n" + "=" * 80
      puts "SCHEMA UPDATE COMPLETE"
      puts "=" * 80
      puts "Operations updated: #{updated_count}"
    end
    
    desc "Full Stripe cleanup: analyze, cleanup duplicates, add schemas"
    task full_cleanup: [:analyze, :cleanup, :add_schemas] do
      puts "\n" + "=" * 80
      puts "🎉 FULL STRIPE CLEANUP COMPLETE"
      puts "=" * 80
      puts "Run `rails integrations:stripe:analyze` to verify the results"
    end
  end
end
