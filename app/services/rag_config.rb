class RagConfig
  # Chunking strategies
  STRATEGY_SIMPLE = 'simple'      # Current paragraph-based
  STRATEGY_SEMANTIC = 'semantic'  # Ottomator-style with overlap

  class << self
    # Get chunking strategy from ENV
    def chunking_strategy
      strategy = ENV.fetch('RAG_CHUNKING_STRATEGY', STRATEGY_SIMPLE).downcase
      valid_strategies = [STRATEGY_SIMPLE, STRATEGY_SEMANTIC]

      unless valid_strategies.include?(strategy)
        Rails.logger.warn "⚠️ Invalid RAG_CHUNKING_STRATEGY: #{strategy}, using #{STRATEGY_SIMPLE}"
        return STRATEGY_SIMPLE
      end

      strategy
    end

    # Check if using semantic chunking
    def semantic_chunking?
      chunking_strategy == STRATEGY_SEMANTIC
    end

    # Check if using simple chunking
    def simple_chunking?
      chunking_strategy == STRATEGY_SIMPLE
    end

    # Chunk size (tokens for semantic, characters for simple)
    def chunk_size
      ENV.fetch('RAG_CHUNK_SIZE', '1000').to_i
    end

    # Chunk overlap (only for semantic)
    def chunk_overlap
      return 0 unless semantic_chunking?
      ENV.fetch('RAG_CHUNK_OVERLAP', '200').to_i
    end

    # Embedding cache enabled?
    def embedding_cache_enabled?
      ENV.fetch('RAG_EMBEDDING_CACHE_ENABLED', 'false').downcase == 'true'
    end

    # Embedding batch size
    def embedding_batch_size
      size = ENV.fetch('RAG_EMBEDDING_BATCH_SIZE', '100').to_i
      # Clamp between 1-100 (OpenAI limit)
      [[size, 1].max, 100].min
    end

    # OpenAI embedding model
    def embedding_model
      ENV.fetch('OPENAI_EMBEDDING_MODEL', 'text-embedding-ada-002')
    end

    # Summary of current configuration
    def summary
      {
        chunking_strategy: chunking_strategy,
        chunk_size: chunk_size,
        chunk_overlap: chunk_overlap,
        embedding_cache: embedding_cache_enabled?,
        embedding_batch_size: embedding_batch_size,
        embedding_model: embedding_model
      }
    end

    # Log current configuration
    def log_config
      config = summary
      Rails.logger.info "📊 RAG Configuration:"
      Rails.logger.info "  Chunking: #{config[:chunking_strategy]} (size: #{config[:chunk_size]}, overlap: #{config[:chunk_overlap]})"
      Rails.logger.info "  Embedding: #{config[:embedding_model]} (batch: #{config[:embedding_batch_size]}, cache: #{config[:embedding_cache]})"
    end
  end
end
