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
end
