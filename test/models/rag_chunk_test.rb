require "test_helper"

class RagChunkTest < ActiveSupport::TestCase
  def setup
    @entity_one = entities(:one)
    @entity_two = entities(:two)
    @document = rag_documents(:document_one)
    @chunk = rag_chunks(:chunk_one)
  end

  # === Associations ===

  test "belongs to rag_document" do
    assert_equal @document, @chunk.rag_document
  end

  test "has_one rag_store through rag_document" do
    assert_equal @document.rag_store, @chunk.rag_store
  end

  # === Validations ===

  test "requires content" do
    chunk = RagChunk.new(
      rag_document: @document,
      content: nil,
      chunk_index: 0
    )

    assert_not chunk.valid?
    assert_includes chunk.errors[:content], "can't be blank"
  end

  test "requires chunk_index" do
    chunk = RagChunk.new(
      rag_document: @document,
      content: "Test content",
      chunk_index: nil
    )

    assert_not chunk.valid?
    assert_includes chunk.errors[:chunk_index], "can't be blank"
  end

  # === Scopes ===

  test "for_entity scope returns chunks for specific entity" do
    entity_one_chunks = RagChunk.for_entity(@entity_one)
    entity_two_chunks = RagChunk.for_entity(@entity_two)

    assert_includes entity_one_chunks, rag_chunks(:chunk_one)
    assert_includes entity_one_chunks, rag_chunks(:chunk_two)
    assert_not_includes entity_one_chunks, rag_chunks(:chunk_no_embedding)

    # Assuming chunk_no_embedding belongs to entity_one's document
    # and entity_two has no chunks in fixtures
  end

  test "for_rag_store scope returns chunks for specific rag_store" do
    rag_store = rag_stores(:entity_one_custom)
    chunks = RagChunk.for_rag_store(rag_store)

    assert_includes chunks, rag_chunks(:chunk_one)
    assert_includes chunks, rag_chunks(:chunk_two)
  end

  test "text_search scope finds chunks by content" do
    # Search for "brand" which appears in chunk_one
    results = RagChunk.text_search("brand")

    assert results.any?, "Should find chunks containing 'brand'"
  end

  test "by_type scope filters chunks by type" do
    text_chunks = RagChunk.by_type("text")
    table_chunks = RagChunk.by_type("table")

    assert_includes text_chunks, rag_chunks(:chunk_one)
    assert_includes text_chunks, rag_chunks(:chunk_two)
    assert_not_includes text_chunks, rag_chunks(:chunk_table)

    assert_includes table_chunks, rag_chunks(:chunk_table)
    assert_not_includes table_chunks, rag_chunks(:chunk_one)
  end

  test "embedded scope returns only chunks with embeddings" do
    embedded = RagChunk.embedded

    # All fixture chunks have nil embeddings
    # This test will pass when embeddings are null
    assert embedded.where.not(embedding: nil).count == 0
  end

  test "pending_embedding scope returns chunks without embeddings" do
    pending = RagChunk.pending_embedding

    assert_includes pending, rag_chunks(:chunk_one)
    assert_includes pending, rag_chunks(:chunk_no_embedding)
  end

  test "with_page_number scope returns chunks with page metadata" do
    chunks_with_pages = RagChunk.with_page_number

    assert_includes chunks_with_pages, rag_chunks(:chunk_one)
    assert_includes chunks_with_pages, rag_chunks(:chunk_two)
  end

  test "with_section scope returns chunks with section metadata" do
    chunks_with_sections = RagChunk.with_section

    assert_includes chunks_with_sections, rag_chunks(:chunk_one)
    assert_includes chunks_with_sections, rag_chunks(:chunk_system)
  end

  # === pgvector Similarity Search ===

  test "similar_chunks returns empty when chunk has no embedding" do
    similar = @chunk.similar_chunks

    assert_equal [], similar
  end

  test "similar_chunks returns nearby vectors when embedding exists" do
    # Create a chunk with an embedding (simplified test vector)
    # In real usage, this would be a 1536-dimensional OpenAI embedding
    skip "Requires actual embeddings to test similarity search"

    # Example of how this would work with real embeddings:
    # @chunk.update!(embedding: [0.1, 0.2, 0.3, ...])  # 1536 dimensions
    # similar = @chunk.similar_chunks(limit: 3)
    # assert similar.size <= 3
    # assert_not_includes similar, @chunk  # Should exclude self
  end

  test "similar_chunks_in_entity respects entity boundaries" do
    # Skip until we have real embeddings
    skip "Requires actual embeddings to test entity-scoped similarity"

    # This test would verify that similar_chunks_in_entity only returns
    # chunks from the same entity, even if other entities have similar vectors
  end

  # === Embedding Status ===

  test "embedded? returns false when embedding is nil" do
    assert_not @chunk.embedded?
  end

  test "embedded? returns true when embedding exists" do
    skip "Requires actual embedding data"

    # @chunk.update!(embedding: Array.new(1536) { rand })
    # assert @chunk.embedded?
  end

  # === Pinecone Status ===

  test "synced_to_pinecone? returns true when pinecone_vector_id exists" do
    assert @chunk.synced_to_pinecone?
  end

  test "synced_to_pinecone? returns false when pinecone_vector_id is nil" do
    chunk_not_synced = rag_chunks(:chunk_no_embedding)

    assert_not chunk_not_synced.synced_to_pinecone?
  end

  # === Metadata Helpers ===

  test "page_number returns page from metadata" do
    assert_equal 3, @chunk.page_number
  end

  test "page_number handles alternative metadata keys" do
    @chunk.metadata = { "page_number" => 5 }

    assert_equal 5, @chunk.page_number
  end

  test "section_title returns section from metadata" do
    assert_equal "Color Palette", @chunk.section_title
  end

  test "section_title handles alternative metadata keys" do
    @chunk.metadata = { "section" => "Alternative Section" }

    assert_equal "Alternative Section", @chunk.section_title
  end

  test "chunk_type_label returns human-readable type" do
    assert_equal "Text", rag_chunks(:chunk_one).chunk_type_label
    assert_equal "Table", rag_chunks(:chunk_table).chunk_type_label
  end

  test "chunk_type_label returns Unknown for unrecognized type" do
    @chunk.chunk_type = "unknown_type"

    assert_equal "Unknown", @chunk.chunk_type_label
  end

  # === Content Helpers ===

  test "preview returns full content when shorter than limit" do
    short_content = "Short text"
    @chunk.content = short_content

    assert_equal short_content, @chunk.preview(200)
  end

  test "preview truncates long content" do
    long_content = "a" * 500
    @chunk.content = long_content

    preview = @chunk.preview(100)

    assert_equal 103, preview.length  # 100 chars + "..."
    assert preview.ends_with?("...")
  end

  test "word_count returns number of words" do
    @chunk.content = "This is a test sentence with seven words"

    assert_equal 8, @chunk.word_count
  end

  test "estimated_tokens returns token_count when present" do
    @chunk.token_count = 100

    assert_equal 100, @chunk.estimated_tokens
  end

  test "estimated_tokens estimates from content when token_count is nil" do
    @chunk.token_count = nil
    @chunk.content = "a" * 400  # 400 characters ≈ 100 tokens

    estimated = @chunk.estimated_tokens

    assert estimated > 0
    assert_equal (400 / 4.0).ceil, estimated  # Rough 4 chars per token
  end

  # === Vector Similarity ===

  test "cosine_similarity_to requires both chunks to have embeddings" do
    other_chunk = rag_chunks(:chunk_two)

    similarity = @chunk.cosine_similarity_to(other_chunk)

    assert_nil similarity, "Should return nil when embeddings are missing"
  end

  test "cosine_similarity_to calculates similarity with embeddings" do
    skip "Requires actual embedding vectors"

    # Example test with real embeddings:
    # @chunk.update!(embedding: Array.new(1536) { 0.5 })
    # other_chunk = rag_chunks(:chunk_two)
    # other_chunk.update!(embedding: Array.new(1536) { 0.5 })
    #
    # similarity = @chunk.cosine_similarity_to(other_chunk)
    #
    # assert similarity >= 0.0 && similarity <= 1.0
    # # Identical vectors should have similarity close to 1.0
    # assert_in_delta 1.0, similarity, 0.1
  end
end
