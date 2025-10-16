class RagLoaderService
  # Load and cache available RAG stores for Scout agent
  # Called during Scout initialization to show available knowledge bases

  def self.load_for_entity(entity)
    new(entity).load
  end

  def initialize(entity)
    @entity = entity
  end

  def load
    Rails.logger.info "📚 Loading RAG stores for entity: #{@entity.name} (ID: #{@entity.id})"

    # Load system stores (shared AMOS knowledge)
    system_stores = load_system_stores

    # Load entity-specific stores
    entity_stores = load_entity_stores

    result = {
      system_stores: system_stores,
      entity_stores: entity_stores,
      total_stores: system_stores.length + entity_stores.length,
      total_chunks: (system_stores + entity_stores).sum { |s| s[:chunk_count] }
    }

    log_summary(result)

    result
  end

  private

  def load_system_stores
    stores = RagStore.system_stores.active.order(:app_name)

    stores.map do |store|
      {
        id: store.id,
        name: store.name,
        app_name: store.app_name,
        type: 'system',
        chunk_count: store.chunk_count,
        icon: '🌐',
        description: "Shared #{store.app_name} integration knowledge"
      }
    end
  end

  def load_entity_stores
    stores = RagStore.entity_stores(@entity).active.order(:app_name)

    stores.map do |store|
      {
        id: store.id,
        name: store.name,
        app_name: store.app_name,
        type: 'entity',
        chunk_count: store.chunk_count,
        icon: '🏢',
        description: "Your custom #{store.app_name} knowledge"
      }
    end
  end

  def log_summary(result)
    Rails.logger.info "  🌐 System stores: #{result[:system_stores].length}"
    Rails.logger.info "  🏢 Entity stores: #{result[:entity_stores].length}"
    Rails.logger.info "  📄 Total chunks available: #{result[:total_chunks]}"

    # Log individual stores
    result[:system_stores].each do |store|
      Rails.logger.info "    #{store[:icon]} #{store[:app_name]} (#{store[:chunk_count]} chunks)"
    end

    result[:entity_stores].each do |store|
      Rails.logger.info "    #{store[:icon]} #{store[:app_name]} (#{store[:chunk_count]} chunks)"
    end
  end
end
