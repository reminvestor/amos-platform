require "test_helper"

module Rag
  class ChunkingJobTest < ActiveJob::TestCase
    setup do
      @rag_document = rag_documents(:pdf_doc_one)
      @rag_store = @rag_document.rag_store

      # Sample Docling output with structure
      @docling_output = {
        'text' => 'Full document text content that will be chunked',
        'sections' => [
          {
            'heading' => 'Introduction',
            'content' => 'This is the introduction section with important information about the topic.',
            'level' => 1,
            'page' => 1
          },
          {
            'heading' => 'Main Content',
            'content' => 'This is the main content section with detailed information. ' * 50, # Long content
            'level' => 1,
            'page' => 2
          },
          {
            'heading' => 'Subsection',
            'content' => 'This is a subsection with more specific details.',
            'level' => 2,
            'page' => 2
          }
        ],
        'tables' => [
          {
            'markdown' => "| Header 1 | Header 2 |\n|----------|----------|\n| Data 1   | Data 2   |",
            'page' => 3
          }
        ]
      }

      @rag_document.update!(docling_metadata: @docling_output)
    end

    # ===== Successful Chunking =====

    test "successfully creates chunks from Docling output" do
      with_mocked_chunking_service(sample_chunks) do
        assert_difference 'RagChunk.count', 3 do
          ChunkingJob.perform_now(@rag_document.id)
        end
      end
    end

    test "queues EmbeddingBatchJob after chunking" do
      with_mocked_chunking_service(sample_chunks) do
        assert_enqueued_with(job: Rag::EmbeddingBatchJob) do
          ChunkingJob.perform_now(@rag_document.id)
        end
      end
    end

    test "creates processing job record" do
      with_mocked_chunking_service(sample_chunks) do
        assert_difference 'RagProcessingJob.count', 1 do
          ChunkingJob.perform_now(@rag_document.id)
        end

        job_record = RagProcessingJob.last
        assert_equal 'chunking', job_record.job_type
        assert_equal 'completed', job_record.status
      end
    end

    test "stores chunk metadata correctly" do
      with_mocked_chunking_service(sample_chunks) do
        ChunkingJob.perform_now(@rag_document.id)
      end

      chunk = RagChunk.last
      assert_not_nil chunk.metadata
      assert chunk.metadata.key?('section_title')
      assert chunk.metadata.key?('page')
    end

    # ===== Chunk Content =====

    test "preserves chunk content from service" do
      expected_content = "This is a test chunk content"
      chunks = [{ content: expected_content, chunk_index: 0, metadata: {} }]

      with_mocked_chunking_service(chunks) do
        ChunkingJob.perform_now(@rag_document.id)
      end

      chunk = RagChunk.last
      assert_equal expected_content, chunk.content
    end

    test "assigns sequential chunk indices" do
      with_mocked_chunking_service(sample_chunks) do
        ChunkingJob.perform_now(@rag_document.id)
      end

      chunks = @rag_document.rag_chunks.order(:chunk_index)
      assert_equal [0, 1, 2], chunks.map(&:chunk_index)
    end

    test "estimates token count for each chunk" do
      with_mocked_chunking_service(sample_chunks) do
        ChunkingJob.perform_now(@rag_document.id)
      end

      @rag_document.rag_chunks.each do |chunk|
        assert chunk.token_count > 0
        # Rough estimate: ~4 chars per token
        assert chunk.token_count <= (chunk.content.length / 4.0).ceil + 10
      end
    end

    # ===== Different Chunk Types =====

    test "handles text chunks" do
      chunks = [{ content: 'Text content', chunk_type: 'text', chunk_index: 0, metadata: {} }]

      with_mocked_chunking_service(chunks) do
        ChunkingJob.perform_now(@rag_document.id)
      end

      chunk = RagChunk.last
      assert_equal 'text', chunk.chunk_type
    end

    test "handles table chunks" do
      chunks = [{ content: '| H1 | H2 |', chunk_type: 'table', chunk_index: 0, metadata: { page: 3 } }]

      with_mocked_chunking_service(chunks) do
        ChunkingJob.perform_now(@rag_document.id)
      end

      chunk = RagChunk.last
      assert_equal 'table', chunk.chunk_type
    end

    test "handles heading chunks" do
      chunks = [{ content: 'Introduction', chunk_type: 'heading', chunk_index: 0, metadata: { level: 1 } }]

      with_mocked_chunking_service(chunks) do
        ChunkingJob.perform_now(@rag_document.id)
      end

      chunk = RagChunk.last
      assert_equal 'heading', chunk.chunk_type
      assert_equal 1, chunk.metadata['level']
    end

    # ===== Batch Processing =====

    test "batches chunks for embedding jobs (10 per batch)" do
      # Create 25 chunks
      large_chunk_set = 25.times.map do |i|
        { content: "Chunk #{i}", chunk_index: i, metadata: {} }
      end

      with_mocked_chunking_service(large_chunk_set) do
        # Should enqueue 3 embedding jobs (10, 10, 5)
        assert_enqueued_jobs 3, only: Rag::EmbeddingBatchJob do
          ChunkingJob.perform_now(@rag_document.id)
        end
      end
    end

    test "handles single batch when chunks <= 10" do
      small_chunk_set = 5.times.map do |i|
        { content: "Chunk #{i}", chunk_index: i, metadata: {} }
      end

      with_mocked_chunking_service(small_chunk_set) do
        assert_enqueued_jobs 1, only: Rag::EmbeddingBatchJob do
          ChunkingJob.perform_now(@rag_document.id)
        end
      end
    end

    # ===== Edge Cases =====

    test "handles empty Docling output" do
      @rag_document.update!(docling_metadata: nil)

      # Should fall back to simple text splitting
      assert_difference 'RagChunk.count', 0 do
        ChunkingJob.perform_now(@rag_document.id)
      end
    end

    test "handles very long single section" do
      long_content = 'A' * 10000 # 10k characters
      long_section = {
        'sections' => [
          { 'heading' => 'Long', 'content' => long_content, 'level' => 1 }
        ]
      }
      @rag_document.update!(docling_metadata: long_section)

      # Simulate chunking service splitting long content
      chunks = []
      long_content.scan(/.{1,1000}/).each_with_index do |chunk_text, i|
        chunks << { content: chunk_text, chunk_index: i, metadata: {} }
      end

      # Should split into multiple chunks
      with_mocked_chunking_service(chunks) do
        assert_difference 'RagChunk.count', 10 do
          ChunkingJob.perform_now(@rag_document.id)
        end
      end
    end

    test "handles special characters in content" do
      special_content = "Content with émojis 🔥 and spëcial çharacters"
      chunks = [{ content: special_content, chunk_index: 0, metadata: {} }]

      with_mocked_chunking_service(chunks) do
        ChunkingJob.perform_now(@rag_document.id)
      end

      chunk = RagChunk.last
      assert_equal special_content, chunk.content
    end

    # ===== Error Handling =====

    test "marks processing job as failed on error" do
      with_mocked_chunking_service(proc { raise StandardError, 'Chunking failed' }) do
        assert_raises(StandardError) do
          ChunkingJob.perform_now(@rag_document.id)
        end
      end

      job_record = RagProcessingJob.last
      assert_equal 'failed', job_record.status
      assert_includes job_record.error_message, 'Chunking failed'
    end

    test "retries on transient errors" do
      # Simulate transient error then success
      call_count = 0

      DoclingChunkingService.stub :chunk_document, proc {
        call_count += 1
        if call_count == 1
          raise StandardError, 'Temporary error'
        else
          sample_chunks
        end
      } do
        # First call raises, retry succeeds
        begin
          ChunkingJob.perform_now(@rag_document.id)
        rescue StandardError
          # Retry
          ChunkingJob.perform_now(@rag_document.id)
        end
      end

      assert_equal 2, call_count
      assert_equal 'completed', RagProcessingJob.last.status
    end

    # ===== Document State =====

    test "does not process if document already has chunks" do
      # Create existing chunks
      @rag_document.rag_chunks.create!(
        content: 'Existing chunk',
        chunk_index: 0,
        token_count: 10
      )

      # Should skip processing
      assert_no_difference 'RagChunk.count' do
        ChunkingJob.perform_now(@rag_document.id)
      end
    end

    test "processes fresh document without chunks" do
      assert_equal 0, @rag_document.rag_chunks.count

      with_mocked_chunking_service(sample_chunks) do
        assert_difference 'RagChunk.count', 3 do
          ChunkingJob.perform_now(@rag_document.id)
        end
      end
    end

    # ===== Service Integration =====

    test "calls DoclingChunkingService with correct parameters" do
      service_called = false
      expected_metadata = @rag_document.docling_metadata

      DoclingChunkingService.stub :chunk_document, proc { |metadata, **options|
        service_called = true
        assert_equal expected_metadata, metadata
        assert_kind_of Hash, options
        sample_chunks
      } do
        ChunkingJob.perform_now(@rag_document.id)
      end

      assert service_called
    end

    test "passes RAG document ID to embedding jobs" do
      with_mocked_chunking_service(sample_chunks) do
        ChunkingJob.perform_now(@rag_document.id)
      end

      # Verify embedding job was enqueued with correct chunk IDs
      chunk_ids = @rag_document.rag_chunks.pluck(:id)
      assert_enqueued_with(job: Rag::EmbeddingBatchJob, args: [chunk_ids])
    end

    # ===== Metadata Preservation =====

    test "preserves page numbers in chunk metadata" do
      chunks = [
        { content: 'Page 1 content', chunk_index: 0, metadata: { page: 1 } },
        { content: 'Page 2 content', chunk_index: 1, metadata: { page: 2 } }
      ]

      with_mocked_chunking_service(chunks) do
        ChunkingJob.perform_now(@rag_document.id)
      end

      chunk_pages = @rag_document.rag_chunks.order(:chunk_index).pluck('metadata -> \'page\'')
      assert_equal ['1', '2'], chunk_pages.map(&:to_s)
    end

    test "preserves section titles in chunk metadata" do
      chunks = [
        { content: 'Intro', chunk_index: 0, metadata: { section_title: 'Introduction' } }
      ]

      with_mocked_chunking_service(chunks) do
        ChunkingJob.perform_now(@rag_document.id)
      end

      chunk = RagChunk.last
      assert_equal 'Introduction', chunk.metadata['section_title']
    end

    private

    def sample_chunks
      [
        {
          content: 'This is the first chunk of content from the introduction section.',
          chunk_index: 0,
          chunk_type: 'text',
          metadata: { section_title: 'Introduction', page: 1 }
        },
        {
          content: 'This is the second chunk from the main content section.',
          chunk_index: 1,
          chunk_type: 'text',
          metadata: { section_title: 'Main Content', page: 2 }
        },
        {
          content: '| Header 1 | Header 2 |\n|----------|----------|',
          chunk_index: 2,
          chunk_type: 'table',
          metadata: { page: 3 }
        }
      ]
    end

    # Helper method for stubbing DoclingChunkingService
    def with_mocked_chunking_service(chunks)
      DoclingChunkingService.any_instance.stubs(:chunk).returns(chunks)
      yield
    end
  end
end
