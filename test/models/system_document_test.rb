require "test_helper"

class SystemDocumentTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  def setup
    @admin = users(:admin)
    @unique_suffix = SecureRandom.hex(6)
    @valid_attrs = {
      category: 'api_docs',
      subcategory: 'test',
      description: 'Test document',
      original_filename: "test_api_doc_#{@unique_suffix}.pdf",
      content_type: 'application/pdf',
      file_size_bytes: 1024,
      uploaded_by: @admin
    }
  end

  # === Validations ===

  test "should be valid with valid attributes" do
    doc = SystemDocument.new(@valid_attrs)
    assert doc.valid?, doc.errors.full_messages.join(", ")
  end

  test "should require category" do
    doc = SystemDocument.new(@valid_attrs.except(:category))
    assert_not doc.valid?
    assert_includes doc.errors[:category], "can't be blank"
  end

  test "should require original_filename" do
    doc = SystemDocument.new(@valid_attrs.except(:original_filename))
    assert_not doc.valid?
    assert_includes doc.errors[:original_filename], "can't be blank"
  end

  test "should require content_type" do
    doc = SystemDocument.new(@valid_attrs.except(:content_type))
    assert_not doc.valid?
    assert_includes doc.errors[:content_type], "can't be blank"
  end

  test "should require file_size_bytes" do
    doc = SystemDocument.new(@valid_attrs.except(:file_size_bytes))
    assert_not doc.valid?
    assert_includes doc.errors[:file_size_bytes], "can't be blank"
  end

  test "should require uploaded_by" do
    doc = SystemDocument.new(@valid_attrs.except(:uploaded_by))
    assert_not doc.valid?
  end

  test "should reject file_size_bytes over 50MB" do
    doc = SystemDocument.new(@valid_attrs.merge(file_size_bytes: 51.megabytes))
    assert_not doc.valid?
    assert_includes doc.errors[:file_size_bytes], "must be less than or equal to 52428800"
  end

  test "should accept file_size_bytes under 50MB" do
    doc = SystemDocument.new(@valid_attrs.merge(file_size_bytes: 49.megabytes))
    assert doc.valid?
  end

  test "should require unique s3_key" do
    doc1 = SystemDocument.create!(@valid_attrs)
    doc2 = SystemDocument.new(@valid_attrs.merge(original_filename: 'different.pdf'))
    doc2.s3_key = doc1.s3_key # Force duplicate
    assert_not doc2.valid?
    assert_includes doc2.errors[:s3_key], "has already been taken"
  end

  # === Enums ===

  test "should define category enum" do
    assert_equal %w[amos_platform integrations help_support api_docs], SystemDocument.categories.keys
  end

  test "should define status enum" do
    assert_equal %w[pending processing indexed failed], SystemDocument.statuses.keys
  end

  test "should default status to pending" do
    doc = SystemDocument.create!(@valid_attrs)
    assert doc.status_pending?
  end

  # === Callbacks ===

  test "should automatically set filename from original_filename" do
    doc = SystemDocument.new(@valid_attrs)
    doc.valid? # Trigger callbacks
    assert_not_nil doc.filename
    # Filename includes original name + timestamp (and possibly hex suffix from test setup)
    assert_match /test_api_doc_[a-f0-9]*_?\d+\.pdf/, doc.filename
  end

  test "should automatically set s3_key" do
    doc = SystemDocument.new(@valid_attrs)
    doc.valid? # Trigger callbacks
    assert_not_nil doc.s3_key
    # s3_key includes category/subcategory/filename with timestamp
    assert_match /^system\/api_docs\/test\/test_api_doc_[a-f0-9]*_?\d+\.pdf$/, doc.s3_key
  end

  test "should generate s3_key without subcategory if not provided" do
    doc = SystemDocument.new(@valid_attrs.except(:subcategory))
    doc.valid? # Trigger callbacks
    # s3_key includes category/filename with timestamp (no subcategory)
    assert_match /^system\/api_docs\/test_api_doc_[a-f0-9]*_?\d+\.pdf$/, doc.s3_key
  end

  test "should include timestamp in generated filename" do
    doc1 = SystemDocument.create!(@valid_attrs)
    sleep 0.01 # Ensure different timestamp
    doc2 = SystemDocument.create!(@valid_attrs.merge(original_filename: 'test_api_doc.pdf'))
    assert_not_equal doc1.filename, doc2.filename
  end

  # === Scopes ===

  test "should filter by category" do
    api_doc = SystemDocument.create!(@valid_attrs.merge(category: 'api_docs'))
    help_doc = SystemDocument.create!(@valid_attrs.merge(
      category: 'help_support',
      original_filename: 'help.pdf'
    ))

    result = SystemDocument.by_category('api_docs')
    assert_includes result, api_doc
    assert_not_includes result, help_doc
  end

  test "should filter by subcategory" do
    stripe_doc = SystemDocument.create!(@valid_attrs.merge(subcategory: 'stripe'))
    hubspot_doc = SystemDocument.create!(@valid_attrs.merge(
      subcategory: 'hubspot',
      original_filename: 'hubspot.pdf'
    ))

    result = SystemDocument.by_subcategory('stripe')
    assert_includes result, stripe_doc
    assert_not_includes result, hubspot_doc
  end

  test "should filter indexed documents" do
    indexed_doc = SystemDocument.create!(@valid_attrs.merge(status: 'indexed'))
    pending_doc = SystemDocument.create!(@valid_attrs.merge(
      original_filename: 'pending.pdf',
      status: 'pending'
    ))

    result = SystemDocument.indexed
    assert_includes result, indexed_doc
    assert_not_includes result, pending_doc
  end

  test "should filter pending_or_processing documents" do
    pending = SystemDocument.create!(@valid_attrs.merge(status: 'pending'))
    processing = SystemDocument.create!(@valid_attrs.merge(
      original_filename: 'processing.pdf',
      status: 'processing'
    ))
    indexed = SystemDocument.create!(@valid_attrs.merge(
      original_filename: 'indexed.pdf',
      status: 'indexed'
    ))

    result = SystemDocument.pending_or_processing
    assert_includes result, pending
    assert_includes result, processing
    assert_not_includes result, indexed
  end

  test "should filter failed documents" do
    failed_doc = SystemDocument.create!(@valid_attrs.merge(status: 'failed'))
    indexed_doc = SystemDocument.create!(@valid_attrs.merge(
      original_filename: 'indexed.pdf',
      status: 'indexed'
    ))

    result = SystemDocument.failed
    assert_includes result, failed_doc
    assert_not_includes result, indexed_doc
  end

  test "should order by recent" do
    old_doc = SystemDocument.create!(@valid_attrs)
    old_doc.update_column(:created_at, 2.days.ago)
    new_doc = SystemDocument.create!(@valid_attrs.merge(original_filename: 'new.pdf'))

    result = SystemDocument.recent
    assert_equal new_doc, result.first
  end

  # === Instance Methods ===

  test "generate_s3_key should create correct path with subcategory" do
    doc = SystemDocument.new(@valid_attrs)
    doc.filename = 'test_123.pdf'
    expected = 'system/api_docs/test/test_123.pdf'
    assert_equal expected, doc.generate_s3_key
  end

  test "generate_s3_key should create correct path without subcategory" do
    doc = SystemDocument.new(@valid_attrs.except(:subcategory))
    doc.filename = 'test_123.pdf'
    expected = 'system/api_docs/test_123.pdf'
    assert_equal expected, doc.generate_s3_key
  end

  test "ready? should return true when indexed with rag_store" do
    rag_store = rag_stores(:entity_store_one)
    doc = SystemDocument.create!(@valid_attrs.merge(
      status: 'indexed',
      rag_store: rag_store
    ))
    assert doc.ready?
  end

  test "ready? should return false when indexed without rag_store" do
    doc = SystemDocument.create!(@valid_attrs.merge(status: 'indexed'))
    assert_not doc.ready?
  end

  test "ready? should return false when not indexed" do
    doc = SystemDocument.create!(@valid_attrs.merge(status: 'pending'))
    assert_not doc.ready?
  end

  test "mark_processing! should update status" do
    doc = SystemDocument.create!(@valid_attrs)
    doc.mark_processing!
    assert doc.status_processing?
    assert_nil doc.error_message
  end

  test "mark_indexed! should update all relevant fields" do
    rag_store = rag_stores(:entity_store_one)
    doc = SystemDocument.create!(@valid_attrs.merge(status: 'processing'))

    doc.mark_indexed!(rag_store, 42)

    assert doc.status_indexed?
    assert_equal rag_store, doc.rag_store
    assert_equal 42, doc.chunk_count
    assert_not_nil doc.indexed_at
    assert_nil doc.error_message
  end

  test "mark_failed! should store error message" do
    doc = SystemDocument.create!(@valid_attrs.merge(status: 'processing'))
    error = StandardError.new("Something went wrong")

    doc.mark_failed!(error)

    assert doc.status_failed?
    assert_equal "Something went wrong", doc.error_message
  end

  test "mark_failed! should truncate long error messages" do
    doc = SystemDocument.create!(@valid_attrs.merge(status: 'processing'))
    long_error = StandardError.new("x" * 2000)

    doc.mark_failed!(long_error)

    assert_equal 1000, doc.error_message.length
  end

  test "reindex! should reset status and enqueue job" do
    doc = SystemDocument.create!(@valid_attrs.merge(
      status: 'failed',
      error_message: 'Old error'
    ))

    assert_enqueued_with(job: SystemDocumentIndexJob, args: [doc.id]) do
      doc.reindex!
    end

    assert doc.status_pending?
    assert_nil doc.error_message
  end

  # === File Type Helpers ===

  test "pdf? should return true for PDF files" do
    doc = SystemDocument.new(@valid_attrs.merge(content_type: 'application/pdf'))
    assert doc.pdf?
  end

  test "word_doc? should return true for DOCX files" do
    doc = SystemDocument.new(@valid_attrs.merge(
      content_type: 'application/vnd.openxmlformats-officedocument.wordprocessingml.document'
    ))
    assert doc.word_doc?
  end

  test "word_doc? should return true for legacy DOC files" do
    doc = SystemDocument.new(@valid_attrs.merge(content_type: 'application/msword'))
    assert doc.word_doc?
  end

  test "markdown? should return true for markdown content type" do
    doc = SystemDocument.new(@valid_attrs.merge(content_type: 'text/markdown'))
    assert doc.markdown?
  end

  test "markdown? should return true for .md extension" do
    doc = SystemDocument.new(@valid_attrs.merge(
      content_type: 'text/plain',
      original_filename: 'readme.md'
    ))
    assert doc.markdown?
  end

  test "text? should return true for text/* content types" do
    doc = SystemDocument.new(@valid_attrs.merge(content_type: 'text/plain'))
    assert doc.text?
  end

  # === Display Methods ===

  test "human_file_size should format bytes" do
    doc = SystemDocument.new(@valid_attrs.merge(file_size_bytes: 1_024_000))
    assert_equal "1000 KB", doc.human_file_size
  end

  test "display_name should include category and filename" do
    doc = SystemDocument.new(@valid_attrs)
    doc.valid? # Generate filename
    assert_match /Api Docs → Test → test_api_doc/, doc.display_name
  end

  test "display_name should exclude subcategory if not present" do
    doc = SystemDocument.new(@valid_attrs.except(:subcategory))
    doc.valid?
    assert_match /Api Docs → test_api_doc/, doc.display_name
    assert_no_match /→.*→/, doc.display_name # Should only have one arrow
  end

  # === Class Methods ===

  test "categories_with_counts should group by category and subcategory" do
    SystemDocument.create!(@valid_attrs.merge(category: 'api_docs', subcategory: 'stripe'))
    SystemDocument.create!(@valid_attrs.merge(
      category: 'api_docs',
      subcategory: 'stripe',
      original_filename: 'stripe2.pdf'
    ))
    SystemDocument.create!(@valid_attrs.merge(
      category: 'integrations',
      subcategory: 'hubspot',
      original_filename: 'hubspot.pdf'
    ))

    counts = SystemDocument.categories_with_counts
    assert_equal 2, counts[['api_docs', 'stripe']]
    assert_equal 1, counts[['integrations', 'hubspot']]
  end

  test "total_storage_used should sum file_size_bytes" do
    SystemDocument.create!(@valid_attrs.merge(file_size_bytes: 1000))
    SystemDocument.create!(@valid_attrs.merge(
      file_size_bytes: 2000,
      original_filename: 'doc2.pdf'
    ))

    assert_equal 3000, SystemDocument.total_storage_used
  end

  # === Associations ===

  test "should belong to uploaded_by user" do
    doc = SystemDocument.create!(@valid_attrs)
    assert_equal @admin, doc.uploaded_by
  end

  test "should optionally belong to rag_store" do
    rag_store = rag_stores(:entity_store_one)
    doc = SystemDocument.create!(@valid_attrs.merge(rag_store: rag_store))
    assert_equal rag_store, doc.rag_store
  end

  test "should allow nil rag_store" do
    doc = SystemDocument.create!(@valid_attrs)
    assert_nil doc.rag_store
  end
end
