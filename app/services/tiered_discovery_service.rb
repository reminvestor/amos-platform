# TieredDiscoveryService
#
# Provides intelligent, RAG-based discovery for agents, tools, and integrations.
# Uses vector similarity search with prioritization based on:
# - User ownership (user-created items ranked higher)
# - Entity scope (entity-specific items ranked higher)
# - Usage frequency (popular items ranked higher)
# - Semantic relevance (cosine similarity)
#
# This enables scaling to thousands of tools/agents/integrations while only
# sending a focused, relevant subset to the LLM.
#
class TieredDiscoveryService
  # Core tools that are ALWAYS available (essential for basic operation)
  CORE_TOOLS = %w[
    load_canvas
    ask_user
    get_data
    get_schema
    create_object
    update_object
    delegate_to_agent
    list_available_agents
    web_search
    read_document
    query_document_content
  ].freeze

  # Maximum tools to send to LLM per category
  MAX_DISCOVERED_TOOLS = 15
  MAX_DISCOVERED_AGENTS = 10
  MAX_DISCOVERED_INTEGRATIONS = 10
  MAX_DISCOVERED_OPERATIONS = 10

  # Boost factors for prioritization
  USER_OWNERSHIP_BOOST = 0.3
  ENTITY_SCOPE_BOOST = 0.2
  CONNECTED_INTEGRATION_BOOST = 0.25
  USAGE_FREQUENCY_BOOST = 0.15

  attr_reader :user, :entity, :prompt

  def initialize(user:, entity:, prompt: nil)
    @user = user
    @entity = entity
    @prompt = prompt
    @usage_cache = nil
  end

  # Get cached usage data for the entity
  def usage_data
    @usage_cache ||= if defined?(ToolUsageMetric) && @entity
      ToolUsageMetric.top_tools_for_entity(@entity, limit: 50)
    else
      {}
    end
  end

  # Calculate usage boost based on frequency
  def usage_boost_for(tool_name)
    return 0.0 unless usage_data.any?

    count = usage_data[tool_name] || 0
    max_count = usage_data.values.max || 1

    # Normalize to 0-1 range and apply boost factor
    (count.to_f / max_count) * USAGE_FREQUENCY_BOOST
  end

  # Main discovery method - returns prioritized tools for the LLM
  def discover_tools(prompt: nil, include_core: true)
    @prompt = prompt if prompt.present?
    return core_tools if @prompt.blank?

    discovered = []

    # 1. Always include core tools
    discovered += core_tools if include_core

    # 2. Discover relevant class-based tools via RAG
    discovered += discover_class_tools

    # 3. Discover relevant dynamic tools (ToolDefinition) via RAG
    discovered += discover_dynamic_tools

    # 4. Discover relevant integration operations
    discovered += discover_integration_tools

    # Deduplicate by tool name
    discovered.uniq { |t| t[:name] }
  end

  # Discover relevant agents for delegation
  def discover_agents(prompt: nil, limit: MAX_DISCOVERED_AGENTS)
    @prompt = prompt if prompt.present?
    return [] if @prompt.blank?

    begin
      # Use vector similarity search
      agents = AgentPlugin.active.search_by_similarity(@prompt, limit: limit * 2)

      # Apply prioritization
      prioritized = agents.map do |agent|
        score = agent.try(:neighbor_distance) || 0.5 # Lower is better for cosine
        similarity = 1.0 - score # Convert to similarity (higher is better)

        # Apply boosts
        similarity += USER_OWNERSHIP_BOOST if agent.user_id == @user&.id
        similarity += ENTITY_SCOPE_BOOST if agent.entity_id == @entity&.id

        {
          agent: agent,
          score: similarity,
          editable: agent.editable_by?(@user)
        }
      end

      # Sort by score (highest first) and take top results
      prioritized
        .sort_by { |a| -a[:score] }
        .first(limit)
        .map do |item|
          agent = item[:agent]
          {
            slug: agent.slug,
            name: agent.name,
            role: agent.role,
            description: agent.description,
            capabilities: agent.agent_capabilities.map(&:capability_name),
            editable: item[:editable],
            relevance_score: item[:score].round(3)
          }
        end
    rescue => e
      Rails.logger.error "Agent discovery failed: #{e.message}"
      []
    end
  end

  # Discover relevant integrations
  def discover_integrations(prompt: nil, limit: MAX_DISCOVERED_INTEGRATIONS)
    @prompt = prompt if prompt.present?
    return [] if @prompt.blank?

    begin
      # Get connected integrations for this entity
      connected_integration_ids = Connection
        .where(entity: @entity, status: :connected)
        .pluck(:integration_id)

      # Use vector similarity search
      integrations = Integration.active.search_by_similarity(@prompt, limit: limit * 2)

      # Apply prioritization
      prioritized = integrations.map do |integration|
        score = integration.try(:neighbor_distance) || 0.5
        similarity = 1.0 - score

        # Boost connected integrations significantly
        similarity += CONNECTED_INTEGRATION_BOOST if connected_integration_ids.include?(integration.id)

        {
          integration: integration,
          score: similarity,
          connected: connected_integration_ids.include?(integration.id)
        }
      end

      # Sort by score and take top results
      prioritized
        .sort_by { |i| -i[:score] }
        .first(limit)
        .map do |item|
          integration = item[:integration]
          {
            slug: integration.slug,
            name: integration.name,
            category: integration.category,
            description: integration.description,
            connected: item[:connected],
            operation_count: integration.integration_operations.enabled.count,
            relevance_score: item[:score].round(3)
          }
        end
    rescue => e
      Rails.logger.error "Integration discovery failed: #{e.message}"
      []
    end
  end

  # Discover operations for a specific integration
  def discover_operations(integration_slug:, prompt: nil, limit: MAX_DISCOVERED_OPERATIONS)
    @prompt = prompt if prompt.present?

    integration = Integration.find_by(slug: integration_slug)
    return [] unless integration

    operations = integration.integration_operations.enabled

    # If we have a prompt and operations have embeddings, use RAG
    if @prompt.present? && operations.first&.respond_to?(:embedding) && operations.first&.embedding.present?
      begin
        query_embedding = AiAgents::VectorStore.instance.generate_embedding(@prompt)
        operations = operations.nearest_neighbors(:embedding, query_embedding, distance: "cosine").first(limit)
      rescue => e
        Rails.logger.warn "Operation RAG search failed, falling back to all: #{e.message}"
        operations = operations.limit(limit)
      end
    else
      operations = operations.limit(limit)
    end

    operations.map do |op|
      {
        operation_id: op.operation_id,
        name: op.name,
        description: op.description,
        http_method: op.http_method,
        path_template: op.path_template,
        requires_confirmation: op.requires_confirmation
      }
    end
  end

  # Get a combined discovery result for the LLM context
  def full_discovery(prompt: nil)
    @prompt = prompt if prompt.present?

    {
      tools: discover_tools,
      agents: discover_agents,
      integrations: discover_integrations,
      prompt_used: @prompt,
      discovery_timestamp: Time.current.iso8601
    }
  end

  private

  def core_tools
    catalog = Tools::ToolCatalog.instance
    
    CORE_TOOLS.filter_map do |tool_name|
      tool_def = catalog.get_tool_definition(tool_name)
      next unless tool_def

      {
        name: tool_def[:name],
        description: tool_def[:description],
        parameters: tool_def[:parameters],
        source: :core,
        priority: :high
      }
    end
  end

  def discover_class_tools
    return [] if @prompt.blank?

    catalog = Tools::ToolCatalog.instance
    all_tools = catalog.all_tools

    # Get tool names and descriptions for semantic matching
    tool_texts = all_tools.map do |name, info|
      next if CORE_TOOLS.include?(name)
      {
        name: name,
        text: "#{name}: #{info[:metadata][:description]}",
        metadata: info[:metadata]
      }
    end.compact

    # Simple keyword matching as fallback (class tools don't have embeddings)
    # In future, we could add embeddings to class tools too
    keywords = extract_keywords(@prompt)
    
    matched = tool_texts.select do |tool|
      keywords.any? { |kw| tool[:text].downcase.include?(kw.downcase) }
    end

    matched.first(MAX_DISCOVERED_TOOLS / 2).map do |tool|
      {
        name: tool[:name],
        description: tool[:metadata][:description],
        parameters: tool[:metadata][:input_schema] || tool[:metadata][:parameters],
        source: :class,
        priority: :medium
      }
    end
  end

  def discover_dynamic_tools
    return [] if @prompt.blank?

    begin
      # Use vector similarity search on ToolDefinition
      tools = ToolDefinition
        .for_entity(@entity)
        .where.not(embedding: nil)
        .search_by_similarity(@prompt, limit: MAX_DISCOVERED_TOOLS)

      # Apply prioritization
      prioritized = tools.map do |tool|
        score = tool.try(:neighbor_distance) || 0.5
        similarity = 1.0 - score

        # Apply boosts
        similarity += USER_OWNERSHIP_BOOST if tool.created_by_id == @user&.id
        similarity += ENTITY_SCOPE_BOOST if tool.entity_id == @entity&.id
        similarity += usage_boost_for(tool.name)

        { tool: tool, score: similarity }
      end

      prioritized
        .sort_by { |t| -t[:score] }
        .first(MAX_DISCOVERED_TOOLS / 2)
        .map do |item|
          tool = item[:tool]
          {
            name: tool.name,
            description: tool.description,
            parameters: tool.parameters,
            source: :dynamic,
            priority: tool.created_by_id == @user&.id ? :high : :medium,
            owner: tool.created_by_id == @user&.id ? :user : :system,
            relevance_score: item[:score].round(3)
          }
        end
    rescue => e
      Rails.logger.error "Dynamic tool discovery failed: #{e.message}"
      []
    end
  end

  def discover_integration_tools
    return [] if @prompt.blank?

    # Find connected integrations relevant to the prompt
    relevant_integrations = discover_integrations(limit: 3)
    
    tools = []

    relevant_integrations.each do |int_info|
      next unless int_info[:connected]

      # Add a meta-tool for invoking this integration
      tools << {
        name: "invoke_#{int_info[:slug]}",
        description: "Execute operations on #{int_info[:name]}: #{int_info[:description]}",
        parameters: {
          type: "object",
          properties: {
            operation: { type: "string", description: "The operation to execute" },
            params: { type: "object", description: "Parameters for the operation" }
          },
          required: ["operation"]
        },
        source: :integration,
        priority: :high,
        integration_slug: int_info[:slug],
        available_operations: int_info[:operation_count]
      }
    end

    tools
  end

  def extract_keywords(text)
    # Simple keyword extraction - remove common words
    stopwords = %w[the a an is are was were be been being have has had do does did will would could should may might must shall can need want to from for with on at by about into through during before after above below between under again further then once here there when where why how all each few more most other some such no nor not only own same so than too very just]
    
    text.downcase
        .gsub(/[^a-z0-9\s]/, '')
        .split(/\s+/)
        .reject { |w| stopwords.include?(w) || w.length < 3 }
        .uniq
        .first(10)
  end
end

