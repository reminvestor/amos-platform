# frozen_string_literal: true

# Rake tasks for agent training and knowledge management

namespace :agents do
  desc "Train an agent by slug (e.g., rails agents:train[quickbooks_agent])"
  task :train, [:agent_slug] => :environment do |_t, args|
    slug = args[:agent_slug]
    
    if slug.blank?
      puts "❌ Please specify an agent slug:"
      puts "   rails agents:train[quickbooks_agent]"
      exit 1
    end
    
    agent = AgentPlugin.find_by(slug: slug)
    
    if agent.nil?
      puts "❌ Agent not found: #{slug}"
      puts "\nAvailable agents:"
      AgentPlugin.pluck(:slug, :name, :status).each do |s, n, st|
        puts "  - #{s} (#{n}) [#{st}]"
      end
      exit 1
    end
    
    puts "🎓 Starting training for: #{agent.name}"
    puts "   Status: #{agent.status}"
    puts "   Role: #{agent.role}"
    puts "-" * 50
    
    service = AgentTrainingService.new(agent)
    result = service.start_training!
    
    puts "-" * 50
    puts "\n📋 Training Log:"
    service.training_log.each do |entry|
      puts "  #{entry[:message]}"
    end
    
    puts "\n" + "=" * 50
    if result[:success]
      puts "✅ Training completed! Agent status: #{agent.reload.status}"
    else
      puts "❌ Training incomplete. Failed at phase: #{result[:phase]}"
      puts "   Error: #{result[:error]}"
    end
  end

  desc "List agents that need training (draft or in_school status)"
  task needs_training: :environment do
    puts "📚 Agents needing training:\n\n"
    
    agents = AgentPlugin.where(status: %w[draft in_school])
    
    if agents.empty?
      puts "  No agents currently need training."
    else
      agents.each do |agent|
        puts "  #{agent.slug}"
        puts "    Name: #{agent.name}"
        puts "    Status: #{agent.status}"
        puts "    Role: #{agent.role}"
        puts "    Created: #{agent.created_at.strftime('%Y-%m-%d')}"
        puts
      end
    end
  end

  desc "Train all draft agents"
  task train_all_drafts: :environment do
    agents = AgentPlugin.where(status: 'draft')
    
    if agents.empty?
      puts "No draft agents to train."
      exit 0
    end
    
    puts "🎓 Training #{agents.count} draft agents...\n\n"
    
    results = { success: 0, failed: 0 }
    
    agents.each do |agent|
      puts "Training: #{agent.name}..."
      service = AgentTrainingService.new(agent)
      result = service.start_training!
      
      if result[:success]
        results[:success] += 1
        puts "  ✅ Graduated (status: #{agent.reload.status})"
      else
        results[:failed] += 1
        puts "  ❌ Failed at #{result[:phase]}: #{result[:error]}"
      end
    end
    
    puts "\n" + "=" * 50
    puts "Results: #{results[:success]} graduated, #{results[:failed]} need attention"
  end

  desc "Show an agent's knowledge base contents"
  task :knowledge, [:agent_slug] => :environment do |_t, args|
    slug = args[:agent_slug]
    
    if slug.blank?
      puts "❌ Please specify an agent slug:"
      puts "   rails agents:knowledge[quickbooks_agent]"
      exit 1
    end
    
    agent = AgentPlugin.find_by(slug: slug)
    
    if agent.nil?
      puts "❌ Agent not found: #{slug}"
      exit 1
    end
    
    kb = agent.knowledge_base
    
    puts "📚 Knowledge Base for: #{agent.name}"
    puts "=" * 50
    
    if kb.nil?
      puts "  No knowledge base found."
      exit 0
    end
    
    puts "Store: #{kb.name}"
    puts "Status: #{kb.status}"
    puts "Documents: #{kb.rag_documents.count}"
    puts "Total Chunks: #{kb.rag_chunks.count}"
    puts
    
    kb.rag_documents.each do |doc|
      puts "📄 #{doc.title || doc.original_filename}"
      puts "   Type: #{doc.metadata&.dig('type') || 'unknown'}"
      puts "   Phase: #{doc.metadata&.dig('phase') || 'unknown'}"
      puts "   Chunks: #{doc.rag_chunks.count}"
      puts "   Created: #{doc.created_at.strftime('%Y-%m-%d %H:%M')}"
      puts
    end
  end

  desc "Test an agent's knowledge retrieval"
  task :test_knowledge, [:agent_slug, :query] => :environment do |_t, args|
    slug = args[:agent_slug]
    query = args[:query] || "What operations are available?"
    
    if slug.blank?
      puts "❌ Please specify an agent slug and query:"
      puts "   rails agents:test_knowledge[quickbooks_agent,'How do I list invoices?']"
      exit 1
    end
    
    agent = AgentPlugin.find_by(slug: slug)
    
    if agent.nil?
      puts "❌ Agent not found: #{slug}"
      exit 1
    end
    
    puts "🔍 Testing knowledge for: #{agent.name}"
    puts "Query: #{query}"
    puts "=" * 50
    
    results = agent.search_knowledge(query, limit: 3)
    
    if results.empty?
      puts "No results found."
    else
      results.each_with_index do |result, i|
        puts "\nResult #{i + 1}:"
        puts "-" * 40
        content = result[:content] || result['content']
        puts content.to_s.truncate(500)
      end
    end
  end

  desc "Create a new integration agent (e.g., rails agents:create_integration[quickbooks])"
  task :create_integration, [:integration_slug] => :environment do |_t, args|
    integration_slug = args[:integration_slug]
    
    if integration_slug.blank?
      puts "❌ Please specify an integration slug:"
      puts "   rails agents:create_integration[quickbooks]"
      exit 1
    end
    
    integration = Integration.find_by(slug: integration_slug)
    
    if integration.nil?
      puts "❌ Integration not found: #{integration_slug}"
      exit 1
    end
    
    agent_slug = "#{integration_slug}_agent"
    
    if AgentPlugin.exists?(slug: agent_slug)
      puts "Agent already exists: #{agent_slug}"
      puts "Run: rails agents:train[#{agent_slug}]"
      exit 0
    end
    
    puts "🤖 Creating agent for: #{integration.name}"
    
    agent = AgentPlugin.create!(
      name: "#{integration.name} Agent",
      slug: agent_slug,
      role: 'executor',
      status: 'draft',
      description: "Expert agent for #{integration.name} integration. Specializes in #{integration.description}",
      configuration: {
        integration_slug: integration_slug,
        integration_id: integration.id
      },
      system_prompt: {
        role: "You are an expert in #{integration.name}.",
        context: "You have deep knowledge of the #{integration.name} API, best practices, and common patterns.",
        guidelines: [
          "Always verify connection status before operations",
          "Use the correct API syntax for this integration",
          "Explain what you're doing and why"
        ]
      }
    )
    
    puts "✅ Created agent: #{agent.name} (#{agent.slug})"
    puts "\nTo train this agent, run:"
    puts "   rails agents:train[#{agent.slug}]"
  end
end


# ============================================
# REFLECTION TASKS
# ============================================

namespace :agents do
  desc "Run reflection cycle for an agent"
  task :reflect, [:agent_slug] => :environment do |_t, args|
    slug = args[:agent_slug]
    
    if slug.blank?
      puts "❌ Please specify an agent slug:"
      puts "   rails agents:reflect[quickbooks_agent]"
      exit 1
    end
    
    agent = AgentPlugin.find_by(slug: slug)
    
    if agent.nil?
      puts "❌ Agent not found: #{slug}"
      exit 1
    end
    
    puts "🔄 Starting reflection cycle for: #{agent.name}"
    puts "-" * 50
    
    service = AgentReflectionService.new(agent)
    result = service.run_reflection_cycle!
    
    puts "\n📋 Reflection Log:"
    service.reflection_log.each do |entry|
      puts "  #{entry[:message]}"
    end
    
    puts "\n" + "=" * 50
    if result[:success]
      puts "✅ Reflection complete!"
      puts "\n📊 Insights:"
      puts "   Tasks analyzed: #{result[:insights][:tasks_analyzed]}"
      puts "   Feedback analyzed: #{result[:insights][:feedback_analyzed]}"
      puts "   Gaps identified: #{result[:insights][:gaps_identified].size}"
      puts "   Knowledge added: #{result[:insights][:knowledge_added]}"
      puts "   Notes created: #{result[:insights][:notes_created]}"
    else
      puts "⏭️ Reflection skipped: #{result[:reason]}"
    end
  end

  desc "Run reflection for all active agents"
  task reflect_all: :environment do
    puts "🔄 Running reflection for all active agents...\n\n"
    
    agents = AgentPlugin.where(status: %w[active probation])
    
    if agents.empty?
      puts "No active agents to reflect."
      exit 0
    end
    
    results = { success: 0, skipped: 0, failed: 0 }
    
    agents.each do |agent|
      puts "Reflecting: #{agent.name}..."
      
      begin
        service = AgentReflectionService.new(agent)
        result = service.run_reflection_cycle!
        
        if result[:success]
          results[:success] += 1
          puts "  ✅ Complete (#{result[:insights][:knowledge_added]} knowledge added)"
        else
          results[:skipped] += 1
          puts "  ⏭️ Skipped (#{result[:reason]})"
        end
      rescue => e
        results[:failed] += 1
        puts "  ❌ Failed: #{e.message}"
      end
    end
    
    puts "\n" + "=" * 50
    puts "Results: #{results[:success]} complete, #{results[:skipped]} skipped, #{results[:failed]} failed"
  end

  desc "Queue async reflection for all active agents"
  task queue_reflections: :environment do
    count = AgentReflectionJob.perform_all_active
    puts "✅ Queued reflection jobs for #{count} agents"
  end

  desc "View an agent's self-notes"
  task :notes, [:agent_slug] => :environment do |_t, args|
    slug = args[:agent_slug]
    
    if slug.blank?
      puts "❌ Please specify an agent slug:"
      puts "   rails agents:notes[quickbooks_agent]"
      exit 1
    end
    
    agent = AgentPlugin.find_by(slug: slug)
    
    if agent.nil?
      puts "❌ Agent not found: #{slug}"
      exit 1
    end
    
    kb = agent.knowledge_base
    
    if kb.nil?
      puts "No knowledge base found for #{agent.name}"
      exit 0
    end
    
    notes = kb.rag_documents.where("metadata->>'phase' = ?", 'self_notes')
               .order(created_at: :desc)
               .limit(10)
    
    puts "📝 Self-Notes for: #{agent.name}"
    puts "=" * 50
    
    if notes.empty?
      puts "  No self-notes yet. Run reflection first:"
      puts "  rails agents:reflect[#{slug}]"
    else
      notes.each do |note|
        puts "\n📄 #{note.title}"
        puts "   Created: #{note.created_at.strftime('%Y-%m-%d %H:%M')}"
        puts "-" * 40
        
        content = note.rag_chunks.first&.content
        puts content&.truncate(500) || "(no content)"
        puts
      end
    end
  end

  desc "Show agent learning statistics"
  task :learning_stats, [:agent_slug] => :environment do |_t, args|
    slug = args[:agent_slug]
    
    agent = if slug.present?
      AgentPlugin.find_by(slug: slug)
    else
      nil
    end
    
    agents = agent ? [agent] : AgentPlugin.where(status: %w[active probation])
    
    puts "📊 Agent Learning Statistics"
    puts "=" * 60
    
    agents.each do |a|
      kb = a.knowledge_base
      metadata = a.metadata || {}
      
      puts "\n#{a.name} (#{a.slug})"
      puts "-" * 40
      puts "  Status: #{a.status}"
      puts "  Knowledge Documents: #{kb&.rag_documents&.count || 0}"
      puts "  Knowledge Chunks: #{kb&.rag_chunks&.count || 0}"
      puts "  Reflection Count: #{metadata['reflection_count'] || 0}"
      puts "  Last Reflection: #{metadata['last_reflection_at'] || 'Never'}"
      
      if metadata['training_competency']
        puts "  Training Pass Rate: #{metadata['training_competency']['pass_rate']}%"
      end
      
      if metadata['last_reflection_insights']
        insights = metadata['last_reflection_insights']
        puts "  Last Insights:"
        puts "    - Tasks Analyzed: #{insights['tasks_analyzed']}"
        puts "    - Knowledge Added: #{insights['knowledge_added']}"
        puts "    - Notes Created: #{insights['notes_created']}"
      end
    end
  end
end
