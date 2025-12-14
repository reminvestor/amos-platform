# Seed data for Hub (Collaborative Intelligence)
#
# Creates default channels and sets up Hub for existing entities

puts "🌐 Seeding Hub Defaults..."

Entity.find_each do |entity|
  puts "  Setting up Hub for #{entity.name}..."

  # Create default channels if they don't exist
  unless entity.team_channels.exists?
    TeamChannel.create_defaults_for(entity)
    puts "    ✓ Created default channels"
  end

  # Create presence records for active agents
  entity_agents = AgentPlugin.active.where(entity: entity).or(AgentPlugin.active.system_wide)
  entity_agents.find_each do |agent|
    HubPresence.find_or_create_by!(
      entity: entity,
      participant: agent
    ) do |presence|
      presence.status = 'online'
      presence.last_seen_at = Time.current
    end
  end
  puts "    ✓ Created agent presence records"

  # Add agents to default channels
  general_channel = entity.team_channels.default_for(entity)
  if general_channel
    entity_agents.find_each do |agent|
      general_channel.add_agent(agent) unless general_channel.has_agent?(agent)
    end
    puts "    ✓ Added agents to channels"
  end
end

puts "✅ Hub Defaults seeded"
