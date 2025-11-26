namespace :embeddings do
  desc "Update embeddings for all models (agents, tools, integrations, class tools)"
  task update_all: :environment do
    puts "🔄 Updating embeddings for all models..."
    
    # Update database-backed models
    result = UpdateEmbeddingsJob.perform_now(model: "all")
    puts "📊 Database models: #{result}"
    
    # Update class-based tools (cached)
    puts "🔄 Updating class tool embeddings..."
    ClassToolEmbeddingsService.instance.reload!
    puts "✅ Class tools updated and cached"
    
    puts "✅ All embeddings complete!"
  end

  desc "Update embeddings for class-based tools only (cached)"
  task update_class_tools: :environment do
    puts "🔄 Updating class tool embeddings..."
    ClassToolEmbeddingsService.instance.reload!
    puts "✅ Class tools updated and cached"
  end

  desc "Update embeddings for agents only"
  task update_agents: :environment do
    puts "🔄 Updating embeddings for agents..."
    result = UpdateEmbeddingsJob.perform_now(model: "AgentPlugin")
    puts "✅ Complete: #{result}"
  end

  desc "Update embeddings for tools only"
  task update_tools: :environment do
    puts "🔄 Updating embeddings for tools..."
    result = UpdateEmbeddingsJob.perform_now(model: "ToolDefinition")
    puts "✅ Complete: #{result}"
  end

  desc "Update embeddings for integrations only"
  task update_integrations: :environment do
    puts "🔄 Updating embeddings for integrations..."
    result = UpdateEmbeddingsJob.perform_now(model: "Integration")
    puts "✅ Complete: #{result}"
  end

  desc "Update embeddings for integration operations only"
  task update_operations: :environment do
    puts "🔄 Updating embeddings for integration operations..."
    result = UpdateEmbeddingsJob.perform_now(model: "IntegrationOperation")
    puts "✅ Complete: #{result}"
  end

  desc "Force update all embeddings (even if already set)"
  task force_update_all: :environment do
    puts "🔄 Force updating ALL embeddings..."
    result = UpdateEmbeddingsJob.perform_now(model: "all", force: true)
    puts "✅ Complete: #{result}"
  end

  desc "Show embedding statistics"
  task stats: :environment do
    puts "\n📊 Embedding Statistics\n"
    puts "=" * 50

    # Database-backed models
    models = [
      { name: "AgentPlugin", class: AgentPlugin },
      { name: "ToolDefinition (Dynamic)", class: ToolDefinition },
      { name: "Integration", class: Integration }
    ]

    # Add IntegrationOperation only if it has embedding column
    if IntegrationOperation.column_names.include?("embedding")
      models << { name: "IntegrationOperation", class: IntegrationOperation }
    end

    models.each do |model|
      total = model[:class].count
      with_embedding = model[:class].where.not(embedding: nil).count
      without_embedding = total - with_embedding
      percentage = total > 0 ? (with_embedding.to_f / total * 100).round(1) : 0

      puts "\n#{model[:name]}:"
      puts "  Total: #{total}"
      puts "  With embedding: #{with_embedding} (#{percentage}%)"
      puts "  Without embedding: #{without_embedding}"
    end

    # Class-based tools (cached)
    puts "\nClass-Based Tools (Cached):"
    begin
      service = ClassToolEmbeddingsService.instance
      embeddings = service.embeddings
      total_class = embeddings.size
      with_embedding_class = embeddings.count { |_, data| data[:embedding].present? }
      percentage_class = total_class > 0 ? (with_embedding_class.to_f / total_class * 100).round(1) : 0
      
      puts "  Total: #{total_class}"
      puts "  With embedding: #{with_embedding_class} (#{percentage_class}%)"
      puts "  Without embedding: #{total_class - with_embedding_class}"
    rescue => e
      puts "  Error loading: #{e.message}"
    end

    puts "\n" + "=" * 50
  end

  desc "Test tiered discovery with a sample prompt"
  task :test_discovery, [:prompt] => :environment do |_t, args|
    prompt = args[:prompt] || "send email to stripe customers"
    
    # Use first admin user for testing
    user = User.find_by(admin: true) || User.first
    entity = user&.entities&.first || Entity.first

    unless user && entity
      puts "❌ No user/entity found for testing"
      next
    end

    puts "\n🔍 Testing Tiered Discovery"
    puts "=" * 50
    puts "Prompt: #{prompt}"
    puts "User: #{user.email}"
    puts "Entity: #{entity.name}"
    puts "=" * 50

    discovery = TieredDiscoveryService.new(user: user, entity: entity, prompt: prompt)

    puts "\n📦 Discovered Tools:"
    tools = discovery.discover_tools
    tools.each do |tool|
      priority = tool[:priority] || :normal
      source = tool[:source] || :unknown
      puts "  [#{priority}][#{source}] #{tool[:name]}: #{tool[:description]&.truncate(60)}"
    end

    puts "\n🤖 Discovered Agents:"
    agents = discovery.discover_agents
    agents.each do |agent|
      puts "  [#{agent[:relevance_score]}] #{agent[:name]} (#{agent[:role]}): #{agent[:description]&.truncate(50)}"
    end

    puts "\n🔌 Discovered Integrations:"
    integrations = discovery.discover_integrations
    integrations.each do |int|
      connected = int[:connected] ? "✅" : "❌"
      puts "  #{connected} [#{int[:relevance_score]}] #{int[:name]} (#{int[:category]}): #{int[:operation_count]} operations"
    end

    puts "\n" + "=" * 50
    puts "Total: #{tools.length} tools, #{agents.length} agents, #{integrations.length} integrations"
  end
end

