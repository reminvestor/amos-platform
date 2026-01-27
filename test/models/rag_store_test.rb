require "test_helper"

class RagStoreTest < ActiveSupport::TestCase
  def setup
    @entity_one = entities(:one)
    @entity_two = entities(:two)
  end

  test "should create system RAG store without entity" do
    unique_suffix = SecureRandom.hex(8)
    store = RagStore.create!(
      name: "Stripe Docs",
      app_name: "Stripe",
      store_type: 'system',
      entity: nil,
      pinecone_index: "amos-system-knowledge",
      pinecone_namespace: "system_stripe_#{unique_suffix}",
      status: "active"
    )

    assert store.store_type_system?
    assert_nil store.entity_id
  end

  test "should create entity RAG store with entity" do
    store = RagStore.create!(
      name: "Custom API Docs",
      app_name: "CustomAPI",
      store_type: 'entity',
      entity: @entity_one,
      pinecone_index: "amos-entity-knowledge",
      pinecone_namespace: "entity_#{@entity_one.id}_customapi_1234567890",
      status: "active"
    )

    assert store.store_type_entity?
    assert_equal @entity_one.id, store.entity_id
  end

  test "should not allow entity RAG store without entity" do
    assert_raises ActiveRecord::RecordInvalid do
      RagStore.create!(
        name: "Invalid Store",
        app_name: "Test",
        store_type: 'entity',
        entity: nil,
        pinecone_index: "test-index",
        pinecone_namespace: "test-namespace",
        status: "active"
      )
    end
  end

  test "should not allow system RAG store with entity" do
    assert_raises ActiveRecord::RecordInvalid do
      RagStore.create!(
        name: "Invalid Store",
        app_name: "Test",
        store_type: 'system',
        entity: @entity_one,
        pinecone_index: "test-index",
        pinecone_namespace: "test-namespace",
        status: "active"
      )
    end
  end

  test "accessible_by scope should return system stores for any entity" do
    system_store = RagStore.create!(
      name: "System Store",
      app_name: "System",
      store_type: 'system',
      entity: nil,
      pinecone_index: "amos-system-knowledge",
      pinecone_namespace: "system_test",
      status: "active"
    )

    assert_includes RagStore.accessible_by(@entity_one), system_store
    assert_includes RagStore.accessible_by(@entity_two), system_store
  end

  test "accessible_by scope should only return entity's own stores" do
    entity_one_store = RagStore.create!(
      name: "Entity One Store",
      app_name: "EntityOneApp",
      store_type: 'entity',
      entity: @entity_one,
      pinecone_index: "amos-entity-knowledge",
      pinecone_namespace: "entity_#{@entity_one.id}_test",
      status: "active"
    )

    entity_two_store = RagStore.create!(
      name: "Entity Two Store",
      app_name: "EntityTwoApp",
      store_type: 'entity',
      entity: @entity_two,
      pinecone_index: "amos-entity-knowledge",
      pinecone_namespace: "entity_#{@entity_two.id}_test",
      status: "active"
    )

    entity_one_accessible = RagStore.accessible_by(@entity_one)
    entity_two_accessible = RagStore.accessible_by(@entity_two)

    assert_includes entity_one_accessible, entity_one_store
    assert_not_includes entity_one_accessible, entity_two_store

    assert_includes entity_two_accessible, entity_two_store
    assert_not_includes entity_two_accessible, entity_one_store
  end

  test "find_accessible should return system store for any entity" do
    system_store = RagStore.create!(
      name: "System Store",
      app_name: "System",
      store_type: 'system',
      entity: nil,
      pinecone_index: "amos-system-knowledge",
      pinecone_namespace: "system_test",
      status: "active"
    )

    assert_equal system_store, RagStore.find_accessible(system_store.id, @entity_one)
    assert_equal system_store, RagStore.find_accessible(system_store.id, @entity_two)
  end

  test "find_accessible should return entity store only for owning entity" do
    entity_store = RagStore.create!(
      name: "Entity Store",
      app_name: "EntityApp",
      store_type: 'entity',
      entity: @entity_one,
      pinecone_index: "amos-entity-knowledge",
      pinecone_namespace: "entity_#{@entity_one.id}_test",
      status: "active"
    )

    assert_equal entity_store, RagStore.find_accessible(entity_store.id, @entity_one)

    assert_raises ActiveRecord::RecordNotFound do
      RagStore.find_accessible(entity_store.id, @entity_two)
    end
  end

  test "accessible_by? should return true for system stores" do
    system_store = RagStore.create!(
      name: "System Store",
      app_name: "System",
      store_type: 'system',
      entity: nil,
      pinecone_index: "amos-system-knowledge",
      pinecone_namespace: "system_test",
      status: "active"
    )

    assert system_store.accessible_by?(@entity_one)
    assert system_store.accessible_by?(@entity_two)
    assert system_store.accessible_by?(nil)
  end

  test "accessible_by? should only return true for owning entity" do
    entity_store = RagStore.create!(
      name: "Entity Store",
      app_name: "EntityApp",
      store_type: 'entity',
      entity: @entity_one,
      pinecone_index: "amos-entity-knowledge",
      pinecone_namespace: "entity_#{@entity_one.id}_test",
      status: "active"
    )

    assert entity_store.accessible_by?(@entity_one)
    assert_not entity_store.accessible_by?(@entity_two)
    assert_not entity_store.accessible_by?(nil)
  end

  test "latest_for_app should respect entity scoping" do
    skip "TODO: Fix - fixture conflicts in parallel tests"
    # Create system store
    system_store = RagStore.create!(
      name: "Stripe System Docs",
      app_name: "Stripe",
      store_type: 'system',
      entity: nil,
      pinecone_index: "amos-system-knowledge",
      pinecone_namespace: "system_stripe",
      status: "active",
      created_at: 1.day.ago
    )

    # Create entity-specific store (newer)
    entity_store = RagStore.create!(
      name: "Stripe Custom Docs",
      app_name: "Stripe",
      store_type: 'entity',
      entity: @entity_one,
      pinecone_index: "amos-entity-knowledge",
      pinecone_namespace: "entity_#{@entity_one.id}_stripe",
      status: "active",
      created_at: Time.current
    )

    # Without entity, should return latest (entity store)
    latest = RagStore.latest_for_app("Stripe")
    assert_equal entity_store, latest

    # With entity, should return entity's latest accessible store
    latest_for_entity_one = RagStore.latest_for_app("Stripe", entity: @entity_one)
    assert_equal entity_store, latest_for_entity_one

    # Different entity should only see system store
    latest_for_entity_two = RagStore.latest_for_app("Stripe", entity: @entity_two)
    assert_equal system_store, latest_for_entity_two
  end

  # === New Associations (Enhanced Storage) ===

  test "has many rag_documents" do
    store = rag_stores(:entity_one_custom)

    assert_respond_to store, :rag_documents
    assert_kind_of ActiveRecord::Associations::CollectionProxy, store.rag_documents
    assert store.rag_documents.any?
  end

  test "has many rag_chunks through rag_documents" do
    store = rag_stores(:entity_one_custom)

    assert_respond_to store, :rag_chunks
    assert_kind_of ActiveRecord::Associations::CollectionProxy, store.rag_chunks
    assert store.rag_chunks.any?
  end

  test "has many rag_queries" do
    store = rag_stores(:entity_one_custom)

    assert_respond_to store, :rag_queries
    assert_kind_of ActiveRecord::Associations::CollectionProxy, store.rag_queries
    assert store.rag_queries.any?
  end

  test "has many rag_processing_jobs" do
    store = rag_stores(:entity_one_custom)

    assert_respond_to store, :rag_processing_jobs
    assert_kind_of ActiveRecord::Associations::CollectionProxy, store.rag_processing_jobs
    assert store.rag_processing_jobs.any?
  end

  test "destroys dependent documents when store is destroyed" do
    store = rag_stores(:entity_one_custom)
    document_ids = store.rag_documents.pluck(:id)

    assert document_ids.any?, "Store should have documents"

    store.destroy

    document_ids.each do |doc_id|
      assert_not RagDocument.exists?(doc_id)
    end
  end

  # === S3 Path Helpers ===

  test "s3_key_prefix returns entity-scoped path" do
    entity_store = rag_stores(:entity_one_custom)

    prefix = entity_store.s3_key_prefix

    assert_equal "entities/#{@entity_one.id}", prefix
  end

  test "s3_key_prefix returns system path for system stores" do
    system_store = rag_stores(:system_stripe)

    prefix = system_store.s3_key_prefix

    assert_match /^system\//, prefix
  end

  test "s3_raw_path returns correct path with default" do
    store = rag_stores(:entity_one_custom)

    path = store.s3_raw_path

    assert_equal "entities/#{@entity_one.id}/raw_documents/#{store.id}", path
  end

  test "s3_raw_path returns custom path when set" do
    store = rag_stores(:entity_one_custom)
    custom_path = "custom/path/to/raw"
    store.update!(s3_raw_path: custom_path)

    assert_equal custom_path, store.s3_raw_path
  end

  test "s3_processed_path returns correct path" do
    store = rag_stores(:entity_one_custom)

    path = store.s3_processed_path

    assert_equal "entities/#{@entity_one.id}/processed/#{store.id}", path
  end

  test "s3_docling_output_path returns correct path" do
    store = rag_stores(:entity_one_custom)

    path = store.s3_docling_output_path

    assert_equal "entities/#{@entity_one.id}/docling_output/#{store.id}", path
  end

  # === Embedding Status ===

  test "all_chunks_embedded? returns true when all chunks have embeddings" do
    store = rag_stores(:entity_one_custom)

    # Set embeddings on all chunks
    store.rag_chunks.each do |chunk|
      chunk.update!(embedding: Array.new(1536) { rand })
    end

    assert store.all_chunks_embedded?
  end

  test "all_chunks_embedded? returns false when some chunks lack embeddings" do
    store = rag_stores(:entity_one_custom)

    # Fixture chunks have nil embeddings
    assert_not store.all_chunks_embedded?
  end

  test "all_chunks_embedded? returns false when no chunks exist" do
    store = RagStore.create!(
      name: "Empty Store",
      app_name: "Test",
      store_type: 'entity',
      entity: @entity_one,
      pinecone_index: "test-index",
      pinecone_namespace: "test-namespace",
      status: "active"
    )

    assert_not store.all_chunks_embedded?
  end

  # === Access Tracking ===

  test "track_access! increments access count" do
    store = rag_stores(:entity_one_custom)
    original_count = store.access_count || 0

    store.track_access!

    assert_equal original_count + 1, store.reload.access_count
  end

  test "track_access! updates last_accessed_at timestamp" do
    store = rag_stores(:entity_one_custom)
    original_time = store.last_accessed_at

    travel_to 1.hour.from_now do
      store.track_access!
    end

    assert_not_equal original_time, store.reload.last_accessed_at
  end

  # === Statistics Helpers ===

  test "document_count returns number of documents" do
    store = rag_stores(:entity_one_custom)

    # Fixtures should have at least 2 documents
    assert store.document_count >= 2
  end

  test "chunk_count returns number of chunks across all documents" do
    store = rag_stores(:entity_one_custom)

    # Fixtures should have multiple chunks
    assert store.chunk_count >= 3
  end

  test "query_count returns number of queries" do
    store = rag_stores(:entity_one_custom)

    # Fixtures should have queries
    assert store.query_count >= 1
  end

  test "average_query_time calculates mean response time" do
    store = rag_stores(:entity_one_custom)

    avg_time = store.average_query_time

    assert avg_time > 0
    assert avg_time.is_a?(Numeric)
  end

  test "average_query_time returns 0 when no queries" do
    store = RagStore.create!(
      name: "No Queries Store",
      app_name: "Test",
      store_type: 'entity',
      entity: @entity_one,
      pinecone_index: "test-index",
      pinecone_namespace: "test-namespace",
      status: "active"
    )

    assert_equal 0, store.average_query_time
  end

  test "cache_hit_rate calculates percentage of cached queries" do
    store = rag_stores(:entity_one_custom)

    rate = store.cache_hit_rate

    assert rate >= 0
    assert rate <= 100
  end

  test "cache_hit_rate returns 0 when no queries" do
    store = RagStore.create!(
      name: "No Queries Store",
      app_name: "Test",
      store_type: 'entity',
      entity: @entity_one,
      pinecone_index: "test-index",
      pinecone_namespace: "test-namespace",
      status: "active"
    )

    assert_equal 0, store.cache_hit_rate
  end

  # === Processing Metrics ===

  test "processing_time_seconds returns time in seconds" do
    store = rag_stores(:entity_one_custom)
    store.update!(processing_time_ms: 5000)

    assert_equal 5.0, store.processing_time_seconds
  end

  test "processing_time_seconds returns 0 when nil" do
    store = rag_stores(:entity_one_custom)
    store.update!(processing_time_ms: nil)

    assert_equal 0, store.processing_time_seconds
  end

  test "recently_accessed? returns true when accessed within timeframe" do
    store = rag_stores(:entity_one_custom)

    travel_to 1.hour.ago do
      store.track_access!
    end

    assert store.recently_accessed?(within: 2.hours)
    assert_not store.recently_accessed?(within: 30.minutes)
  end

  test "recently_accessed? returns false when never accessed" do
    store = RagStore.create!(
      name: "Never Accessed",
      app_name: "Test",
      store_type: 'entity',
      entity: @entity_one,
      pinecone_index: "test-index",
      pinecone_namespace: "test-namespace",
      status: "active"
    )

    assert_not store.recently_accessed?
  end

  # === Status Helpers ===

  test "has_documents? returns true when documents exist" do
    store = rag_stores(:entity_one_custom)

    assert store.has_documents?
  end

  test "has_documents? returns false when no documents" do
    store = RagStore.create!(
      name: "Empty Store",
      app_name: "Test",
      store_type: 'entity',
      entity: @entity_one,
      pinecone_index: "test-index",
      pinecone_namespace: "test-namespace",
      status: "active"
    )

    assert_not store.has_documents?
  end

  test "has_queries? returns true when queries exist" do
    store = rag_stores(:entity_one_custom)

    assert store.has_queries?
  end

  test "embedding_complete? returns true when all chunks embedded" do
    store = rag_stores(:entity_one_custom)

    # Set embeddings on all chunks
    store.rag_chunks.each do |chunk|
      chunk.update!(embedding: Array.new(1536) { rand })
    end

    assert store.embedding_complete?
  end

  test "embedding_complete? returns false when chunks pending" do
    store = rag_stores(:entity_one_custom)

    assert_not store.embedding_complete?
  end
end
