# frozen_string_literal: true

# Default AI Usage Policies
#
# These policies are applied to every entity to ensure sensible defaults
# for AI agent operations. Entities can customize or disable these as needed.
#
# Policies include:
#   - Write protection (requires confirmation)
#   - Delete protection (requires confirmation)
#   - External API call budgets (1000/day)
#   - Email sending confirmation
#   - Bulk operation confirmation
#   - Financial operation confirmation
#   - Data export confirmation
#   - Read access (allowed by default)

puts "🛡️  Seeding default AI usage policies..."

# Backfill policies for all existing entities that don't have them
# NOTE: Global fallback policies are skipped because policy_rules.entity_id
# has a NOT NULL constraint. Entity-specific policies are sufficient since
# DefaultPoliciesService.create_for runs on Entity after_create.
created = 0
Entity.find_each do |entity|
  if entity.policy_rules.empty?
    count = DefaultPoliciesService.create_for(entity)
    created += count
    puts "  ✅ Created #{count} default policies for #{entity.name}" if count > 0
  end
end

total = PolicyRule.count
puts "✅ Default AI usage policies seeded!"
puts "   - #{total} total policies across all entities"
puts "   - #{created} new policies created this run"
