# frozen_string_literal: true

namespace :integrations do
  desc "Mark an integration as 'coming soon'"
  task :mark_coming_soon, [:slug] => :environment do |_t, args|
    integration = Integration.find_by(slug: args[:slug])
    if integration
      integration.mark_as_coming_soon!
      puts "✓ Marked '#{integration.name}' as coming soon"
    else
      puts "✗ Integration with slug '#{args[:slug]}' not found"
    end
  end

  desc "Mark an integration as 'beta'"
  task :mark_beta, [:slug] => :environment do |_t, args|
    integration = Integration.find_by(slug: args[:slug])
    if integration
      integration.mark_as_beta!
      puts "✓ Marked '#{integration.name}' as beta"
    else
      puts "✗ Integration with slug '#{args[:slug]}' not found"
    end
  end

  desc "Mark an integration as 'available' (remove status)"
  task :mark_available, [:slug] => :environment do |_t, args|
    integration = Integration.find_by(slug: args[:slug])
    if integration
      integration.mark_as_available!
      puts "✓ Marked '#{integration.name}' as available"
    else
      puts "✗ Integration with slug '#{args[:slug]}' not found"
    end
  end

  desc "List all integrations with their status"
  task list_status: :environment do
    puts "\n📦 Integration Status Report"
    puts "=" * 60

    Integration.global.order(:category, :name).each do |integration|
      status_badge = case integration.status
                     when 'coming_soon' then '🔜 Coming Soon'
                     when 'beta' then '🧪 Beta'
                     when 'deprecated' then '⚠️  Deprecated'
                     else '✅ Available'
                     end
      puts "  [#{integration.category}] #{integration.name.ljust(25)} #{status_badge}"
    end

    puts "\n" + "=" * 60
    puts "Total: #{Integration.global.count} integrations"
    puts "  Coming Soon: #{Integration.global.coming_soon.count}"
    puts "  Beta: #{Integration.global.beta.count}"
    puts "  Available: #{Integration.global.available.count}"
  end

  desc "Seed some integrations as coming soon for demo purposes"
  task seed_coming_soon: :environment do
    # Example integrations that might be coming soon
    coming_soon_slugs = %w[
      salesforce
      hubspot-crm
      dynamics-365
      zendesk
      intercom
    ]

    coming_soon_slugs.each do |slug|
      integration = Integration.find_by(slug: slug)
      if integration
        integration.mark_as_coming_soon!
        puts "✓ Marked '#{integration.name}' as coming soon"
      end
    end
  end
end
