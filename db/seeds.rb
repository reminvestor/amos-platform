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

# Load additional seeds
load Rails.root.join('db', 'seeds', 'tool_definitions.rb')
load Rails.root.join('db', 'seeds', 'agent_plugins.rb')
load Rails.root.join('db', 'seeds', 'ai_rulesets.rb')
# Temporarily disabled - has invalid attributes for current schema
# load Rails.root.join('db', 'seeds', 'integration_repair_agent.rb')
load Rails.root.join('db', 'seeds', 'analytics_agent.rb')
load Rails.root.join('db', 'seeds', 'document_export_agent.rb')
load Rails.root.join('db', 'seeds', 'document_import_agent.rb')
load Rails.root.join('db', 'seeds', 'space_definitions.rb')
load Rails.root.join('db', 'seeds', 'platform_factory.rb')
load Rails.root.join('db', 'seeds', 'application_planner.rb')
load Rails.root.join('db', 'seeds', 'frontend_design_expert.rb')
load Rails.root.join('db', 'seeds', 'integrations.rb')
load Rails.root.join('db', 'seeds', 'integration_actions.rb')
load Rails.root.join('db', 'seeds', 'godaddy_integration.rb')

if Rails.env.development?
  load Rails.root.join('db', 'seeds', 'demo_users.rb')
end
