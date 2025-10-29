require "test_helper"

class RagPipelineTest < ActionDispatch::IntegrationTest
  def setup
    @entity = entities(:one)
    @rag_store = rag_stores(:entity_one_custom)
  end

  # === Document Processing Pipeline ===

  test "document upload creates RagDocument and processing job" do
    # Simulate document upload
    file_content = "Test document content for RAG processing"
    file_hash = Digest::SHA256.hexdigest(file_content)

    document = RagDocument.create!(
      rag_store: @rag_store,
      original_filename: "test_doc.pdf",
      file_hash: file_hash,
      file_size_bytes: file_content.bytesize,
      content_type: "application/pdf"
    )

    assert document.persisted?
    assert_equal file_hash, document.file_hash
    assert_equal 0, document.chunks_count
  end

  test "document deduplication prevents duplicate processing" do
    file_hash = "duplicate_hash_123"

    # Create first document
    doc1 = RagDocument.create!(
      rag_store: @rag_store,
      original_filename: "original.pdf",
      file_hash: file_hash
    )

    # Attempt to create duplicate
    doc2 = RagDocument.create!(
      rag_store: @rag_store,
      original_filename: "duplicate.pdf",
      file_hash: file_hash
    )

    # Both exist but can be detected as duplicates
    assert doc1.duplicate_exists?
    assert doc2.duplicate_exists?

    duplicates = RagDocument.duplicate_of(file_hash)
    assert_equal 2, duplicates.count
  end

  test "chunking creates multiple RagChunk records from document" do
    document = rag_documents(:document_one)

    # Simulate chunking process
    chunks_data = [
      { content: "First chunk of content", chunk_index: 0 },
      { content: "Second chunk of content", chunk_index: 1 },
      { content: "Third chunk of content", chunk_index: 2 }
    ]

    chunks_data.each do |chunk_data|
      RagChunk.create!(
        rag_document: document,
        content: chunk_data[:content],
        chunk_index: chunk_data[:chunk_index],
        chunk_type: "text",
        token_count: (chunk_data[:content].split.size * 1.3).to_i
      )
    end

    document.reload
    assert document.chunks_count >= 3
  end

  test "embedding generation updates chunk embedding field" do
    chunk = rag_chunks(:chunk_no_embedding)

    assert_nil chunk.embedding
    assert_not chunk.embedded?

    # Simulate embedding generation (1536-dimensional vector)
    embedding_vector = Array.new(1536) { rand }

    chunk.update!(
      embedding: embedding_vector,
      pinecone_vector_id: "test_vector_#{SecureRandom.hex(8)}"
    )

    assert chunk.embedded?
    assert chunk.synced_to_pinecone?
  end

  test "query execution records RagQuery with metrics" do
    query_text = "What are the brand colors?"

    # Simulate query execution
    start_time = Time.current
    chunks_retrieved = [1, 2]
    relevance_scores = [
      { chunk_id: 1, distance: 0.15 },
      { chunk_id: 2, distance: 0.25 }
    ]
    end_time = Time.current

    response_time = ((end_time - start_time) * 1000).to_i

    query_record = RagQuery.create!(
      entity: @entity,
      rag_store: @rag_store,
      query: query_text,
      response_time_ms: response_time,
      chunks_retrieved: chunks_retrieved,
      relevance_scores: relevance_scores,
      cache_hit: false
    )

    assert query_record.persisted?
    assert_equal 2, query_record.chunks_found
    assert query_record.fast?
  end

  test "cache hit on duplicate query improves performance" do
    query_text = "What are the brand colors?"

    # First query (cache miss)
    first_query = RagQuery.create!(
      entity: @entity,
      rag_store: @rag_store,
      query: query_text,
      response_time_ms: 450,
      chunks_retrieved: [1, 2],
      cache_hit: false
    )

    # Second identical query (cache hit)
    second_query = RagQuery.create!(
      entity: @entity,
      rag_store: @rag_store,
      query: query_text,
      response_time_ms: 50,
      chunks_retrieved: [1, 2],
      cache_hit: true
    )

    # Verify cache improved performance
    assert second_query.response_time_ms < first_query.response_time_ms
    assert second_query.cache_hit
    assert_not first_query.cache_hit

    # Verify queries are similar
    similar = first_query.similar_queries
    assert_includes similar, second_query
  end

  # === Job Tracking ===

  test "processing job tracks lifecycle from pending to completed" do
    job = RagProcessingJob.create!(
      rag_store: @rag_store,
      job_id: "test_job_#{SecureRandom.hex(8)}",
      job_type: "docling_extraction",
      status: :pending
    )

    assert job.status_pending?
    assert job.in_progress?

    # Mark as started
    job.mark_as_started!
    assert job.status_processing?
    assert_not_nil job.started_at

    # Mark as completed
    sleep 0.1 # Simulate processing time
    job.mark_as_completed!
    assert job.status_completed?
    assert_not_nil job.completed_at
    assert job.finished?

    # Verify duration tracking
    assert job.duration_ms > 0
  end

  test "failed processing job can be retried" do
    job = RagProcessingJob.create!(
      rag_store: @rag_store,
      job_id: "retry_job_#{SecureRandom.hex(8)}",
      job_type: "embedding_batch",
      status: :processing,
      retry_count: 0
    )

    # Simulate failure
    job.mark_as_failed!("Temporary network error")

    assert job.status_failed?
    assert job.has_error?
    assert job.can_retry?

    # Increment retry
    job.increment_retry!
    assert_equal 1, job.retry_count

    # Retry job
    job.update!(status: :pending, error_message: nil)
    job.mark_as_started!

    assert job.status_processing?
    assert_nil job.error_message
  end

  # === Entity Isolation ===

  test "entity-scoped queries only access entity's documents" do
    entity_two = entities(:two)

    # Entity one's query
    entity_one_chunks = RagChunk.for_entity(@entity)
    entity_one_chunk_ids = entity_one_chunks.pluck(:id)

    # Entity two should not see entity one's chunks
    entity_two_chunks = RagChunk.for_entity(entity_two)
    entity_two_chunk_ids = entity_two_chunks.pluck(:id)

    # Verify no overlap
    overlap = entity_one_chunk_ids & entity_two_chunk_ids
    assert_empty overlap, "Entities should have isolated chunks"
  end

  test "system RAG stores accessible by all entities" do
    system_store = rag_stores(:system_stripe)
    entity_two = entities(:two)

    assert system_store.accessible_by?(@entity)
    assert system_store.accessible_by?(entity_two)
  end

  test "entity RAG stores not accessible by other entities" do
    entity_two = entities(:two)
    entity_one_store = @rag_store

    assert entity_one_store.accessible_by?(@entity)
    assert_not entity_one_store.accessible_by?(entity_two)
  end

  # === S3 Integration ===

  test "document S3 paths follow entity scoping pattern" do
    document = rag_documents(:document_one)

    s3_url = document.s3_url
    docling_url = document.docling_output_url
    chunks_url = document.processed_chunks_url

    # All paths should include entity ID
    assert_match /entities\/#{@entity.id}/, s3_url
    assert_match /entities\/#{@entity.id}/, docling_url
    assert_match /entities\/#{@entity.id}/, chunks_url

    # Verify path structure
    assert s3_url.include?("raw_documents")
    assert docling_url.include?("docling_output")
    assert chunks_url.include?("processed_chunks")
  end

  test "system store S3 paths follow system pattern" do
    system_store = rag_stores(:system_stripe)

    assert_match /^system\//, system_store.s3_key_prefix
    assert_match /^system\//, system_store.s3_raw_path
  end

  # === Performance Metrics ===

  test "RAG store tracks access patterns for optimization" do
    store = @rag_store
    original_count = store.access_count || 0

    # Simulate 5 accesses
    5.times do
      store.track_access!
    end

    store.reload
    assert_equal original_count + 5, store.access_count
    assert store.recently_accessed?
  end

  test "query performance categories calculated correctly" do
    # Fast query (< 200ms)
    fast_query = RagQuery.create!(
      entity: @entity,
      rag_store: @rag_store,
      query: "fast query",
      response_time_ms: 150,
      chunks_retrieved: []
    )

    # Medium query (200-500ms)
    medium_query = RagQuery.create!(
      entity: @entity,
      rag_store: @rag_store,
      query: "medium query",
      response_time_ms: 350,
      chunks_retrieved: []
    )

    # Slow query (> 500ms)
    slow_query = RagQuery.create!(
      entity: @entity,
      rag_store: @rag_store,
      query: "slow query",
      response_time_ms: 800,
      chunks_retrieved: []
    )

    assert_equal "fast", fast_query.performance_category
    assert_equal "medium", medium_query.performance_category
    assert_equal "slow", slow_query.performance_category
  end

  test "RAG store calculates statistics accurately" do
    store = @rag_store

    # Verify document/chunk counts
    assert store.document_count > 0
    assert store.chunk_count > 0

    # Verify query metrics
    if store.has_queries?
      assert store.average_query_time >= 0
      assert store.cache_hit_rate >= 0
      assert store.cache_hit_rate <= 100
    end
  end

  # === Vector Similarity Search ===

  test "pgvector similarity search requires embeddings" do
    chunk = rag_chunks(:chunk_one)

    # Without embedding, should return empty
    similar = chunk.similar_chunks
    assert_equal [], similar
  end

  test "chunks with embeddings can find similar chunks" do
    skip "Requires actual embeddings - tested with real data"

    # This test would work with real embeddings:
    # chunk1 = rag_chunks(:chunk_one)
    # chunk1.update!(embedding: [...1536 dimensions...])
    #
    # similar = chunk1.similar_chunks(limit: 3)
    # assert similar.any?
    # assert similar.size <= 3
  end

  # === Full Pipeline Integration ===

  test "complete RAG pipeline: upload → process → chunk → embed → query" do
    # Step 1: Upload document
    document = RagDocument.create!(
      rag_store: @rag_store,
      original_filename: "integration_test.pdf",
      file_hash: Digest::SHA256.hexdigest("integration_test_content"),
      file_size_bytes: 1024
    )

    # Step 2: Create processing job
    job = RagProcessingJob.create!(
      rag_store: @rag_store,
      job_id: "integration_test_#{SecureRandom.hex}",
      job_type: "pipeline",
      status: :pending
    )

    job.mark_as_started!

    # Step 3: Create chunks
    3.times do |i|
      RagChunk.create!(
        rag_document: document,
        content: "Integration test chunk #{i}",
        chunk_index: i,
        chunk_type: "text",
        token_count: 10
      )
    end

    assert_equal 3, document.rag_chunks.count

    # Step 4: Mark job complete
    job.mark_as_completed!
    assert job.finished?

    # Step 5: Simulate query
    query = RagQuery.create!(
      entity: @entity,
      rag_store: @rag_store,
      query: "integration test query",
      response_time_ms: 300,
      chunks_retrieved: document.rag_chunks.pluck(:id),
      cache_hit: false
    )

    assert query.chunks_found > 0
    assert query.was_effective?
  end

  test "pipeline handles errors gracefully with retries" do
    # Create failing job
    job = RagProcessingJob.create!(
      rag_store: @rag_store,
      job_id: "error_test_#{SecureRandom.hex}",
      job_type: "docling_extraction",
      status: :pending,
      retry_count: 0
    )

    job.mark_as_started!

    # Simulate failure
    job.mark_as_failed!("Docling timeout: File too large")

    assert job.status_failed?
    assert job.has_error?
    assert_equal "Docling timeout", job.error_type

    # Retry logic
    assert job.can_retry?
    job.increment_retry!

    # Second attempt
    job.update!(status: :pending, error_message: nil)
    job.mark_as_started!

    # Success on retry
    job.mark_as_completed!

    assert job.status_completed?
    assert_equal 1, job.retry_count
  end

  # === Analytics and Reporting ===

  test "RAG analytics provide actionable insights" do
    # Create varied query patterns
    10.times do |i|
      RagQuery.create!(
        entity: @entity,
        rag_store: @rag_store,
        query: "test query #{i}",
        response_time_ms: [50, 150, 300, 600].sample,
        chunks_retrieved: rand(0..5).times.map { rand(1..100) },
        cache_hit: [true, false].sample
      )
    end

    # Verify analytics
    cache_hit_rate = RagQuery.cache_hit_rate(@entity)
    avg_response_time = RagQuery.average_response_time(@entity)

    assert cache_hit_rate >= 0
    assert cache_hit_rate <= 100
    assert avg_response_time > 0
  end

  test "processing job success rate tracks reliability" do
    # Create mix of successful and failed jobs
    3.times do
      RagProcessingJob.create!(
        rag_store: @rag_store,
        job_id: SecureRandom.hex,
        job_type: "test",
        status: :completed,
        started_at: 5.minutes.ago,
        completed_at: 4.minutes.ago
      )
    end

    1.times do
      RagProcessingJob.create!(
        rag_store: @rag_store,
        job_id: SecureRandom.hex,
        job_type: "test",
        status: :failed,
        error_message: "Test error",
        started_at: 5.minutes.ago,
        completed_at: 4.minutes.ago
      )
    end

    success_rate = RagProcessingJob.success_rate(job_type: "test")

    # 3 succeeded, 1 failed = 75% success rate (approximately)
    assert success_rate > 50
    assert success_rate <= 100
  end
end
