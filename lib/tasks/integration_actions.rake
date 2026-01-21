# frozen_string_literal: true

namespace :integration_actions do
  desc "Audit which operations are missing actions"
  task audit: :environment do
    puts "\n📊 Integration Actions Audit"
    puts "=" * 50

    results = Integrations::ActionGeneratorService.audit

    puts "Total Operations: #{results[:total_operations]}"
    puts "With Actions: #{results[:with_actions]}"
    puts "Missing Actions: #{results[:missing_actions]}"

    if results[:missing].any?
      puts "\n📋 Operations Missing Actions:"
      results[:missing].group_by { |m| m[:integration] }.each do |integration, ops|
        puts "\n  #{integration}:"
        ops.each do |op|
          puts "    - #{op[:operation_id]} (#{op[:method]} #{op[:name]})"
        end
      end

      puts "\n💡 To generate actions for a specific integration:"
      puts "   rake integration_actions:backfill[stripe]"
      puts "\n   To generate for all:"
      puts "   rake integration_actions:backfill_all"
    else
      puts "\n✅ All operations have actions!"
    end
  end

  desc "Backfill actions for a specific integration"
  task :backfill, [:integration_slug] => :environment do |_t, args|
    integration_slug = args[:integration_slug]
    
    unless integration_slug
      puts "❌ Please specify an integration slug: rake integration_actions:backfill[stripe]"
      exit 1
    end

    puts "\n🔧 Backfilling actions for: #{integration_slug}"
    puts "=" * 50

    results = Integrations::ActionGeneratorService.backfill_for_integration(integration_slug)

    puts "\n✅ Created: #{results[:created].length}"
    results[:created].each { |name| puts "   - #{name}" }

    puts "\n⏭️  Skipped (already exist): #{results[:skipped].length}"
    
    if results[:errors].any?
      puts "\n❌ Errors: #{results[:errors].length}"
      results[:errors].each { |e| puts "   - #{e[:operation]}: #{e[:error]}" }
    end
  end

  desc "Backfill actions for ALL integrations"
  task backfill_all: :environment do
    puts "\n🔧 Backfilling actions for ALL integrations"
    puts "=" * 50

    results = Integrations::ActionGeneratorService.backfill_all

    results.each do |integration, data|
      created = data[:created].length
      skipped = data[:skipped].length
      errors = data[:errors].length
      
      status = errors > 0 ? "⚠️" : "✅"
      puts "#{status} #{integration}: #{created} created, #{skipped} skipped, #{errors} errors"
    end

    puts "\nDone!"
  end

  desc "Generate action for a specific operation (with AI)"
  task :generate, [:operation_id] => :environment do |_t, args|
    operation_id = args[:operation_id]
    
    unless operation_id
      puts "❌ Please specify an operation ID: rake integration_actions:generate[stripe.list_customers]"
      exit 1
    end

    operation = IntegrationOperation.find_by(operation_id: operation_id)
    unless operation
      puts "❌ Operation not found: #{operation_id}"
      exit 1
    end

    puts "\n🤖 Generating action with AI for: #{operation_id}"

    result = Integrations::ActionGeneratorService.generate_for_operation(
      operation,
      use_ai: true,
      auto_activate: false
    )

    if result[:success]
      action = result[:action]
      puts "\n✅ Created: #{action.slug}"
      puts "   Status: #{action.status}"
      puts "   Input Schema:"
      action.input_schema.each do |field|
        req = field[:required] ? "*" : ""
        puts "     - #{field[:name]}#{req} (#{field[:type]})"
      end
      puts "\n   Mapping Code:"
      puts action.mapping_code.lines.map { |l| "     #{l}" }.join
    else
      puts "❌ Failed: #{result[:error]}"
    end
  end

  desc "Activate all draft actions for an integration"
  task :activate, [:integration_slug] => :environment do |_t, args|
    integration_slug = args[:integration_slug]
    
    integration = Integration.find_by(slug: integration_slug)
    unless integration
      puts "❌ Integration not found: #{integration_slug}"
      exit 1
    end

    count = IntegrationAction.where(integration: integration, status: :draft).update_all(status: :active)
    puts "✅ Activated #{count} actions for #{integration.name}"
  end

  desc "List all actions for an integration"
  task :list, [:integration_slug] => :environment do |_t, args|
    integration_slug = args[:integration_slug]
    
    integration = Integration.find_by(slug: integration_slug)
    unless integration
      puts "❌ Integration not found: #{integration_slug}"
      exit 1
    end

    actions = IntegrationAction.where(integration: integration).order(:action_name)

    puts "\n📋 Actions for #{integration.name} (#{actions.count} total)"
    puts "=" * 60

    actions.each do |action|
      status_icon = case action.status
      when 'active' then '✅'
      when 'draft' then '📝'
      when 'testing' then '🧪'
      when 'deprecated' then '⚠️'
      else '❓'
      end

      puts "#{status_icon} #{action.action_name}"
      puts "   Slug: #{action.slug}"
      puts "   Operation: #{action.integration_operation&.operation_id}"
      puts "   Inputs: #{action.input_field_names.join(', ')}"
      puts "   Usage: #{action.usage_count} (#{action.success_rate}% success)"
      puts ""
    end
  end
end

