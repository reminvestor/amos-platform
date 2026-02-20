# Run with: podman compose exec web rails runner scripts/check_agent_model.rb

agent = AgentPlugin.find_by(slug: 'landing_page_manager')
if agent
  puts "Agent: #{agent.name}"
  puts "ai_model: #{agent.ai_model.inspect}"
  puts "configuration: #{agent.configuration.inspect}"
  puts ""
  puts "All agents with ai_model set:"
  AgentPlugin.where.not(ai_model: [nil, '']).each do |a|
    puts "  - #{a.slug}: #{a.ai_model}"
  end
else
  puts "Agent not found!"
end
