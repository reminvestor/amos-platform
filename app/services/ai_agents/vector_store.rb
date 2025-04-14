require 'singleton'
require 'matrix'

module AiAgents
  class VectorStore
    include Singleton
    
    def initialize
      @data = []  # Will store [text, embedding, metadata] tuples
      @embedding_cache = {}
      Rails.logger.info("VECTOR_STORE: Initialized singleton instance")
    end
    
    def add(text, metadata = {})
      return if text.nil? || text.strip.empty?
      
      # Check if we already have this text
      if @data.any? { |item| item[0] == text }
        Rails.logger.info("VECTOR_STORE: Text already exists in store, skipping: #{text.truncate(50)}")
        return
      end
      
      Rails.logger.info("VECTOR_STORE: Adding new text: #{text.truncate(50)}")
      Rails.logger.debug("VECTOR_STORE: Metadata: #{metadata.inspect}")
      
      embedding = get_embedding(text)
      @data << [text, embedding, metadata]
      Rails.logger.info("VECTOR_STORE: Added text with embedding of dimension #{embedding.size}")
    end
    
    def add_batch(texts, metadatas = [])
      Rails.logger.info("VECTOR_STORE: Batch adding #{texts.size} texts")
      added_count = 0
      
      texts.each_with_index do |text, i|
        metadata = metadatas[i] || {}
        add(text, metadata)
        added_count += 1
      end
      
      Rails.logger.info("VECTOR_STORE: Completed batch add with #{added_count} texts added")
    end
    
    def search(query, limit = 5)
      Rails.logger.info("VECTOR_STORE: Searching for: #{query.truncate(50)}")
      Rails.logger.info("VECTOR_STORE: Database size: #{@data.size} items")
      
      return [] if @data.empty?
      
      search_start_time = Time.current
      query_embedding = get_embedding(query)
      Rails.logger.info("VECTOR_STORE: Generated query embedding of dimension #{query_embedding.size}")
      
      # Calculate cosine similarity against all stored embeddings
      Rails.logger.info("VECTOR_STORE: Calculating similarities with #{@data.size} stored embeddings")
      similarities = @data.map do |text, embedding, metadata|
        # Calculate cosine similarity
        similarity = cosine_similarity(query_embedding, embedding)
        [text, similarity, metadata]
      end
      
      # Sort by similarity (descending) and take top k
      results = similarities.sort_by { |_, similarity, _| -similarity }.first(limit)
      search_duration = Time.current - search_start_time
      
      Rails.logger.info("VECTOR_STORE: Search completed in #{search_duration.round(4)}s, returning #{results.size} results")
      if results.any?
        results.each_with_index do |(text, similarity, metadata), index|
          Rails.logger.info("VECTOR_STORE: Result #{index+1}: similarity=#{similarity.round(4)}, text=#{text.truncate(50)}")
        end
      else
        Rails.logger.info("VECTOR_STORE: No results found for query: #{query.truncate(50)}")
      end
      
      results
    end
    
    def clear
      old_size = @data.size
      @data = []
      @embedding_cache = {}
      Rails.logger.info("VECTOR_STORE: Cleared database (removed #{old_size} items)")
    end
    
    private
    
    def get_embedding(text)
      # Return cached embedding if available
      if @embedding_cache.key?(text)
        Rails.logger.info("VECTOR_STORE: Using cached embedding for text: #{text.truncate(50)}")
        return @embedding_cache[text]
      end
      
      # Otherwise, generate new embedding
      Rails.logger.info("VECTOR_STORE: Generating new embedding for text: #{text.truncate(50)}")
      start_time = Time.current
      embedding = generate_embedding(text)
      duration = Time.current - start_time
      
      Rails.logger.info("VECTOR_STORE: Embedding generated in #{duration.round(2)}s (dimension: #{embedding.size})")
      @embedding_cache[text] = embedding
      embedding
    end
    
    def generate_embedding(text)
      # Call OpenAI API to get embedding
      require 'net/http'
      require 'uri'
      require 'json'
      
      Rails.logger.info("VECTOR_STORE: Calling OpenAI API for embedding generation")
      
      uri = URI.parse("https://api.openai.com/v1/embeddings")
      request = Net::HTTP::Post.new(uri)
      request.content_type = "application/json"
      request["Authorization"] = "Bearer #{ENV['OPENAI_API_KEY']}"
      
      request.body = JSON.dump({
        "model" => "text-embedding-3-small",
        "input" => text
      })
      
      req_options = {
        use_ssl: uri.scheme == "https"
      }
      
      api_start_time = Time.current
      response = Net::HTTP.start(uri.hostname, uri.port, req_options) do |http|
        http.request(request)
      end
      api_duration = Time.current - api_start_time
      
      if response.code == "200"
        result = JSON.parse(response.body)
        embedding = result["data"][0]["embedding"]
        Rails.logger.info("VECTOR_STORE: OpenAI API returned embedding in #{api_duration.round(2)}s (dimension: #{embedding.size})")
        return embedding
      else
        Rails.logger.error("VECTOR_STORE: Error getting embedding - HTTP #{response.code}: #{response.body}")
        Rails.logger.warn("VECTOR_STORE: Using random embedding as fallback")
        # Return a random embedding as fallback
        return Array.new(1536) { rand }
      end
    rescue => e
      Rails.logger.error("VECTOR_STORE: Error calling OpenAI API for embedding: #{e.message}")
      Rails.logger.error(e.backtrace.join("\n"))
      Rails.logger.warn("VECTOR_STORE: Using random embedding as fallback")
      # Return a random embedding as fallback
      return Array.new(1536) { rand }
    end
    
    def cosine_similarity(vec1, vec2)
      # Convert to Vector objects
      v1 = Vector.elements(vec1)
      v2 = Vector.elements(vec2)
      
      # Calculate cosine similarity
      dot_product = v1.inner_product(v2)
      magnitude1 = Math.sqrt(v1.inner_product(v1))
      magnitude2 = Math.sqrt(v2.inner_product(v2))
      
      similarity = dot_product / (magnitude1 * magnitude2)
      Rails.logger.debug("VECTOR_STORE: Calculated similarity: #{similarity}")
      similarity
    rescue => e
      Rails.logger.error("VECTOR_STORE: Error calculating cosine similarity: #{e.message}")
      Rails.logger.error(e.backtrace.join("\n"))
      0.0
    end
  end
end 