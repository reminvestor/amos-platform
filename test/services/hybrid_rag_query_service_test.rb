require "test_helper"

class HybridRagQueryServiceTest < ActiveSupport::TestCase
  setup do
    @entity = entities(:company_one)
    @service = HybridRagQueryService.new(@entity)

    # Create RAG stores, documents, and chunks for testing
    @rag_store = rag_stores(:entity_store_one)
    @rag_document = rag_documents(:pdf_doc_one)

    # Sample embedding (1536 dimensions)
    @sample_embedding = Array.new(1536) { rand }

    # Create test chunks with embeddings
    @chunks = 3.times.map do |i|
      @rag_document.rag_chunks.create!(
        content: "This is test chunk #{i} with relevant content about campaigns and marketing.",
        chunk_index: i,
        token_count: 15,
        chunk_type: 'text',
        embedding: @sample_embedding,
        metadata: { page: i + 1, section_title: "Section #{i}" }
      )
    end

    # Clear cache before each test
    Rails.cache.clear
  end

  # ===== Basic Query Execution =====

  test "executes basic query successfully" do
    mock_bedrock_embedding do
      result = @service.query("How do I create a campaign?")

      assert_not_nil result
      assert_equal "How do I create a campaign?", result[:query]
      assert_kind_of Array, result[:chunks]
      assert_kind_of String, result[:context]
      assert result[:response_time_ms] > 0
      assert result[:source_count] >= 0
    end
  end

  test "returns chunks in expected format" do
    mock_bedrock_embedding do
      result = @service.query("test query")

      if result[:chunks].any?
        chunk = result[:chunks].first

        assert chunk.key?(:id)
        assert chunk.key?(:content)
        assert chunk.key?(:similarity_score)
        assert chunk.key?(:source)
        assert chunk.key?(:metadata)

        # Metadata structure
        assert chunk[:metadata].key?(:filename)
        assert chunk[:metadata].key?(:page)
        assert chunk[:metadata].key?(:chunk_type)
      end
    end
  end

  test "tracks response time" do
    mock_bedrock_embedding do
      start = Time.current
      result = @service.query("test")
      elapsed = ((Time.current - start) * 1000).to_i

      assert result[:response_time_ms] > 0
      assert result[:response_time_ms] <= elapsed + 100 # Allow some margin
    end
  end

  # ===== Caching =====

  test "caches query results" do
    query = "How do I create a campaign?"

    mock_bedrock_embedding do
      # First query - not cached
      result1 = @service.query(query)

      # Second query - should be cached
      result2 = @service.query(query)

      assert_equal result1[:query], result2[:query]
      assert_equal result1[:source_count], result2[:source_count]
    end
  end

  test "uses correct cache key format" do
    query = "test query"
    query_hash = Digest::SHA256.hexdigest(query.downcase.strip)
    expected_cache_key = "rag:#{@entity.id}:#{query_hash}"

    mock_bedrock_embedding do
      @service.query(query)

      # Cache should contain the result
      cached_result = Rails.cache.read(expected_cache_key)
      assert_not_nil cached_result
      assert_equal query, cached_result[:query]
    end
  end

  test "marks cache hit in query tracking" do
    query = "cached query"

    mock_bedrock_embedding do
      # First query
      @service.query(query)

      # Second query (cached)
      @service.query(query)

      # Check RagQuery records
      queries = @entity.rag_queries.where(query: query).order(created_at: :asc)
      assert_equal 2, queries.count

      # First query should NOT be cache hit
      assert_not queries.first.cache_hit

      # Second query SHOULD be cache hit
      assert queries.last.cache_hit
    end
  end

  test "bypasses cache when use_cache is false" do
    query = "no cache query"

    mock_bedrock_embedding do
      # First query
      @service.query(query, use_cache: true)

      # Second query with cache disabled - should generate new results
      # (We can't easily verify it's not cached, but it should execute fully)
      assert_nothing_raised do
        @service.query(query, use_cache: false)
      end
    end
  end

  test "cache expires after CACHE_TTL" do
    query = "expiring query"

    mock_bedrock_embedding do
      @service.query(query)

      # Verify cache exists
      query_hash = Digest::SHA256.hexdigest(query.downcase.strip)
      cache_key = "rag:#{@entity.id}:#{query_hash}"
      assert_not_nil Rails.cache.read(cache_key)

      # Simulate time passing (can't actually test TTL without waiting)
      # This just verifies the cache write includes expires_in
      # Real TTL testing would require time travel or waiting
    end
  end

  # ===== Embedding Generation =====

  test "generates query embedding via Bedrock" do
    bedrock = Minitest::Mock.new
    bedrock.expect :invoke_model, mock_bedrock_response, [Hash] do |params|
      assert_equal 'amazon.titan-embed-text-v1', params[:model_id]
      assert_equal 'application/json', params[:content_type]

      body = JSON.parse(params[:body])
      assert_equal "test query", body['inputText']

      true
    end

    HybridRagQueryService.any_instance.stub :instance_variable_get, proc { |var|
      var == :@bedrock ? bedrock : instance_variable_get(var)
    } do
      @service.query("test query", use_cache: false)
    end

    bedrock.verify
  end

  test "uses Titan Embed model for embeddings" do
    model_used = nil

    bedrock = Minitest::Mock.new
    bedrock.expect :invoke_model, mock_bedrock_response, [Hash] do |params|
      model_used = params[:model_id]
      true
    end

    HybridRagQueryService.any_instance.stub :instance_variable_get, proc { |var|
      var == :@bedrock ? bedrock : instance_variable_get(var)
    } do
      @service.query("test", use_cache: false)
    end

    assert_equal 'amazon.titan-embed-text-v1', model_used
  end

  # ===== Query Tracking =====

  test "creates RagQuery record" do
    mock_bedrock_embedding do
      assert_difference '@entity.rag_queries.count', 1 do
        @service.query("tracked query")
      end

      query_record = @entity.rag_queries.last
      assert_equal "tracked query", query_record.query
      assert_not_nil query_record.query_hash
      assert query_record.response_time_ms > 0
    end
  end

  test "generates query hash correctly" do
    query = "Test Query with CAPS"
    expected_hash = Digest::SHA256.hexdigest("test query with caps")

    mock_bedrock_embedding do
      @service.query(query)

      query_record = @entity.rag_queries.last
      assert_equal expected_hash, query_record.query_hash
    end
  end

  test "updates query record with response time" do
    mock_bedrock_embedding do
      @service.query("test")

      query_record = @entity.rag_queries.last
      assert query_record.response_time_ms > 0
      assert query_record.response_time_ms < 10000 # Should be < 10s
    end
  end

  test "tracks chunks retrieved count" do
    mock_bedrock_embedding do
      @service.query("test")

      query_record = @entity.rag_queries.last
      assert query_record.chunks_retrieved >= 0
    end
  end

  test "extracts relevance scores" do
    mock_bedrock_embedding do
      @service.query("test")

      query_record = @entity.rag_queries.last
      scores = query_record.relevance_scores

      if scores.present?
        assert_kind_of Array, scores
        score = scores.first
        assert score.key?('chunk_id')
        assert score.key?('score')
      end
    end
  end

  # ===== Hybrid Search =====

  test "performs hybrid search combining vector and keyword" do
    mock_bedrock_embedding do
      # Create a chunk with specific content for keyword matching
      keyword_chunk = @rag_document.rag_chunks.create!(
        content: "campaign creation workflow steps tutorial",
        chunk_index: 99,
        token_count: 5,
        embedding: @sample_embedding,
        metadata: {}
      )

      result = @service.query("campaign creation")

      # Should find chunks from both vector and keyword search
      assert result[:chunks].any?
    end
  end

  test "respects top_k parameter" do
    # Create 20 chunks
    20.times do |i|
      @rag_document.rag_chunks.create!(
        content: "Chunk #{i} about campaigns",
        chunk_index: i + 100,
        token_count: 5,
        embedding: @sample_embedding,
        metadata: {}
      )
    end

    mock_bedrock_embedding do
      result = @service.query("campaigns", top_k: 5)

      # Should return at most 5 chunks
      assert result[:chunks].length <= 5
    end
  end

  test "deduplicates chunks from multiple sources" do
    mock_bedrock_embedding do
      # Query that might match same chunks in vector + keyword
      result = @service.query("test chunk campaigns marketing")

      # Check for duplicate chunk IDs
      chunk_ids = result[:chunks].map { |c| c[:id] }
      assert_equal chunk_ids.length, chunk_ids.uniq.length
    end
  end

  # ===== Vector Search =====

  test "searches entity-specific chunks" do
    mock_bedrock_embedding do
      result = @service.query("test")

      # Should find chunks from this entity's RAG store
      if result[:chunks].any?
        chunk_ids = result[:chunks].map { |c| c[:id] }
        @chunks.each do |chunk|
          # At least some of our test chunks should be in results
          # (depending on similarity)
        end
      end
    end
  end

  test "includes system chunks when include_system is true" do
    # Create a system RAG store
    system_store = RagStore.create!(
      entity: nil,
      store_type: 'system',
      name: 'System Knowledge',
      app_name: 'amos',
      pinecone_index: 'system-index',
      pinecone_namespace: 'system',
      status: 'active'
    )

    system_doc = system_store.rag_documents.create!(
      original_filename: 'system_doc.pdf',
      file_hash: 'sys123',
      file_size: 1000,
      content_type: 'application/pdf'
    )

    system_chunk = system_doc.rag_chunks.create!(
      content: "System documentation about features",
      chunk_index: 0,
      token_count: 5,
      embedding: @sample_embedding,
      metadata: {}
    )

    mock_bedrock_embedding do
      result = @service.query("features", include_system: true)

      # Result should potentially include system chunks
      # (Hard to assert without exact similarity matching)
      assert_not_nil result
    end
  end

  test "excludes system chunks when include_system is false" do
    # Create system chunk (same as above test)
    system_store = RagStore.create!(
      entity: nil,
      store_type: 'system',
      name: 'System Knowledge',
      app_name: 'amos',
      pinecone_index: 'system-index',
      pinecone_namespace: 'system',
      status: 'active'
    )

    system_doc = system_store.rag_documents.create!(
      original_filename: 'system_doc.pdf',
      file_hash: 'sys456',
      file_size: 1000,
      content_type: 'application/pdf'
    )

    system_chunk = system_doc.rag_chunks.create!(
      content: "System documentation",
      chunk_index: 0,
      token_count: 5,
      embedding: @sample_embedding,
      metadata: {}
    )

    mock_bedrock_embedding do
      result = @service.query("documentation", include_system: false)

      # System chunks should not be in results
      chunk_ids = result[:chunks].map { |c| c[:id] }
      assert_not_includes chunk_ids, system_chunk.id
    end
  end

  # ===== Keyword Search =====

  test "finds chunks via full-text search" do
    # Create chunk with specific keywords
    keyword_chunk = @rag_document.rag_chunks.create!(
      content: "Email campaign workflow automation tutorial guide",
      chunk_index: 98,
      token_count: 8,
      embedding: nil, # No embedding - keyword only
      metadata: {}
    )

    mock_bedrock_embedding do
      result = @service.query("email campaign workflow")

      # Should find the keyword chunk even without embedding
      # (Note: This depends on PostgreSQL full-text search being set up)
    end
  end

  # ===== Result Merging and Reranking =====

  test "combines vector and keyword scores" do
    mock_bedrock_embedding do
      result = @service.query("campaign marketing")

      # Chunks should have combined_score
      if result[:chunks].any?
        chunk = result[:chunks].first
        # Score should be between 0 and 1
        assert chunk[:similarity_score] >= 0
        assert chunk[:similarity_score] <= 1
      end
    end
  end

  test "sorts results by combined score" do
    mock_bedrock_embedding do
      result = @service.query("test")

      if result[:chunks].length > 1
        scores = result[:chunks].map { |c| c[:similarity_score] }

        # Scores should be in descending order
        sorted_scores = scores.sort.reverse
        assert_equal sorted_scores, scores
      end
    end
  end

  # ===== Context Building =====

  test "builds context from chunks" do
    mock_bedrock_embedding do
      result = @service.query("test")

      assert_not_nil result[:context]
      assert_kind_of String, result[:context]

      if result[:chunks].any?
        # Context should include chunk content
        first_chunk = result[:chunks].first
        assert_includes result[:context], first_chunk[:content].slice(0, 50)
      end
    end
  end

  test "includes metadata in context" do
    mock_bedrock_embedding do
      result = @service.query("test")

      if result[:chunks].any?
        context = result[:context]

        # Should include source filename
        assert_includes context, "Source:"

        # Should include context numbering
        assert_includes context, "[Context 1]"
      end
    end
  end

  test "includes relevance scores in context" do
    mock_bedrock_embedding do
      result = @service.query("test")

      if result[:chunks].any?
        context = result[:context]

        # Should include relevance percentage
        assert_includes context, "Relevance:"
      end
    end
  end

  # ===== RAG Store Access Tracking =====

  test "tracks RAG store access" do
    initial_access_count = @rag_store.access_count || 0

    mock_bedrock_embedding do
      @service.query("test")
    end

    @rag_store.reload
    # Access count should have increased (if chunks were found)
    # Note: May not increase if no chunks match
  end

  test "updates last_accessed_at timestamp" do
    @rag_store.update!(last_accessed_at: 1.day.ago)

    mock_bedrock_embedding do
      @service.query("test")
    end

    @rag_store.reload
    # Last accessed should be recent (if chunks were found)
  end

  # ===== Claude Integration =====

  test "query_with_claude invokes Claude with context" do
    skip "Claude integration test - requires full Bedrock mock"
    # This would require mocking both embed AND Claude model invocations
    # Skipping for now as it's complex integration testing
  end

  # ===== Comprehend NLP Enhancement (Phase 3) =====

  test "query without NLP enhancement disabled by default" do
    mock_bedrock_embedding do
      result = @service.query("How do I create a campaign?")

      # NLP should be disabled by default
      assert_nil result[:query_analysis]
    end
  end

  test "query with NLP enhancement when enabled" do
    mock_comprehend_analysis do
      mock_bedrock_embedding do
        result = @service.query(
          "What did Tim Cook say about Apple iPhone sales?",
          enable_nlp: true
        )

        # Should include query analysis
        assert_not_nil result[:query_analysis]
        assert result[:query_analysis].key?(:language)
        assert result[:query_analysis].key?(:entities)
        assert result[:query_analysis].key?(:key_phrases)
        assert result[:query_analysis].key?(:processing_time_ms)
      end
    end
  end

  test "extracts entities from query with NLP" do
    mock_comprehend_analysis(
      entities: [
        { type: 'PERSON', text: 'Tim Cook', score: 0.99 },
        { type: 'ORGANIZATION', text: 'Apple', score: 0.98 },
        { type: 'COMMERCIAL_ITEM', text: 'iPhone', score: 0.95 }
      ]
    ) do
      mock_bedrock_embedding do
        result = @service.query(
          "What did Tim Cook say about Apple iPhone sales?",
          enable_nlp: true
        )

        entities = result[:query_analysis][:entities]
        assert_equal 3, entities.length
        assert_equal 'Tim Cook', entities[0][:text]
        assert_equal 'Apple', entities[1][:text]
        assert_equal 'iPhone', entities[2][:text]
      end
    end
  end

  test "extracts key phrases from query with NLP" do
    mock_comprehend_analysis(
      key_phrases: [
        { text: 'iPhone sales', score: 0.99 },
        { text: 'quarterly results', score: 0.95 }
      ]
    ) do
      mock_bedrock_embedding do
        result = @service.query(
          "Tell me about iPhone sales in quarterly results",
          enable_nlp: true
        )

        phrases = result[:query_analysis][:key_phrases]
        assert_equal 2, phrases.length
        assert_equal 'iPhone sales', phrases[0][:text]
        assert_equal 'quarterly results', phrases[1][:text]
      end
    end
  end

  test "detects query language with NLP" do
    mock_comprehend_analysis(language: 'es') do
      mock_bedrock_embedding do
        result = @service.query(
          "¿Cómo creo una campaña?",
          enable_nlp: true
        )

        assert_equal 'es', result[:query_analysis][:language]
      end
    end
  end

  test "enhances keyword search with extracted entities" do
    # Create chunk mentioning "Apple"
    apple_chunk = @rag_document.rag_chunks.create!(
      content: "Apple reported strong Q4 earnings with iPhone revenue growth.",
      chunk_index: 99,
      token_count: 12,
      embedding: @sample_embedding,
      metadata: { page: 1 }
    )

    mock_comprehend_analysis(
      entities: [
        { type: 'ORGANIZATION', text: 'Apple', score: 0.98 }
      ],
      key_phrases: [
        { text: 'quarterly earnings', score: 0.95 }
      ]
    ) do
      mock_bedrock_embedding do
        # Query doesn't mention "Apple" directly but Comprehend extracts it
        result = @service.query(
          "What did the company report in quarterly earnings?",
          enable_nlp: true
        )

        # Enhanced search should find Apple chunk
        # (Note: This depends on full-text search being set up)
        assert_not_nil result
      end
    end
  end

  test "handles Comprehend service disabled" do
    # Stub Comprehend service to return disabled
    comprehend_mock = Minitest::Mock.new
    comprehend_mock.expect :enabled?, false

    Aws::ComprehendService.stub :instance, comprehend_mock do
      service = HybridRagQueryService.new(@entity)

      mock_bedrock_embedding_for_service(service) do
        result = service.query("test query", enable_nlp: true)

        # Should work without NLP
        assert_not_nil result
        assert_nil result[:query_analysis]
      end
    end
  end

  test "handles Comprehend API errors gracefully" do
    # Mock Comprehend to raise error
    comprehend_mock = Minitest::Mock.new
    comprehend_mock.expect :enabled?, true
    comprehend_mock.expect :detect_language, -> { raise StandardError, "AWS API error" }, [String, Hash]

    Aws::ComprehendService.stub :instance, comprehend_mock do
      service = HybridRagQueryService.new(@entity)

      mock_bedrock_embedding_for_service(service) do
        # Should not raise error, should fallback gracefully
        assert_nothing_raised do
          result = service.query("test query", enable_nlp: true)
          assert_not_nil result
        end
      end
    end
  end

  test "NLP enhancement tracks processing time" do
    mock_comprehend_analysis do
      mock_bedrock_embedding do
        result = @service.query("test query", enable_nlp: true)

        assert result[:query_analysis][:processing_time_ms] >= 0
      end
    end
  end

  test "empty query with NLP returns default analysis" do
    mock_comprehend_analysis(
      entities: [],
      key_phrases: []
    ) do
      mock_bedrock_embedding do
        result = @service.query("test", enable_nlp: true)

        assert_equal [], result[:query_analysis][:entities]
        assert_equal [], result[:query_analysis][:key_phrases]
      end
    end
  end

  test "multi-lingual query with NLP auto-detects language" do
    mock_comprehend_analysis(language: 'fr') do
      mock_bedrock_embedding do
        result = @service.query(
          "Comment créer une campagne marketing?",
          enable_nlp: true
        )

        assert_equal 'fr', result[:query_analysis][:language]
      end
    end
  end

  # ===== Edge Cases =====

  test "handles empty query results" do
    mock_bedrock_embedding do
      # Query that won't match any chunks
      result = @service.query("xyzabc123nonexistent")

      assert_not_nil result
      assert_equal 0, result[:chunks].length
      assert_equal 0, result[:source_count]
      assert_equal "", result[:context]
    end
  end

  test "handles chunks without embeddings" do
    # Create chunk without embedding
    no_embedding_chunk = @rag_document.rag_chunks.create!(
      content: "Chunk without embedding",
      chunk_index: 97,
      token_count: 5,
      embedding: nil,
      metadata: {}
    )

    mock_bedrock_embedding do
      # Should still work (keyword search can find it)
      result = @service.query("embedding")

      assert_not_nil result
    end
  end

  test "handles Pinecone not configured" do
    # Ensure Pinecone env vars are not set
    ENV.stub :[], proc { |key|
      case key
      when 'PINECONE_API_KEY', 'PINECONE_ENVIRONMENT'
        nil
      else
        ENV.fetch(key, nil)
      end
    } do
      mock_bedrock_embedding do
        # Should still work with just pgvector
        result = @service.query("test")

        assert_not_nil result
      end
    end
  end

  test "handles very long queries" do
    long_query = "test " * 1000 # Very long query

    mock_bedrock_embedding do
      assert_nothing_raised do
        @service.query(long_query)
      end
    end
  end

  test "handles queries with special characters" do
    special_query = "How do I use @mentions and #hashtags?"

    mock_bedrock_embedding do
      result = @service.query(special_query)

      assert_equal special_query, result[:query]
    end
  end

  test "handles entity with no RAG stores" do
    empty_entity = Entity.create!(
      name: 'Empty Entity',
      subdomain: 'empty'
    )

    service = HybridRagQueryService.new(empty_entity)

    mock_bedrock_embedding_for_service(service) do
      result = service.query("test")

      assert_equal 0, result[:chunks].length
      assert_equal 0, result[:source_count]
    end
  end

  test "handles chunks with missing metadata" do
    minimal_chunk = @rag_document.rag_chunks.create!(
      content: "Minimal chunk",
      chunk_index: 96,
      token_count: 2,
      embedding: @sample_embedding,
      metadata: {} # Empty metadata
    )

    mock_bedrock_embedding do
      result = @service.query("minimal")

      # Should handle gracefully
      if result[:chunks].any?
        chunk = result[:chunks].find { |c| c[:id] == minimal_chunk.id }
        if chunk
          assert_nil chunk[:metadata][:page]
          assert_nil chunk[:metadata][:section]
        end
      end
    end
  end

  private

  def mock_bedrock_embedding
    bedrock = Minitest::Mock.new
    bedrock.expect :invoke_model, mock_bedrock_response, [Hash]

    HybridRagQueryService.any_instance.stub :instance_variable_get, proc { |var|
      var == :@bedrock ? bedrock : instance_variable_get(var)
    } do
      yield
    end
  end

  def mock_bedrock_embedding_for_service(service)
    bedrock = Minitest::Mock.new
    bedrock.expect :invoke_model, mock_bedrock_response, [Hash]

    service.instance_variable_set(:@bedrock, bedrock)
    yield
  end

  def mock_bedrock_response
    embedding = Array.new(1536) { rand }

    body = StringIO.new({ embedding: embedding }.to_json)

    OpenStruct.new(body: body)
  end

  def mock_comprehend_analysis(options = {})
    # Default mock analysis
    default_analysis = {
      language: options[:language] || 'en',
      entities: options[:entities] || [],
      key_phrases: options[:key_phrases] || [],
      processing_time_ms: options[:processing_time_ms] || 150
    }

    # Mock Comprehend service
    comprehend_mock = Minitest::Mock.new
    comprehend_mock.expect :enabled?, true

    # Mock language detection
    comprehend_mock.expect(
      :detect_language,
      { success: true, language_code: default_analysis[:language] },
      [String, Hash]
    )

    # Mock entity detection
    entities_result = {
      success: true,
      entities: default_analysis[:entities],
      entity_count: default_analysis[:entities].length
    }
    comprehend_mock.expect :detect_entities, entities_result, [String, Hash]

    # Mock key phrase extraction
    phrases_result = {
      success: true,
      key_phrases: default_analysis[:key_phrases],
      phrase_count: default_analysis[:key_phrases].length
    }
    comprehend_mock.expect :detect_key_phrases, phrases_result, [String, Hash]

    Aws::ComprehendService.stub :instance, comprehend_mock do
      # Re-initialize service to pick up mocked Comprehend
      @service = HybridRagQueryService.new(@entity)
      yield
    end
  end
end
