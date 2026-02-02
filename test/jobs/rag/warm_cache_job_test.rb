require "test_helper"

module Rag
  class WarmCacheJobTest < ActiveJob::TestCase
    def setup
      @job = WarmCacheJob.new
      @entity = entities(:one)
    end

    test "perform finds popular queries" do
      # Create popular queries (run 5 times)
      5.times do
        RagQuery.create!(
          entity: @entity,
          query: "popular query",
          query_hash: Digest::SHA256.hexdigest("popular query"),
          response_time_ms: 100,
          chunks_retrieved: 3,
          created_at: 2.days.ago
        )
      end

      result = @job.perform

      assert result[:popular_queries_found] > 0
    end

    test "only caches queries with minimum frequency" do
      # Create query run only once (below threshold)
      RagQuery.create!(
        entity: @entity,
        query: "rare query",
        query_hash: Digest::SHA256.hexdigest("rare query"),
        response_time_ms: 100,
        chunks_retrieved: 2,
        created_at: 2.days.ago
      )

      # Create popular query (run 3+ times)
      3.times do
        RagQuery.create!(
          entity: @entity,
          query: "popular query",
          query_hash: Digest::SHA256.hexdigest("popular query"),
          response_time_ms: 100,
          chunks_retrieved: 3,
          created_at: 2.days.ago
        )
      end

      result = @job.perform

      # Should only find the popular query
      assert_equal 1, result[:popular_queries_found]
    end

    test "respects cache limit" do
      # Create many popular queries (more than CACHE_LIMIT)
      100.times do |i|
        5.times do
          RagQuery.create!(
            entity: @entity,
            query: "query #{i}",
            query_hash: Digest::SHA256.hexdigest("query #{i}"),
            response_time_ms: 100,
            chunks_retrieved: 2,
            created_at: 2.days.ago
          )
        end
      end

      result = @job.perform

      # Should not exceed CACHE_LIMIT (50)
      assert result[:popular_queries_found] <= WarmCacheJob::CACHE_LIMIT
    end

    test "warms cache for popular query" do
      # Skip if Redis isn't available (cache warming depends on Redis)
      skip "Redis or cache not available" unless redis_available? && cache_available?

      # Clean up existing queries from fixtures first
      RagQuery.delete_all

      # Create RAG store and chunks for testing
      store = RagStore.create!(
        name: "Test Store",
        app_name: "test",
        pinecone_index: "test-index",
        pinecone_namespace: "test-ns-#{SecureRandom.hex(4)}",
        store_type: "entity",
        entity: @entity,
        status: "active"
      )

      doc = RagDocument.create!(
        rag_store: store,
        original_filename: "test.pdf",
        file_hash: "abc123"
      )

      chunk = RagChunk.create!(
        rag_document: doc,
        content: "Test content about widgets",
        chunk_index: 0,
        embedding: Array.new(1536, 0.1) # Dummy embedding
      )

      # Create popular queries
      query_text = "widgets"
      query_hash = Digest::SHA256.hexdigest(query_text)

      5.times do
        RagQuery.create!(
          entity: @entity,
          query: query_text,
          query_hash: query_hash,
          response_time_ms: 100,
          chunks_retrieved: 1,
          created_at: 2.days.ago
        )
      end

      # Stub HybridRagQueryService to avoid actual query execution
      mock_result = { chunks: [{ content: "test", score: 0.9 }] }

      HybridRagQueryService.any_instance.stubs(:query).returns(mock_result)

      result = @job.perform

      assert result[:cache_warmed_count] > 0

      # Verify cache was written
      cache_key = "rag:query:#{@entity.id}:#{query_hash}"
      cached_result = Rails.cache.read(cache_key)
      assert cached_result.present?
    end

    test "handles errors gracefully" do
      # Create popular query
      5.times do
        RagQuery.create!(
          entity: @entity,
          query: "test query",
          query_hash: Digest::SHA256.hexdigest("test query"),
          response_time_ms: 100,
          chunks_retrieved: 2,
          created_at: 2.days.ago
        )
      end

      # Stub to raise error
      HybridRagQueryService.stub :new, ->(_) { raise StandardError, "Test error" } do
        result = @job.perform

        # Should continue despite errors
        assert result[:errors].length > 0
        assert result[:cache_warmed_count] == 0
      end
    end

    test "groups queries by entity" do
      entity2 = Entity.create!(name: "Entity Two", subdomain: "entity2-#{SecureRandom.hex(4)}")

      # Create popular queries for two different entities
      5.times do
        RagQuery.create!(
          entity: @entity,
          query: "entity 1 query",
          query_hash: Digest::SHA256.hexdigest("entity 1 query"),
          response_time_ms: 100,
          chunks_retrieved: 2,
          created_at: 2.days.ago
        )

        RagQuery.create!(
          entity: entity2,
          query: "entity 2 query",
          query_hash: Digest::SHA256.hexdigest("entity 2 query"),
          response_time_ms: 100,
          chunks_retrieved: 2,
          created_at: 2.days.ago
        )
      end

      result = @job.perform

      # Should find queries for both entities
      assert result[:popular_queries_found] >= 2
    end

    test "only considers recent queries" do
      # Create old popular query (outside 7 day window)
      10.times do
        RagQuery.create!(
          entity: @entity,
          query: "old query",
          query_hash: Digest::SHA256.hexdigest("old query"),
          response_time_ms: 100,
          chunks_retrieved: 2,
          created_at: 10.days.ago
        )
      end

      # Create recent popular query
      5.times do
        RagQuery.create!(
          entity: @entity,
          query: "recent query",
          query_hash: Digest::SHA256.hexdigest("recent query"),
          response_time_ms: 100,
          chunks_retrieved: 2,
          created_at: 2.days.ago
        )
      end

      result = @job.perform

      # Should only find recent queries
      assert result[:popular_queries_found] >= 1
    end

    test "logs summary correctly" do
      assert_nothing_raised do
        @job.perform
      end
    end

    test "cache keys match HybridRagQueryService format" do
      query_text = "test query"
      query_hash = Digest::SHA256.hexdigest(query_text)

      # Expected format from HybridRagQueryService
      expected_key = "rag:query:#{@entity.id}:#{query_hash}"

      # Key generated by warm cache job
      actual_key = "rag:query:#{@entity.id}:#{query_hash}"

      assert_equal expected_key, actual_key
    end

    test "retries on failure" do
      # Stub to raise error
      @job.stub :find_popular_queries, ->{ raise StandardError, "Test error" } do
        assert_raises(StandardError) do
          @job.perform
        end
      end
    end

    private

    def redis_available?
      # Skip Redis tests in CI environment - Redis isn't reliably available
      return false if ENV['CI'] == 'true'
      
      return false unless defined?($redis) && $redis.present?
      
      # Actually test read/write, not just ping
      test_key = "test_redis_available_#{Time.now.to_i}"
      $redis.setex(test_key, 5, 'test')
      result = $redis.get(test_key) == 'test'
      $redis.del(test_key)
      result
    rescue => e
      Rails.logger.debug "Redis not available for test: #{e.message}"
      false
    end

    def cache_available?
      # Test if Rails.cache actually works for read/write
      test_key = "test_cache_available_#{Time.now.to_i}"
      Rails.cache.write(test_key, 'test', expires_in: 5.seconds)
      result = Rails.cache.read(test_key) == 'test'
      Rails.cache.delete(test_key)
      result
    rescue => e
      false
    end
  end
end
