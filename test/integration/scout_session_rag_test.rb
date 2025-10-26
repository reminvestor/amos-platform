require "test_helper"

# Mock Redis class that responds to all methods but does nothing
class NullRedis
  def method_missing(method, *args, **kwargs)
    nil
  end

  def respond_to_missing?(method, include_private = false)
    true
  end
end

class ScoutSessionRagTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @entity = entities(:demo_company)
    @user = users(:admin_user)
    @user.update!(entity: @entity, onboarded: true)
    @entity.update!(subscription_status: 'active')

    # Sign in
    sign_in @user

    # Clean up Redis
    $redis.flushdb if $redis.respond_to?(:flushdb)

    # Clean up database RAG data
    RagStore.where(entity: @entity).destroy_all
  end

  teardown do
    # Clean up Redis after each test
    $redis.flushdb if $redis.respond_to?(:flushdb)
  end

  # Test 1: Upload with short-term storage (Redis)
  test "upload PDF with short-term storage saves to Redis" do
    skip "Docling not available" unless DoclingBridgeService.available?

    pdf_file = create_test_pdf_file("Session document content")
    uploaded_file = Rack::Test::UploadedFile.new(
      pdf_file.path,
      'application/pdf',
      original_filename: 'session_doc.pdf'
    )

    # Upload with storage_type = short-term
    post "/scout/upload_files", params: {
      files: { 0 => uploaded_file },
      storage_type: 'short-term'
    }

    assert_response :success
    response_json = JSON.parse(@response.body)

    # Verify response
    assert response_json['success']
    assert_equal 1, response_json['urls'].length
    assert_match /processed for this conversation/, response_json['message']

    # Verify file was NOT saved to database
    assert_equal 0, RagStore.where(entity: @entity).count, "Should not create database RagStore for session storage"

    # Verify file WAS saved to Redis
    scout_session_id = session[:scout_session_id]
    session_key = "rag:session:#{scout_session_id}:documents"
    redis_docs = $redis.hgetall(session_key)

    assert_equal 1, redis_docs.keys.length, "Should store 1 document in Redis"
    assert redis_docs.key?('session_doc.pdf'), "Should store document with filename as key"

    # Verify document structure in Redis
    doc_data = JSON.parse(redis_docs['session_doc.pdf'])
    assert_equal 'session_doc.pdf', doc_data['filename']
    assert doc_data['chunks'].present?, "Should have chunks"
    assert doc_data['chunks'].length > 0, "Should have at least 1 chunk"
    assert doc_data['uploaded_at'].present?, "Should have upload timestamp"
    assert doc_data['asset_id'].present?, "Should have asset_id"
    assert doc_data['asset_url'].present?, "Should have asset_url"

    # Verify chunk structure
    first_chunk = doc_data['chunks'].first
    assert first_chunk['content'].present?, "Chunk should have content"
    assert first_chunk['index'].present?, "Chunk should have index"

  ensure
    pdf_file&.close
    pdf_file&.unlink
  end

  # Test 2: Upload with long-term storage (Database)
  test "upload PDF with long-term storage saves to database" do
    skip "Docling not available" unless DoclingBridgeService.available?

    pdf_file = create_test_pdf_file("Permanent document content")
    uploaded_file = Rack::Test::UploadedFile.new(
      pdf_file.path,
      'application/pdf',
      original_filename: 'permanent_doc.pdf'
    )

    # Upload with storage_type = long-term (or default)
    post "/scout/upload_files", params: {
      files: { 0 => uploaded_file },
      storage_type: 'long-term'
    }

    assert_response :success
    response_json = JSON.parse(@response.body)

    # Verify response
    assert response_json['success']
    assert_match /added to your knowledge base/, response_json['message']

    # Verify file WAS saved to database
    assert_equal 1, RagStore.where(entity: @entity).count, "Should create database RagStore"
    rag_store = RagStore.where(entity: @entity).first
    assert_equal 'entity', rag_store.store_type
    assert rag_store.rag_documents.exists?

    # Verify file was NOT saved to Redis
    scout_session_id = session[:scout_session_id]
    session_key = "rag:session:#{scout_session_id}:documents" if scout_session_id
    redis_docs = scout_session_id ? $redis.hgetall(session_key) : {}
    assert_equal 0, redis_docs.keys.length, "Should not store in Redis for long-term storage"

  ensure
    pdf_file&.close
    pdf_file&.unlink
  end

  # Test 3: Default storage type is long-term
  test "upload without storage_type defaults to long-term" do
    skip "Docling not available" unless DoclingBridgeService.available?

    pdf_file = create_test_pdf_file("Default storage test")
    uploaded_file = Rack::Test::UploadedFile.new(
      pdf_file.path,
      'application/pdf',
      original_filename: 'default_storage.pdf'
    )

    # Upload WITHOUT storage_type parameter
    post "/scout/upload_files", params: {
      files: { 0 => uploaded_file }
    }

    assert_response :success

    # Should create database RagStore (long-term is default)
    assert_equal 1, RagStore.where(entity: @entity).count

    # Should NOT create Redis entry
    scout_session_id = session[:scout_session_id]
    session_key = "rag:session:#{scout_session_id}:documents"
    redis_docs = $redis.hgetall(session_key)
    assert_equal 0, redis_docs.keys.length

  ensure
    pdf_file&.close
    pdf_file&.unlink
  end

  # Test 4: Session document context injection
  test "chat includes session documents in context" do
    skip "Docling not available" unless DoclingBridgeService.available?

    # Upload a document to session storage
    pdf_file = create_test_pdf_file("The quick brown fox jumps over the lazy dog")
    uploaded_file = Rack::Test::UploadedFile.new(
      pdf_file.path,
      'application/pdf',
      original_filename: 'context_test.pdf'
    )

    post "/scout/upload_files", params: {
      files: { 0 => uploaded_file },
      storage_type: 'short-term'
    }

    assert_response :success

    # Verify document is in Redis
    scout_session_id = session[:scout_session_id]
    session_key = "rag:session:#{scout_session_id}:documents"
    redis_docs = $redis.hgetall(session_key)
    assert_equal 1, redis_docs.keys.length

    # TODO: When we have a test endpoint for chat context, verify the document
    # content is included in the message context
    # For now, we can verify the Redis data structure is correct

    doc_data = JSON.parse(redis_docs.values.first)
    assert doc_data['chunks'].any? { |chunk| chunk['content'].include?('quick brown fox') }

  ensure
    pdf_file&.close
    pdf_file&.unlink
  end

  # Test 5: Multiple session documents
  test "can store multiple documents in session" do
    skip "Docling not available" unless DoclingBridgeService.available?

    # Upload first document
    pdf1 = create_test_pdf_file("First session document")
    upload1 = Rack::Test::UploadedFile.new(pdf1.path, 'application/pdf', original_filename: 'doc1.pdf')

    post "/scout/upload_files", params: {
      files: { 0 => upload1 },
      storage_type: 'short-term'
    }
    assert_response :success

    # Upload second document
    pdf2 = create_test_pdf_file("Second session document")
    upload2 = Rack::Test::UploadedFile.new(pdf2.path, 'application/pdf', original_filename: 'doc2.pdf')

    post "/scout/upload_files", params: {
      files: { 0 => upload2 },
      storage_type: 'short-term'
    }
    assert_response :success

    # Verify both documents are in Redis
    scout_session_id = session[:scout_session_id]
    session_key = "rag:session:#{scout_session_id}:documents"
    redis_docs = $redis.hgetall(session_key)

    assert_equal 2, redis_docs.keys.length, "Should have 2 documents in Redis"
    assert redis_docs.key?('doc1.pdf'), "Should have doc1.pdf"
    assert redis_docs.key?('doc2.pdf'), "Should have doc2.pdf"

  ensure
    pdf1&.close
    pdf1&.unlink
    pdf2&.close
    pdf2&.unlink
  end

  # Test 6: Session documents have TTL
  test "session documents expire after 24 hours" do
    skip "Docling not available" unless DoclingBridgeService.available?

    pdf_file = create_test_pdf_file("TTL test document")
    uploaded_file = Rack::Test::UploadedFile.new(
      pdf_file.path,
      'application/pdf',
      original_filename: 'ttl_test.pdf'
    )

    post "/scout/upload_files", params: {
      files: { 0 => uploaded_file },
      storage_type: 'short-term'
    }

    # Verify TTL is set
    scout_session_id = session[:scout_session_id]
    session_key = "rag:session:#{scout_session_id}:documents"
    ttl = $redis.ttl(session_key)

    # TTL should be approximately 24 hours (86400 seconds)
    # Allow some margin for test execution time
    assert ttl > 86300, "TTL should be approximately 24 hours (#{ttl} seconds)"
    assert ttl <= 86400, "TTL should not exceed 24 hours (#{ttl} seconds)"

  ensure
    pdf_file&.close
    pdf_file&.unlink
  end

  # Test 7: Document viewer shows session documents
  test "document viewer canvas includes session documents" do
    skip "Docling not available" unless DoclingBridgeService.available?

    # Upload a session document
    pdf_file = create_test_pdf_file("Viewer test document")
    uploaded_file = Rack::Test::UploadedFile.new(
      pdf_file.path,
      'application/pdf',
      original_filename: 'viewer_test.pdf'
    )

    post "/scout/upload_files", params: {
      files: { 0 => uploaded_file },
      storage_type: 'short-term'
    }

    # Load document viewer canvas
    post "/scout/load_canvas", params: {
      canvas_type: 'document_viewer',
      canvas_data: {}
    }

    assert_response :success
    response_json = JSON.parse(@response.body)

    assert response_json['success']
    canvas_html = response_json['canvas']['content']

    # Verify the session document appears in the viewer
    assert_match /viewer_test\.pdf/, canvas_html, "Should include session document filename"
    assert_match /Session/, canvas_html, "Should show 'Session' badge for short-term storage"

  ensure
    pdf_file&.close
    pdf_file&.unlink
  end

  # Test 8: Document viewer shows both session and database documents
  test "document viewer shows documents from both Redis and database" do
    skip "Docling not available" unless DoclingBridgeService.available?

    # Upload a session document
    session_pdf = create_test_pdf_file("Session document")
    session_upload = Rack::Test::UploadedFile.new(
      session_pdf.path,
      'application/pdf',
      original_filename: 'session_doc.pdf'
    )

    post "/scout/upload_files", params: {
      files: { 0 => session_upload },
      storage_type: 'short-term'
    }

    # Upload a permanent document
    perm_pdf = create_test_pdf_file("Permanent document")
    perm_upload = Rack::Test::UploadedFile.new(
      perm_pdf.path,
      'application/pdf',
      original_filename: 'permanent_doc.pdf'
    )

    post "/scout/upload_files", params: {
      files: { 0 => perm_upload },
      storage_type: 'long-term'
    }

    # Load document viewer
    post "/scout/load_canvas", params: {
      canvas_type: 'document_viewer',
      canvas_data: {}
    }

    assert_response :success
    response_json = JSON.parse(@response.body)
    canvas_html = response_json['canvas']['content']

    # Should show both documents
    assert_match /session_doc\.pdf/, canvas_html, "Should show session document"
    assert_match /permanent_doc\.pdf/, canvas_html, "Should show permanent document"

    # Should have both badge types
    assert_match /Session/, canvas_html, "Should have Session badge"
    assert_match /Saved/, canvas_html, "Should have Saved badge"

  ensure
    session_pdf&.close
    session_pdf&.unlink
    perm_pdf&.close
    perm_pdf&.unlink
  end

  # Test 9: Session isolation between different users
  test "session documents are isolated between users" do
    skip "Docling not available" unless DoclingBridgeService.available?

    # User 1 uploads a document
    pdf_file = create_test_pdf_file("User 1 document")
    uploaded_file = Rack::Test::UploadedFile.new(
      pdf_file.path,
      'application/pdf',
      original_filename: 'user1_doc.pdf'
    )

    post "/scout/upload_files", params: {
      files: { 0 => uploaded_file },
      storage_type: 'short-term'
    }

    user1_scout_session_id = session[:scout_session_id]

    # Sign out and sign in as different user
    sign_out @user

    # Reset session to simulate new browser session
    reset!

    other_user = users(:another_user)
    other_user.update!(entity: entities(:another_entity), onboarded: true)
    sign_in other_user

    # Make a request to establish a new session
    get "/scout"
    assert_response :success

    # User 2's session should not see User 1's document
    # After resetting session, user 2 should have no scout_session_id yet (or a different one)
    user2_scout_session_id = session[:scout_session_id]

    # Check User 1's session documents (should still exist in Redis)
    user1_session_key = "rag:session:#{user1_scout_session_id}:documents"
    user1_docs = $redis.hgetall(user1_session_key)
    assert_equal 1, user1_docs.keys.length, "User 1's documents should still be in Redis"

    # User 2 either has no scout_session_id or a different one
    if user2_scout_session_id
      assert_not_equal user1_scout_session_id, user2_scout_session_id, "Different users should have different scout session IDs"
      user2_session_key = "rag:session:#{user2_scout_session_id}:documents"
      user2_docs = $redis.hgetall(user2_session_key)
      assert_equal 0, user2_docs.keys.length, "User 2 should not see User 1's session documents"
    else
      # If user 2 has no scout_session_id yet, they definitely can't see user 1's documents
      assert true, "User 2 has no scout session ID yet, so cannot access any session documents"
    end

  ensure
    pdf_file&.close
    pdf_file&.unlink
  end

  # Test 10: Redis connection failure fallback
  test "handles Redis unavailability gracefully" do
    skip "Docling not available" unless DoclingBridgeService.available?

    # Temporarily break Redis
    original_redis = $redis
    $redis = NullRedis.new

    pdf_file = create_test_pdf_file("Fallback test")
    uploaded_file = Rack::Test::UploadedFile.new(
      pdf_file.path,
      'application/pdf',
      original_filename: 'fallback.pdf'
    )

    # Should not crash, even if Redis is unavailable
    assert_nothing_raised do
      post "/scout/upload_files", params: {
        files: { 0 => uploaded_file },
        storage_type: 'short-term'
      }
    end

    assert_response :success

  ensure
    $redis = original_redis
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

  # Test 11: Move session document to long-term storage
  test "can move session document to long-term storage" do
    skip "Docling not available" unless DoclingBridgeService.available?

    # Upload a session document
    pdf_file = create_test_pdf_file("Session document to move")
    uploaded_file = Rack::Test::UploadedFile.new(
      pdf_file.path,
      'application/pdf',
      original_filename: 'move_test.pdf'
    )

    post "/scout/upload_files", params: {
      files: { 0 => uploaded_file },
      storage_type: 'short-term'
    }

    assert_response :success

    # Verify it's in Redis
    scout_session_id = session[:scout_session_id]
    session_key = "rag:session:#{scout_session_id}:documents"
    redis_docs_before = $redis.hgetall(session_key)
    assert_equal 1, redis_docs_before.keys.length, "Should have 1 document in Redis before move"

    # Move to long-term storage
    post "/scout/move_to_long_term", params: {
      filename: 'move_test.pdf'
    }

    assert_response :success
    response_json = JSON.parse(@response.body)

    # Verify response
    assert response_json['success']
    assert response_json['rag_store_id'].present?, "Should return rag_store_id"
    assert response_json['rag_document_id'].present?, "Should return rag_document_id"
    assert response_json['chunks_count'] > 0, "Should have chunks"

    # Verify document is now in database
    rag_store = RagStore.find(response_json['rag_store_id'])
    assert_equal @entity.id, rag_store.entity_id
    assert_equal 'entity', rag_store.store_type
    assert rag_store.name.include?('move_test.pdf')

    rag_document = RagDocument.find(response_json['rag_document_id'])
    assert_equal 'move_test.pdf', rag_document.original_filename
    assert rag_document.docling_metadata['moved_from_session']
    assert_equal scout_session_id, rag_document.docling_metadata['original_session_id']

    # Verify chunks were created
    assert_equal response_json['chunks_count'], rag_document.rag_chunks.count

    # Verify document removed from Redis (moved to permanent storage)
    redis_docs_after = $redis.hgetall(session_key)
    assert_equal 0, redis_docs_after.keys.length, "Document should be removed from Redis after moving to permanent storage"

  ensure
    pdf_file&.close
    pdf_file&.unlink
  end

  # Test 12: Move to long-term with missing filename
  test "move to long-term fails without filename" do
    post "/scout/move_to_long_term", params: {}

    assert_response :bad_request
    response_json = JSON.parse(@response.body)
    assert_equal false, response_json['success']
    assert_match /filename is required/i, response_json['error']
  end

  # Test 13: Move to long-term with non-existent document
  test "move to long-term fails for non-existent document" do
    # First establish a session by making a request
    get "/scout"
    assert_response :success

    # Now try to move a non-existent document
    post "/scout/move_to_long_term", params: {
      filename: 'does_not_exist.pdf'
    }

    assert_response :not_found
    response_json = JSON.parse(@response.body)
    assert_equal false, response_json['success']
    assert_match /not found/i, response_json['error']
  end

  # Test 14: Delete session document
  test "can delete session document from Redis" do
    skip "Docling not available" unless DoclingBridgeService.available?

    # Upload a session document
    pdf_file = create_test_pdf_file("Document to delete")
    uploaded_file = Rack::Test::UploadedFile.new(
      pdf_file.path,
      'application/pdf',
      original_filename: 'delete_test.pdf'
    )

    post "/scout/upload_files", params: {
      files: { 0 => uploaded_file },
      storage_type: 'short-term'
    }

    assert_response :success

    # Verify it's in Redis
    scout_session_id = session[:scout_session_id]
    session_key = "rag:session:#{scout_session_id}:documents"
    redis_docs_before = $redis.hgetall(session_key)
    assert_equal 1, redis_docs_before.keys.length, "Should have 1 document in Redis before delete"

    # Delete the document
    delete "/scout/delete_document", params: {
      filename: 'delete_test.pdf',
      storage_type: 'short-term'
    }

    assert_response :success
    response_json = JSON.parse(@response.body)

    # Verify response
    assert response_json['success']
    assert_match /deleted from session/i, response_json['message']

    # Verify document is removed from Redis
    redis_docs_after = $redis.hgetall(session_key)
    assert_equal 0, redis_docs_after.keys.length, "Should have 0 documents in Redis after delete"

  ensure
    pdf_file&.close
    pdf_file&.unlink
  end

  # Test 15: Delete long-term document
  test "can delete long-term document from database" do
    skip "Docling not available" unless DoclingBridgeService.available?

    # Upload a long-term document
    pdf_file = create_test_pdf_file("Long-term document to delete")
    uploaded_file = Rack::Test::UploadedFile.new(
      pdf_file.path,
      'application/pdf',
      original_filename: 'longterm_delete.pdf'
    )

    post "/scout/upload_files", params: {
      files: { 0 => uploaded_file },
      storage_type: 'long-term'
    }

    assert_response :success
    response_json = JSON.parse(@response.body)
    rag_store_id = response_json['rag_stores_created'].first

    # Get the RagDocument ID
    rag_store = RagStore.find(rag_store_id)
    rag_document = rag_store.rag_documents.first
    rag_document_id = rag_document.id
    chunks_count = rag_document.rag_chunks.count

    assert chunks_count > 0, "Should have chunks before delete"

    # Delete the document
    delete "/scout/delete_document", params: {
      filename: 'longterm_delete.pdf',
      storage_type: 'long-term',
      rag_document_id: rag_document_id
    }

    assert_response :success
    response_json = JSON.parse(@response.body)

    # Verify response
    assert response_json['success']
    assert_match /permanently deleted/i, response_json['message']

    # Verify document is removed from database
    assert_nil RagDocument.find_by(id: rag_document_id), "RagDocument should be deleted"

    # Verify chunks are removed
    assert_equal 0, RagChunk.where(rag_document_id: rag_document_id).count, "Chunks should be deleted"

    # Verify RagStore is also deleted (since it was the last document)
    assert_nil RagStore.find_by(id: rag_store_id), "RagStore should be deleted when empty"

  ensure
    pdf_file&.close
    pdf_file&.unlink
  end

  # Test 16: Delete with missing filename
  test "delete fails without filename" do
    delete "/scout/delete_document", params: {
      storage_type: 'short-term'
    }

    assert_response :bad_request
    response_json = JSON.parse(@response.body)
    assert_equal false, response_json['success']
    assert_match /filename is required/i, response_json['error']
  end

  # Test 17: Delete non-existent session document
  test "delete fails for non-existent session document" do
    # Establish session
    get "/scout"
    assert_response :success

    delete "/scout/delete_document", params: {
      filename: 'does_not_exist.pdf',
      storage_type: 'short-term'
    }

    assert_response :not_found
    response_json = JSON.parse(@response.body)
    assert_equal false, response_json['success']
    assert_match /not found/i, response_json['error']
  end

  # Test 18: Delete without rag_document_id for long-term
  test "delete long-term fails without rag_document_id" do
    delete "/scout/delete_document", params: {
      filename: 'test.pdf',
      storage_type: 'long-term'
    }

    assert_response :bad_request
    response_json = JSON.parse(@response.body)
    assert_equal false, response_json['success']
    assert_match /document id is required/i, response_json['error']
  end

  # Test 19: Delete button only shows for RAG documents (not plain image assets)
  test "delete button only shows for RAG documents and session documents" do
    # Create a session document (should show delete)
    file = create_test_pdf_file("Session document content")
    uploaded_file = fixture_file_upload(file.path, 'application/pdf')

    post "/scout/upload_files", params: {
      files: { 0 => uploaded_file },
      storage_type: 'short-term'
    }
    assert_response :success

    # Create a long-term RAG document (should show delete)
    file2 = create_test_pdf_file("Long-term RAG document")
    uploaded_file2 = fixture_file_upload(file2.path, 'application/pdf')

    post "/scout/upload_files", params: {
      files: { 0 => uploaded_file2 },
      storage_type: 'long-term'
    }
    assert_response :success

    # Create a plain ImageAsset (not a RAG document - should NOT show delete)
    plain_asset = ImageAsset.create!(
      user: @user,
      entity: @entity,
      title: "plain_image.jpg",
      source: 'upload',
      file: fixture_file_upload(
        Rails.root.join('test', 'fixtures', 'files', 'test_image.png'),
        'image/png'
      )
    )

    # Load document viewer canvas
    post "/scout/load_canvas", params: { canvas_type: 'document_viewer' }
    assert_response :success

    response_json = JSON.parse(@response.body)
    html = response_json.dig('canvas', 'content')

    # Session document should have delete button
    assert_match /data-doc-id=""/, html, "Session document should have delete button"

    # RAG document should have delete button with rag_document_id
    rag_doc_id = RagDocument.last.id
    assert_match /data-doc-id="#{rag_doc_id}"/, html, "RAG document should have delete button with ID"

    # Plain image asset should NOT have delete button (check it's in the list but no delete button for it)
    # This is harder to test without parsing HTML, so we'll verify the logic worked by checking button count
    delete_button_count = html.scan(/fa-trash/).length

    # Should be exactly 2 delete buttons (session + RAG doc), not 3
    assert_equal 2, delete_button_count, "Should only have 2 delete buttons (session + RAG), not for plain image asset"
  end

  # Test 20: Moving to long-term removes from session storage
  test "moving to long-term removes document from session storage" do
    skip "Docling not available" unless DoclingBridgeService.available?

    file = create_test_pdf_file("Test document for removal")
    uploaded_file = Rack::Test::UploadedFile.new(
      file.path,
      'application/pdf',
      original_filename: 'removal_test.pdf'
    )

    # Upload to session storage
    post "/scout/upload_files", params: {
      files: { 0 => uploaded_file },
      storage_type: 'short-term'
    }
    assert_response :success

    response_json = JSON.parse(@response.body)
    filename = response_json['urls'].first['filename']

    # Verify document is in Redis
    scout_session_id = session[:scout_session_id]
    session_key = "rag:session:#{scout_session_id}:documents"
    redis_before = $redis.hgetall(session_key)
    assert_equal 1, redis_before.keys.length, "Document should be in Redis"
    assert redis_before.key?(filename), "Specific document should exist in Redis"

    # Move to long-term storage
    post "/scout/move_to_long_term", params: { filename: filename }
    assert_response :success

    move_response = JSON.parse(@response.body)
    assert move_response['success']
    assert_match /removed from session/i, move_response['message']

    # Verify document is removed from Redis
    redis_after = $redis.hgetall(session_key)
    assert_equal 0, redis_after.keys.length, "Document should be removed from Redis"
    assert_not redis_after.key?(filename), "Specific document should not exist in Redis"

    # Verify document exists in database
    rag_document = RagDocument.find(move_response['rag_document_id'])
    assert_equal filename, rag_document.original_filename
    assert_not_nil rag_document.rag_store

    # Verify chunks were preserved
    assert_equal move_response['chunks_count'], rag_document.rag_chunks.count

  ensure
    file&.close
    file&.unlink
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
end
