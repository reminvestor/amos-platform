# frozen_string_literal: true

# Initialize energy states for all agents that don't have one
puts "🔋 Initializing Agent Energy States..."

count = 0
errors = 0

AgentPlugin.find_each do |agent|
  next if agent.energy_state.present?

  begin
    entity = agent.entity || Entity.first

    AgentEnergyState.create!(
      agent_plugin: agent,
      entity: entity,
      current_energy: 50.0,
      max_energy: 100.0,
      regeneration_rate: 2.0,
      last_energy_update_at: Time.current
    )

    # Also create decision boundary
    AgentDecisionBoundary.find_or_create_by!(agent_plugin: agent)

    count += 1
    puts "  ✓ Initialized energy state for #{agent.name}"
  rescue => e
    errors += 1
    puts "  ✗ Error initializing #{agent.name}: #{e.message}"
  end
end

# Initialize community pools for all entities
Entity.find_each do |entity|
  CommunityEnergyPool.find_or_create_by!(entity: entity)
end

puts "✅ Initialized #{count} agent energy states (#{errors} errors)"
puts "✅ Initialized community pools for all entities"

