require "test_helper"

class RagStoreServiceComprehensiveTest < ActiveSupport::TestCase
  def setup
    @entity = entities(:one)
    @user = users(:one)

    # Ensure API keys are set for testing
    ENV['PINECONE_API_KEY'] ||= 'test-pinecone-key'
    ENV['OPENAI_API_KEY'] ||= 'test-openai-key'

    @service = RagStoreService.new
  end

  # ============================================================================
  # UNIT TESTS - Individual Methods
  # ============================================================================

  test "initialize should configure Pinecone and OpenAI clients" do
    service = RagStoreService.new

    assert_not_nil service.instance_variable_get(:@pinecone)
    assert_not_nil service.instance_variable_get(:@openai_client)
    assert_not_nil service.instance_variable_get(:@embedding_cache)
    assert_instance_of Pinecone::Client, service.instance_variable_get(:@pinecone)
    assert_instance_of OpenAI::Client, service.instance_variable_get(:@openai_client)
  end

  test "generate_namespace creates entity-scoped namespace" do
    namespace = @service.send(:generate_namespace, "TestApp", 'entity', @entity)

    assert_match /^entity_#{@entity.id}_testapp_\d+$/, namespace
    assert_includes namespace, "entity_#{@entity.id}"
    assert_includes namespace, "testapp"
  end

  test "generate_namespace creates system namespace without entity prefix" do
    namespace = @service.send(:generate_namespace, "TestApp", 'system', nil)

    assert_match /^system_testapp_\d+$/, namespace
    assert_includes namespace, "system_"
    refute_includes namespace, "entity_"
  end

  test "can_access_rag_store allows system stores for any entity" do
    system_store = rag_stores(:system_stripe)

    assert @service.send(:can_access_rag_store?, system_store, @entity)
    assert @service.send(:can_access_rag_store?, system_store, entities(:two))
    assert @service.send(:can_access_rag_store?, system_store, nil)
  end

  test "can_access_rag_store restricts entity stores to owner" do
    entity_store = rag_stores(:entity_one_custom)
    other_entity = entities(:two)

    assert @service.send(:can_access_rag_store?, entity_store, @entity)
    refute @service.send(:can_access_rag_store?, entity_store, other_entity)
    refute @service.send(:can_access_rag_store?, entity_store, nil)
  end

  test "raises SecurityError when creating entity store without entity" do
    error = assert_raises SecurityError do
      @service.create_rag_store(
        "TestApp",
        [{ content: "test", metadata: { source: "test.pdf" } }],
        { store_type: 'entity', entity: nil }
      )
    end

    assert_match /cannot create entity RAG store without entity/i, error.message
  end

  # ============================================================================
  # INTEGRATION TESTS - Require Valid API Keys
  # ============================================================================

  test "create_rag_store successfully creates entity-scoped store" do
    skip "Requires valid API keys - run end-to-end test instead"
  end

  test "create_rag_store creates system store accessible to all" do
    skip "Requires valid API keys - run end-to-end test instead"
  end

  test "query_rag_store enforces entity access control" do
    entity_store = rag_stores(:entity_one_custom)
    other_entity = entities(:two)

    error = assert_raises SecurityError do
      @service.query_rag_store(entity_store.id, "test query", current_entity: other_entity)
    end

    assert_match /access denied/i, error.message
  end

  test "query_rag_store returns relevant results with metadata" do
    skip "Requires valid API keys - run end-to-end test instead"
  end

  # ============================================================================
  # EMBEDDING CACHE TESTS
  # ============================================================================

  test "embedding cache reduces OpenAI API calls" do
    skip "Requires valid API keys and Redis - run end-to-end test instead"
  end

  # ============================================================================
  # HOST-BASED INDEXING TESTS
  # ============================================================================

  test "get_index_host retrieves and caches host URL" do
    skip "Requires valid API keys - test caching in end-to-end test"
  end

  test "get_index_host raises error when host not found" do
    skip "Requires valid API keys"
  end

  # ============================================================================
  # METADATA ENHANCEMENT TESTS (Phase 3)
  # ============================================================================

  test "create_rag_store tracks enhanced metadata" do
    skip "Requires valid API keys - run end-to-end test instead"
  end
end
