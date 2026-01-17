require "singleton"
require "matrix"

module AiAgents
  class VectorStore
    include Singleton

    def initialize
      @data = []  # Will store [text, embedding, metadata] tuples
      @embedding_cache = {}
      Rails.logger.debug("VECTOR_STORE: Initialized singleton instance")
    end

    def add(text, metadata = {})
      return if text.nil? || text.strip.empty?

      # Check if we already have this text
      if @data.any? { |item| item[0] == text }
        Rails.logger.debug("VECTOR_STORE: Text already exists, skipping")
        return
      end

      Rails.logger.debug("VECTOR_STORE: Adding new text: #{text.truncate(50)}")

      embedding = get_embedding(text)
      @data << [ text, embedding, metadata ]
    end

    def add_batch(texts, metadatas = [])
      Rails.logger.debug("VECTOR_STORE: Batch adding #{texts.size} texts")
      texts.each_with_index do |text, i|
        metadata = metadatas[i] || {}
        add(text, metadata)
      end
    end

    def search(query, limit = 5)
      Rails.logger.debug("VECTOR_STORE: Searching (#{@data.size} items)")

      return [] if @data.empty?

      query_embedding = get_embedding(query)

      # Calculate cosine similarity against all stored embeddings
      similarities = @data.map do |text, embedding, metadata|
        similarity = cosine_similarity(query_embedding, embedding)
        [ text, similarity, metadata ]
      end

      # Sort by similarity (descending) and take top k
      similarities.sort_by { |_, similarity, _| -similarity }.first(limit)
    end

    def clear
      old_size = @data.size
      @data = []
      @embedding_cache = {}
      Rails.logger.debug("VECTOR_STORE: Cleared (removed #{old_size} items)")
    end

    def generate_embedding(text)
      # Use EmbeddingService which defaults to AWS Bedrock (Titan)
      embedding_service = EmbeddingService.new
      embedding = embedding_service.generate(text)

      if embedding.present?
        embedding
      else
        Rails.logger.warn("VECTOR_STORE: EmbeddingService returned nil, using fallback")
        Array.new(1536) { rand }
      end
    rescue => e
      Rails.logger.error("VECTOR_STORE: Embedding error: #{e.message}")
      Array.new(1536) { rand }
    end

    private

    def get_embedding(text)
      return @embedding_cache[text] if @embedding_cache.key?(text)

      embedding = generate_embedding(text)
      @embedding_cache[text] = embedding
      embedding
    end

    def cosine_similarity(vec1, vec2)
      v1 = Vector.elements(vec1)
      v2 = Vector.elements(vec2)

      dot_product = v1.inner_product(v2)
      magnitude1 = Math.sqrt(v1.inner_product(v1))
      magnitude2 = Math.sqrt(v2.inner_product(v2))

      dot_product / (magnitude1 * magnitude2)
    rescue => e
      Rails.logger.error("VECTOR_STORE: Similarity error: #{e.message}")
      0.0
    end
  end
end
