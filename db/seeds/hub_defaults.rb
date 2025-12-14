# Seed data for Hub (Collaborative Intelligence)
#
# Creates default channels and sets up Hub for existing entities

puts "🌐 Seeding Hub Defaults..."

Entity.find_each do |entity|
  puts "  Setting up Hub for #{entity.name}..."

  # Create default channels if they don't exist
  unless entity.team_channels.exists?
    begin
      TeamChannel.create_defaults_for(entity)
      puts "    ✓ Created default channels"
    rescue => e
      puts "    ⚠ Channels may already exist: #{e.message.truncate(50)}"
    end
  end

  # Create presence records for active agents
  # Note: Presence is unique by (participant_type, participant_id) globally
  entity_agents = AgentPlugin.active.where(entity: entity).or(AgentPlugin.active.system_wide)
  entity_agents.find_each do |agent|
    begin
      existing = HubPresence.find_by(participant: agent)
      if existing
        existing.update(entity: entity) if existing.entity_id.nil?
      else
        HubPresence.create!(
          entity: entity,
          participant: agent,
          status: 'online',
          last_seen_at: Time.current
        )
      end
    rescue ActiveRecord::RecordNotUnique
      # Already exists, skip
    end
  end
  puts "    ✓ Created agent presence records"

  # Add agents to default channels
  general_channel = entity.team_channels.find_by(is_default: true) || entity.team_channels.first
  if general_channel
    entity_agents.find_each do |agent|
      begin
        general_channel.add_agent(agent) unless general_channel.has_agent?(agent)
      rescue => e
        # Skip if already added
      end
    end
    puts "    ✓ Added agents to channels"
  end
end

puts "✅ Hub Defaults seeded"
