# frozen_string_literal: true

namespace :policies do
  desc "Backfill default AI usage policies for all entities"
  task backfill: :environment do
    puts "🛡️  Backfilling default AI usage policies..."
    
    entities_without_policies = Entity.left_joins(:policy_rules)
                                       .where(policy_rules: { id: nil })
                                       .distinct
    
    puts "   Found #{entities_without_policies.count} entities without policies"
    
    entities_without_policies.find_each do |entity|
      count = DefaultPoliciesService.create_for(entity)
      puts "   ✅ Created #{count} policies for: #{entity.name}"
    end
    
    # Create global fallbacks
    global_count = DefaultPoliciesService.create_global_fallbacks
    puts "   ✅ Created #{global_count} global fallback policies"
    
    puts ""
    puts "✅ Done! Total policies: #{PolicyRule.count}"
    puts "   - Entity-specific: #{PolicyRule.where.not(entity_id: nil).count}"
    puts "   - Global fallbacks: #{PolicyRule.where(entity_id: nil).count}"
  end

  desc "List all policies for an entity"
  task :list, [:entity_id] => :environment do |t, args|
    entity = Entity.find(args[:entity_id])
    
    puts "📋 Policies for: #{entity.name}"
    puts "-" * 60
    
    entity.policy_rules.each do |policy|
      status = policy.is_active ? "✅ Active" : "❌ Inactive"
      confirm = policy.requires_confirmation ? "🔐 Requires Confirmation" : ""
      
      puts "#{status} #{policy.name}"
      puts "   Type: #{policy.resource_type} | Action: #{policy.action} #{confirm}"
      puts ""
    end
  end
end
