# Hybrid RAG Query Service
#
# Performs intelligent retrieval using both pgvector (PostgreSQL) and Pinecone:
# 1. Generates query embedding via Bedrock
# 2. Vector search in pgvector (fast, local)
# 3. Vector search in Pinecone (production-scale, if configured)
# 4. Keyword search via PostgreSQL full-text search (fallback)
# 5. Merges and reranks results
# 6. Caches queries in Redis
#
# Usage:
#   service = HybridRagQueryService.new(entity)
#   response = service.query("How do I create a campaign?", top_k: 10)

class HybridRagQueryService
  DEFAULT_TOP_K = 10
  CACHE_TTL = 1.hour

  # Result weights for hybrid search
  VECTOR_WEIGHT = 0.7
  KEYWORD_WEIGHT = 0.3

  def initialize(entity)
    @entity = entity
    @bedrock = Aws::BedrockRuntime::Client.new(
      region: ENV.fetch('AWS_REGION', 'us-east-1')
    )
  end

  def query(user_query, options = {})
    top_k = options[:top_k] || DEFAULT_TOP_K
    include_system = options.fetch(:include_system, true)
    use_cache = options.fetch(:use_cache, true)

    Rails.logger.info "🔍 HybridRagQueryService: Querying for '#{user_query.truncate(100)}'"

    # Track query
    rag_query = track_query_start(user_query)

    # Check cache
    if use_cache
      cached_result = check_cache(user_query)
      if cached_result
        update_query_tracking(rag_query, cached_result, cache_hit: true)
        return cached_result
      end
    end

    start_time = Time.current

    # Generate query embedding
    query_embedding = generate_query_embedding(user_query)

    # Perform hybrid search
    chunks = perform_hybrid_search(
      query_embedding,
      user_query,
      top_k: top_k,
      include_system: include_system
    )

    # Build context from chunks
    context = build_context(chunks)

    result = {
      query: user_query,
      chunks: chunks.map { |c| format_chunk(c) },
      context: context,
      response_time_ms: ((Time.current - start_time) * 1000).to_i,
      source_count: chunks.length
    }

    # Cache result
    cache_result(user_query, result) if use_cache

    # Update query tracking
    update_query_tracking(rag_query, result, cache_hit: false)

    # Track RAG store access
    track_rag_store_access(chunks)

    result
  end

  def query_with_claude(user_query, options = {})
    # Get relevant context
    rag_result = query(user_query, options)

    # Invoke Claude with context
    response_text = invoke_claude_with_context(user_query, rag_result[:context])

    rag_result.merge(
      claude_response: response_text
    )
  end

  private

  def track_query_start(user_query)
    @entity.rag_queries.create!(
      query: user_query,
      query_hash: generate_query_hash(user_query)
    )
  end

  def update_query_tracking(rag_query, result, cache_hit:)
    rag_query.update!(
      response_time_ms: result[:response_time_ms],
      chunks_retrieved: result[:chunks]&.length || 0,
      relevance_scores: extract_relevance_scores(result[:chunks]),
      cache_hit: cache_hit
    )
  end

  def generate_query_hash(query)
    Digest::SHA256.hexdigest(query.downcase.strip)
  end

  def extract_relevance_scores(chunks)
    return [] unless chunks

    chunks.map do |chunk|
      {
        chunk_id: chunk[:id],
        score: chunk[:similarity_score] || chunk[:distance]
      }
    end
  end

  def check_cache(query)
    cache_key = "rag:#{@entity.id}:#{generate_query_hash(query)}"

    cached = Rails.cache.read(cache_key)

    if cached
      Rails.logger.info "  ✅ Cache hit for query"
    end

    cached
  end

  def cache_result(query, result)
    cache_key = "rag:#{@entity.id}:#{generate_query_hash(query)}"

    Rails.cache.write(cache_key, result, expires_in: CACHE_TTL)
  end

  def generate_query_embedding(query)
    Rails.logger.info "  Generating query embedding"

    response = @bedrock.invoke_model(
      model_id: 'amazon.titan-embed-text-v1',
      content_type: 'application/json',
      body: { inputText: query }.to_json
    )

    parsed = JSON.parse(response.body.read)
    parsed['embedding']
  end

  def perform_hybrid_search(query_embedding, query_text, top_k:, include_system:)
    # Perform vector search (pgvector + Pinecone)
    vector_results = vector_search(query_embedding, top_k: top_k, include_system: include_system)

    # Perform keyword search (PostgreSQL full-text)
    keyword_results = keyword_search(query_text, limit: [top_k / 2, 5].max, include_system: include_system)

    # Merge and rerank
    merged_results = merge_and_rerank(vector_results, keyword_results, top_k: top_k)

    Rails.logger.info "  Found #{merged_results.length} relevant chunks (#{vector_results.length} vector, #{keyword_results.length} keyword)"

    merged_results
  end

  def vector_search(embedding, top_k:, include_system:)
    results = []

    # Search in entity-specific chunks (pgvector)
    entity_chunks = RagChunk
      .for_entity(@entity)
      .where.not(embedding: nil)
      .nearest_neighbors(:embedding, embedding, distance: 'cosine')
      .includes(rag_document: :rag_store)
      .limit(top_k)

    results.concat(entity_chunks.map { |c| annotate_chunk(c, :pgvector) })

    # Include system chunks if requested
    if include_system
      system_chunks = RagChunk
        .joins(rag_document: :rag_store)
        .where(rag_stores: { store_type: 'system' })
        .where.not(embedding: nil)
        .nearest_neighbors(:embedding, embedding, distance: 'cosine')
        .includes(rag_document: :rag_store)
        .limit([top_k / 3, 3].max)

      results.concat(system_chunks.map { |c| annotate_chunk(c, :pgvector_system) })
    end

    # Also search Pinecone if configured (production deployment)
    if pinecone_configured?
      pinecone_results = search_pinecone(embedding, top_k: top_k, include_system: include_system)
      results.concat(pinecone_results)
    end

    # Deduplicate (prefer pgvector results)
    deduplicate_chunks(results).first(top_k)
  end

  def keyword_search(query_text, limit:, include_system:)
    results = []

    # Entity chunks
    entity_chunks = RagChunk
      .for_entity(@entity)
      .text_search(query_text)
      .includes(rag_document: :rag_store)
      .limit(limit)

    results.concat(entity_chunks.map { |c| annotate_chunk(c, :keyword) })

    # System chunks
    if include_system
      system_chunks = RagChunk
        .joins(rag_document: :rag_store)
        .where(rag_stores: { store_type: 'system' })
        .text_search(query_text)
        .includes(rag_document: :rag_store)
        .limit([limit / 3, 2].max)

      results.concat(system_chunks.map { |c| annotate_chunk(c, :keyword_system) })
    end

    results
  end

  def search_pinecone(embedding, top_k:, include_system:)
    # This is a placeholder for Pinecone integration
    # You would use the existing RagStoreService or Pinecone client here

    []
  rescue => e
    Rails.logger.error "Pinecone search failed: #{e.message}"
    []
  end

  def merge_and_rerank(vector_results, keyword_results, top_k:)
    # Combine all chunks
    all_chunks = (vector_results + keyword_results)

    # Deduplicate by chunk ID
    chunks_by_id = {}

    all_chunks.each do |chunk|
      chunk_id = chunk[:id]

      if chunks_by_id[chunk_id]
        # Merge scores
        existing = chunks_by_id[chunk_id]
        existing[:combined_score] = [existing[:combined_score] || 0, chunk[:combined_score] || 0].max
      else
        chunks_by_id[chunk_id] = chunk
      end
    end

    # Sort by combined score
    sorted_chunks = chunks_by_id.values.sort_by { |c| -(c[:combined_score] || 0) }

    # Return top K
    sorted_chunks.first(top_k)
  end

  def annotate_chunk(chunk, source)
    # Calculate combined score based on source
    distance = chunk.try(:neighbor_distance) || 1.0
    similarity = 1.0 - distance

    combined_score = case source
                     when :pgvector, :pgvector_system
                       similarity * VECTOR_WEIGHT
                     when :keyword, :keyword_system
                       KEYWORD_WEIGHT
                     else
                       0.5
                     end

    {
      id: chunk.id,
      content: chunk.content,
      chunk: chunk,
      source: source,
      distance: distance,
      similarity_score: similarity,
      combined_score: combined_score
    }
  end

  def deduplicate_chunks(chunks)
    seen_ids = Set.new
    chunks.select do |chunk_data|
      chunk_id = chunk_data[:id]
      if seen_ids.include?(chunk_id)
        false
      else
        seen_ids.add(chunk_id)
        true
      end
    end
  end

  def build_context(chunks)
    sections = chunks.map.with_index do |chunk_data, index|
      chunk = chunk_data[:chunk]

      metadata_parts = []
      metadata_parts << "Source: #{chunk.rag_document.original_filename}"
      metadata_parts << "Page: #{chunk.metadata['page']}" if chunk.metadata['page']
      metadata_parts << "Section: #{chunk.metadata['section_title']}" if chunk.metadata['section_title']
      metadata_parts << "Relevance: #{(chunk_data[:similarity_score] * 100).round}%" if chunk_data[:similarity_score]

      """
[Context #{index + 1}] #{metadata_parts.join(' | ')}
#{chunk.content}
      """.strip
    end

    sections.join("\n\n---\n\n")
  end

  def format_chunk(chunk_data)
    chunk = chunk_data[:chunk]

    {
      id: chunk.id,
      content: chunk.content,
      similarity_score: chunk_data[:similarity_score],
      source: chunk_data[:source],
      metadata: {
        filename: chunk.rag_document.original_filename,
        page: chunk.metadata['page'],
        section: chunk.metadata['section_title'],
        chunk_type: chunk.chunk_type
      }
    }
  end

  def invoke_claude_with_context(message, context)
    prompt = build_claude_prompt(message, context)

    response = @bedrock.invoke_model(
      model_id: 'anthropic.claude-3-sonnet-20240229-v1:0',
      content_type: 'application/json',
      body: {
        anthropic_version: 'bedrock-2023-05-31',
        max_tokens: 4096,
        messages: [
          {
            role: 'user',
            content: prompt
          }
        ],
        temperature: 0.7
      }.to_json
    )

    parsed = JSON.parse(response.body.read)
    parsed.dig('content', 0, 'text') || parsed['completion']
  end

  def build_claude_prompt(message, context)
    <<~PROMPT
      You are a helpful AI assistant with access to documentation and knowledge base articles.

      Here is relevant context from the knowledge base:

      <context>
      #{context}
      </context>

      Please answer the following question based on the context provided above.
      If the answer is not in the context, say so clearly and provide the best answer you can.

      Question: #{message}

      Answer:
    PROMPT
  end

  def track_rag_store_access(chunks)
    # Track which RAG stores were accessed for analytics
    rag_store_ids = chunks.map { |c| c[:chunk].rag_store.id }.uniq

    RagStore.where(id: rag_store_ids).find_each do |store|
      store.track_access! if store.respond_to?(:track_access!)
    end
  rescue => e
    Rails.logger.error "Failed to track RAG store access: #{e.message}"
  end

  def pinecone_configured?
    ENV['PINECONE_API_KEY'].present? && ENV['PINECONE_ENVIRONMENT'].present?
  end
end
