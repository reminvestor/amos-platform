require "test_helper"

class RagStoreTest < ActiveSupport::TestCase
  def setup
    @entity_one = entities(:one)
    @entity_two = entities(:two)
  end

  test "should create system RAG store without entity" do
    store = RagStore.create!(
      name: "Stripe Docs",
      app_name: "Stripe",
      store_type: 'system',
      entity: nil,
      pinecone_index: "amos-system-knowledge",
      pinecone_namespace: "system_stripe_1234567890",
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
end
