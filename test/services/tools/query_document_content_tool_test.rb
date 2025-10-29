require "test_helper"

class QueryDocumentContentToolTest < ActiveSupport::TestCase
  setup do
    @entity = entities(:demo_company)
    @user = users(:admin_user)

    # Create tool instance with required parameters
    @tool = Tools::QueryDocumentContentTool.new(user: @user, entity: @entity, context: { session_id: SecureRandom.uuid })

    # Clean up existing data
    RagStore.where(entity: @entity).destroy_all
  end

  test "finds document in RAG database" do
    # Create a RAG store with a document (simulating a previously uploaded PDF)
    rag_store = RagStore.create!(
      entity: @entity,
      name: "Test RAG Store",
      app_name: "test",
      store_type: "entity",
      status: "active",
      processing_method: "docling",
      pinecone_index: "test-index",
      pinecone_namespace: "test-namespace"
    )

    # Create document
    rag_document = RagDocument.create!(
      rag_store: rag_store,
      original_filename: "Server Error.pdf",
      file_size_bytes: 1024,
      content_type: "application/pdf",
      file_hash: Digest::SHA256.hexdigest("test content")
    )

    # Create chunk with searchable content
    content = "Something went wrong\n\nActivity Id: 4d03d1ae-e204-422e-b4ec-0b1c761b045d\nSession Id: 66b77b1b-a307-464a-a910-bd1b51ff88b2"

    rag_chunk = RagChunk.create!(
      rag_store: rag_store,
      rag_document: rag_document,
      content: content,
      chunk_index: 0,
      token_count: 50,
      embedding: Array.new(1536) { rand } # Mock embedding vector
    )

    # Mock HybridRagQueryService to return our chunk
    mock_result = {
      chunks: [{
        content: content,
        score: 0.95,
        filename: "Server Error.pdf",
        chunk_index: 0
      }],
      response_time_ms: 100
    }

    HybridRagQueryService.any_instance.stubs(:query).returns(mock_result)

    # Execute the tool
    result = @tool.execute({ query: "server error" })

    # Verify success
    assert result[:success], "Tool should succeed"
    assert_equal "rag", result[:source], "Should find document in RAG storage"
    assert_equal 1, result[:count], "Should return 1 result"
    assert result[:results].first[:content].include?("Activity Id"), "Should return document content"
  end

  test "returns empty when no documents found" do
    # Mock HybridRagQueryService to return no results
    HybridRagQueryService.any_instance.stubs(:query).returns({ chunks: [], response_time_ms: 50 })

    # Execute the tool
    result = @tool.execute({ query: "nonexistent content" })

    # Verify success with no results
    assert result[:success], "Tool should succeed even with no results"
    assert_equal "none", result[:source]
    assert_equal 0, result[:count]
    assert result[:message].include?("No documents contain")
  end

  test "searches session storage first before RAG" do
    session_id = @tool.instance_variable_get(:@context)[:session_id]

    # Store document in Redis session storage
    session_key = "rag:session:#{session_id}:documents"
    doc_data = {
      filename: "test.pdf",
      asset_id: "123",
      chunks: [
        { content: "This is session storage content about tires" }
      ]
    }
    $redis.hset(session_key, "test.pdf", doc_data.to_json)

    # Execute the tool
    result = @tool.execute({ query: "tires" })

    # Verify it found content in session storage
    assert result[:success], "Tool should succeed"
    assert_equal "session", result[:source], "Should find in session storage"
    assert_equal 1, result[:count]
    assert result[:results].first[:content].include?("tires")

    # Clean up
    $redis.del(session_key)
  end

  test "falls back to RAG when session storage is empty" do
    # Session storage is empty (no Redis data)

    # Mock RAG to return results
    mock_result = {
      chunks: [{
        content: "Content from RAG database",
        score: 0.9,
        filename: "rag_doc.pdf",
        chunk_index: 0
      }],
      response_time_ms: 150
    }
    HybridRagQueryService.any_instance.stubs(:query).returns(mock_result)

    # Execute the tool
    result = @tool.execute({ query: "database" })

    # Verify it fell back to RAG
    assert result[:success], "Tool should succeed"
    assert_equal "rag", result[:source], "Should fall back to RAG storage"
    assert_equal 1, result[:count]
  end

  test "requires query parameter" do
    result = @tool.execute({})

    assert_not result[:success], "Should fail without query"
    assert result[:error].include?("Query is required")
  end

  test "respects top_k parameter" do
    mock_result = {
      chunks: (1..10).map { |i|
        {
          content: "Result #{i}",
          score: 1.0 - (i * 0.1),
          filename: "doc.pdf",
          chunk_index: i
        }
      },
      response_time_ms: 200
    }
    HybridRagQueryService.any_instance.stubs(:query).with("test", top_k: 3).returns(
      { chunks: mock_result[:chunks].first(3), response_time_ms: 200 }
    )

    result = @tool.execute({ query: "test", top_k: 3 })

    assert result[:success], "Tool should succeed"
    assert_equal 3, result[:count], "Should respect top_k limit"
  end
end
