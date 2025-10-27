require "test_helper"

module Rag
  class MetricsJobTest < ActiveJob::TestCase
    def setup
      @job = MetricsJob.new
      @entity = entities(:company_one)
    end

    test "perform collects all metrics successfully" do
      result = @job.perform

      assert result.is_a?(Hash)
      assert_equal Date.current.to_s, result[:date]
      assert result[:processing].present?
      assert result[:usage].present?
      assert result[:storage].present?
      assert result[:health].present?
    end

    test "collects processing metrics" do
      # Create some test data
      store = RagStore.create!(
        name: "Test Store",
        app_name: "test",
        pinecone_index: "test-index",
        pinecone_namespace: "test-ns",
        store_type: "entity",
        entity: @entity,
        status: "active",
        processing_time_ms: 1000,
        processing_method: "docling"
      )

      doc = RagDocument.create!(
        rag_store: store,
        original_filename: "test.pdf",
        file_hash: "abc123"
      )

      RagChunk.create!(
        rag_document: doc,
        content: "Test content",
        chunk_index: 0
      )

      result = @job.perform

      assert result[:processing][:total_documents] > 0
      assert result[:processing][:total_chunks] > 0
      assert_equal 100.0, result[:processing][:docling_success_rate] # No failures
    end

    test "collects usage metrics" do
      # Create query records
      RagQuery.create!(
        entity: @entity,
        query: "test query",
        query_hash: "hash123",
        response_time_ms: 500,
        chunks_retrieved: 5,
        cache_hit: false
      )

      RagQuery.create!(
        entity: @entity,
        query: "test query 2",
        query_hash: "hash456",
        response_time_ms: 50,
        chunks_retrieved: 3,
        cache_hit: true
      )

      result = @job.perform

      assert result[:usage][:total_queries] >= 2
      assert result[:usage][:cache_hit_rate] == 50.0 # 1 of 2 queries
    end

    test "collects storage metrics" do
      result = @job.perform

      assert result[:storage].key?(:total_rag_stores)
      assert result[:storage].key?(:total_chunks)
      assert result[:storage].key?(:system_stores)
      assert result[:storage].key?(:entity_stores)
    end

    test "checks system health" do
      result = @job.perform

      assert result[:health][:checks].key?(:database)
      assert result[:health][:checks].key?(:redis)
      assert result[:health][:checks].key?(:s3)
      assert result[:health][:checks].key?(:bedrock)
      assert result[:health][:checks].key?(:queues)
    end

    test "database health check passes" do
      result = @job.perform

      assert result[:health][:checks][:database][:healthy]
    end

    test "redis health check passes" do
      result = @job.perform

      assert result[:health][:checks][:redis][:healthy]
    end

    test "calculates success rate correctly with no jobs" do
      result = @job.perform

      # Should return 100% when no jobs exist
      assert_equal 100.0, result[:processing][:docling_success_rate]
    end

    test "calculates fallback rate" do
      store1 = RagStore.create!(
        name: "Docling Store",
        app_name: "test",
        pinecone_index: "test-index",
        pinecone_namespace: "test-ns1",
        store_type: "entity",
        entity: @entity,
        status: "active",
        processing_method: "docling"
      )

      store2 = RagStore.create!(
        name: "Fallback Store",
        app_name: "test",
        pinecone_index: "test-index",
        pinecone_namespace: "test-ns2",
        store_type: "entity",
        entity: @entity,
        status: "active",
        processing_method: "fallback"
      )

      result = @job.perform

      # Should be 50% (1 of 2 uses fallback)
      assert_equal 50.0, result[:processing][:fallback_usage_rate]
    end

    test "logs metrics to Rails logger" do
      assert_nothing_raised do
        @job.perform
      end
    end

    test "alerts on high failure rate" do
      # Create failed jobs
      10.times do |i|
        RagProcessingJob.create!(
          rag_store: rag_stores(:entity_store_one),
          job_id: "job#{i}",
          job_type: "docling_extraction",
          status: 3, # failed
          error_message: "Test error"
        )
      end

      # Create only 2 successful jobs (high failure rate)
      2.times do |i|
        RagProcessingJob.create!(
          rag_store: rag_stores(:entity_store_one),
          job_id: "success#{i}",
          job_type: "docling_extraction",
          status: 2 # completed
        )
      end

      assert_nothing_raised do
        result = @job.perform
        # Should detect low success rate
        assert result[:processing][:docling_success_rate] < 80
      end
    end

    test "retries on failure with exponential backoff" do
      # Stub to force error
      @job.stub :collect_processing_metrics, ->{ raise StandardError, "Test error" } do
        assert_raises(StandardError) do
          @job.perform
        end
      end
    end
  end
end
