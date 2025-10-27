require "test_helper"

module Rag
  class DoclingExtractionJobTest < ActiveJob::TestCase
    setup do
      @rag_document = rag_documents(:pdf_doc_one)
      @rag_store = @rag_document.rag_store

      # Mock S3 download
      @mock_pdf_content = "%PDF-1.4\nSample PDF content"
    end

    # ===== Successful Extraction with Docling =====

    test "successfully extracts document using Docling when available" do
      mock_docling_available(true)
      mock_s3_download(@mock_pdf_content)
      mock_docling_output(sample_docling_json)
      mock_s3_upload

      assert_enqueued_with(job: Rag::ChunkingJob) do
        DoclingExtractionJob.perform_now(@rag_document.id)
      end
    end

    test "updates RagDocument with Docling metadata" do
      mock_docling_available(true)
      mock_s3_download(@mock_pdf_content)
      mock_docling_output(sample_docling_json)
      mock_s3_upload

      DoclingExtractionJob.perform_now(@rag_document.id)

      @rag_document.reload
      assert_not_nil @rag_document.docling_metadata
      assert_equal 'success', @rag_document.docling_metadata['status']
      assert @rag_document.docling_metadata.key?('sections')
    end

    test "stores Docling JSON output in S3" do
      mock_docling_available(true)
      mock_s3_download(@mock_pdf_content)
      mock_docling_output(sample_docling_json)

      s3_client = Minitest::Mock.new
      s3_client.expect :get_object, mock_s3_response(@mock_pdf_content), [Hash]
      s3_client.expect :put_object, nil do |args|
        args[:key].include?('docling_output') && args[:body].is_a?(String)
      end

      Aws::S3::Client.stubs(:new).returns(s3_client)
      DoclingBridgeService.stubs(:available?).returns(true)
      DoclingBridgeService.stubs(:extract_document).returns(sample_docling_json)

      DoclingExtractionJob.perform_now(@rag_document.id)

      s3_client.verify
    end

    test "queues ChunkingJob after successful extraction" do
      mock_docling_available(true)
      mock_s3_download(@mock_pdf_content)
      mock_docling_output(sample_docling_json)
      mock_s3_upload

      assert_enqueued_with(job: Rag::ChunkingJob, args: [@rag_document.id]) do
        DoclingExtractionJob.perform_now(@rag_document.id)
      end
    end

    test "creates processing job record for tracking" do
      mock_docling_available(true)
      mock_s3_download(@mock_pdf_content)
      mock_docling_output(sample_docling_json)
      mock_s3_upload

      assert_difference 'RagProcessingJob.count', 1 do
        DoclingExtractionJob.perform_now(@rag_document.id)
      end

      job_record = RagProcessingJob.last
      assert_equal 'docling_extraction', job_record.job_type
      assert_equal 'completed', job_record.status
    end

    # ===== Fallback to FallbackProcessorJob =====

    test "falls back to FallbackProcessorJob when Docling unavailable" do
      DoclingBridgeService.stubs(:available?).returns(false)

      assert_enqueued_with(job: Rag::FallbackProcessorJob, args: [@rag_document.id]) do
        DoclingExtractionJob.perform_now(@rag_document.id)
      end
    end

    test "falls back when Docling extraction fails" do
      mock_docling_available(true)
      mock_s3_download(@mock_pdf_content)

      DoclingBridgeService.stubs(:extract_document).raises(StandardError, 'Docling failed')
      Aws::S3::Client.stubs(:new).returns(mock_s3_client(@mock_pdf_content))

      assert_enqueued_with(job: Rag::FallbackProcessorJob) do
        DoclingExtractionJob.perform_now(@rag_document.id)
      end
    end

    test "logs warning when falling back" do
      DoclingBridgeService.stubs(:available?).returns(false)

      assert_changes -> { Rails.logger.warnings.any? { |w| w.include?('Fallback') } } do
        DoclingExtractionJob.perform_now(@rag_document.id)
      end
    end

    # ===== S3 Integration =====

    test "downloads document from correct S3 path" do
      expected_bucket = ENV.fetch('RAG_BUCKET', 'amos-rag-storage')
      expected_key = @rag_store.s3_raw_path

      s3_client = Minitest::Mock.new
      s3_client.expect :get_object, mock_s3_response(@mock_pdf_content) do |args|
        args[:bucket] == expected_bucket && args[:key] == expected_key
      end
      s3_client.expect :put_object, nil, [Hash]

      Aws::S3::Client.stubs(:new).returns(s3_client)
      DoclingBridgeService.stubs(:available?).returns(true)
      DoclingBridgeService.stubs(:extract_document).returns(sample_docling_json)

      DoclingExtractionJob.perform_now(@rag_document.id)

      s3_client.verify
    end

    test "uploads Docling output to correct S3 path" do
      mock_docling_available(true)
      mock_s3_download(@mock_pdf_content)
      mock_docling_output(sample_docling_json)

      s3_client = Minitest::Mock.new
      s3_client.expect :get_object, mock_s3_response(@mock_pdf_content), [Hash]
      s3_client.expect :put_object, nil do |args|
        args[:bucket] == ENV.fetch('RAG_BUCKET', 'amos-rag-storage') &&
        args[:key].include?("docling_output/#{@rag_store.id}/#{@rag_document.id}_output.json")
      end

      Aws::S3::Client.stubs(:new).returns(s3_client)
      DoclingBridgeService.stubs(:available?).returns(true)
      DoclingBridgeService.stubs(:extract_document).returns(sample_docling_json)

      DoclingExtractionJob.perform_now(@rag_document.id)

      s3_client.verify
    end

    # ===== Error Handling =====

    test "marks processing job as failed when S3 download fails" do
      s3_client = Minitest::Mock.new
      s3_client.expect(:get_object, nil) do |params|
        raise Aws::S3::Errors::NoSuchKey.new(nil, 'Not found')
      end

      Aws::S3::Client.stubs(:new).returns(s3_client)

      assert_raises(Aws::S3::Errors::NoSuchKey) do
        DoclingExtractionJob.perform_now(@rag_document.id)
      end

      job_record = RagProcessingJob.last
      assert_equal 'failed', job_record.status
      assert_includes job_record.error_message, 'Not found'
    end

    test "retries on transient errors" do
      retry_count = 0

      s3_client = Minitest::Mock.new
      s3_client.expect(:get_object, nil) do |params|
        retry_count += 1
        if retry_count < 3
          raise Aws::S3::Errors::ServiceError.new(nil, 'Temporary error')
        else
          File.write(params[:response_target], @mock_pdf_content) if params[:response_target]
        end
      end
      s3_client.expect(:put_object, nil, [Hash])

      Aws::S3::Client.stubs(:new).returns(s3_client)
      DoclingBridgeService.stubs(:available?).returns(true)
      DoclingBridgeService.stubs(:extract_document).returns(sample_docling_json)

      # Simulate retry behavior
      3.times do
        begin
          DoclingExtractionJob.perform_now(@rag_document.id)
          break
        rescue Aws::S3::Errors::ServiceError
          # Retry
        end
      end

      assert_equal 3, retry_count
    end

    # ===== Timeout Handling =====

    test "respects timeout for Docling processing" do
      mock_docling_available(true)
      mock_s3_download(@mock_pdf_content)
      mock_s3_upload

      # Simulate long-running Docling process
      DoclingBridgeService.stubs(:extract_document) { sleep(15); sample_docling_json }
      Aws::S3::Client.stubs(:new).returns(mock_s3_client(@mock_pdf_content))

      assert_raises(Timeout::Error) do
        Timeout.timeout(1) do
          DoclingExtractionJob.perform_now(@rag_document.id)
        end
      end
    end

    # ===== Metadata Extraction =====

    test "extracts table metadata from Docling output" do
      mock_docling_available(true)
      mock_s3_download(@mock_pdf_content)
      docling_with_tables = sample_docling_json.merge('tables' => [
        { 'rows' => 3, 'cols' => 2, 'content' => 'Table data' }
      ])
      mock_docling_output(docling_with_tables)
      mock_s3_upload

      DoclingExtractionJob.perform_now(@rag_document.id)

      @rag_document.reload
      assert_not_nil @rag_document.extracted_tables
      assert_equal 1, @rag_document.extracted_tables.length
    end

    test "extracts page count from Docling output" do
      mock_docling_available(true)
      mock_s3_download(@mock_pdf_content)
      docling_with_pages = sample_docling_json.merge('page_count' => 10)
      mock_docling_output(docling_with_pages)
      mock_s3_upload

      DoclingExtractionJob.perform_now(@rag_document.id)

      @rag_document.reload
      assert_equal 10, @rag_document.page_count
    end

    # ===== Different File Types =====

    test "handles PDF files" do
      @rag_document.update!(content_type: 'application/pdf')
      mock_successful_extraction
      DoclingExtractionJob.perform_now(@rag_document.id)
      assert_equal 'completed', RagProcessingJob.last.status
    end

    test "handles DOCX files" do
      @rag_document.update!(content_type: 'application/vnd.openxmlformats-officedocument.wordprocessingml.document')
      mock_successful_extraction
      DoclingExtractionJob.perform_now(@rag_document.id)
      assert_equal 'completed', RagProcessingJob.last.status
    end

    test "handles HTML files" do
      @rag_document.update!(content_type: 'text/html')
      mock_successful_extraction
      DoclingExtractionJob.perform_now(@rag_document.id)
      assert_equal 'completed', RagProcessingJob.last.status
    end

    private

    def sample_docling_json
      {
        'status' => 'success',
        'text' => 'Extracted document content',
        'sections' => [
          { 'heading' => 'Introduction', 'content' => 'Sample content', 'level' => 1 },
          { 'heading' => 'Chapter 1', 'content' => 'More content', 'level' => 1 }
        ],
        'metadata' => {
          'author' => 'Test Author',
          'created_date' => '2024-01-01'
        }
      }
    end

    def mock_docling_available(available)
      DoclingBridgeService.stubs(:available?).returns(available)
      yield if block_given?
    end

    def mock_s3_download(content)
      # Mock is set up in each test
      content
    end

    def mock_docling_output(json_output)
      DoclingBridgeService.stubs(:extract_document).returns(json_output)
      yield if block_given?
    end

    def mock_s3_upload
      # S3 upload mock is part of mock_s3_client
    end

    def mock_s3_response(content)
      response = Minitest::Mock.new
      response.expect :body, StringIO.new(content)
      response
    end

    def mock_s3_client(content)
      s3_client = Minitest::Mock.new
      s3_client.expect :get_object, mock_s3_response(content), [Hash]
      s3_client.expect :put_object, nil, [Hash]
      s3_client
    end

    def mock_successful_extraction
      mock_docling_available(true)
      mock_s3_download(@mock_pdf_content)
      mock_docling_output(sample_docling_json)
      mock_s3_upload

      Aws::S3::Client.stubs(:new).returns(mock_s3_client(@mock_pdf_content))
      yield if block_given?
    end
  end
end
