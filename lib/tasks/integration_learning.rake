# frozen_string_literal: true

namespace :integrations do
  desc "Analyze all integrations and apply schema learnings from historical data"
  task learn: :environment do
    puts "=" * 80
    puts "INTEGRATION SCHEMA LEARNING"
    puts "=" * 80
    
    total_updated = 0
    
    Integration.find_each do |integration|
      puts "\n📊 Analyzing: #{integration.name} (#{integration.slug})"
      
      result = IntegrationSchemaLearnerService.analyze_integration(integration.slug)
      
      if result[:error]
        puts "   ❌ Error: #{result[:error]}"
        next
      end
      
      puts "   Operations analyzed: #{result[:operations_analyzed]}"
      puts "   Schemas updated: #{result[:schemas_updated]}"
      
      result[:suggestions].each do |suggestion|
        puts "   🔧 #{suggestion[:operation]}: #{suggestion[:changes].map { |c| c[:type] }.join(', ')}"
      end
      
      total_updated += result[:schemas_updated]
    end
    
    puts "\n" + "=" * 80
    puts "LEARNING COMPLETE: #{total_updated} schemas updated"
    puts "=" * 80
  end
  
  desc "Learn from integration logs (last 7 days of successes/failures)"
  task learn_from_logs: :environment do
    puts "=" * 80
    puts "LEARNING FROM INTEGRATION LOGS"
    puts "=" * 80
    
    # Find all recent integration logs
    recent_logs = IntegrationLog.where('created_at > ?', 7.days.ago)
                                .includes(:integration_operation)
    
    puts "Analyzing #{recent_logs.count} recent logs..."
    
    successes = 0
    failures = 0
    
    recent_logs.find_each do |log|
      operation = log.integration_operation
      next unless operation
      
      params = log.metadata&.dig('params') || {}
      
      if log.response_status.to_i < 400
        IntegrationSchemaLearnerService.learn_from_success(
          operation: operation,
          params: params,
          response: {} # Response body is encrypted, skip for now
        )
        successes += 1
      else
        IntegrationSchemaLearnerService.learn_from_failure(
          operation: operation,
          params: params,
          error: "HTTP #{log.response_status}"
        )
        failures += 1
      end
    end
    
    puts "\nProcessed:"
    puts "  ✅ Successes: #{successes}"
    puts "  ❌ Failures: #{failures}"
    
    # Now apply the learnings
    Rake::Task['integrations:learn'].invoke
  end
  
  desc "Show deprecated/problematic parameters across all integrations"
  task show_deprecated: :environment do
    puts "=" * 80
    puts "DEPRECATED/PROBLEMATIC PARAMETERS"
    puts "=" * 80
    
    Integration.find_each do |integration|
      deprecated_ops = integration.integration_operations.select do |op|
        op.request_schema&.dig('deprecated_params')&.any?
      end
      
      next if deprecated_ops.empty?
      
      puts "\n📦 #{integration.name}"
      deprecated_ops.each do |op|
        deprecated = op.request_schema['deprecated_params']
        puts "   #{op.operation_id}: #{deprecated.join(', ')}"
      end
    end
  end
  
  desc "Reset learning data for an integration"
  task :reset_learning, [:slug] => :environment do |_t, args|
    slug = args[:slug]
    unless slug
      puts "Usage: rails integrations:reset_learning[stripe]"
      exit 1
    end
    
    integration = Integration.find_by(slug: slug)
    unless integration
      puts "Integration '#{slug}' not found"
      exit 1
    end
    
    puts "Resetting learning data for #{integration.name}..."
    
    integration.integration_operations.find_each do |op|
      metadata = op.metadata || {}
      metadata.delete('successful_calls')
      metadata.delete('recent_failures')
      
      schema = op.request_schema || {}
      schema.delete('deprecated_params')
      schema.delete('last_learned')
      
      # Remove learned_at from properties
      if schema['properties']
        schema['properties'].each do |_key, props|
          props.delete('learned_at') if props.is_a?(Hash)
          props.delete('deprecated') if props.is_a?(Hash)
        end
      end
      
      op.update!(metadata: metadata, request_schema: schema)
    end
    
    puts "✅ Done"
  end
  
  namespace :cleanup do
    desc "Full cleanup for all major integrations"
    task all: :environment do
      puts "=" * 80
      puts "FULL INTEGRATION CLEANUP"
      puts "=" * 80
      
      %w[stripe quickbooks hubspot].each do |slug|
        if Integration.exists?(slug: slug)
          puts "\n🔧 Cleaning up #{slug}..."
          Rake::Task["integrations:#{slug}:full_cleanup"].invoke rescue nil
          Rake::Task["integrations:#{slug}:full_cleanup"].reenable
        end
      end
      
      puts "\n📚 Applying learnings..."
      Rake::Task['integrations:learn'].invoke
      
      puts "\n🎉 DONE"
    end
  end
end
