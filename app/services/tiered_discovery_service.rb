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
# CACHING: Results are cached for 60 seconds by prompt hash to reduce latency
# on repeated similar queries.
#
class TieredDiscoveryService
  # Simple in-memory cache for discovery results
  # Key: entity_id:space_id:prompt_hash, Value: { result:, expires_at: }
  # SPACE-AWARE: Different spaces may need different tool sets
  CACHE = {}
  CACHE_TTL = 60.seconds # Short TTL - prompts change frequently
  CACHE_MAX_SIZE = 100   # Prevent memory bloat
  
  def self.cache_key(entity_id, prompt, space_id: nil)
    # Normalize prompt for caching (lowercase, remove extra whitespace)
    normalized = prompt.to_s.downcase.gsub(/\s+/, ' ').strip
    space_part = space_id.present? ? ":s#{space_id}" : ""
    "#{entity_id}#{space_part}:#{Digest::MD5.hexdigest(normalized)}"
  end
  
  def self.get_cached(entity_id, prompt, space_id: nil)
    key = cache_key(entity_id, prompt, space_id: space_id)
    cached = CACHE[key]
    return nil unless cached
    return nil if Time.current > cached[:expires_at]
    cached[:result]
  end
  
  def self.set_cached(entity_id, prompt, result, space_id: nil)
    # Evict old entries if cache is full
    if CACHE.size >= CACHE_MAX_SIZE
      expired_keys = CACHE.select { |_, v| Time.current > v[:expires_at] }.keys
      expired_keys.each { |k| CACHE.delete(k) }
      
      # If still full, remove oldest half
      if CACHE.size >= CACHE_MAX_SIZE
        oldest = CACHE.sort_by { |_, v| v[:expires_at] }.first(CACHE.size / 2)
        oldest.each { |k, _| CACHE.delete(k) }
      end
    end
    
    key = cache_key(entity_id, prompt, space_id: space_id)
    CACHE[key] = { result: result.deep_dup, expires_at: Time.current + CACHE_TTL }
  end
  
  # Clear all cache entries
  def self.clear_cache!
    CACHE.clear
    Rails.logger.info "[TieredDiscovery] Cache cleared"
  end
  
  # Clear cache for a specific entity (e.g., on fresh start)
  def self.clear_cache_for_entity!(entity_id)
    prefix = "#{entity_id}:"
    keys_to_delete = CACHE.keys.select { |k| k.start_with?(prefix) }
    keys_to_delete.each { |k| CACHE.delete(k) }
    Rails.logger.info "[TieredDiscovery] Cleared #{keys_to_delete.size} cache entries for entity #{entity_id}"
  end
  
  # Clear cache for a specific space (e.g., on space switch)
  def self.clear_cache_for_space!(entity_id, space_id)
    pattern = "#{entity_id}:s#{space_id}:"
    keys_to_delete = CACHE.keys.select { |k| k.start_with?(pattern) }
    keys_to_delete.each { |k| CACHE.delete(k) }
    Rails.logger.info "[TieredDiscovery] Cleared #{keys_to_delete.size} cache entries for space #{space_id}"
  end
  # Core tools that are ALWAYS available (essential for basic operation)
  # NOTE: This is legacy for Scout - tool allowlist is now managed via ScoutLoadoutConfiguration
  # For agents, these tools enable collaboration and basic operations
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
    view_web_page
    read_document
    query_document_content
  ].freeze

  # Core tools specifically for AGENT collaboration
  # These are always available to agents (in addition to their assigned tools)
  # 
  # NOTE: delegate_to_planner is NOT included here intentionally.
  # Only Amos (the orchestrator) should initiate planning.
  # Agents that feel overwhelmed should use ask_agent_for_help instead,
  # which escalates to Amos if needed, and Amos decides if planning is required.
  #
  AGENT_COLLABORATION_TOOLS = %w[
    ask_agent_for_help
    list_available_agents
    ask_user
    save_to_knowledge_base
    research_and_learn
    save_to_scratchpad
    read_from_scratchpad
    list_scratchpad
    load_dm_canvas
  ].freeze

  # Maximum tools to send to LLM per category
  # REDUCED from 15 to 10 to save tokens (~500 tokens per 5 tools)
  MAX_DISCOVERED_TOOLS = 10
  
  # TOTAL cap on all tools (core + discovered) to prevent prompt bloat
  # 25 tools ≈ 6,000 tokens - leaves room for prompt and context
  MAX_TOTAL_TOOLS = 25
  MAX_DISCOVERED_AGENTS = 10
  MAX_DISCOVERED_INTEGRATIONS = 10
  MAX_DISCOVERED_OPERATIONS = 10

  # Boost factors for prioritization
  USER_OWNERSHIP_BOOST = 0.3
  ENTITY_SCOPE_BOOST = 0.2
  CONNECTED_INTEGRATION_BOOST = 0.25
  USAGE_FREQUENCY_BOOST = 0.15
  REPUTATION_BOOST = 0.25           # For high-reputation agents/tools
  SYSTEM_TIER_BOOST = 0.3           # For system-level resources
  PUBLIC_APPROVED_BOOST = 0.15      # For vetted public resources
  FAVORITE_BOOST = 0.4              # User's favorites get highest priority

  attr_reader :user, :entity, :prompt

  def initialize(user:, entity:, prompt: nil, space_id: nil)
    @user = user
    @entity = entity
    @prompt = prompt
    @space_id = space_id || user&.active_space
    @usage_cache = nil
    @favorites_cache = nil
  end

  # Cache of user's favorited items by type
  def favorite_ids(type)
    @favorites_cache ||= {}
    @favorites_cache[type] ||= if @user && defined?(UserFavorite)
      UserFavorite.favorited_ids_for(@user, type)
    else
      []
    end
  end

  # Check if an item is favorited
  def favorited?(item)
    favorite_ids(item.class.name).include?(item.id)
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
  # KEY: Returns a FOCUSED, CAPPED toolset - NOT an exhaustive list
  # This is the core of intelligent tool selection - RAG-based, not regex!
  def discover_tools(prompt: nil, include_core: true)
    @prompt = prompt if prompt.present?
    return core_tools if @prompt.blank?

    # Check cache first (saves ~600-1200ms on repeated queries)
    # Cache is space-aware - different spaces may need different tools
    cache_key_prompt = "tools:#{include_core}:#{@prompt}"
    if (cached = self.class.get_cached(@entity&.id, cache_key_prompt, space_id: @space_id))
      Rails.logger.debug "⚡ Cache hit for tool discovery (space: #{@space_id})"
      return cached
    end

    discovered = []

    # 1. Always include core tools (highest priority)
    discovered += core_tools if include_core

    # 2. Discover relevant class-based tools via RAG (semantic search)
    # RAG finds tools based on MEANING, not keywords
    discovered += discover_class_tools

    # 3. Discover relevant dynamic tools (ToolDefinition) via RAG
    discovered += discover_dynamic_tools

    # 4. Discover relevant integration operations
    discovered += discover_integration_tools

    # Deduplicate by tool name
    unique_tools = discovered.uniq { |t| t[:name] }
    
    # CAP TOTAL TOOLS to prevent prompt bloat
    # Core tools are already included, so they get priority
    # Additional tools are limited to MAX_TOTAL_TOOLS
    if unique_tools.length > MAX_TOTAL_TOOLS
      Rails.logger.info "🔧 Tool cap: #{unique_tools.length} → #{MAX_TOTAL_TOOLS} (removed #{unique_tools.length - MAX_TOTAL_TOOLS} lower-priority tools)"
      unique_tools = unique_tools.first(MAX_TOTAL_TOOLS)
    end
    
    # Cache the result (space-aware)
    self.class.set_cached(@entity&.id, cache_key_prompt, unique_tools, space_id: @space_id)
    
    unique_tools
  end

  # Discover relevant agents for delegation
  # Prioritizes by: similarity, ownership, entity scope, reputation, and tier
  def discover_agents(prompt: nil, limit: MAX_DISCOVERED_AGENTS, include_public: true)
    @prompt = prompt if prompt.present?
    return [] if @prompt.blank?

    # Check cache first (space-aware - different spaces have different agents)
    cache_key_prompt = "agents:#{limit}:#{include_public}:#{@prompt}"
    if (cached = self.class.get_cached(@entity&.id, cache_key_prompt, space_id: @space_id))
      Rails.logger.debug "⚡ Cache hit for agent discovery (space: #{@space_id})"
      return cached
    end

    begin
      # Build base query
      base_scope = AgentPlugin.active

      # Include public approved agents if requested
      if include_public
        # System agents OR entity-scoped OR public approved
        base_scope = base_scope.where(
          "user_id IS NULL OR entity_id = ? OR (is_public = true AND publish_status = 'approved')",
          @entity&.id
        )
      else
        # Only system and entity-scoped
        base_scope = base_scope.for_entity(@entity)
      end

      # Use vector similarity search
      agents = base_scope.search_by_similarity(@prompt, limit: limit * 3)

      # Apply prioritization with reputation and favorites
      favorited_agent_ids = favorite_ids('AgentPlugin')
      
      prioritized = agents.map do |agent|
        score = agent.try(:neighbor_distance) || 0.5 # Lower is better for cosine
        similarity = 1.0 - score # Convert to similarity (higher is better)

        # FAVORITES get highest priority boost
        is_favorite = favorited_agent_ids.include?(agent.id)
        similarity += FAVORITE_BOOST if is_favorite

        # Tier-based boosts (discovery_tier: 1=system, 2=entity, 3=public approved)
        tier = calculate_agent_tier(agent)
        similarity += SYSTEM_TIER_BOOST if tier == 1
        similarity += ENTITY_SCOPE_BOOST if tier == 2
        similarity += PUBLIC_APPROVED_BOOST if tier == 3

        # Ownership boost
        similarity += USER_OWNERSHIP_BOOST if agent.user_id == @user&.id

        # Reputation boost (0 to REPUTATION_BOOST based on combined score)
        if agent.respond_to?(:combined_reputation_score)
          reputation = agent.combined_reputation_score
          similarity += reputation * REPUTATION_BOOST
        end

        {
          agent: agent,
          score: similarity,
          tier: tier,
          editable: agent.editable_by?(@user),
          is_favorite: is_favorite
        }
      end

      # Sort by score (highest first) and take top results
      result = prioritized
        .sort_by { |a| [ a[:tier], -a[:score] ] } # Primary: tier, Secondary: score
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
            relevance_score: item[:score].round(3),
            tier: tier_label(item[:tier]),
            reputation_score: agent.respond_to?(:combined_reputation_score) ? agent.combined_reputation_score.round(3) : nil,
            is_public: agent.respond_to?(:is_public) && agent.is_public,
            is_favorite: item[:is_favorite]
          }
        end
      
      # Cache the result (space-aware)
      self.class.set_cached(@entity&.id, cache_key_prompt, result, space_id: @space_id)
      result
    rescue => e
      Rails.logger.error "Agent discovery failed: #{e.message}"
      []
    end
  end

  # Calculate agent discovery tier
  # 1 = System (highest priority)
  # 2 = Entity-specific
  # 3 = Public approved
  # 4 = Public pending review
  # 5 = Private/rejected
  def calculate_agent_tier(agent)
    return 1 if agent.user_id.nil?                                      # System agent
    return 2 if agent.entity_id == @entity&.id && !agent.is_public      # Entity-specific
    return 3 if agent.is_public && agent.publish_status == 'approved'   # Public approved
    return 4 if agent.is_public && agent.publish_status == 'pending_review'
    5 # Private or rejected
  end

  def tier_label(tier)
    case tier
    when 1 then 'system'
    when 2 then 'entity'
    when 3 then 'public_approved'
    when 4 then 'public_pending'
    else 'private'
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

  # Get core collaboration tools for agents
  # These enable agent-to-agent collaboration and are always available
  def self.agent_collaboration_tools
    catalog = Tools::ToolCatalog.instance
    
    AGENT_COLLABORATION_TOOLS.filter_map do |tool_name|
      catalog.get_tool_definition(tool_name)
    end
  end

  # Get the list of agent collaboration tool names
  def self.agent_collaboration_tool_names
    AGENT_COLLABORATION_TOOLS
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

    # Try RAG-based search first (using ClassToolEmbeddingsService)
    begin
      service = ClassToolEmbeddingsService.instance
      results = service.search(@prompt, limit: MAX_DISCOVERED_TOOLS / 2)
      
      if results.any?
        Rails.logger.debug "🔍 RAG discovery: #{results.length} class tools found"
        return results.reject { |t| CORE_TOOLS.include?(t[:name]) }.map do |tool|
          tool.merge(priority: :medium)
        end
      end
    rescue => e
      Rails.logger.debug "RAG discovery fallback: #{e.message}"
    end

    # Fallback to keyword matching if RAG fails
    catalog = Tools::ToolCatalog.instance
    all_tools = catalog.all_tools

    tool_texts = all_tools.map do |name, info|
      next if CORE_TOOLS.include?(name)
      next unless info[:type] == :class
      {
        name: name,
        text: "#{name}: #{info[:metadata][:description]}",
        metadata: info[:metadata]
      }
    end.compact

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

  def discover_dynamic_tools(include_public: true)
    return [] if @prompt.blank?

    begin
      # Build base query for tools
      base_scope = ToolDefinition.where.not(embedding: nil)
      
      if include_public
        # Entity tools OR public approved tools
        base_scope = base_scope.where(
          "entity_id = ? OR (is_public = true AND publish_status = 'approved')",
          @entity&.id
        )
      else
        base_scope = base_scope.for_entity(@entity)
      end

      # Use vector similarity search
      tools = base_scope.search_by_similarity(@prompt, limit: MAX_DISCOVERED_TOOLS)

      # Apply prioritization with favorites
      favorited_tool_ids = favorite_ids('ToolDefinition')
      
      prioritized = tools.map do |tool|
        score = tool.try(:neighbor_distance) || 0.5
        similarity = 1.0 - score

        # FAVORITES get highest priority boost
        is_favorite = favorited_tool_ids.include?(tool.id)
        similarity += FAVORITE_BOOST if is_favorite

        # Apply boosts
        similarity += USER_OWNERSHIP_BOOST if tool.created_by_id == @user&.id
        similarity += ENTITY_SCOPE_BOOST if tool.entity_id == @entity&.id
        similarity += usage_boost_for(tool.name)

        # Reputation boost for public tools
        if tool.respond_to?(:reputation_score)
          reputation = tool.reputation_score
          similarity += reputation * REPUTATION_BOOST
        end

        # Security rating boost
        similarity += 0.1 if tool.security_rating == 'pass'
        similarity -= 0.2 if tool.security_rating == 'review'
        # Tools with 'fail' rating should be filtered out, but just in case:
        similarity -= 0.5 if tool.security_rating == 'fail'

        { tool: tool, score: similarity, is_favorite: is_favorite }
      end

      prioritized
        .reject { |t| t[:tool].security_rating == 'fail' } # Never return failed security tools
        .sort_by { |t| -t[:score] }
        .first(MAX_DISCOVERED_TOOLS / 2)
        .map do |item|
          tool = item[:tool]
          {
            name: tool.name,
            description: tool.description,
            parameters: tool.parameters,
            source: :dynamic,
            priority: item[:is_favorite] ? :favorite : (tool.created_by_id == @user&.id ? :high : :medium),
            owner: tool.created_by_id == @user&.id ? :user : :system,
            relevance_score: item[:score].round(3),
            security_rating: tool.security_rating,
            is_public: tool.is_public,
            is_favorite: item[:is_favorite]
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

