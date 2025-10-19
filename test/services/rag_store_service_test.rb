require "test_helper"

class RagStoreServiceTest < ActiveSupport::TestCase
  def setup
    @entity_one = entities(:one)
    @entity_two = entities(:two)

    # Create service with API keys stubbed
    ENV['PINECONE_API_KEY'] ||= 'test-key'
    ENV['OPENAI_API_KEY'] ||= 'test-key'

    @service = RagStoreService.new
  end

  test "create_rag_store should create system store without entity" do
    skip "Requires Pinecone/OpenAI mocking"
    # Test implementation here
  end

  test "create_rag_store should create entity store with entity" do
    skip "Requires Pinecone/OpenAI mocking"
    # Test implementation here
  end

  test "create_rag_store should reject entity store without entity" do
    assert_raises SecurityError do
      @service.create_rag_store(
        "TestApp",
        [{ content: "test", metadata: { source: "test" } }],
        {
          store_type: 'entity',
          entity: nil
        }
      )
    end
  end

  test "generate_namespace should prefix entity stores with entity_id" do
    namespace = @service.send(:generate_namespace, "Stripe", 'entity', @entity_one)

    assert_match /^entity_#{@entity_one.id}_stripe_\d+$/, namespace
  end

  test "generate_namespace should prefix system stores with system" do
    namespace = @service.send(:generate_namespace, "Stripe", 'system', nil)

    assert_match /^system_stripe_\d+$/, namespace
  end

  test "can_access_rag_store? should allow system stores for all entities" do
    system_store = rag_stores(:system_stripe)

    assert @service.send(:can_access_rag_store?, system_store, @entity_one)
    assert @service.send(:can_access_rag_store?, system_store, @entity_two)
    assert @service.send(:can_access_rag_store?, system_store, nil)
  end

  test "can_access_rag_store? should only allow entity stores for owning entity" do
    entity_store = rag_stores(:entity_one_custom)

    assert @service.send(:can_access_rag_store?, entity_store, @entity_one)
    assert_not @service.send(:can_access_rag_store?, entity_store, @entity_two)
    assert_not @service.send(:can_access_rag_store?, entity_store, nil)
  end

  test "query_rag_store should reject access to other entity's store" do
    entity_store = rag_stores(:entity_one_custom)

    assert_raises SecurityError do
      @service.query_rag_store(
        entity_store.id,
        "test query",
        current_entity: @entity_two
      )
    end
  end

  test "query_rag_store should allow access to own entity store" do
    skip "Requires Pinecone mocking"
    # Test implementation here
  end

  test "query_rag_store should allow access to system stores" do
    skip "Requires Pinecone mocking"
    # Test implementation here
  end
end
