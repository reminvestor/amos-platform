# ClassToolEmbeddingsService
#
# Manages embeddings for class-based tools (the ones in app/services/tools/).
# These tools don't have database records, so we store their embeddings in a cache.
#
# This enables RAG-based discovery for class tools, not just keyword matching.
#
class ClassToolEmbeddingsService
  include Singleton

  CACHE_KEY = "class_tool_embeddings_v1"
  CACHE_EXPIRY = 24.hours

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
  def search(query, limit: 10)
    return [] if query.blank?

    begin
      query_embedding = AiAgents::VectorStore.instance.generate_embedding(query)
      return [] unless query_embedding

      # Calculate cosine similarity for each tool
      scored_tools = embeddings.map do |tool_name, data|
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
      Rails.logger.error "ClassToolEmbeddingsService search failed: #{e.message}"
      []
    end
  end

  # Force reload embeddings (call after adding new tools)
  def reload!
    @loaded = false
    @embeddings = {}
    Rails.cache.delete(CACHE_KEY)
    load_embeddings
  end

  # Check if a specific tool has an embedding
  def has_embedding?(tool_name)
    embeddings[tool_name]&.dig(:embedding).present?
  end

  private

  def load_embeddings
    # Try to load from cache first
    cached = Rails.cache.read(CACHE_KEY)
    if cached.present?
      @embeddings = cached
      @loaded = true
      Rails.logger.info "📚 Loaded #{@embeddings.size} class tool embeddings from cache"
      return
    end

    # Generate embeddings for all class tools
    generate_all_embeddings
    @loaded = true
  end

  def generate_all_embeddings
    catalog = Tools::ToolCatalog.instance
    class_tools = catalog.all_tools.select { |_, info| info[:type] == :class }

    Rails.logger.info "🔄 Generating embeddings for #{class_tools.size} class tools..."

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

    # Cache the embeddings
    Rails.cache.write(CACHE_KEY, @embeddings, expires_in: CACHE_EXPIRY)
    Rails.logger.info "✅ Generated and cached #{@embeddings.size} class tool embeddings"
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

