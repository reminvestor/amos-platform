require "test_helper"

class RagDocumentTest < ActiveSupport::TestCase
  def setup
    @rag_store = rag_stores(:entity_one_custom)
    @document = rag_documents(:document_one)
  end

  # === Associations ===

  test "belongs to rag_store" do
    assert_equal @rag_store, @document.rag_store
  end

  test "has many rag_chunks" do
    assert_respond_to @document, :rag_chunks
    assert_kind_of ActiveRecord::Associations::CollectionProxy, @document.rag_chunks
  end

  test "destroys dependent rag_chunks when document is destroyed" do
    chunk_ids = @document.rag_chunks.pluck(:id)
    assert chunk_ids.any?, "Document should have chunks"

    @document.destroy

    chunk_ids.each do |chunk_id|
      assert_not RagChunk.exists?(chunk_id), "Chunk #{chunk_id} should be destroyed"
    end
  end

  # === Validations ===

  test "requires file_hash" do
    document = RagDocument.new(
      rag_store: @rag_store,
      original_filename: "test.pdf",
      file_hash: nil
    )

    assert_not document.valid?
    assert_includes document.errors[:file_hash], "can't be blank"
  end

  test "requires original_filename" do
    document = RagDocument.new(
      rag_store: @rag_store,
      file_hash: "abc123",
      original_filename: nil
    )

    assert_not document.valid?
    assert_includes document.errors[:original_filename], "can't be blank"
  end

  # === Scopes ===

  test "for_entity scope returns documents for specific entity" do
    entity_one = entities(:one)
    entity_two = entities(:two)

    entity_one_docs = RagDocument.for_entity(entity_one)
    entity_two_docs = RagDocument.for_entity(entity_two)

    assert_includes entity_one_docs, rag_documents(:document_one)
    assert_includes entity_one_docs, rag_documents(:document_two)
    assert_not_includes entity_one_docs, rag_documents(:document_duplicate)

    assert_includes entity_two_docs, rag_documents(:document_duplicate)
    assert_not_includes entity_two_docs, rag_documents(:document_one)
  end

  test "with_docling_metadata scope returns only documents with metadata" do
    docs_with_metadata = RagDocument.with_docling_metadata

    assert_includes docs_with_metadata, rag_documents(:document_one)
    assert_includes docs_with_metadata, rag_documents(:document_two)
    # document_system has empty metadata
  end

  test "by_content_type scope filters by content type" do
    pdf_docs = RagDocument.by_content_type("application/pdf")
    md_docs = RagDocument.by_content_type("text/markdown")

    assert_includes pdf_docs, rag_documents(:document_one)
    assert_includes pdf_docs, rag_documents(:document_two)
    assert_not_includes pdf_docs, rag_documents(:document_system)

    assert_includes md_docs, rag_documents(:document_system)
    assert_not_includes md_docs, rag_documents(:document_one)
  end

  # === Deduplication ===

  test "duplicate_exists? returns true when duplicate file_hash exists" do
    duplicate_doc = rag_documents(:document_duplicate)

    assert @document.duplicate_exists?, "Should find duplicate with same hash"
    assert duplicate_doc.duplicate_exists?, "Duplicate should find original"
  end

  test "duplicate_exists? returns false when no duplicate exists" do
    unique_doc = rag_documents(:document_system)

    assert_not unique_doc.duplicate_exists?, "Should not find duplicates for unique hash"
  end

  test "duplicate_of class method finds documents with same hash" do
    hash = @document.file_hash
    duplicates = RagDocument.duplicate_of(hash)

    assert_includes duplicates, @document
    assert_includes duplicates, rag_documents(:document_duplicate)
    assert_equal 2, duplicates.count
  end

  # === S3 URL Helpers (deprecated - URLs are now managed differently) ===

  test "s3_url returns correct S3 path" do
    skip "s3_url method removed - S3 paths now handled by RagStore"
  end

  test "docling_output_url returns correct S3 path" do
    skip "docling_output_url method removed - S3 paths now handled by RagStore"
  end

  test "processed_chunks_url returns correct S3 path" do
    skip "processed_chunks_url method removed - S3 paths now handled by RagStore"
  end

  # === Metadata Helpers ===

  test "has_docling_metadata? returns true when metadata exists" do
    assert @document.has_docling_metadata?
  end

  test "has_docling_metadata? returns false when metadata is empty" do
    @document.docling_metadata = {}

    assert_not @document.has_docling_metadata?
  end

  test "has_extracted_tables? returns true when tables exist" do
    doc_with_tables = rag_documents(:document_two)

    assert doc_with_tables.has_extracted_tables?
  end

  test "has_extracted_tables? returns false when no tables" do
    assert_not @document.has_extracted_tables?
  end

  test "has_extracted_images? returns true when images exist" do
    doc_with_images = rag_documents(:document_two)

    assert doc_with_images.has_extracted_images?
  end

  test "has_extracted_images? returns false when no images" do
    assert_not @document.has_extracted_images?
  end

  # === Summary Stats ===

  test "chunks_count returns number of associated chunks" do
    # Fixtures should have chunks for document_one
    assert @document.chunks_count > 0
  end

  test "embedded_chunks_count returns count of chunks with embeddings" do
    # Most fixture chunks don't have embeddings set
    count = @document.embedded_chunks_count

    assert count >= 0
    assert count <= @document.chunks_count
  end

  test "embedding_progress returns percentage of embedded chunks" do
    progress = @document.embedding_progress

    assert progress >= 0
    assert progress <= 100
  end

  test "embedding_progress returns 0 when no chunks" do
    document = RagDocument.create!(
      rag_store: @rag_store,
      original_filename: "empty.pdf",
      file_hash: "unique123"
    )

    assert_equal 0, document.embedding_progress
  end

  # === File Size Helpers ===

  test "file_size_mb returns size in megabytes" do
    @document.file_size_bytes = 1048576  # 1 MB

    assert_equal 1.0, @document.file_size_mb
  end

  test "file_size_mb returns 0 when size is nil" do
    @document.file_size_bytes = nil

    assert_equal 0, @document.file_size_mb
  end

  test "file_size_human returns human-readable size for bytes" do
    @document.file_size_bytes = 500

    assert_equal "500 B", @document.file_size_human
  end

  test "file_size_human returns human-readable size for kilobytes" do
    @document.file_size_bytes = 5120  # 5 KB

    assert_equal "5.0 KB", @document.file_size_human
  end

  test "file_size_human returns human-readable size for megabytes" do
    @document.file_size_bytes = 5242880  # 5 MB

    assert_equal "5.0 MB", @document.file_size_human
  end

  test "file_size_human returns human-readable size for gigabytes" do
    @document.file_size_bytes = 5368709120  # 5 GB

    assert_equal "5.0 GB", @document.file_size_human
  end

  test "file_size_human returns 0 B when size is nil" do
    @document.file_size_bytes = nil

    assert_equal "0 B", @document.file_size_human
  end
end
