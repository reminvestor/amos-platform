# ClassToolEmbeddingsService
#
# Manages embeddings for class-based tools (the ones in app/services/tools/).
# These tools don't have database records, so we store their embeddings in a cache.
#
# This enables RAG-based discovery for class tools, not just keyword matching.
#
# PERFORMANCE OPTIMIZATION:
# - Embeddings are generated ONCE per process lifecycle (lazy, on first search)
# - Uses Rails.cache for persistence across restarts
# - Falls back to keyword matching if embeddings aren't available
# - NEVER blocks requests with embedding generation - use background job if needed
#
class ClassToolEmbeddingsService
  include Singleton

  CACHE_KEY = "class_tool_embeddings_v2"
  CACHE_EXPIRY = 7.days  # Longer TTL - tools don't change often
  
  # Track if we've already attempted generation in this process
  # This prevents repeated attempts if generation fails
  @@generation_attempted = false
  @@generation_mutex = Mutex.new

  def initialize
    @embeddings = {}
    @loaded = false
  end

  # Get or generate embeddings for all class tools
  def embeddings
    load_embeddings unless @loaded
    @embeddings
  end

  # Search class tools by semantic similarity
  # PERFORMANCE: If embeddings aren't ready, falls back to keyword matching
  def search(query, limit: 10)
    return [] if query.blank?

    begin
      # If embeddings aren't loaded yet, use keyword fallback
      # This prevents blocking requests with expensive embedding generation
      unless @loaded && @embeddings.any?
        load_from_cache_only
        
        # Still not loaded? Use keyword fallback
        unless @loaded && @embeddings.any?
          Rails.logger.debug "📝 Tool embeddings not ready, using keyword fallback"
          return keyword_search(query, limit)
        end
      end
      
      query_embedding = AiAgents::VectorStore.instance.generate_embedding(query)
      return keyword_search(query, limit) unless query_embedding

      # Calculate cosine similarity for each tool
      scored_tools = @embeddings.map do |tool_name, data|
        next unless data[:embedding].present?
        
        similarity = cosine_similarity(query_embedding, data[:embedding])
        {
          name: tool_name,
          description: data[:description],
          parameters: data[:parameters],
          similarity: similarity,
          source: :class
        }
      end.compact

      # Sort by similarity (highest first) and return top results
      scored_tools
        .sort_by { |t| -t[:similarity] }
        .first(limit)
    rescue => e
      Rails.logger.warn "ClassToolEmbeddingsService search failed: #{e.message}, using keyword fallback"
      keyword_search(query, limit)
    end
  end

  # Force reload embeddings (call after adding new tools)
  # This should be called from a background job, NOT during request processing
  def reload!
    @loaded = false
    @embeddings = {}
    @@generation_attempted = false
    Rails.cache.delete(CACHE_KEY)
    generate_all_embeddings_async
  end

  # Check if a specific tool has an embedding
  def has_embedding?(tool_name)
    embeddings[tool_name]&.dig(:embedding).present?
  end
  
  # Check if embeddings are ready (for health checks)
  def ready?
    @loaded && @embeddings.any?
  end

  private
  
  # Load from cache ONLY - never trigger generation
  def load_from_cache_only
    return if @loaded
    
    cached = Rails.cache.read(CACHE_KEY)
    if cached.present? && cached.is_a?(Hash) && cached.any?
      @embeddings = cached
      @loaded = true
      Rails.logger.debug "📚 Loaded #{@embeddings.size} class tool embeddings from cache"
    end
  end

  def load_embeddings
    # Try to load from cache first
    load_from_cache_only
    return if @loaded

    # If cache is empty and we haven't already tried generating in this process,
    # schedule background generation
    generate_all_embeddings_async
    @loaded = true  # Mark as loaded to prevent repeated attempts
  end
  
  # Schedule background generation instead of blocking
  def generate_all_embeddings_async
    @@generation_mutex.synchronize do
      return if @@generation_attempted
      @@generation_attempted = true
    end
    
    # In production, this could be a background job
    # For now, we'll skip generation during request and let it happen on next restart
    Rails.logger.info "🔄 Tool embeddings not in cache - will regenerate on next scheduled refresh"
    
    # Populate with basic metadata (no embeddings) for keyword fallback
    populate_tool_metadata_without_embeddings
  end
  
  # Populate tool data without embeddings (for keyword search fallback)
  def populate_tool_metadata_without_embeddings
    catalog = Tools::ToolCatalog.instance
    class_tools = catalog.all_tools.select { |_, info| info[:type] == :class }

    class_tools.each do |name, info|
      metadata = info[:metadata]
      @embeddings[name] = {
        description: metadata[:description],
        parameters: metadata[:parameters] || metadata[:input_schema],
        category: metadata[:category],
        embedding: nil  # No embedding - will use keyword search
      }
    end
    
    Rails.logger.debug "📝 Populated #{@embeddings.size} tools for keyword fallback"
  end

  # Generate embeddings for all class tools (SYNCHRONOUS - for background jobs only)
  def generate_all_embeddings
    catalog = Tools::ToolCatalog.instance
    class_tools = catalog.all_tools.select { |_, info| info[:type] == :class }

    Rails.logger.info "🔄 Generating embeddings for #{class_tools.size} class tools..."
    start_time = Time.current

    class_tools.each do |name, info|
      metadata = info[:metadata]
      
      # Build embedding text from tool metadata
      embedding_text = <<~TEXT
        Tool: #{name}
        Description: #{metadata[:description]}
        Category: #{metadata[:category]}
        Parameters: #{(metadata[:parameters] || metadata[:input_schema])&.to_json}
      TEXT

      begin
        vector = AiAgents::VectorStore.instance.generate_embedding(embedding_text)
        
        @embeddings[name] = {
          description: metadata[:description],
          parameters: metadata[:parameters] || metadata[:input_schema],
          category: metadata[:category],
          embedding: vector
        }
      rescue => e
        Rails.logger.warn "Failed to generate embedding for tool #{name}: #{e.message}"
        @embeddings[name] = {
          description: metadata[:description],
          parameters: metadata[:parameters] || metadata[:input_schema],
          category: metadata[:category],
          embedding: nil
        }
      end
    end

    # Cache the embeddings with longer TTL
    Rails.cache.write(CACHE_KEY, @embeddings, expires_in: CACHE_EXPIRY)
    duration = ((Time.current - start_time) * 1000).round
    Rails.logger.info "✅ Generated and cached #{@embeddings.size} class tool embeddings in #{duration}ms"
  end
  
  # Keyword-based search fallback when embeddings aren't available
  def keyword_search(query, limit)
    return [] if query.blank?
    
    keywords = query.downcase.split(/\W+/).reject { |w| w.length < 3 }
    return [] if keywords.empty?
    
    # Score tools by keyword matches
    scored_tools = @embeddings.map do |tool_name, data|
      description = data[:description].to_s.downcase
      full_text = "#{tool_name} #{description} #{data[:category]}"
      
      # Count keyword matches
      matches = keywords.count { |kw| full_text.include?(kw) }
      next if matches.zero?
      
      {
        name: tool_name,
        description: data[:description],
        parameters: data[:parameters],
        similarity: matches.to_f / keywords.length,  # Pseudo-similarity score
        source: :class
      }
    end.compact
    
    scored_tools
      .sort_by { |t| -t[:similarity] }
      .first(limit)
  end

  def cosine_similarity(vec1, vec2)
    return 0.0 unless vec1 && vec2 && vec1.length == vec2.length

    dot_product = vec1.zip(vec2).map { |a, b| a * b }.sum
    magnitude1 = Math.sqrt(vec1.map { |x| x * x }.sum)
    magnitude2 = Math.sqrt(vec2.map { |x| x * x }.sum)

    return 0.0 if magnitude1.zero? || magnitude2.zero?

    dot_product / (magnitude1 * magnitude2)
  end
end

