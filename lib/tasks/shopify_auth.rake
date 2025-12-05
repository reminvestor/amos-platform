# frozen_string_literal: true

namespace :integrations do
  desc "Configure Shopify OAuth to use X-Shopify-Access-Token header"
  task configure_shopify_auth: :environment do
    puts "Configuring Shopify OAuth authentication..."
    
    integration = Integration.find_by(slug: "shopify")
    unless integration
      puts "❌ Shopify integration not found"
      exit 1
    end
    
    oauth_config = integration.oauth_configurations.first
    unless oauth_config
      puts "❌ Shopify OAuth configuration not found"
      exit 1
    end
    
    # Check if auth config already exists
    existing = oauth_config.auth_configs.find_by(auth_key: "X-Shopify-Access-Token")
    
    if existing
      puts "✅ Shopify auth config already exists: #{existing.auth_key} = #{existing.auth_value}"
    else
      auth_config = oauth_config.auth_configs.create!(
        auth_key: "X-Shopify-Access-Token",
        auth_value: "{access_token}",
        auth_placement: "header",
        position: 1
      )
      puts "✅ Created Shopify auth config: #{auth_config.auth_key} = #{auth_config.auth_value}"
    end
    
    puts "Done! Shopify OAuth will now use X-Shopify-Access-Token header."
  end
end

