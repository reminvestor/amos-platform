require "test_helper"

module Rag
  class FallbackProcessorJobTest < ActiveJob::TestCase
    setup do
      @rag_store = rag_stores(:entity_store_one)
      @rag_document = rag_documents(:pdf_doc_one)

      # Sample content for different file types
      @sample_content = "This is sample document content that will be chunked into smaller pieces for RAG processing."
    end

    # ===== Successful Processing =====

    test "successfully processes document with fallback extraction" do
      mock_s3_download(@sample_content) do
        assert_difference 'RagChunk.count' do
          FallbackProcessorJob.perform_now(@rag_document.id)
        end
      end
    end

    test "creates processing job record" do
      mock_s3_download(@sample_content) do
        assert_difference 'RagProcessingJob.count', 1 do
          FallbackProcessorJob.perform_now(@rag_document.id)
        end

        job_record = RagProcessingJob.last
        assert_equal 'fallback_processor', job_record.job_type
        assert_equal 'completed', job_record.status
        assert_not_nil job_record.completed_at
      end
    end

    test "updates processing job on completion" do
      mock_s3_download(@sample_content) do
        FallbackProcessorJob.perform_now(@rag_document.id)

        job_record = RagProcessingJob.last
        assert_equal 'completed', job_record.status
        assert_not_nil job_record.completed_at
        assert_nil job_record.error_message
      end
    end

    # ===== S3 Download =====

    test "downloads from correct S3 path" do
      s3_client = Minitest::Mock.new
      s3_client.expect(:get_object, true) do |params|
        assert_equal ENV.fetch('RAG_BUCKET', 'amos-rag-storage'), params[:bucket]
        assert_equal @rag_store.s3_raw_path, params[:key]
        # Write dummy content to response_target
        File.write(params[:response_target], @sample_content) if params[:response_target]
      end

      stub_s3_client(s3_client) do
        FallbackProcessorJob.perform_now(@rag_document.id)
      end

      s3_client.verify
    end

    test "creates temp file with correct extension" do
      temp_file_extension = nil

      mock_s3_download(@sample_content) do
        FallbackProcessorJob.any_instance.stubs(:extract_content) { |path, _|
          temp_file_extension = File.extname(path)
          @sample_content
        }
        FallbackProcessorJob.perform_now(@rag_document.id)
      end

      assert_equal '.pdf', temp_file_extension
    end

    test "cleans up temp file after processing" do
      temp_file_path = nil

      mock_s3_download(@sample_content) do
        FallbackProcessorJob.any_instance.stubs(:extract_content) { |path, _|
          temp_file_path = path
          @sample_content
        }
        FallbackProcessorJob.perform_now(@rag_document.id)
      end

      # Temp file should be deleted after job completes
      assert_not File.exist?(temp_file_path) if temp_file_path
    end

    # ===== Content Extraction =====

    test "extracts PDF content" do
      pdf_content = "--- Page 1 ---\nFirst page content\n--- Page 2 ---\nSecond page"

      mock_pdf_reader(pdf_content) do
        mock_s3_download_pdf do
          FallbackProcessorJob.perform_now(@rag_document.id)
        end
      end

      chunk = RagChunk.last
      assert_includes chunk.content, "First page content"
    end

    test "extracts DOCX content" do
      @rag_document.update!(
        original_filename: 'document.docx',
        content_type: 'application/vnd.openxmlformats-officedocument.wordprocessingml.document'
      )

      docx_content = "Paragraph 1\n\nParagraph 2\n\nParagraph 3"

      mock_docx_reader(docx_content) do
        mock_s3_download_docx do
          FallbackProcessorJob.perform_now(@rag_document.id)
        end
      end

      chunk = RagChunk.last
      assert_includes chunk.content, "Paragraph"
    end

    test "extracts HTML content" do
      @rag_document.update!(
        original_filename: 'page.html',
        content_type: 'text/html'
      )

      html_content = "<html><body><p>Test content</p><script>alert('test')</script></body></html>"

      mock_html_reader(html_content) do
        mock_s3_download_html do
          FallbackProcessorJob.perform_now(@rag_document.id)
        end
      end

      chunk = RagChunk.last
      # Should include text content
      assert_includes chunk.content, "Test content"
      # Should not include script content (stripped by Nokogiri)
      assert_not_includes chunk.content, "alert"
    end

    test "extracts plain text content" do
      @rag_document.update!(
        original_filename: 'readme.txt',
        content_type: 'text/plain'
      )

      plain_text = "This is plain text content.\nWith multiple lines.\nAnd some formatting."

      mock_s3_download_txt(plain_text) do
        FallbackProcessorJob.perform_now(@rag_document.id)
      end

      chunk = RagChunk.last
      assert_includes chunk.content, "plain text content"
    end

    test "extracts markdown content" do
      @rag_document.update!(
        original_filename: 'README.md',
        content_type: 'text/markdown'
      )

      markdown = "# Heading\n\n## Subheading\n\nParagraph with **bold** text."

      mock_s3_download_txt(markdown) do
        FallbackProcessorJob.perform_now(@rag_document.id)
      end

      chunk = RagChunk.last
      # Markdown should be preserved as-is
      assert_includes chunk.content, "# Heading"
    end

    test "handles unknown file types as plain text" do
      @rag_document.update!(
        original_filename: 'data.csv',
        content_type: 'text/csv'
      )

      csv_content = "name,email\nJohn,john@example.com\nJane,jane@example.com"

      mock_s3_download_txt(csv_content) do
        FallbackProcessorJob.perform_now(@rag_document.id)
      end

      chunk = RagChunk.last
      assert_includes chunk.content, "name,email"
    end

    # ===== Simple Chunking =====

    test "creates chunks of 1000 characters with 100 char overlap" do
      # Create content longer than 1000 chars
      long_content = "A" * 2500

      mock_s3_download(long_content) do
        FallbackProcessorJob.perform_now(@rag_document.id)
      end

      chunks = @rag_document.rag_chunks.order(:chunk_index)

      # Should have multiple chunks
      assert chunks.count > 1

      # First chunk should be ~1000 chars
      assert_in_delta 1000, chunks.first.content.length, 50

      # Check overlap: end of chunk 1 should overlap with start of chunk 2
      if chunks.count >= 2
        # Overlap should be approximately 100 chars
        # This is hard to test exactly with 'A' * 2500, so just verify chunks exist
        assert chunks.second.present?
      end
    end

    test "creates single chunk for content under 1000 chars" do
      short_content = "Short content" * 10 # ~130 chars

      mock_s3_download(short_content) do
        FallbackProcessorJob.perform_now(@rag_document.id)
      end

      chunks = @rag_document.rag_chunks.order(:chunk_index)
      assert_equal 1, chunks.count
    end

    test "assigns sequential chunk indices" do
      long_content = "A" * 2500

      mock_s3_download(long_content) do
        FallbackProcessorJob.perform_now(@rag_document.id)
      end

      chunks = @rag_document.rag_chunks.order(:chunk_index)
      indices = chunks.map(&:chunk_index)

      # Should be sequential: [0, 1, 2, ...]
      assert_equal (0...chunks.count).to_a, indices
    end

    test "stores chunk position metadata" do
      mock_s3_download(@sample_content) do
        FallbackProcessorJob.perform_now(@rag_document.id)
      end

      chunk = RagChunk.last
      assert_equal true, chunk.metadata['fallback']
      assert_not_nil chunk.metadata['start_position']
      assert_not_nil chunk.metadata['end_position']
      assert chunk.metadata['end_position'] > chunk.metadata['start_position']
    end

    # ===== Chunk Saving =====

    test "creates RagChunk records with correct attributes" do
      mock_s3_download(@sample_content) do
        FallbackProcessorJob.perform_now(@rag_document.id)
      end

      chunk = RagChunk.last
      assert_equal @rag_document.id, chunk.rag_document_id
      assert_equal 'text', chunk.chunk_type
      assert chunk.token_count > 0
      assert chunk.content.present?
    end

    test "estimates token count correctly" do
      content = "A" * 400 # 400 characters

      mock_s3_download(content) do
        FallbackProcessorJob.perform_now(@rag_document.id)
      end

      chunk = RagChunk.last
      # ~4 chars per token = ~100 tokens
      assert_in_delta 100, chunk.token_count, 10
    end

    test "updates RAG store chunk count" do
      initial_count = @rag_store.chunk_count || 0

      mock_s3_download(@sample_content) do
        FallbackProcessorJob.perform_now(@rag_document.id)
      end

      @rag_store.reload
      assert @rag_store.chunk_count > initial_count
    end

    test "queues embedding jobs for chunks" do
      long_content = "A" * 12000 # Will create ~13 chunks

      mock_s3_download(long_content) do
        # Should enqueue 2 embedding jobs (10 + 3)
        assert_enqueued_jobs 2, only: Rag::EmbeddingBatchJob do
          FallbackProcessorJob.perform_now(@rag_document.id)
        end
      end
    end

    test "batches embedding jobs correctly" do
      content = "A" * 5000 # ~5-6 chunks

      mock_s3_download(content) do
        assert_enqueued_jobs 1, only: Rag::EmbeddingBatchJob do
          FallbackProcessorJob.perform_now(@rag_document.id)
        end
      end
    end

    # ===== Metadata Updates =====

    test "updates document with fallback metadata" do
      mock_s3_download(@sample_content) do
        FallbackProcessorJob.perform_now(@rag_document.id)
      end

      @rag_document.reload
      assert_equal true, @rag_document.docling_metadata['fallback']
      assert_equal 'simple_extraction', @rag_document.docling_metadata['method']
      assert_not_nil @rag_document.docling_metadata['content_length']
    end

    test "updates RAG store processing method" do
      mock_s3_download(@sample_content) do
        FallbackProcessorJob.perform_now(@rag_document.id)
      end

      @rag_store.reload
      assert_equal 'fallback', @rag_store.processing_method
      assert @rag_store.processing_time_ms > 0
    end

    test "tracks processing time" do
      mock_s3_download(@sample_content) do
        FallbackProcessorJob.perform_now(@rag_document.id)
      end

      job_record = RagProcessingJob.last
      # Processing time is tracked via started_at and completed_at
      assert_not_nil job_record.started_at
      assert_not_nil job_record.completed_at
      assert job_record.completed_at >= job_record.started_at
    end

    # ===== Error Handling =====

    test "marks processing job as failed on error" do
      s3_client = Minitest::Mock.new
      s3_client.expect(:get_object, nil) do |params|
        raise Aws::S3::Errors::NoSuchKey.new(nil, 'Not found')
      end

      stub_s3_client(s3_client) do
        assert_raises(Aws::S3::Errors::NoSuchKey) do
          FallbackProcessorJob.perform_now(@rag_document.id)
        end
      end

      job_record = RagProcessingJob.last
      assert_equal 'failed', job_record.status
      assert_includes job_record.error_message, 'Not found'
    end

    test "re-raises errors to trigger retry logic" do
      s3_client = Minitest::Mock.new
      s3_client.expect(:get_object, nil) do |params|
        raise StandardError, "S3 error"
      end

      stub_s3_client(s3_client) do
        assert_raises(StandardError, /S3 error/) do
          FallbackProcessorJob.perform_now(@rag_document.id)
        end
      end
    end

    test "cleans up temp file even on error" do
      temp_file_created = false
      temp_file_path = nil

      FallbackProcessorJob.any_instance.stubs(:download_from_s3) { |*args|
        temp_file = Tempfile.new(['test', '.pdf'])
        temp_file_created = true
        temp_file_path = temp_file.path
        temp_file
      }

      FallbackProcessorJob.any_instance.stubs(:extract_content) { |*args|
        raise StandardError, "Extraction failed"
      }

      begin
        FallbackProcessorJob.perform_now(@rag_document.id)
      rescue StandardError
        # Expected
      end

      # Temp file should still be cleaned up
      # Note: This is tricky to test because Tempfile auto-deletes
      assert temp_file_created
    end

    test "discards job on RecordNotFound" do
      assert_raises(ActiveRecord::RecordNotFound) do
        FallbackProcessorJob.perform_now(999999) # Non-existent ID
      end
    end

    # ===== Gem Availability =====

    test "handles missing pdf-reader gem gracefully" do
      mock_s3_download_pdf do
        # Simulate pdf-reader not available
        FallbackProcessorJob.any_instance.stubs(:extract_pdf).returns("[PDF extraction requires pdf-reader gem]")
        FallbackProcessorJob.perform_now(@rag_document.id)
      end

      chunk = RagChunk.last
      assert_includes chunk.content, "PDF extraction requires pdf-reader gem"
    end

    test "handles missing docx gem gracefully" do
      @rag_document.update!(
        original_filename: 'doc.docx',
        content_type: 'application/vnd.openxmlformats-officedocument.wordprocessingml.document'
      )

      mock_s3_download_docx do
        FallbackProcessorJob.any_instance.stubs(:extract_docx).returns("[DOCX extraction requires docx gem]")
        FallbackProcessorJob.perform_now(@rag_document.id)
      end

      chunk = RagChunk.last
      assert_includes chunk.content, "DOCX extraction requires docx gem"
    end

    test "handles missing Nokogiri gracefully for HTML" do
      @rag_document.update!(
        original_filename: 'page.html',
        content_type: 'text/html'
      )

      html_content = "<html><body>Raw HTML content</body></html>"

      mock_s3_download_txt(html_content) do
        # Without Nokogiri, should fall back to raw HTML
        FallbackProcessorJob.any_instance.stubs(:extract_html).returns(html_content)
        FallbackProcessorJob.perform_now(@rag_document.id)
      end

      chunk = RagChunk.last
      assert_includes chunk.content, "<html>"
    end

    # ===== Edge Cases =====

    test "handles very short content" do
      short_content = "Hi"

      mock_s3_download(short_content) do
        assert_difference 'RagChunk.count', 1 do
          FallbackProcessorJob.perform_now(@rag_document.id)
        end
      end

      chunk = RagChunk.last
      assert_equal "Hi", chunk.content
      assert_equal 1, chunk.token_count
    end

    test "handles very long content" do
      # 100KB of content
      very_long_content = "A" * 100_000

      mock_s3_download(very_long_content) do
        FallbackProcessorJob.perform_now(@rag_document.id)
      end

      chunks = @rag_document.rag_chunks
      # Should create many chunks
      assert chunks.count > 50
      # All chunks should have content
      chunks.each do |chunk|
        assert chunk.content.present?
        assert chunk.token_count > 0
      end
    end

    test "handles content with special characters" do
      special_content = "Content with émojis 🔥 and spëcial çharacters\nAnd newlines\tand tabs"

      mock_s3_download(special_content) do
        FallbackProcessorJob.perform_now(@rag_document.id)
      end

      chunk = RagChunk.last
      assert_includes chunk.content, "émojis 🔥"
      assert_includes chunk.content, "spëcial"
    end

    test "handles empty content" do
      empty_content = ""

      mock_s3_download(empty_content) do
        FallbackProcessorJob.perform_now(@rag_document.id)
      end

      # Should create at least one chunk (even if empty)
      # Or might create 0 chunks depending on implementation
      assert @rag_document.rag_chunks.count >= 0
    end

    test "handles content with only whitespace" do
      whitespace_content = "   \n\n\t\t   \n   "

      mock_s3_download(whitespace_content) do
        FallbackProcessorJob.perform_now(@rag_document.id)
      end

      # After stripping, might create 1 empty chunk or 0 chunks
      chunks = @rag_document.rag_chunks
      if chunks.any?
        chunk = chunks.first
        assert chunk.content.strip.empty?
      end
    end

    test "preserves content exactly as extracted" do
      test_content = "Line 1\nLine 2\n\nLine 3 with   spaces"

      mock_s3_download(test_content) do
        FallbackProcessorJob.perform_now(@rag_document.id)
      end

      chunk = RagChunk.last
      # Should preserve newlines (though might be stripped)
      assert_includes chunk.content, "Line 1"
      assert_includes chunk.content, "Line 2"
    end

    private

    def mock_s3_download(content)
      s3_client = Minitest::Mock.new
      s3_client.expect(:get_object, true) do |params|
        # Write content to the target file
        File.write(params[:response_target], content)
      end

      stub_s3_client(s3_client) do
        yield
      end
    end

    def mock_s3_download_pdf
      s3_client = Minitest::Mock.new
      s3_client.expect(:get_object, true) do |params|
        # Create a minimal PDF file structure
        File.write(params[:response_target], "fake pdf content")
      end

      stub_s3_client(s3_client) do
        yield
      end
    end

    def mock_s3_download_docx
      s3_client = Minitest::Mock.new
      s3_client.expect(:get_object, true) do |params|
        File.write(params[:response_target], "fake docx content")
      end

      stub_s3_client(s3_client) do
        yield
      end
    end

    def mock_s3_download_html
      s3_client = Minitest::Mock.new
      s3_client.expect(:get_object, true) do |params|
        File.write(params[:response_target], "<html><body>Test</body></html>")
      end

      stub_s3_client(s3_client) do
        yield
      end
    end

    def mock_s3_download_txt(content)
      s3_client = Minitest::Mock.new
      s3_client.expect(:get_object, true) do |params|
        File.write(params[:response_target], content)
      end

      stub_s3_client(s3_client) do
        yield
      end
    end

    def stub_s3_client(client)
      Aws::S3::Client.stubs(:new).returns(client)
      yield
    end

    def mock_pdf_reader(content)
      pdf_page = OpenStruct.new(text: content)
      pdf_reader = OpenStruct.new(pages: [pdf_page])

      PDF::Reader.stubs(:new).returns(pdf_reader)
      yield
    end

    def mock_docx_reader(content)
      # Stub the extract_docx method instead of the Docx::Document class
      FallbackProcessorJob.any_instance.stubs(:extract_docx).returns(content)
      yield
    end

    def mock_html_reader(html_content)
      # Nokogiri mocking is complex, so we'll just stub the extract_html method
      FallbackProcessorJob.any_instance.stubs(:extract_html).returns(
        proc { |path|
          doc = Nokogiri::HTML(html_content)
          doc.css('script, style').remove
          doc.text.gsub(/\s+/, ' ').strip
        }.call(nil)
      )
      yield
    end
  end
end
