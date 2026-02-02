# frozen_string_literal: true

# Default AI Usage Policies
#
# These policies are applied to every new entity to ensure sensible defaults
# for AI agent operations. Entities can customize or disable these as needed.

puts "🛡️  Seeding default AI usage policies..."

# Backfill policies for all existing entities that don't have them
DefaultPoliciesService.backfill_all

puts "✅ Default AI usage policies seeded!"
puts "   - #{PolicyRule.where.not(entity_id: nil).count} entity-specific policies"
puts "   - #{PolicyRule.where(entity_id: nil).count} global fallback policies"
