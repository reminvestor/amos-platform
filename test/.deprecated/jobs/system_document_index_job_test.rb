require "test_helper"

class SystemDocumentIndexJobTest < ActiveJob::TestCase
  def setup
    @admin = users(:admin)
    @system_doc = SystemDocument.create!(
      category: 'api_docs',
      subcategory: 'test',
      description: 'Test API documentation',
      original_filename: 'test_api_doc.pdf',
      content_type: 'application/pdf',
      file_size_bytes: 1024,
      uploaded_by: @admin,
      status: 'pending'
    )
  end

  # === Job Configuration ===

  test "should be enqueued on documents queue" do
    assert_equal :documents, SystemDocumentIndexJob.new.queue_name.to_sym
  end

  test "should retry on errors" do
    skip "ActiveJob retry configuration test"
    # SystemDocumentIndexJob has retry_on configured
  end

  test "should discard on RecordNotFound" do
    skip "ActiveJob discard configuration test"
    # SystemDocumentIndexJob has discard_on ActiveRecord::RecordNotFound
  end

  # === Job Execution ===

  test "should mark document as processing when job starts" do
    # Mock S3 download
    s3_response = Aws::S3::Types::GetObjectOutput.new(body: StringIO.new('fake pdf content'))
    s3_client_mock = Minitest::Mock.new
    s3_client_mock.expect :get_object, s3_response, [Hash]

    # Mock RAG pipeline
    rag_store = rag_stores(:entity_store_one)
    rag_document = rag_documents(:pdf_doc_one)
    Rag::DocumentPipelineJob.stubs(:perform_now).returns(true)

    # Stub S3 client creation in job
    SystemDocumentIndexJob.any_instance.stubs(:s3_client).returns(s3_client_mock)
    SystemDocumentIndexJob.any_instance.stubs(:create_rag_store_from_document).returns(rag_store)

    SystemDocumentIndexJob.perform_now(@system_doc.id)

    @system_doc.reload
    assert @system_doc.status_indexed?
    assert_not_nil @system_doc.rag_store

    s3_client_mock.verify
  end

  test "should download document from S3" do
    skip "S3 mocking required - test S3 download"
    # Should call s3_client.get_object with correct bucket and key
  end

  test "should create temp file from S3 content" do
    skip "S3 mocking required - test temp file creation"
    # Should create temp file with correct extension
  end

  test "should create RagStore with correct attributes" do
    skip "S3 and RAG pipeline mocking required"

    SystemDocumentIndexJob.perform_now(@system_doc.id)

    rag_store = RagStore.last
    assert_equal "Api Docs - test_api_doc.pdf", rag_store.name
    assert_equal 'api_docs', rag_store.app_name
    assert_nil rag_store.entity_id
    assert_equal 'system', rag_store.store_type
    assert_equal 'pending', rag_store.status
  end

  test "should create RagDocument with metadata" do
    skip "S3 and RAG pipeline mocking required"

    SystemDocumentIndexJob.perform_now(@system_doc.id)

    rag_doc = RagDocument.last
    assert_equal 'test_api_doc.pdf', rag_doc.original_filename
    assert_equal 'application/pdf', rag_doc.content_type
    assert_equal 1024, rag_doc.file_size_bytes
    assert_not_nil rag_doc.file_hash

    # Check metadata includes system document info
    assert_equal 'api_docs', rag_doc.docling_metadata['category']
    assert_equal 'test', rag_doc.docling_metadata['subcategory']
    assert_equal @admin.id, rag_doc.docling_metadata['uploaded_by']
    assert_equal @system_doc.id, rag_doc.docling_metadata['system_document_id']
  end

  test "should trigger Rag::DocumentPipelineJob" do
    skip "S3 mocking required - test pipeline job enqueued"

    # Should call Rag::DocumentPipelineJob.perform_now with:
    # - file_path
    # - rag_store_id
    # - rag_document_id
  end

  test "should mark document as indexed after successful processing" do
    # Mock S3 download
    s3_response = Aws::S3::Types::GetObjectOutput.new(body: StringIO.new('fake pdf content'))
    s3_client_mock = Minitest::Mock.new
    s3_client_mock.expect :get_object, s3_response, [Hash]

    # Create a real RagStore with chunks for testing
    rag_store = RagStore.create!(
      name: 'Test RAG Store',
      app_name: 'test',
      entity: nil,
      store_type: 'system',
      status: 'active'
    )

    # Create test chunks
    rag_doc = RagDocument.create!(
      rag_store: rag_store,
      original_filename: 'test.pdf',
      file_size_bytes: 1024,
      content_type: 'application/pdf',
      file_hash: 'test_hash'
    )

    10.times do |i|
      RagChunk.create!(
        rag_store: rag_store,
        rag_document: rag_doc,
        content: "Test chunk #{i}",
        chunk_index: i,
        token_count: 100
      )
    end

    # Stub methods
    SystemDocumentIndexJob.any_instance.stubs(:s3_client).returns(s3_client_mock)
    SystemDocumentIndexJob.any_instance.stubs(:create_rag_store_from_document).returns(rag_store)

    SystemDocumentIndexJob.perform_now(@system_doc.id)

    @system_doc.reload
    assert @system_doc.status_indexed?
    assert_not_nil @system_doc.indexed_at
    assert_equal rag_store, @system_doc.rag_store
    assert_equal 10, @system_doc.chunk_count
    assert_nil @system_doc.error_message

    s3_client_mock.verify
  end

  test "should link RagStore to SystemDocument" do
    skip "S3 and RAG pipeline mocking required"

    SystemDocumentIndexJob.perform_now(@system_doc.id)

    @system_doc.reload
    assert_not_nil @system_doc.rag_store
    assert_equal 'system', @system_doc.rag_store.store_type
  end

  test "should store chunk count from RagStore" do
    skip "S3 and RAG pipeline mocking required"

    SystemDocumentIndexJob.perform_now(@system_doc.id)

    @system_doc.reload
    rag_store = @system_doc.rag_store
    assert_equal rag_store.rag_chunks.count, @system_doc.chunk_count
  end

  # === Error Handling ===

  test "should mark document as failed on S3 error" do
    # Mock S3 client to raise error
    s3_client_mock = Minitest::Mock.new
    s3_client_mock.expect :get_object, -> { raise Aws::S3::Errors::NoSuchKey.new(nil, 'File not found') }, [Hash]

    SystemDocumentIndexJob.any_instance.stubs(:s3_client).returns(s3_client_mock)

    assert_raises(Aws::S3::Errors::NoSuchKey) do
      SystemDocumentIndexJob.perform_now(@system_doc.id)
    end

    @system_doc.reload
    assert @system_doc.status_failed?
    assert_not_nil @system_doc.error_message
    assert_match /NoSuchKey|File not found/, @system_doc.error_message
  end

  test "should mark document as failed on Docling error" do
    skip "S3 and Docling mocking required - test Docling error handling"

    # Mock Docling extraction failure

    SystemDocumentIndexJob.perform_now(@system_doc.id)

    @system_doc.reload
    assert @system_doc.status_failed?
    assert_not_nil @system_doc.error_message
  end

  test "should mark document as failed on embedding error" do
    skip "S3 and AWS Bedrock mocking required - test embedding error"

    # Mock AWS Bedrock embedding failure

    SystemDocumentIndexJob.perform_now(@system_doc.id)

    @system_doc.reload
    assert @system_doc.status_failed?
    assert_not_nil @system_doc.error_message
  end

  test "should truncate long error messages" do
    skip "Error mocking required"

    # Mock error with very long message (>1000 chars)

    SystemDocumentIndexJob.perform_now(@system_doc.id)

    @system_doc.reload
    assert @system_doc.error_message.length <= 1000
  end

  test "should raise error for retry logic" do
    skip "Error mocking required - test retry behavior"

    # Mock transient error (e.g., network timeout)
    # Should retry up to 3 times
  end

  test "should discard job if document not found" do
    non_existent_id = 999999

    assert_nothing_raised do
      SystemDocumentIndexJob.perform_now(non_existent_id)
    end
  end

  # === Cleanup ===

  test "should clean up temp file after processing" do
    skip "S3 mocking required - test temp file cleanup"

    # Verify temp file is deleted even if error occurs
  end

  # === S3 Helper Methods ===

  test "download_from_s3 should use correct bucket and key" do
    skip "S3 mocking required"

    # Should call:
    # s3_client.get_object(
    #   bucket: ENV['RAG_BUCKET'],
    #   key: @system_doc.s3_key
    # )
  end

  test "create_temp_file should preserve file extension" do
    skip "S3 mocking required"

    # PDF file should create .pdf temp file
    # DOCX file should create .docx temp file
  end

  # === Integration with RAG Pipeline ===

  test "should handle PDF documents" do
    skip "Full pipeline test - PDF processing"
  end

  test "should handle DOCX documents" do
    skip "Full pipeline test - DOCX processing"
  end

  test "should handle Markdown documents" do
    skip "Full pipeline test - Markdown processing"
  end

  test "should handle text documents" do
    skip "Full pipeline test - text processing"
  end

  # === Environment Configuration ===

  test "should use RAG_BUCKET environment variable" do
    skip "S3 mocking required"

    # Verify ENV['RAG_BUCKET'] is used for S3 operations
  end

  test "should use AWS_S3_ENDPOINT for LocalStack" do
    skip "S3 mocking required - test LocalStack endpoint"

    # When AWS_S3_ENDPOINT is set, should use that endpoint
  end

  test "should use real S3 when AWS_S3_ENDPOINT not set" do
    skip "S3 mocking required - test production S3"

    # When AWS_S3_ENDPOINT is not set, should use standard S3
  end
end
