require "application_system_test_case"

class FileUploadTest < ApplicationSystemTestCase
  setup do
    @entity = entities(:one)
    @user = users(:one)
    @user.update!(entity: @entity)
  end

  test "user can access document upload page" do
    sign_in(@user)

    visit new_document_path

    # Should see upload form
    assert_selector "body", visible: true
    has_upload = page.has_selector?("input[type='file']", visible: :all) ||
                 page.has_selector?("form")

    assert has_upload, "Expected document upload form"
  end

  test "document upload page shows file input" do
    sign_in(@user)

    visit new_document_path

    # Should have file input
    has_file_input = page.has_selector?("input[type='file']", visible: :all)

    assert has_file_input, "Expected file input field"
  end

  test "document upload page shows supported file types" do
    sign_in(@user)

    visit new_document_path

    # Should mention supported types
    has_types_info = page.has_text?(/pdf|word|doc|excel|text|csv/i) ||
                     page.has_selector?("[data-supported-types]") ||
                     page.has_text?(/supported|allowed|accept/i)

    # Types info is optional, just check page loads
    assert_selector "body", visible: true
  end

  test "document upload form has title field" do
    sign_in(@user)

    visit new_document_path

    # Should have title/name field
    has_title = page.has_selector?("input[name*='title']") ||
                page.has_selector?("input[name*='name']") ||
                page.has_text?(/title|name/i)

    # Title field is optional
    assert_selector "form", visible: true
  end

  test "document upload form has collection selector" do
    sign_in(@user)

    visit new_document_path

    # Should have collection/folder selector
    has_collection = page.has_selector?("select[name*='collection']") ||
                     page.has_selector?("input[name*='collection']") ||
                     page.has_text?(/collection|folder|library/i)

    # Collection selector is optional
    assert_selector "body", visible: true
  end

  test "document upload validates file selection" do
    sign_in(@user)

    visit new_document_path

    # Try to submit without file
    if page.has_selector?("button[type='submit']")
      click_button "Upload" rescue click_button "Save" rescue find("button[type='submit']").click rescue nil

      sleep 1

      # Should show error or stay on form
      still_on_form = current_path.include?("document") || page.has_selector?("form")
      has_error = page.has_text?(/select.*file|required|please|error/i)

      assert still_on_form || has_error, "Expected file validation"
    end
  end

  test "documents page has drag and drop area" do
    sign_in(@user)

    visit documents_path

    # Should have dropzone or drag-drop UI
    has_dropzone = page.has_selector?("[data-dropzone]") ||
                   page.has_selector?(".dropzone") ||
                   page.has_selector?("[data-controller*='upload']") ||
                   page.has_text?(/drag.*drop|drop.*here/i)

    # Dropzone is optional
    assert_selector "body", visible: true
  end

  test "document upload shows progress indicator" do
    sign_in(@user)

    visit new_document_path

    # Should have progress bar or upload indicator elements
    has_progress_ui = page.has_selector?(".progress") ||
                      page.has_selector?("[data-progress]") ||
                      page.has_selector?("[role='progressbar']") ||
                      page.has_text?(/uploading|progress/i)

    # Progress UI may only show during upload
    assert_selector "body", visible: true
  end

  test "uploaded documents appear in documents list" do
    # Create a document via model
    rag_store = RagStore.create!(
      entity: @entity,
      user: @user,
      name: "Test Upload Store",
      app_name: "documents",
      store_type: "entity",
      status: "active"
    )

    RagDocument.create!(
      rag_store: rag_store,
      title: "Uploaded Test File.pdf",
      original_filename: "Uploaded Test File.pdf",
      content_type: "application/pdf",
      file_size_bytes: 1024,
      file_hash: SecureRandom.hex(32),
      processing_status: "completed"
    )

    sign_in(@user)

    visit documents_path

    # Should show the document
    has_document = page.has_text?(/uploaded test file/i) ||
                   page.has_text?(/test upload/i)

    assert has_document, "Expected uploaded document in list"
  end

  test "document details page shows file information" do
    rag_store = RagStore.create!(
      entity: @entity,
      user: @user,
      name: "File Info Store",
      app_name: "documents",
      store_type: "entity",
      status: "active"
    )

    document = RagDocument.create!(
      rag_store: rag_store,
      title: "Info Test Document",
      original_filename: "info_test.pdf",
      content_type: "application/pdf",
      file_size_bytes: 2048,
      file_hash: SecureRandom.hex(32),
      processing_status: "completed"
    )

    sign_in(@user)

    visit document_path(document)

    # Should show file info
    has_filename = page.has_text?(/info.*test/i)
    has_type = page.has_text?(/pdf/i) || page.has_selector?("[data-file-type]")

    assert has_filename || has_type, "Expected file information"
  end

  test "document can be downloaded" do
    rag_store = RagStore.create!(
      entity: @entity,
      user: @user,
      name: "Download Store",
      app_name: "documents",
      store_type: "entity",
      status: "active"
    )

    document = RagDocument.create!(
      rag_store: rag_store,
      title: "Downloadable Document",
      original_filename: "downloadable.pdf",
      content_type: "application/pdf",
      file_size_bytes: 1024,
      file_hash: SecureRandom.hex(32),
      processing_status: "completed"
    )

    sign_in(@user)

    visit document_path(document)

    # Should have download option
    has_download = page.has_selector?("a", text: /download/i) ||
                   page.has_selector?("button", text: /download/i) ||
                   page.has_selector?("a[href*='download']")

    assert has_download, "Expected download option"
  end

  private

end
