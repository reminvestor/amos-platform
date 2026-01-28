require "test_helper"

class ScoutUploadRagE2eTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @entity = entities(:demo_company)
    @user = users(:admin_user)
    @user.update!(entity: @entity, onboarded: true)
    @entity.update!(subscription_status: 'active')

    # Sign in using Devise test helper
    sign_in @user

    # Set up session for Scout
    @session_id = SecureRandom.uuid

    # Clean up any existing RAG data
    RagStore.where(entity: @entity).destroy_all
  end

  # E2E Test 1: Upload PDF → Docling Processing → RAG Storage
  test "upload PDF through Scout creates RAG knowledge base with Docling processing" do
    # Skip if Docling not available
    unless DoclingBridgeService.available?
      skip "Docling not available in test environment"
    end

    # Create a test PDF file
    pdf_content = create_test_pdf("Test Document Content", pages: 2)
    pdf_file = Tempfile.new(['test_doc', '.pdf'])
    pdf_file.binmode
    pdf_file.write(pdf_content)
    pdf_file.rewind

    uploaded_file = Rack::Test::UploadedFile.new(pdf_file.path, 'application/pdf', original_filename: 'test_document.pdf')

    # Upload via Scout
    post "/scout/upload_files", params: {
      files: {
        0 => uploaded_file
      }
    }

    assert_response :success
    response_json = JSON.parse(@response.body)

    # Verify response structure
    assert response_json['success']
    assert_equal 1, response_json['urls'].length
    assert_equal 1, response_json['rag_stores_created'].length
    assert_match /document\(s\) processed/, response_json['message']

    # Verify file details
    file_data = response_json['urls'].first
    assert_equal 'test_document.pdf', file_data['filename']
    assert_equal 'application/pdf', file_data['content_type']
    assert file_data['rag_store_id'].present?
    assert file_data['chunks_created'] > 0
    assert_equal 'docling', file_data['processed_with']

    # Verify RagStore was created
    rag_store = RagStore.find(file_data['rag_store_id'])
    assert_equal @entity, rag_store.entity
    assert_equal 'entity', rag_store.store_type
    assert_match /Upload: test_document.pdf/, rag_store.name
    assert_equal 'docling', rag_store.processing_method

    # Verify RagDocument was created
    rag_document = rag_store.rag_documents.first
    assert rag_document.present?
    assert_equal 'test_document.pdf', rag_document.original_filename
    assert rag_document.file_hash.present?
    assert_equal 64, rag_document.file_hash.length # SHA256 length

    # Verify RagChunks were created
    chunks = rag_document.rag_chunks
    assert chunks.count > 0
    assert_equal file_data['chunks_created'], chunks.count

    # Verify chunk structure
    first_chunk = chunks.first
    assert first_chunk.content.present?
    assert_equal 0, first_chunk.chunk_index
    assert first_chunk.chunk_type.present?

    # Verify ImageAsset was also created (for file storage)
    assert file_data['asset_id'].present?
    image_asset = ImageAsset.find(file_data['asset_id'])
    assert_equal @entity, image_asset.entity
    assert_equal @user, image_asset.user
    assert image_asset.file.attached?

  ensure
    pdf_file&.close
    pdf_file&.unlink
  end

  # E2E Test 2: Upload Image → Active Storage Only (No RAG Processing)
  test "upload image through Scout creates ImageAsset without RAG processing" do
    # Create a test image file
    image_file = create_test_image(100, 100)
    uploaded_file = Rack::Test::UploadedFile.new(image_file.path, 'image/png', original_filename: 'test_image.png')

    # Upload via Scout
    post "/scout/upload_files", params: {
      files: {
        0 => uploaded_file
      }
    }

    assert_response :success
    response_json = JSON.parse(@response.body)

    # Verify response structure
    assert response_json['success']
    assert_equal 1, response_json['urls'].length
    assert_nil response_json['rag_stores_created'] # No RAG processing for images

    # Verify file details
    file_data = response_json['urls'].first
    assert_equal 'test_image.png', file_data['filename']
    assert_equal 'image/png', file_data['content_type']
    assert_nil file_data['rag_store_id'] # No RAG for images
    assert_nil file_data['chunks_created']

    # Verify ImageAsset was created
    assert file_data['asset_id'].present?
    image_asset = ImageAsset.find(file_data['asset_id'])
    assert_equal @entity, image_asset.entity
    assert_equal @user, image_asset.user
    assert image_asset.file.attached?

    # Verify no RAG data was created
    assert_equal 0, RagStore.where(entity: @entity).count

  ensure
    image_file&.close
    image_file&.unlink
  end

  # E2E Test 3: Upload Multiple Files (Mixed Documents and Images)
  test "upload multiple files processes documents with RAG and images with Active Storage" do
    skip "Docling not available" unless DoclingBridgeService.available?

    # Create test files
    pdf_file = create_test_pdf_file("Document 1")
    image_file = create_test_image(100, 100)

    pdf_upload = Rack::Test::UploadedFile.new(pdf_file.path, 'application/pdf', original_filename: 'doc1.pdf')
    image_upload = Rack::Test::UploadedFile.new(image_file.path, 'image/png', original_filename: 'img1.png')

    # Upload via Scout
    post "/scout/upload_files", params: {
      files: {
        0 => pdf_upload,
        1 => image_upload
      }
    }

    assert_response :success
    response_json = JSON.parse(@response.body)

    # Verify response
    assert response_json['success']
    assert_equal 2, response_json['urls'].length
    assert_equal 1, response_json['rag_stores_created'].length # Only 1 document

    # Find PDF and image responses
    pdf_response = response_json['urls'].find { |f| f['filename'] == 'doc1.pdf' }
    image_response = response_json['urls'].find { |f| f['filename'] == 'img1.png' }

    # Verify PDF was processed with RAG
    assert pdf_response['rag_store_id'].present?
    assert pdf_response['chunks_created'] > 0

    # Verify image was NOT processed with RAG
    assert_nil image_response['rag_store_id']
    assert_nil image_response['chunks_created']

    # Both should have ImageAsset IDs
    assert pdf_response['asset_id'].present?
    assert image_response['asset_id'].present?

  ensure
    pdf_file&.close
    pdf_file&.unlink
    image_file&.close
    image_file&.unlink
  end

  # E2E Test 4: Query RAG Knowledge Base After Upload
  test "can query RAG knowledge base after uploading and processing document" do
    skip "Docling not available" unless DoclingBridgeService.available?

    # Upload document with known content
    pdf_content = create_test_pdf("The quick brown fox jumps over the lazy dog", pages: 1)
    pdf_file = Tempfile.new(['searchable_doc', '.pdf'])
    pdf_file.binmode
    pdf_file.write(pdf_content)
    pdf_file.rewind

    uploaded_file = Rack::Test::UploadedFile.new(pdf_file.path, 'application/pdf', original_filename: 'searchable.pdf')

    post "/scout/upload_files", params: {
      files: { 0 => uploaded_file }
    }

    assert_response :success
    response_json = JSON.parse(@response.body)
    rag_store_id = response_json['urls'].first['rag_store_id']

    # Verify chunks exist
    rag_store = RagStore.find(rag_store_id)
    assert rag_store.rag_chunks.count > 0

    # Test full-text search on chunks
    matching_chunks = rag_store.rag_chunks.text_search("quick brown fox")
    assert matching_chunks.count > 0, "Should find chunks with 'quick brown fox' text"

    # Test entity isolation
    other_entity = entities(:another_entity)
    other_entity_chunks = RagChunk.for_entity(other_entity)
    assert_equal 0, other_entity_chunks.count, "Other entity should not see these chunks"

    # Test document retrieval
    rag_document = rag_store.rag_documents.first
    assert_equal 'searchable.pdf', rag_document.original_filename

  ensure
    pdf_file&.close
    pdf_file&.unlink
  end

  # E2E Test 5: Successful Processing of Simple PDF (Even Invalid Content)
  test "successfully processes even simple text PDFs" do
    # Create a simple text file labeled as PDF (Docling is robust and can handle this)
    simple_pdf_file = Tempfile.new(['simple', '.pdf'])
    simple_pdf_file.write("This is simple text content")
    simple_pdf_file.rewind

    uploaded_file = Rack::Test::UploadedFile.new(simple_pdf_file.path, 'application/pdf', original_filename: 'simple.pdf')

    post "/scout/upload_files", params: {
      files: { 0 => uploaded_file }
    }

    assert_response :success
    response_json = JSON.parse(@response.body)

    # Should succeed and process as RAG (Docling is robust)
    assert response_json['success']
    assert_equal 1, response_json['urls'].length

    file_data = response_json['urls'].first
    assert file_data['asset_id'].present?

    # Docling can process even simple text files, so RAG should work
    assert file_data['rag_store_id'].present?, "Expected RAG processing for simple PDF"
    assert file_data['chunks_created'].to_i > 0

    # Verify both ImageAsset and RagStore were created
    image_asset = ImageAsset.find(file_data['asset_id'])
    assert_equal @entity, image_asset.entity

    rag_store = RagStore.find(file_data['rag_store_id'])
    assert_equal @entity, rag_store.entity

  ensure
    simple_pdf_file&.close
    simple_pdf_file&.unlink
  end

  # E2E Test 6: Duplicate Document Detection
  test "detects duplicate documents based on file hash" do
    skip "Docling not available" unless DoclingBridgeService.available?

    # Upload same document twice
    pdf_content = create_test_pdf("Duplicate test content", pages: 1)

    2.times do |i|
      pdf_file = Tempfile.new(["duplicate_#{i}", '.pdf'])
      pdf_file.binmode
      pdf_file.write(pdf_content)
      pdf_file.rewind

      uploaded_file = Rack::Test::UploadedFile.new(pdf_file.path, 'application/pdf', original_filename: "duplicate_#{i}.pdf")

      post "/scout/upload_files", params: {
        files: { 0 => uploaded_file }
      }

      assert_response :success

      pdf_file.close
      pdf_file.unlink
    end

    # Both uploads should create RagDocuments
    rag_documents = RagDocument.joins(:rag_store).where(rag_stores: { entity: @entity })
    assert_equal 2, rag_documents.count

    # Both should have the same file_hash (duplicate detection)
    hashes = rag_documents.pluck(:file_hash).uniq
    assert_equal 1, hashes.length, "Duplicate documents should have same file hash"

    # Verify duplicate detection method works
    first_doc = rag_documents.first
    assert first_doc.duplicate_exists?, "Should detect duplicate document"
  end

  # E2E Test 7: Complete Scout Chat Flow with Document Upload
  test "complete Scout chat flow with document upload and query" do
    skip "Docling not available" unless DoclingBridgeService.available?

    # Step 1: Upload document
    pdf_content = create_test_pdf("AMOS is an AI marketing automation system built with Ruby on Rails", pages: 1)
    pdf_file = Tempfile.new(['amos_doc', '.pdf'])
    pdf_file.binmode
    pdf_file.write(pdf_content)
    pdf_file.rewind

    uploaded_file = Rack::Test::UploadedFile.new(pdf_file.path, 'application/pdf', original_filename: 'amos_docs.pdf')

    post "/scout/upload_files", params: {
      files: { 0 => uploaded_file }
    }

    assert_response :success
    upload_response = JSON.parse(@response.body)
    rag_store_id = upload_response['urls'].first['rag_store_id']

    # Step 2: Verify knowledge base was created
    rag_store = RagStore.find(rag_store_id)
    assert rag_store.rag_chunks.count > 0

    # Step 3: Verify entity can access the knowledge base
    entity_rag_stores = RagStore.where(entity: @entity, store_type: 'entity')
    assert entity_rag_stores.exists?, "Entity should have RAG stores"

    # Step 4: Search for content
    matching_chunks = rag_store.rag_chunks.text_search("AMOS marketing automation")
    assert matching_chunks.count > 0, "Should find AMOS-related content"

    # Step 5: Verify chunk content
    chunk_contents = matching_chunks.map(&:content).join(" ")
    assert_match /AMOS/, chunk_contents
    assert_match /marketing/, chunk_contents

  ensure
    pdf_file&.close
    pdf_file&.unlink
  end

  private

  # Helper: Create a test PDF with specified content
  def create_test_pdf(content, pages: 1)
    require 'prawn'

    pdf = Prawn::Document.new
    pages.times do |i|
      pdf.start_new_page unless i == 0
      pdf.text "Page #{i + 1}", size: 20, style: :bold
      pdf.move_down 20
      pdf.text content
    end
    pdf.render
  end

  # Helper: Create a test PDF file
  def create_test_pdf_file(content)
    pdf_content = create_test_pdf(content, pages: 1)
    file = Tempfile.new(['test', '.pdf'])
    file.binmode
    file.write(pdf_content)
    file.rewind
    file
  end

  # Helper: Create a test image file
  def create_test_image(width, height)
    require 'chunky_png'

    png = ChunkyPNG::Image.new(width, height, ChunkyPNG::Color::WHITE)
    png[width/2, height/2] = ChunkyPNG::Color.rgb(255, 0, 0) # Red pixel in center

    file = Tempfile.new(['test', '.png'])
    file.binmode
    file.write(png.to_blob)
    file.rewind
    file
  end
end
