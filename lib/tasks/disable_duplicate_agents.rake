namespace :agents do
  desc "Disable duplicate/deprecated agents"
  task disable_duplicates: :environment do
    puts "🔍 Looking for duplicate agents to disable..."
    
    # List of agents to disable (name patterns)
    deprecated_agents = [
      "AI Landing Page Creator",  # Replaced by Landing Page Manager
    ]
    
    deprecated_agents.each do |name_pattern|
      agents = AgentPlugin.where("name ILIKE ?", "%#{name_pattern}%")
      
      if agents.any?
        agents.each do |agent|
          old_status = agent.status
          agent.update!(status: 'inactive')
          puts "  ✅ Disabled: #{agent.name} (ID: #{agent.id}, was: #{old_status})"
        end
      else
        puts "  ⚠️ No agent found matching: #{name_pattern}"
      end
    end
    
    puts "\n✨ Done! Disabled #{deprecated_agents.length} deprecated agent(s)."
  end
  
  desc "List all landing page related agents"
  task list_landing_page_agents: :environment do
    agents = AgentPlugin.where("name ILIKE ? OR slug ILIKE ?", "%landing%page%", "%landing%page%")
    
    puts "\n📋 Landing Page Agents:\n"
    agents.each do |a|
      puts "  - #{a.name} (slug: #{a.slug}, status: #{a.status}, ID: #{a.id})"
    end
    puts "\nTotal: #{agents.count}"
  end
end

