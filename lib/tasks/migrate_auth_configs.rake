namespace :integrations do
  desc "Migrate seed-based auth configs to database OauthConfiguration records"
  task migrate_auth_configs: :environment do
    puts "🔄 Migrating auth configurations to database..."
    
    Integration.where.not(auth_type: 'oauth2').find_each do |integration|
      # Skip if already has oauth_configuration
      if OauthConfiguration.exists?(integration: integration)
        puts "⏭️  Skipping #{integration.name} - already has auth config"
        next
      end
      
      puts "\n📦 Processing #{integration.name} (#{integration.auth_type})..."
      
      # Create oauth_configuration
      oauth_config = OauthConfiguration.create!(
        integration: integration,
        status: :active
      )
      
      # Parse auth_config and create auth_configs based on auth_type
      case integration.auth_type
      when 'basic_auth'
        # Stripe-like: Basic auth with API key as username
        if integration.auth_config&.dig('password_required') == false
          # Just API key in username field
          oauth_config.auth_configs.create!(
            auth_key: 'api_key',
            auth_value: 'Basic {api_key}',
            auth_placement: 'header',
            position: 0
          )
          puts "  ✅ Created: api_key (Basic auth header)"
        else
          # Standard username/password basic auth
          oauth_config.auth_configs.create!(
            auth_key: 'username',
            auth_value: 'Basic {username}:{password}',
            auth_placement: 'header',
            position: 0
          )
          puts "  ✅ Created: username (Basic auth header)"
        end
        
      when 'api_key'
        # Standard API key
        field_name = integration.auth_config&.dig('auth_field_name') || 'X-API-Key'
        oauth_config.auth_configs.create!(
          auth_key: 'api_key',
          auth_value: '{api_key}',
          auth_placement: 'header',
          position: 0
        )
        puts "  ✅ Created: api_key (header: #{field_name})"
        
      when 'bearer_token'
        oauth_config.auth_configs.create!(
          auth_key: 'bearer_token',
          auth_value: 'Bearer {bearer_token}',
          auth_placement: 'header',
          position: 0
        )
        puts "  ✅ Created: bearer_token (Bearer header)"
        
      when 'custom'
        # Handle special cases
        case integration.slug
        when 'slack'
          oauth_config.auth_configs.create!(
            auth_key: 'webhook_url',
            auth_value: '{webhook_url}',
            auth_placement: 'url',
            position: 0
          )
          puts "  ✅ Created: webhook_url (URL)"
        else
          puts "  ⚠️  Custom auth - skipping, needs manual configuration"
        end
      end
    end
    
    puts "\n✅ Migration complete!"
    puts "\n📊 Summary:"
    puts "  Total integrations: #{Integration.count}"
    puts "  With auth configs: #{OauthConfiguration.count}"
    puts "  Auth config fields: #{AuthConfig.count}"
  end
  
  desc "Remove all auth configs (rollback migration)"
  task rollback_auth_configs: :environment do
    puts "⚠️  Rolling back auth configurations..."
    
    count = OauthConfiguration.where.not(integration: Integration.where(auth_type: 'oauth2')).count
    
    if count > 0
      print "Delete #{count} non-OAuth auth configurations? (y/N): "
      response = STDIN.gets.chomp
      
      if response.downcase == 'y'
        OauthConfiguration.where.not(integration: Integration.where(auth_type: 'oauth2')).destroy_all
        puts "✅ Deleted #{count} auth configurations"
      else
        puts "❌ Cancelled"
      end
    else
      puts "No non-OAuth auth configurations to delete"
    end
  end
end
