require "test_helper"

class RagEndToEndTest < ActionDispatch::IntegrationTest
  # This test requires valid API keys and should be run manually
  # Skip by default, run with: rails test test/integration/rag_end_to_end_test.rb

  def setup
    @entity = entities(:one)
    @user = users(:one)

    # Check if we have required API keys (uses Bedrock for embeddings, Pinecone for vectors)
    @has_aws = ENV['AWS_ACCESS_KEY_ID'].present? || ENV['AWS_REGION'].present?
    @has_pinecone = ENV['PINECONE_API_KEY'].present?
    @can_run_e2e = @has_aws && @has_pinecone
  end

  # ============================================================================
  # END-TO-END TEST - Full RAG Workflow
  # ============================================================================

  test "complete RAG workflow: create, store, query" do
    skip "Requires AWS Bedrock and Pinecone API keys - run with RUN_RAG_E2E=true" unless @can_run_e2e && ENV['RUN_RAG_E2E'] == 'true'

    service = RagStoreService.new

    # Step 1: Create test documents
    test_chunks = [
      {
        content: "AMOS is a conversational AI platform that uses AWS Bedrock and Claude for intelligent agent workflows.",
        metadata: {
          source: "docs/introduction.md",
          page: 1,
          type: "documentation",
          heading: "What is AMOS?"
        }
      },
      {
        content: "The RAG system in AMOS uses Pinecone for vector storage and OpenAI embeddings for semantic search.",
        metadata: {
          source: "docs/rag-architecture.md",
          page: 1,
          type: "documentation",
          heading: "RAG Architecture"
        }
      },
      {
        content: "Multi-tenant isolation is achieved through Pinecone namespaces, with entity-scoped prefixes.",
        metadata: {
          source: "docs/rag-architecture.md",
          page: 2,
          type: "documentation",
          heading: "Multi-Tenant Design"
        }
      }
    ]

    # Step 2: Create RAG store (entity-scoped)
    puts "\n=== Creating RAG Store ==="
    result = service.create_rag_store(
      "amos-test-docs",
      test_chunks,
      {
        entity: @entity,
        user: @user,
        name: "AMOS Test Documentation",
        store_type: "entity"
      }
    )

    assert result[:success], "Failed to create RAG store: #{result[:error]}"

    rag_store = result[:rag_store]
    assert_not_nil rag_store
    assert_equal "AMOS Test Documentation", rag_store.name
    assert_equal 3, rag_store.chunk_count
    assert_equal "entity", rag_store.store_type
    assert_equal @entity.id, rag_store.entity_id

    puts "✅ RAG Store Created: #{rag_store.id}"
    puts "   Chunks: #{rag_store.chunk_count}"
    puts "   Namespace: #{rag_store.pinecone_namespace}"

    # Step 3: Query the RAG store
    puts "\n=== Querying RAG Store ==="

    queries = [
      "What is AMOS?",
      "How does RAG work in AMOS?",
      "Explain multi-tenant isolation"
    ]

    queries.each do |query|
      puts "\nQuery: #{query}"

      results = service.query_rag_store(rag_store.id, query, @entity, top_k: 2)

      assert results.is_a?(Array), "Query should return array"
      assert results.length > 0, "Query should return results"
      assert results.length <= 2, "Should respect top_k parameter"

      results.each_with_index do |result, i|
        puts "  #{i + 1}. [Score: #{result[:score].round(3)}] #{result[:content][0..80]}..."

        assert result[:content].present?
        assert result[:score].is_a?(Numeric)
        assert result[:score] >= 0 && result[:score] <= 1
        assert result[:source].present?
      end
    end

    # Step 4: Test access control
    puts "\n=== Testing Access Control ==="

    other_entity = entities(:two)

    error = assert_raises SecurityError do
      service.query_rag_store(rag_store.id, "test", other_entity)
    end

    puts "✅ Access control works: #{error.message}"

    # Step 5: Test system store (if we want shared knowledge)
    puts "\n=== Creating System Store ==="

    system_chunks = [
      {
        content: "Stripe API allows you to create customers, subscriptions, and process payments.",
        metadata: {
          source: "stripe.com/docs",
          type: "api_docs"
        }
      }
    ]

    system_result = service.create_rag_store(
      "stripe-api-docs",
      system_chunks,
      {
        name: "Stripe API Documentation",
        store_type: "system"
      }
    )

    assert system_result[:success]
    system_store = system_result[:rag_store]
    assert_equal "system", system_store.store_type
    assert_nil system_store.entity_id

    puts "✅ System Store Created: #{system_store.id}"

    # Verify any entity can access system store
    results = service.query_rag_store(system_store.id, "stripe API", @entity)
    assert results.length > 0

    results2 = service.query_rag_store(system_store.id, "stripe API", other_entity)
    assert results2.length > 0

    puts "✅ System store accessible to all entities"

    # Step 6: Verify enhanced metadata tracking
    puts "\n=== Verifying Enhanced Metadata ==="

    assert rag_store.supports_page_filtering, "Should support page filtering"
    assert rag_store.supports_heading_search, "Should support heading search"
    assert_equal 3, rag_store.chunks_with_pages
    assert_equal 3, rag_store.chunks_with_headings
    assert rag_store.avg_chunk_tokens > 0

    puts "✅ Enhanced metadata tracked correctly"
    puts "   Pages: #{rag_store.chunks_with_pages}/#{rag_store.chunk_count}"
    puts "   Headings: #{rag_store.chunks_with_headings}/#{rag_store.chunk_count}"
    puts "   Avg tokens: #{rag_store.avg_chunk_tokens}"

    # Cleanup
    puts "\n=== Cleanup ==="
    rag_store.destroy
    system_store.destroy
    puts "✅ Test stores cleaned up"

    puts "\n" + "=" * 60
    puts "✅ END-TO-END RAG TEST PASSED"
    puts "=" * 60
  end

  # ============================================================================
  # PERFORMANCE TEST
  # ============================================================================

  test "RAG query performance is acceptable" do
    skip "Requires valid API keys" unless @can_run_e2e
    skip "Performance test - run manually"

    service = RagStoreService.new

    # Create store with 20 chunks
    chunks = 20.times.map do |i|
      {
        content: "Test document chunk number #{i} with various content about AMOS features.",
        metadata: { source: "test.pdf", page: i + 1 }
      }
    end

    result = service.create_rag_store("perf-test", chunks, { entity: @entity, user: @user })
    store = result[:rag_store]

    # Measure query time
    start_time = Time.current
    results = service.query_rag_store(store.id, "AMOS features", @entity, top_k: 5)
    query_time = Time.current - start_time

    puts "\n=== Performance Results ==="
    puts "Chunks indexed: 20"
    puts "Query time: #{(query_time * 1000).round(2)}ms"
    puts "Results returned: #{results.length}"

    # Query should complete in under 3 seconds (generous for API calls)
    assert query_time < 3.0, "Query took too long: #{query_time}s"

    store.destroy
  end

  # ============================================================================
  # EMBEDDING CACHE TEST
  # ============================================================================

  test "embedding cache improves performance" do
    skip "Requires valid API keys and Redis" unless @can_run_e2e && ENV['REDIS_URL']
    skip "Cache test - run manually"

    service = RagStoreService.new

    # Clear cache
    cache = service.instance_variable_get(:@embedding_cache)
    cache.clear! if cache.available?

    text = "Test content for caching performance"

    # First call - cache miss
    start1 = Time.current
    service.send(:generate_embedding, text)
    time1 = Time.current - start1

    # Second call - cache hit
    start2 = Time.current
    service.send(:generate_embedding, text)
    time2 = Time.current - start2

    puts "\n=== Cache Performance ==="
    puts "First call (cache miss): #{(time1 * 1000).round(2)}ms"
    puts "Second call (cache hit): #{(time2 * 1000).round(2)}ms"
    puts "Speedup: #{(time1 / time2).round(2)}x"

    # Cache hit should be significantly faster
    assert time2 < time1, "Cache hit should be faster than miss"
  end

  # ============================================================================
  # DOCLING INTEGRATION TEST
  # ============================================================================

  test "Docling processes documents correctly" do
    skip "Requires Docling installation"
    skip "Docling test - run manually"

    # Test would upload actual PDF and verify Docling processing
    # This requires Docling Python dependencies to be installed
  end
end
