# Multi-Tenant RAG Architecture Plan

## Overview

AMOS needs **two separate RAG systems** with strict isolation:

1. **System RAG** - AMOS's own knowledge base (shared, read-only for all users)
2. **Entity RAG** - Customer-specific knowledge bases (isolated per entity)

## Current State Analysis

### Existing Schema
```ruby
# rag_stores table
belongs_to :user, optional: true     # ❌ User-level (too granular)
belongs_to :entity, optional: true   # ✅ Entity-level (correct)
```

**Problem**: Current implementation allows `entity: nil`, which means RAG stores can be "global" - this is **insecure** for customer data.

### Current Pinecone Structure
```ruby
index_name = "amos-integrations-#{app_name}"
namespace = "#{app_name}_#{timestamp}"
```

**Problem**: No entity_id in namespace → different entities' data could mix if they use the same `app_name`.

## Security Requirements

### Critical Rules
1. **Isolation**: Customer A must **never** access Customer B's RAG data
2. **System Knowledge**: All customers can access AMOS system knowledge
3. **Entity Scoping**: All queries must be scoped by `current_entity`
4. **Audit Trail**: Log who accesses what RAG store

## Proposed Architecture

### 1. RAG Store Types

```ruby
# Add enum to RagStore model
enum store_type: {
  system: 'system',      # AMOS's own docs (products, integrations, help)
  entity: 'entity'       # Customer-specific docs (API specs, internal docs)
}
```

### 2. Updated Database Schema

```ruby
class AddStoreTypeToRagStores < ActiveRecord::Migration[7.1]
  def change
    add_column :rag_stores, :store_type, :string, default: 'entity', null: false
    add_index :rag_stores, :store_type

    # Make entity required for entity-type stores
    # System stores have entity_id = null
    add_check_constraint :rag_stores,
      "(store_type = 'system' AND entity_id IS NULL) OR (store_type = 'entity' AND entity_id IS NOT NULL)",
      name: 'entity_required_for_entity_stores'
  end
end
```

### 3. Pinecone Namespace Strategy

**Current** (insecure):
```
Index: amos-integrations-stripe
Namespace: stripe_1634567890
```

**Proposed** (secure):
```
# System RAG
Index: amos-system-knowledge
Namespace: stripe_integration_docs  # No entity ID

# Entity RAG
Index: amos-entity-knowledge
Namespace: entity_123_stripe_1634567890  # Entity ID prefix
```

### 4. Updated Services

#### RagStoreService Changes

```ruby
class RagStoreService
  SYSTEM_INDEX = "amos-system-knowledge"
  ENTITY_INDEX = "amos-entity-knowledge"

  def create_rag_store(app_name, chunks, metadata = {})
    store_type = metadata[:store_type] || 'entity'
    entity = metadata[:entity]

    # Validate entity requirement
    if store_type == 'entity' && entity.nil?
      raise "Entity required for entity-type RAG stores"
    end

    # Select index based on type
    index_name = store_type == 'system' ? SYSTEM_INDEX : ENTITY_INDEX

    # Generate namespace with entity isolation
    namespace = if store_type == 'system'
      "system_#{app_name.downcase.gsub(/\s+/, '_')}_#{Time.current.to_i}"
    else
      "entity_#{entity.id}_#{app_name.downcase.gsub(/\s+/, '_')}_#{Time.current.to_i}"
    end

    # ... rest of implementation

    rag_store = RagStore.create!(
      name: metadata[:name] || "#{app_name} Documentation",
      app_name: app_name,
      store_type: store_type,
      entity: (store_type == 'entity' ? entity : nil),
      user: metadata[:user],
      pinecone_index: index_name,
      pinecone_namespace: namespace,
      # ...
    )
  end

  def query_rag_store(rag_store_id, query, current_entity: nil, top_k: 5)
    rag_store = RagStore.find(rag_store_id)

    # SECURITY CHECK: Verify access
    unless can_access_rag_store?(rag_store, current_entity)
      raise SecurityError, "Access denied to RAG store #{rag_store_id}"
    end

    # ... rest of query logic
  end

  private

  def can_access_rag_store?(rag_store, current_entity)
    case rag_store.store_type
    when 'system'
      true  # Everyone can access system knowledge
    when 'entity'
      rag_store.entity_id == current_entity&.id  # Must match entity
    else
      false
    end
  end
end
```

#### Updated RagStore Model

```ruby
class RagStore < ApplicationRecord
  belongs_to :user, optional: true
  belongs_to :entity, optional: true

  enum store_type: { system: 'system', entity: 'entity' }

  validates :store_type, presence: true
  validates :entity, presence: true, if: -> { entity? }  # Required for entity type
  validates :entity, absence: true, if: -> { system? }   # Forbidden for system type

  # Scopes
  scope :system_stores, -> { where(store_type: 'system') }
  scope :entity_stores, -> (entity) { where(store_type: 'entity', entity: entity) }
  scope :accessible_by, ->(entity) {
    where(store_type: 'system').or(where(store_type: 'entity', entity: entity))
  }

  # Find RAG store with security check
  def self.find_accessible(rag_store_id, current_entity)
    store = find(rag_store_id)

    if store.system?
      store  # System stores accessible to all
    elsif store.entity? && store.entity_id == current_entity&.id
      store  # Entity store belongs to current entity
    else
      raise ActiveRecord::RecordNotFound, "RAG store not found or access denied"
    end
  end
end
```

#### Updated Tools

```ruby
# app/services/tools/create_rag_store_tool.rb
module Tools
  class CreateRagStoreTool < BaseTool
    def execute(args)
      # ... existing validation

      # Determine store type
      store_type = get_arg(args, :store_type, 'entity')

      # SECURITY: Entity stores require entity context
      if store_type == 'entity' && entity.nil?
        return error_response("Cannot create entity RAG store without entity context")
      end

      # Create RAG store with proper scoping
      rag_result = rag_service.create_rag_store(
        app_name,
        processing_result[:chunks],
        {
          store_type: store_type,
          entity: entity,
          user: user,
          # ...
        }
      )

      # ...
    end
  end
end

# app/services/tools/query_rag_store_tool.rb
module Tools
  class QueryRagStoreTool < BaseTool
    def execute(args)
      # ... existing validation

      # Find RAG store with security check
      rag_store = if rag_store_id
        RagStore.find_accessible(rag_store_id, entity)
      elsif app_name
        # Find latest accessible store for app
        RagStore.accessible_by(entity)
                .where(app_name: app_name, status: 'active')
                .order(created_at: :desc)
                .first
      end

      unless rag_store
        return error_response("No accessible RAG store found")
      end

      # Query with entity context
      rag_service = RagStoreService.new
      result = rag_service.query_rag_store(
        rag_store.id,
        query,
        current_entity: entity,
        top_k: top_k
      )

      # ...
    end
  end
end
```

### 5. System RAG Setup

Create a rake task to populate system knowledge:

```ruby
# lib/tasks/rag.rake
namespace :rag do
  desc "Populate system RAG with AMOS knowledge"
  task populate_system: :environment do
    puts "📚 Populating system RAG with AMOS knowledge..."

    rag_service = RagStoreService.new

    # Integration documentation
    integrations_docs = [
      { url: "https://stripe.com/docs/api", app_name: "Stripe" },
      { url: "https://developers.hubspot.com/docs/api", app_name: "HubSpot" },
      # ... other integrations
    ]

    integrations_docs.each do |doc|
      puts "Processing #{doc[:app_name]}..."

      processor = DocumentProcessorService.new
      result = processor.process_documents([
        { type: 'url', content: doc[:url] }
      ])

      if result[:success]
        rag_service.create_rag_store(
          doc[:app_name],
          result[:chunks],
          {
            store_type: 'system',
            name: "#{doc[:app_name]} Integration Docs",
            entity: nil,  # System store
            user: nil
          }
        )
        puts "✅ #{doc[:app_name]} indexed"
      else
        puts "❌ Failed: #{result[:error]}"
      end
    end

    puts "✅ System RAG populated"
  end

  desc "Check RAG store access"
  task :check_access, [:entity_id, :rag_store_id] => :environment do |t, args|
    entity = Entity.find(args[:entity_id])
    rag_store = RagStore.find(args[:rag_store_id])

    can_access = if rag_store.system?
      true
    elsif rag_store.entity? && rag_store.entity_id == entity.id
      true
    else
      false
    end

    puts "Entity #{entity.id} can #{can_access ? '✅' : '❌'} access RAG store #{rag_store.id}"
    puts "Store type: #{rag_store.store_type}"
    puts "Store entity: #{rag_store.entity_id || 'system'}"
  end
end
```

## Implementation Plan

### Phase 1: Database Migration (1 day)
- [ ] Add `store_type` column to `rag_stores`
- [ ] Add check constraint for entity requirement
- [ ] Create migration for existing data
- [ ] Add indexes

### Phase 2: Model Updates (1 day)
- [ ] Update `RagStore` model with enum and validations
- [ ] Add scopes: `system_stores`, `entity_stores`, `accessible_by`
- [ ] Add `find_accessible` method
- [ ] Write model tests

### Phase 3: Service Updates (2 days)
- [ ] Update `RagStoreService` with store type handling
- [ ] Implement namespace strategy with entity isolation
- [ ] Add `can_access_rag_store?` security check
- [ ] Update tool implementations
- [ ] Write service tests

### Phase 4: System RAG Population (1 day)
- [ ] Create rake task for system knowledge
- [ ] Index AMOS integration docs (Stripe, HubSpot, etc.)
- [ ] Index AMOS product documentation
- [ ] Index help center content

### Phase 5: Testing & Security Audit (2 days)
- [ ] Unit tests for isolation logic
- [ ] Integration tests for multi-tenant scenarios
- [ ] Security audit: attempt cross-entity access
- [ ] Performance testing with multiple entities
- [ ] Load testing Pinecone queries

### Phase 6: Documentation (1 day)
- [ ] Update API docs
- [ ] Document security model
- [ ] Create admin guide for system RAG
- [ ] Update user-facing help

## Security Test Cases

```ruby
# test/services/rag_store_service_test.rb
test "entity cannot access other entity's RAG store" do
  entity1 = entities(:one)
  entity2 = entities(:two)

  rag_store = RagStore.create!(
    name: "Entity 1 Docs",
    app_name: "Private App",
    store_type: 'entity',
    entity: entity1,
    # ...
  )

  assert_raises(ActiveRecord::RecordNotFound) do
    RagStore.find_accessible(rag_store.id, entity2)
  end
end

test "all entities can access system RAG stores" do
  system_store = RagStore.create!(
    name: "Stripe Integration Docs",
    app_name: "Stripe",
    store_type: 'system',
    entity: nil,
    # ...
  )

  entity1 = entities(:one)
  entity2 = entities(:two)

  assert_equal system_store, RagStore.find_accessible(system_store.id, entity1)
  assert_equal system_store, RagStore.find_accessible(system_store.id, entity2)
end
```

## Monitoring & Observability

Add logging for security events:

```ruby
# app/services/rag_store_service.rb
def query_rag_store(rag_store_id, query, current_entity: nil, top_k: 5)
  rag_store = RagStore.find(rag_store_id)

  # Log access attempt
  Rails.logger.info({
    event: 'rag_access',
    rag_store_id: rag_store_id,
    store_type: rag_store.store_type,
    store_entity_id: rag_store.entity_id,
    current_entity_id: current_entity&.id,
    query: query,
    timestamp: Time.current
  }.to_json)

  unless can_access_rag_store?(rag_store, current_entity)
    Rails.logger.warn({
      event: 'rag_access_denied',
      rag_store_id: rag_store_id,
      current_entity_id: current_entity&.id,
      timestamp: Time.current
    }.to_json)

    raise SecurityError, "Access denied"
  end

  # ... query logic
end
```

## Future Enhancements

1. **Role-Based Access**: Allow entities to share RAG stores with specific partners
2. **RAG Store Marketplace**: Public RAG stores (e.g., common API docs)
3. **Versioning**: Track RAG store versions for rollback
4. **Usage Analytics**: Track queries per entity for billing
5. **RAG Store Templates**: Pre-built knowledge bases for common use cases

## Rollout Strategy

### Testing Environment
1. Create two test entities: `Entity A`, `Entity B`
2. Create system RAG with Stripe docs
3. Create entity-specific RAGs for each
4. Verify isolation via tests
5. Attempt cross-entity access (should fail)

### Production Rollout
1. **Announce**: Email customers about new multi-tenant RAG
2. **Migrate**: Existing RAG stores marked as `entity` type
3. **Populate**: System RAG with integration docs
4. **Monitor**: Watch for access denied errors (shouldn't happen)
5. **Rollback Plan**: Feature flag to disable entity checks if issues

## Compliance Notes

- **GDPR**: Entity data isolated, can be deleted on request
- **SOC 2**: Audit logs for all RAG access
- **HIPAA** (future): Additional encryption for sensitive entities

---

**Priority**: 🔴 **CRITICAL** - Must implement before production launch
**Effort**: ~8 days
**Risk**: High if not done - data leakage between customers
