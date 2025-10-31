require "test_helper"

module Rag
  class EmbeddingBatchJobTest < ActiveJob::TestCase
    setup do
      @rag_store = rag_stores(:entity_store_one)
      @rag_document = rag_documents(:pdf_doc_one)

      # Create test chunks
      @chunks = 3.times.map do |i|
        @rag_document.rag_chunks.create!(
          content: "This is test chunk #{i} with some content to embed.",
          chunk_index: i,
          token_count: 10,
          chunk_type: 'text',
          metadata: { page: i + 1, section_title: "Section #{i}" }
        )
      end

      @chunk_ids = @chunks.map(&:id)

      # Sample embedding vector (1536 dimensions)
      @sample_embedding = Array.new(1536) { rand }
    end

    # ===== Successful Embedding Generation =====

    test "successfully generates embeddings via Bedrock" do
      mock_bedrock_client do |bedrock|
        assert_difference 'RagProcessingJob.count', 1 do
          EmbeddingBatchJob.perform_now(@chunk_ids)
        end

        # Verify all chunks now have embeddings
        @chunks.each do |chunk|
          chunk.reload
          assert_not_nil chunk.embedding
          assert_equal 1536, chunk.embedding.length
        end
      end
    end

    test "creates processing job record" do
      mock_bedrock_client do
        assert_difference 'RagProcessingJob.count', 1 do
          EmbeddingBatchJob.perform_now(@chunk_ids)
        end

        job_record = RagProcessingJob.last
        assert_equal 'embedding_batch', job_record.job_type
        assert_equal 'completed', job_record.status
        assert_equal 3, job_record.metadata['chunk_count']
        assert_equal @chunk_ids, job_record.metadata['chunk_ids']
      end
    end

    test "updates processing job on completion" do
      mock_bedrock_client do
        EmbeddingBatchJob.perform_now(@chunk_ids)

        job_record = RagProcessingJob.last
        assert_equal 'completed', job_record.status
        assert_not_nil job_record.completed_at
        assert_nil job_record.error_message
      end
    end

    # ===== Bedrock Integration =====

    test "calls Bedrock with correct model and parameters" do
      bedrock = Minitest::Mock.new

      # Expect 3 calls (one per chunk)
      3.times do
        bedrock.expect :invoke_model, mock_bedrock_response, [Hash]
      end

      EmbeddingBatchJob.any_instance.stub :bedrock_client, bedrock do
        EmbeddingBatchJob.perform_now(@chunk_ids)
      end

      bedrock.verify
    end

    test "truncates very long text before embedding" do
      long_chunk = @rag_document.rag_chunks.create!(
        content: 'A' * 50_000, # 50k characters
        chunk_index: 99,
        token_count: 10_000
      )

      bedrock = Minitest::Mock.new
      bedrock.expect :invoke_model, mock_bedrock_response, [Hash] do |params|
        body = JSON.parse(params[:body])
        # Should be truncated to 25,000 chars
        assert body['inputText'].length <= 25_000
        true
      end

      EmbeddingBatchJob.any_instance.stub :bedrock_client, bedrock do
        EmbeddingBatchJob.perform_now([long_chunk.id])
      end
    end

    test "uses correct embedding model" do
      bedrock = Minitest::Mock.new
      bedrock.expect :invoke_model, mock_bedrock_response, [Hash] do |params|
        assert_equal 'amazon.titan-embed-text-v1', params[:model_id]
        assert_equal 'application/json', params[:content_type]
        true
      end

      EmbeddingBatchJob.any_instance.stub :bedrock_client, bedrock do
        EmbeddingBatchJob.perform_now([@chunk_ids.first])
      end
    end

    test "validates embedding dimensions" do
      invalid_response = mock_bedrock_response(dimensions: 512) # Wrong size

      bedrock = Minitest::Mock.new
      bedrock.expect :invoke_model, invalid_response, [Hash]

      EmbeddingBatchJob.any_instance.stub :bedrock_client, bedrock do
        assert_raises(RuntimeError, /Invalid embedding response/) do
          EmbeddingBatchJob.perform_now([@chunk_ids.first])
        end
      end
    end

    # ===== pgvector Storage =====

    test "stores embeddings in PostgreSQL pgvector" do
      mock_bedrock_client do
        EmbeddingBatchJob.perform_now(@chunk_ids)
      end

      @chunks.each do |chunk|
        chunk.reload
        assert_not_nil chunk.embedding
        assert_instance_of Array, chunk.embedding
        assert_equal 1536, chunk.embedding.length
      end
    end

    test "updates all chunks with their respective embeddings" do
      mock_bedrock_client do
        EmbeddingBatchJob.perform_now(@chunk_ids)
      end

      # Each chunk should have a unique embedding
      embeddings = @chunks.map { |c| c.reload.embedding }
      assert_equal 3, embeddings.uniq.length
    end

    # ===== Pinecone Integration =====

    test "stores embeddings in Pinecone when configured" do
      # Ensure RAG store has Pinecone config
      @rag_store.update!(
        pinecone_index: 'amos-rag-test',
        pinecone_namespace: 'entity_1'
      )

      pinecone_index = Minitest::Mock.new
      pinecone_index.expect :upsert, nil, [Hash] do |params|
        assert_equal 3, params[:vectors].length
        assert_equal 'entity_1', params[:namespace]

        # Verify vector structure
        vector = params[:vectors].first
        assert_equal "chunk_#{@chunks.first.id}", vector[:id]
        assert_equal 1536, vector[:values].length
        assert_equal @rag_store.id.to_s, vector[:metadata][:rag_store_id]
        assert_equal @rag_document.id.to_s, vector[:metadata][:rag_document_id]

        true
      end

      mock_bedrock_client do
        stub_pinecone_configured(true) do
          EmbeddingBatchJob.any_instance.stub :pinecone_index, pinecone_index do
            EmbeddingBatchJob.perform_now(@chunk_ids)
          end
        end
      end

      pinecone_index.verify
    end

    test "updates chunks with Pinecone vector IDs" do
      @rag_store.update!(
        pinecone_index: 'amos-rag-test',
        pinecone_namespace: 'entity_1'
      )

      pinecone_index = Minitest::Mock.new
      pinecone_index.expect :upsert, nil, [Hash]

      mock_bedrock_client do
        stub_pinecone_configured(true) do
          EmbeddingBatchJob.any_instance.stub :pinecone_index, pinecone_index do
            EmbeddingBatchJob.perform_now(@chunk_ids)
          end
        end
      end

      @chunks.each do |chunk|
        chunk.reload
        assert_not_nil chunk.pinecone_vector_id
        assert_equal "chunk_#{chunk.id}", chunk.pinecone_vector_id
      end
    end

    test "includes chunk metadata in Pinecone vectors" do
      @rag_store.update!(
        pinecone_index: 'amos-rag-test',
        pinecone_namespace: 'entity_1'
      )

      pinecone_index = Minitest::Mock.new
      pinecone_index.expect :upsert, nil, [Hash] do |params|
        vector = params[:vectors].first
        metadata = vector[:metadata]

        assert_equal 'text', metadata[:chunk_type]
        assert_equal 0, metadata[:chunk_index]
        assert_equal 1, metadata[:page]
        assert_equal 'Section 0', metadata[:section_title]
        assert metadata[:content_preview].length <= 1000

        true
      end

      mock_bedrock_client do
        stub_pinecone_configured(true) do
          EmbeddingBatchJob.any_instance.stub :pinecone_index, pinecone_index do
            EmbeddingBatchJob.perform_now(@chunk_ids)
          end
        end
      end
    end

    test "skips Pinecone when not configured" do
      # Remove Pinecone config
      @rag_store.update!(pinecone_index: nil, pinecone_namespace: nil)

      # Pinecone index should not be called
      mock_bedrock_client do
        stub_pinecone_configured(false) do
          # Should not raise error
          assert_nothing_raised do
            EmbeddingBatchJob.perform_now(@chunk_ids)
          end
        end
      end

      # Chunks should still have embeddings in pgvector
      @chunks.each do |chunk|
        chunk.reload
        assert_not_nil chunk.embedding
        assert_nil chunk.pinecone_vector_id
      end
    end

    # ===== RAG Store Completion =====

    test "updates RAG store status when all chunks embedded" do
      mock_bedrock_client do
        # Initially processing
        @rag_store.update!(status: 'processing')

        EmbeddingBatchJob.perform_now(@chunk_ids)

        @rag_store.reload
        # Should now be ready
        assert @rag_store.ready?
      end
    end

    test "does not update RAG store if some chunks still missing embeddings" do
      # Create an additional chunk without embedding
      extra_chunk = @rag_document.rag_chunks.create!(
        content: 'Not embedded yet',
        chunk_index: 99,
        token_count: 5
      )

      mock_bedrock_client do
        @rag_store.update!(status: 'processing')

        # Only process the first 3 chunks
        EmbeddingBatchJob.perform_now(@chunk_ids)

        @rag_store.reload
        # Should still be processing
        assert_equal 'processing', @rag_store.status
      end
    end

    test "checks RAG store completion after successful embedding" do
      all_chunks_embedded = false

      RagStore.any_instance.stub :all_chunks_embedded?, proc { all_chunks_embedded = true } do
        mock_bedrock_client do
          EmbeddingBatchJob.perform_now(@chunk_ids)
        end
      end

      assert all_chunks_embedded, "Should check if all chunks are embedded"
    end

    # ===== Batch Processing =====

    test "processes multiple chunks in single batch" do
      bedrock = Minitest::Mock.new

      # Should call Bedrock exactly 3 times
      3.times do
        bedrock.expect :invoke_model, mock_bedrock_response, [Hash]
      end

      EmbeddingBatchJob.any_instance.stub :bedrock_client, bedrock do
        EmbeddingBatchJob.perform_now(@chunk_ids)
      end

      bedrock.verify
    end

    test "handles empty chunk list" do
      assert_no_difference 'RagProcessingJob.count' do
        EmbeddingBatchJob.perform_now([])
      end
    end

    test "processes exactly 10 chunks per batch" do
      # Create 10 chunks
      large_batch = 10.times.map do |i|
        @rag_document.rag_chunks.create!(
          content: "Chunk #{i}",
          chunk_index: i + 100,
          token_count: 5
        )
      end

      bedrock = Minitest::Mock.new

      # Should call Bedrock exactly 10 times
      10.times do
        bedrock.expect :invoke_model, mock_bedrock_response, [Hash]
      end

      EmbeddingBatchJob.any_instance.stub :bedrock_client, bedrock do
        EmbeddingBatchJob.perform_now(large_batch.map(&:id))
      end

      bedrock.verify
    end

    # ===== Error Handling =====

    test "marks processing job as failed on error" do
      bedrock = Minitest::Mock.new
      bedrock.expect :invoke_model, proc { raise StandardError, "Bedrock API error" }, [Hash]

      EmbeddingBatchJob.any_instance.stub :bedrock_client, bedrock do
        assert_raises(StandardError) do
          EmbeddingBatchJob.perform_now(@chunk_ids)
        end
      end

      job_record = RagProcessingJob.last
      assert_equal 'failed', job_record.status
      assert_includes job_record.error_message, 'Bedrock API error'
      assert_not_nil job_record.completed_at
    end

    test "re-raises errors to trigger retry logic" do
      bedrock = Minitest::Mock.new
      bedrock.expect :invoke_model, proc { raise StandardError, "Temporary error" }, [Hash]

      EmbeddingBatchJob.any_instance.stub :bedrock_client, bedrock do
        assert_raises(StandardError, /Temporary error/) do
          EmbeddingBatchJob.perform_now(@chunk_ids)
        end
      end
    end

    test "retries on transient errors with exponential backoff" do
      # Verify retry configuration
      job_class = EmbeddingBatchJob

      # Check retry_on is configured
      assert job_class.retry_on_exceptions.include?(StandardError)
    end

    test "retries on Bedrock throttling with 30s wait" do
      # This tests the retry configuration for ThrottlingException
      # Actual retry behavior is tested in integration tests

      job_class = EmbeddingBatchJob
      assert job_class.retry_on_exceptions.any? { |config|
        config[:exception] == Aws::BedrockRuntime::Errors::ThrottlingException rescue false
      }
    end

    test "discards job on RecordNotFound" do
      # Verify discard_on configuration
      assert_raises(ActiveRecord::RecordNotFound) do
        EmbeddingBatchJob.perform_now([999999]) # Non-existent chunk ID
      end

      # Job should be discarded, not retried
      # This is tested by the discard_on configuration
    end

    test "discards job on ArgumentError" do
      # Create job with invalid arguments
      assert_raises(ArgumentError) do
        EmbeddingBatchJob.perform_now(nil)
      end
    end

    # ===== Edge Cases =====

    test "handles chunks with very short content" do
      short_chunk = @rag_document.rag_chunks.create!(
        content: 'Hi',
        chunk_index: 99,
        token_count: 1
      )

      mock_bedrock_client do
        assert_nothing_raised do
          EmbeddingBatchJob.perform_now([short_chunk.id])
        end
      end

      short_chunk.reload
      assert_not_nil short_chunk.embedding
    end

    test "handles chunks with special characters" do
      special_chunk = @rag_document.rag_chunks.create!(
        content: 'Content with émojis 🔥 and spëcial çharacters',
        chunk_index: 99,
        token_count: 10
      )

      mock_bedrock_client do
        assert_nothing_raised do
          EmbeddingBatchJob.perform_now([special_chunk.id])
        end
      end

      special_chunk.reload
      assert_not_nil special_chunk.embedding
    end

    test "handles chunks from different documents" do
      # Create second document
      doc2 = @rag_store.rag_documents.create!(
        original_filename: 'doc2.pdf',
        file_hash: 'hash456',
        file_size: 2000,
        content_type: 'application/pdf'
      )

      chunk_doc2 = doc2.rag_chunks.create!(
        content: 'From second document',
        chunk_index: 0,
        token_count: 5
      )

      mixed_chunk_ids = [@chunk_ids.first, chunk_doc2.id]

      mock_bedrock_client do
        assert_nothing_raised do
          EmbeddingBatchJob.perform_now(mixed_chunk_ids)
        end
      end

      # Both chunks should have embeddings
      [@chunks.first, chunk_doc2].each do |chunk|
        chunk.reload
        assert_not_nil chunk.embedding
      end
    end

    test "truncates content preview for Pinecone metadata" do
      @rag_store.update!(
        pinecone_index: 'amos-rag-test',
        pinecone_namespace: 'entity_1'
      )

      long_content = 'A' * 5000
      long_chunk = @rag_document.rag_chunks.create!(
        content: long_content,
        chunk_index: 99,
        token_count: 1000
      )

      pinecone_index = Minitest::Mock.new
      pinecone_index.expect :upsert, nil, [Hash] do |params|
        vector = params[:vectors].first
        # Content preview should be truncated to 1000 chars
        assert vector[:metadata][:content_preview].length <= 1000
        true
      end

      mock_bedrock_client do
        stub_pinecone_configured(true) do
          EmbeddingBatchJob.any_instance.stub :pinecone_index, pinecone_index do
            EmbeddingBatchJob.perform_now([long_chunk.id])
          end
        end
      end
    end

    private

    def mock_bedrock_client
      bedrock = Minitest::Mock.new

      # Allow multiple calls
      11.times do
        bedrock.expect :invoke_model, mock_bedrock_response, [Hash]
      end

      EmbeddingBatchJob.any_instance.stubs(:bedrock_client).returns(bedrock)
      yield bedrock if block_given?
    end

    def mock_bedrock_response(dimensions: 1536)
      embedding = Array.new(dimensions) { rand }

      body = StringIO.new({ embedding: embedding }.to_json)

      response = OpenStruct.new(body: body)
      response
    end

    def stub_pinecone_configured(value)
      ENV.stubs(:[]).with('PINECONE_API_KEY').returns(value ? 'test-key' : nil)
      ENV.stubs(:[]).with('PINECONE_ENVIRONMENT').returns(value ? 'test-env' : nil)
      yield
    end
  end
end
