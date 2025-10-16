class RagStore < ApplicationRecord
  belongs_to :user, optional: true
  belongs_to :entity, optional: true

  # Enums
  enum store_type: {
    system: 'system',  # AMOS's shared knowledge (integrations, help docs)
    entity: 'entity'   # Customer-specific isolated knowledge
  }, _prefix: true

  # Validations
  validates :name, presence: true
  validates :app_name, presence: true
  validates :pinecone_index, presence: true
  validates :pinecone_namespace, presence: true
  validates :status, presence: true
  validates :status, inclusion: { in: %w[building active failed archived] }
  validates :store_type, presence: true

  # Multi-tenant security validations
  validates :entity, presence: true, if: :store_type_entity?
  validates :entity, absence: true, if: :store_type_system?

  # Scopes
  scope :active, -> { where(status: "active") }
  scope :by_app, ->(app_name) { where(app_name: app_name) }
  scope :system_stores, -> { where(store_type: 'system') }
  scope :entity_stores, ->(entity) { where(store_type: 'entity', entity: entity) }
  scope :accessible_by, ->(entity) {
    where(store_type: 'system').or(where(store_type: 'entity', entity: entity))
  }

  # Default values
  after_initialize :set_defaults, if: :new_record?

  # Get the most recent RAG store for an app (with entity scoping)
  def self.latest_for_app(app_name, entity: nil)
    scope = where(app_name: app_name, status: "active")

    # If entity provided, only return accessible stores (system or entity-owned)
    scope = scope.accessible_by(entity) if entity

    scope.order(created_at: :desc).first
  end

  # Find RAG store with security check
  # Raises ActiveRecord::RecordNotFound if not accessible
  def self.find_accessible(rag_store_id, current_entity)
    store = find(rag_store_id)

    if store.store_type_system?
      store  # System stores accessible to all
    elsif store.store_type_entity? && store.entity_id == current_entity&.id
      store  # Entity store belongs to current entity
    else
      raise ActiveRecord::RecordNotFound, "RAG store not found or access denied"
    end
  end

  # Archive this RAG store
  def archive!
    update!(status: "archived")
  end

  # Check if the store is ready for queries
  def ready?
    status == "active" && chunk_count.to_i > 0
  end

  # Status helper methods
  def active?
    status == "active"
  end

  def building?
    status == "building"
  end

  def failed?
    status == "failed"
  end

  def archived?
    status == "archived"
  end

  # Check if current entity can access this RAG store
  def accessible_by?(current_entity)
    if store_type_system?
      true  # System stores accessible to all
    elsif store_type_entity?
      entity_id == current_entity&.id  # Must match entity
    else
      false
    end
  end

  private

  def set_defaults
    self.status ||= "building"
    self.chunk_count ||= 0
    self.metadata ||= {}
    self.store_type ||= 'entity' if store_type.nil?
  end
end