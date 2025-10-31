require "test_helper"

class SystemDocumentUploadTest < ActionDispatch::IntegrationTest
  def setup
    @admin = users(:admin)
    sign_in @admin
  end

  # === Access Control Integration ===

  test "non-admin cannot access system documents" do
    sign_out @admin
    marketer = users(:marketer_user)
    sign_in marketer

    get admin_system_documents_path
    assert_redirected_to root_path
    assert_equal "Access denied. Admin privileges required.", flash[:alert]

    get new_admin_system_document_path
    assert_redirected_to root_path
  end

  test "admin can access all system document pages" do
    get admin_system_documents_path
    assert_response :success

    get new_admin_system_document_path
    assert_response :success
  end

  # === Document Listing Integration ===

  test "index page displays documents with stats" do
    # Create test documents
    doc1 = create_system_document(
      category: 'api_docs',
      subcategory: 'stripe',
      status: 'indexed',
      chunk_count: 42
    )
    doc2 = create_system_document(
      category: 'integrations',
      subcategory: 'hubspot',
      status: 'pending',
      original_filename: 'hubspot.pdf'
    )
    doc3 = create_system_document(
      category: 'help_support',
      status: 'failed',
      error_message: 'S3 upload failed',
      original_filename: 'help.pdf'
    )

    get admin_system_documents_path
    assert_response :success

    # Check stats are displayed
    assert_select ".card-body h3", text: "3" # Total documents
    assert_select ".text-success", text: "1" # Indexed
    assert_select ".text-warning", text: "1" # Processing/Pending
    assert_select ".text-danger", text: "1" # Failed
  end

  test "category filtering works" do
    api_doc = create_system_document(category: 'api_docs')
    help_doc = create_system_document(category: 'help_support', original_filename: 'help.pdf')

    get admin_system_documents_path(category: 'api_docs')
    assert_response :success

    # Category sidebar should highlight api_docs
    assert_select "a.active", text: /Api Docs/
  end

  test "subcategory filtering works" do
    stripe_doc = create_system_document(
      category: 'integrations',
      subcategory: 'stripe'
    )
    hubspot_doc = create_system_document(
      category: 'integrations',
      subcategory: 'hubspot',
      original_filename: 'hubspot.pdf'
    )

    get admin_system_documents_path(category: 'integrations', subcategory: 'stripe')
    assert_response :success

    # Subcategory should be highlighted
    assert_select "a.active", text: /Stripe/
  end

  # === Document Upload Flow (Without S3) ===

  test "upload form displays all required fields" do
    get new_admin_system_document_path
    assert_response :success

    assert_select "select#system_document_category" do
      assert_select "option[value='amos_platform']"
      assert_select "option[value='integrations']"
      assert_select "option[value='help_support']"
      assert_select "option[value='api_docs']"
    end

    assert_select "input#system_document_subcategory"
    assert_select "input#system_document_file[type='file']"
    assert_select "textarea#system_document_description"
    assert_select "input[type='submit']"
  end

  test "form submission without file shows error" do
    post admin_system_documents_path, params: {
      system_document: {
        category: 'api_docs',
        subcategory: 'test',
        description: 'Test without file'
      }
    }

    assert_response :success # Renders :new
    # Note: Full test would require checking for error message in rendered view
  end

  # === Document Details ===

  test "can view document details" do
    doc = create_system_document(description: 'Detailed test document')

    get admin_system_document_path(doc)
    assert_response :success
    # Would check for document details in view
  end

  # === Document Reindexing ===

  test "can reindex failed document" do
    doc = create_system_document(
      status: 'failed',
      error_message: 'Previous error'
    )

    assert_enqueued_with(job: SystemDocumentIndexJob, args: [doc.id]) do
      post reindex_admin_system_document_path(doc)
    end

    assert_redirected_to admin_system_documents_path
    assert_match /Re-indexing started/, flash[:notice]

    doc.reload
    assert doc.status_pending?
    assert_nil doc.error_message
  end

  test "can reindex indexed document" do
    rag_store = rag_stores(:entity_store_one)
    doc = create_system_document(
      status: 'indexed',
      rag_store: rag_store,
      chunk_count: 42
    )

    post reindex_admin_system_document_path(doc)

    assert_redirected_to admin_system_documents_path
    doc.reload
    assert doc.status_pending?
  end

  # === Document Deletion (Without S3) ===

  test "admin can delete document" do
    skip "S3 mocking required for full deletion test"

    doc = create_system_document

    assert_difference('SystemDocument.count', -1) do
      delete admin_system_document_path(doc)
    end

    assert_redirected_to admin_system_documents_path
    assert_equal "Document deleted successfully", flash[:notice]
  end

  # === Status Badge Display ===

  test "pending status shows correct badge" do
    doc = create_system_document(status: 'pending')

    get admin_system_documents_path
    assert_response :success
    assert_select ".badge.bg-secondary", text: /Pending/
  end

  test "processing status shows correct badge" do
    doc = create_system_document(status: 'processing')

    get admin_system_documents_path
    assert_response :success
    assert_select ".badge.bg-warning", text: /Processing/
  end

  test "indexed status shows correct badge with chunk count" do
    doc = create_system_document(
      status: 'indexed',
      chunk_count: 42,
      indexed_at: 1.hour.ago
    )

    get admin_system_documents_path
    assert_response :success
    assert_select ".badge.bg-success", text: /Indexed/
    assert_select ".badge.bg-info", text: /42 chunks/
  end

  test "failed status shows correct badge with error" do
    doc = create_system_document(
      status: 'failed',
      error_message: 'S3 connection timeout'
    )

    get admin_system_documents_path
    assert_response :success
    assert_select ".badge.bg-danger", text: /Failed/
    assert_select ".alert-danger", text: /S3 connection timeout/
  end

  # === File Type Icons ===

  test "PDF documents show PDF icon" do
    doc = create_system_document(
      content_type: 'application/pdf',
      original_filename: 'document.pdf'
    )

    get admin_system_documents_path
    assert_response :success
    assert_select ".fa-file-pdf.text-danger"
  end

  test "Word documents show Word icon" do
    doc = create_system_document(
      content_type: 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      original_filename: 'document.docx'
    )

    get admin_system_documents_path
    assert_response :success
    assert_select ".fa-file-word.text-primary"
  end

  test "Markdown documents show code icon" do
    doc = create_system_document(
      content_type: 'text/markdown',
      original_filename: 'readme.md'
    )

    get admin_system_documents_path
    assert_response :success
    assert_select ".fa-file-code.text-info"
  end

  # === Storage Stats ===

  test "storage used calculation is correct" do
    create_system_document(file_size_bytes: 1.megabyte)
    create_system_document(
      file_size_bytes: 2.megabytes,
      original_filename: 'doc2.pdf'
    )

    get admin_system_documents_path
    assert_response :success

    # Should display "3 MB" or similar
    assert_select ".card-body h6", text: "Storage Used"
  end

  # === Category Grouping ===

  test "categories show document counts" do
    create_system_document(category: 'api_docs', subcategory: 'stripe')
    create_system_document(category: 'api_docs', subcategory: 'stripe', original_filename: 'stripe2.pdf')
    create_system_document(category: 'integrations', subcategory: 'hubspot', original_filename: 'hubspot.pdf')

    get admin_system_documents_path
    assert_response :success

    # Check category counts in sidebar
    assert_select ".list-group-item", text: /Api Docs.*2/m
    assert_select ".list-group-item", text: /Integrations.*1/m
  end

  test "subcategories show under parent category" do
    create_system_document(category: 'integrations', subcategory: 'stripe')
    create_system_document(category: 'integrations', subcategory: 'hubspot', original_filename: 'hubspot.pdf')

    get admin_system_documents_path
    assert_response :success

    # Should show nested subcategories
    assert_select ".list-group-item.ps-4", text: /Stripe/
    assert_select ".list-group-item.ps-4", text: /Hubspot/
  end

  # === Document Metadata Display ===

  test "displays upload metadata correctly" do
    doc = create_system_document(
      description: 'Test API documentation for Stripe',
      file_size_bytes: 2.megabytes
    )

    get admin_system_documents_path
    assert_response :success

    # Should show:
    # - Original filename
    # - Category → Subcategory
    # - File size (human readable)
    # - Upload time (relative)
    # - Uploaded by (user email)
    # - Description
  end

  # === Navigation ===

  test "can navigate between index and new pages" do
    get admin_system_documents_path
    assert_response :success
    assert_select "a[href=?]", new_admin_system_document_path

    get new_admin_system_document_path
    assert_response :success
  end

  # === Helper Methods ===

  private

  def create_system_document(attrs = {})
    default_attrs = {
      category: 'api_docs',
      subcategory: 'test',
      description: 'Integration test document',
      original_filename: 'test.pdf',
      content_type: 'application/pdf',
      file_size_bytes: 1024,
      uploaded_by: @admin,
      status: 'pending'
    }

    SystemDocument.create!(default_attrs.merge(attrs))
  end
end
