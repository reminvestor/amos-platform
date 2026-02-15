# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).
#
# Example:
#
#   ["Action", "Comedy", "Drama", "Horror"].each do |genre_name|
#     MovieGenre.find_or_create_by!(name: genre_name)
#   end

puts "Seeding affiliate tiers..."

# Create affiliate tiers
tiers = [
  {
    name: "Bronze",
    commission_rate: 0.20,  # 20%
    min_referrals: 0,
    benefits: {
      priority_support: false,
      early_feature_access: false,
      dedicated_account_manager: false,
      comarketing_opportunities: false,
      description: "Standard marketing materials"
    },
    is_active: true
  },
  {
    name: "Silver",
    commission_rate: 0.25,  # 25%
    min_referrals: 5,
    benefits: {
      priority_support: true,
      early_feature_access: true,
      dedicated_account_manager: false,
      comarketing_opportunities: false,
      description: "Priority support and early feature access"
    },
    is_active: true
  },
  {
    name: "Gold",
    commission_rate: 0.30,  # 30%
    min_referrals: 20,
    benefits: {
      priority_support: true,
      early_feature_access: true,
      dedicated_account_manager: true,
      comarketing_opportunities: true,
      description: "Dedicated account manager and co-marketing opportunities"
    },
    is_active: true
  }
]

tiers.each do |tier_data|
  tier = AffiliateTier.find_or_initialize_by(name: tier_data[:name])
  tier.update!(tier_data)
  puts "  Created/Updated tier: #{tier.name} (#{(tier.commission_rate * 100).to_i}% commission, #{tier.min_referrals}+ referrals)"
end

puts "Affiliate tiers seeded successfully!"
puts ""

# Seed Voice Assistant settings
puts "Seeding Voice Assistant settings..."
VoiceAssistantSetting.seed_defaults!
puts "Voice Assistant settings seeded!"
puts ""

# Helper: load a seed file with error isolation so one failure doesn't block the rest
def safe_load_seed(file, critical: false)
  path = Rails.root.join('db', 'seeds', file)
  load path
rescue => e
  puts "⚠️  Seed '#{file}' failed: #{e.message}"
  puts "   #{e.backtrace&.first}"
  raise if critical  # Re-raise if this seed is required for subsequent seeds
end

# Load additional seeds — each wrapped so failures don't cascade
safe_load_seed 'tool_definitions.rb'
safe_load_seed 'agent_plugins.rb'
safe_load_seed 'ai_rulesets.rb'
# Temporarily disabled - has invalid attributes for current schema
# safe_load_seed 'integration_repair_agent.rb'
safe_load_seed 'analytics_agent.rb'
safe_load_seed 'document_export_agent.rb'
safe_load_seed 'document_import_agent.rb'
safe_load_seed 'space_definitions.rb'
safe_load_seed 'platform_factory.rb'
safe_load_seed 'application_planner.rb'
safe_load_seed 'frontend_design_expert.rb'

# Integration seeds — integrations.rb must succeed for the cleanup to work
safe_load_seed 'integrations.rb', critical: true
safe_load_seed 'integration_actions.rb'
safe_load_seed 'godaddy_integration.rb'

# Clean up integration operations: remove duplicates, add proper schemas
# This must run AFTER integrations.rb and integration_actions.rb
safe_load_seed 'integration_operations_cleanup.rb'

if Rails.env.development?
  safe_load_seed 'demo_users.rb'
end

# Load policy rules (after entities exist)
safe_load_seed 'policy_rules.rb'
