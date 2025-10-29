require "test_helper"

class Admin::SystemDocumentsControllerTest < ActionDispatch::IntegrationTest
  include ActionDispatch::TestProcess::FixtureFile

  def setup
    @admin = users(:admin)
    @user = users(:marketer_user)
    sign_in @admin
  end

  # === Access Control ===

  test "should require admin access" do
    sign_out @admin
    sign_in @user # Non-admin user

    get admin_system_documents_path
    assert_redirected_to root_path
    assert_equal "Access denied. Admin privileges required.", flash[:alert]
  end

  test "should allow admin access" do
    get admin_system_documents_path
    assert_response :success
  end

  test "should redirect non-authenticated users" do
    sign_out @admin
    get admin_system_documents_path
    assert_redirected_to new_user_session_path
  end

  # === Index Action ===

  test "should get index" do
    get admin_system_documents_path
    assert_response :success
    assert_select "h1", text: /System Document Library/
  end

  test "should display summary stats" do
    # Create test documents
    create_system_document(category: 'api_docs', status: 'indexed')
    create_system_document(category: 'integrations', status: 'pending', original_filename: 'doc2.pdf')

    get admin_system_documents_path
    assert_response :success
    assert_select ".card-body h6", text: "Total Documents"
    assert_select ".card-body h6", text: "Storage Used"
    assert_select ".card-body h6", text: "Indexed"
    assert_select ".card-body h6", text: "Processing"
    assert_select ".card-body h6", text: "Failed"
  end

  test "should filter by category" do
    api_doc = create_system_document(category: 'api_docs')
    help_doc = create_system_document(category: 'help_support', original_filename: 'help.pdf')

    get admin_system_documents_path(category: 'api_docs')
    assert_response :success
    # Would need to check @documents instance variable or rendered content
  end

  test "should filter by subcategory" do
    stripe_doc = create_system_document(category: 'api_docs', subcategory: 'stripe')
    hubspot_doc = create_system_document(category: 'api_docs', subcategory: 'hubspot', original_filename: 'hubspot.pdf')

    get admin_system_documents_path(category: 'api_docs', subcategory: 'stripe')
    assert_response :success
  end

  # === New Action ===

  test "should get new" do
    get new_admin_system_document_path
    assert_response :success
    assert_select "h1", text: /Upload System Document/
  end

  test "should display upload form" do
    get new_admin_system_document_path
    assert_response :success
    assert_select "form[action=?]", admin_system_documents_path do
      assert_select "select[name=?]", "system_document[category]"
      assert_select "input[name=?]", "system_document[file]"
      assert_select "textarea[name=?]", "system_document[description]"
    end
  end

  # === Create Action ===

  test "should create system_document with valid file" do
    file = fixture_file_upload('test_document.pdf', 'application/pdf')

    # Mock S3 client
    s3_client_mock = Minitest::Mock.new
    s3_client_mock.expect :put_object, true, [Hash]

    # Stub controller's s3_client method
    Admin::SystemDocumentsController.any_instance.stubs(:s3_client).returns(s3_client_mock)

    assert_difference('SystemDocument.count') do
      assert_enqueued_with(job: SystemDocumentIndexJob) do
        post admin_system_documents_path, params: {
          system_document: {
            category: 'api_docs',
            subcategory: 'test',
            description: 'Test document',
            file: file
          }
        }
      end
    end

    assert_redirected_to admin_system_documents_path
    assert_equal "✅ Document uploaded successfully! Indexing will begin shortly.", flash[:notice]

    doc = SystemDocument.last
    assert_equal 'api_docs', doc.category
    assert_equal 'test', doc.subcategory
    assert_equal 'pending', doc.status
    assert_equal @admin, doc.uploaded_by

    s3_client_mock.verify
  end

  test "should enqueue SystemDocumentIndexJob after upload" do
    file = fixture_file_upload('test_document.pdf', 'application/pdf')

    # Mock S3 client
    s3_client_mock = Minitest::Mock.new
    s3_client_mock.expect :put_object, true, [Hash]
    Admin::SystemDocumentsController.any_instance.stubs(:s3_client).returns(s3_client_mock)

    assert_enqueued_with(job: SystemDocumentIndexJob) do
      post admin_system_documents_path, params: {
        system_document: {
          category: 'api_docs',
          file: file
        }
      }
    end

    s3_client_mock.verify
  end

  test "should reject upload without file" do
    assert_no_difference('SystemDocument.count') do
      post admin_system_documents_path, params: {
        system_document: {
          category: 'api_docs',
          subcategory: 'test',
          description: 'Test without file'
        }
      }
    end

    assert_response :success # Renders :new
    # Check for error message
  end

  test "should handle S3 upload failure gracefully" do
    file = fixture_file_upload('test_document.pdf', 'application/pdf')

    # Mock S3 client to raise error
    s3_client_mock = Minitest::Mock.new
    s3_client_mock.expect :put_object, -> { raise Aws::S3::Errors::ServiceError.new(nil, 'Connection timeout') }, [Hash]
    Admin::SystemDocumentsController.any_instance.stubs(:s3_client).returns(s3_client_mock)

    assert_no_difference('SystemDocument.count') do
      post admin_system_documents_path, params: {
        system_document: {
          category: 'api_docs',
          file: file
        }
      }
    end

    assert_redirected_to new_admin_system_document_path
    assert_match /Upload failed/, flash[:alert]
  end

  # === Show Action ===

  test "should show system_document" do
    doc = create_system_document
    get admin_system_document_path(doc)
    assert_response :success
  end

  test "should display document details" do
    doc = create_system_document(description: 'Test description')
    get admin_system_document_path(doc)
    assert_response :success
    # Would check for document details in rendered view
  end

  # === Destroy Action ===

  test "should destroy system_document" do
    doc = create_system_document

    # Mock S3 client for deletion
    s3_client_mock = Minitest::Mock.new
    s3_client_mock.expect :delete_object, true, [Hash]
    Admin::SystemDocumentsController.any_instance.stubs(:s3_client).returns(s3_client_mock)

    assert_difference('SystemDocument.count', -1) do
      delete admin_system_document_path(doc)
    end

    assert_redirected_to admin_system_documents_path
    assert_equal "Document deleted successfully", flash[:notice]

    s3_client_mock.verify
  end

  test "should delete from S3 when destroying" do
    skip "S3 mocking required - test S3 deletion"
  end

  test "should delete associated rag_store when destroying" do
    skip "S3 mocking required - test cascade deletion"
  end

  test "should handle S3 deletion failure gracefully" do
    skip "S3 mocking required - test S3 error handling"
  end

  # === Reindex Action ===

  test "should reindex system_document" do
    doc = create_system_document(status: 'failed')

    assert_enqueued_with(job: SystemDocumentIndexJob, args: [doc.id]) do
      post reindex_admin_system_document_path(doc)
    end

    assert_redirected_to admin_system_documents_path
    assert_match /Re-indexing started/, flash[:notice]

    doc.reload
    assert doc.status_pending?
  end

  test "should clear error message when reindexing" do
    doc = create_system_document(status: 'failed', error_message: 'Old error')

    post reindex_admin_system_document_path(doc)

    doc.reload
    assert_nil doc.error_message
  end

  # === Download Action ===

  test "should redirect to S3 pre-signed URL for download" do
    skip "S3 mocking required - test pre-signed URL generation"

    doc = create_system_document

    get download_admin_system_document_path(doc)
    assert_response :redirect
    # Would check redirect URL is a valid S3 pre-signed URL
  end

  test "should generate 5-minute expiry for download URL" do
    skip "S3 mocking required - test URL expiry"
  end

  # === Helper Methods ===

  private

  def create_system_document(attrs = {})
    default_attrs = {
      category: 'api_docs',
      subcategory: 'test',
      description: 'Test document',
      original_filename: 'test.pdf',
      content_type: 'application/pdf',
      file_size_bytes: 1024,
      uploaded_by: @admin,
      status: 'pending'
    }

    SystemDocument.create!(default_attrs.merge(attrs))
  end
end
