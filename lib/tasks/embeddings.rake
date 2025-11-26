namespace :embeddings do
  desc "Update embeddings for all models (agents, tools, integrations)"
  task update_all: :environment do
    puts "🔄 Updating embeddings for all models..."
    result = UpdateEmbeddingsJob.perform_now(model: "all")
    puts "✅ Complete: #{result}"
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

    models = [
      { name: "AgentPlugin", class: AgentPlugin },
      { name: "ToolDefinition", class: ToolDefinition },
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

