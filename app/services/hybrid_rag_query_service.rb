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
    @comprehend = Aws::ComprehendService.instance
  end

  def query(user_query, options = {})
    top_k = options[:top_k] || DEFAULT_TOP_K
    include_system = options.fetch(:include_system, true)
    use_cache = options.fetch(:use_cache, true)

    Rails.logger.debug "🔍 RAG query: #{user_query.truncate(60)}"

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

    # Analyze query with Comprehend for enhanced search (optional)
    query_analysis = nil
    if options.fetch(:enable_nlp, false) && @comprehend.enabled?
      query_analysis = analyze_query_with_comprehend(user_query)
    end

    # Generate query embedding
    query_embedding = generate_query_embedding(user_query)

    # Perform hybrid search (with optional NLP-enhanced terms)
    chunks = perform_hybrid_search(
      query_embedding,
      user_query,
      top_k: top_k,
      include_system: include_system,
      query_analysis: query_analysis
    )

    # Build context from chunks
    context = build_context(chunks)

    result = {
      query: user_query,
      chunks: chunks.map { |c| format_chunk(c) },
      context: context,
      response_time_ms: ((Time.current - start_time) * 1000).to_i,
      source_count: chunks.length,
      query_analysis: query_analysis
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
      Rails.logger.debug "  ✅ Cache hit"
    end

    cached
  end

  def cache_result(query, result)
    cache_key = "rag:#{@entity.id}:#{generate_query_hash(query)}"

    Rails.cache.write(cache_key, result, expires_in: CACHE_TTL)
  end

  def generate_query_embedding(query)
    Rails.logger.debug "  Generating embedding..."

    response = @bedrock.invoke_model(
      model_id: 'amazon.titan-embed-text-v1',
      content_type: 'application/json',
      body: { inputText: query }.to_json
    )

    parsed = JSON.parse(response.body.read)
    parsed['embedding']
  end

  def perform_hybrid_search(query_embedding, query_text, top_k:, include_system:, query_analysis: nil)
    # Perform vector search (pgvector + Pinecone + Bedrock KB)
    vector_results = vector_search(query_embedding, top_k: top_k, include_system: include_system)

    # Enhance keyword search with NLP-extracted terms
    enhanced_query_text = query_text
    if query_analysis
      # Add extracted entities and key phrases to search terms
      search_terms = [query_text]
      search_terms += query_analysis[:entities].map { |e| e[:text] } if query_analysis[:entities]
      search_terms += query_analysis[:key_phrases].map { |p| p[:text] } if query_analysis[:key_phrases]
      enhanced_query_text = search_terms.uniq.join(' ')

      Rails.logger.debug "  🧠 NLP: #{search_terms.count} terms"
    end

    # Perform keyword search (PostgreSQL full-text)
    keyword_results = keyword_search(enhanced_query_text, limit: [top_k / 2, 5].max, include_system: include_system)

    # If Bedrock KB is enabled, also query it
    bedrock_results = []
    if bedrock_kb_enabled?
      bedrock_results = search_bedrock_kb(query_text, top_k: top_k)
    end

    # Merge and rerank all results
    merged_results = merge_and_rerank_multi(vector_results, keyword_results, bedrock_results, top_k: top_k)

    Rails.logger.debug "  📊 RAG results: #{merged_results.length} chunks (v:#{vector_results.length} k:#{keyword_results.length} b:#{bedrock_results.length})"

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
      object: chunk, # Add reference to the chunk object
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
    # Handle both direct chunk object and annotated chunk data
    chunk = chunk_data[:chunk] || chunk_data[:object]
    
    return chunk_data if chunk.nil? # Already formatted
    
    {
      id: chunk.id,
      rag_document_id: chunk.rag_document_id,
      content: chunk.content,
      similarity_score: chunk_data[:similarity_score],
      combined_score: chunk_data[:combined_score],
      source: chunk_data[:source],
      document_title: chunk.rag_document&.display_title,
      metadata: {
        filename: chunk.rag_document&.original_filename,
        page: chunk.metadata&.dig('page'),
        section: chunk.metadata&.dig('section_title'),
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

  # Analyze query with AWS Comprehend for enhanced search
  def analyze_query_with_comprehend(query_text)
    start_time = Time.current

    # Detect language
    language_result = @comprehend.detect_language(query_text, entity: @entity)
    language_code = language_result[:language_code] || 'en'

    # Extract entities (people, organizations, locations, etc.)
    entities_result = @comprehend.detect_entities(query_text, entity: @entity, language_code: language_code)

    # Extract key phrases
    phrases_result = @comprehend.detect_key_phrases(query_text, entity: @entity, language_code: language_code)

    elapsed_ms = ((Time.current - start_time) * 1000).to_i

    analysis = {
      language: language_code,
      entities: entities_result[:success] ? entities_result[:entities] : [],
      key_phrases: phrases_result[:success] ? phrases_result[:key_phrases] : [],
      processing_time_ms: elapsed_ms
    }

    Rails.logger.debug "  🧠 Comprehend: #{analysis[:entities].count} entities, #{analysis[:key_phrases].count} phrases (#{elapsed_ms}ms)"

    analysis
  rescue => e
    Rails.logger.error "❌ Comprehend query analysis failed: #{e.message}"
    { language: 'en', entities: [], key_phrases: [], processing_time_ms: 0 }
  end

  # Bedrock Knowledge Base integration
  def bedrock_kb_enabled?
    @entity.use_bedrock_kb && @entity.bedrock_knowledge_base_id.present?
  end

  def search_bedrock_kb(query_text, top_k:)
    return [] unless bedrock_kb_enabled?

    start_time = Time.current

    kb_service = Aws::BedrockKnowledgeBaseService.instance
    result = kb_service.query(@entity, query_text, max_results: top_k)

    # Convert Bedrock KB results to our chunk format
    chunks = result[:results].map do |r|
      {
        id: "bedrock-#{SecureRandom.hex(8)}",
        content: r[:content],
        metadata: r[:metadata] || {},
        source: :bedrock_kb,
        score: r[:score] || 0.0,
        combined_score: r[:score] || 0.0,
        # Store original Bedrock data for reference
        bedrock_data: {
          retrieval_result_id: r[:retrieval_result_id],
          location: r[:location]
        }
      }
    end

    elapsed_ms = ((Time.current - start_time) * 1000).to_i
    Rails.logger.debug "  📚 Bedrock KB: #{chunks.length} results (#{elapsed_ms}ms)"

    chunks
  rescue => e
    Rails.logger.error "❌ Bedrock KB search failed: #{e.message}"
    Rails.logger.error e.backtrace.first(5).join("\n")
    []
  end

  def merge_and_rerank_multi(vector_results, keyword_results, bedrock_results, top_k:)
    # Combine all chunks from all sources
    all_chunks = (vector_results + keyword_results + bedrock_results)

    # Deduplicate by content similarity
    chunks_by_content = {}

    all_chunks.each do |chunk|
      # Use content hash as key for deduplication
      content_key = chunk[:content].to_s[0..200].strip.downcase

      if chunks_by_content[content_key]
        # Merge scores - take maximum score
        existing = chunks_by_content[content_key]
        new_score = chunk[:combined_score] || 0
        existing[:combined_score] = [existing[:combined_score] || 0, new_score].max

        # Prefer Bedrock KB source if available
        if chunk[:source] == :bedrock_kb
          existing[:source] = :bedrock_kb
          existing[:bedrock_data] = chunk[:bedrock_data] if chunk[:bedrock_data]
        end
      else
        chunks_by_content[content_key] = chunk
      end
    end

    # Sort by combined score
    sorted_chunks = chunks_by_content.values.sort_by { |c| -(c[:combined_score] || 0) }

    # Return top K results
    sorted_chunks.first(top_k)
  end

  # Analyze query with AWS Comprehend for enhanced search
  def analyze_query_with_comprehend(query_text)
    start_time = Time.current

    # Detect language
    language_result = @comprehend.detect_language(query_text, entity: @entity)
    language_code = language_result[:language_code] || 'en'

    # Extract entities (people, organizations, locations, etc.)
    entities_result = @comprehend.detect_entities(query_text, entity: @entity, language_code: language_code)

    # Extract key phrases
    phrases_result = @comprehend.detect_key_phrases(query_text, entity: @entity, language_code: language_code)

    elapsed_ms = ((Time.current - start_time) * 1000).to_i

    analysis = {
      language: language_code,
      entities: entities_result[:success] ? entities_result[:entities] : [],
      key_phrases: phrases_result[:success] ? phrases_result[:key_phrases] : [],
      processing_time_ms: elapsed_ms
    }

    Rails.logger.debug "  🧠 Comprehend: #{analysis[:entities].count} entities, #{analysis[:key_phrases].count} phrases (#{elapsed_ms}ms)"

    analysis
  rescue => e
    Rails.logger.error "❌ Comprehend query analysis failed: #{e.message}"
    { language: 'en', entities: [], key_phrases: [], processing_time_ms: 0 }
  end
end
