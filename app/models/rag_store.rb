class RagStore < ApplicationRecord
  belongs_to :user, optional: true
  belongs_to :entity, optional: true
  belongs_to :agent_plugin, optional: true

  # New associations for enhanced storage
  has_many :rag_documents, dependent: :destroy
  has_many :rag_chunks, through: :rag_documents
  has_many :rag_queries, dependent: :destroy
  has_many :rag_processing_jobs, dependent: :destroy

  # Enums
  enum :store_type, {
    system: 'system',  # AMOS's shared knowledge (integrations, help docs)
    entity: 'entity',  # Customer-specific isolated knowledge
    agent: 'agent'     # Agent-specific domain knowledge (e.g., QuickBooks docs)
  }, prefix: true, _type: :string

  # Validations
  validates :name, presence: true
  validates :app_name, presence: true
  validates :status, presence: true
  validates :status, inclusion: { in: %w[pending processing ready building active failed archived] }
  validates :store_type, presence: true

  # Pinecone fields are optional - pgvector is primary storage for local and AWS
  # Pinecone can be enabled later by setting PINECONE_API_KEY environment variable

  # Multi-tenant security validations
  validates :entity, presence: true, if: :store_type_entity?
  validates :entity, absence: true, if: :store_type_system?
  validates :agent_plugin, presence: true, if: :store_type_agent?

  # Scopes
  scope :active, -> { where(status: "active") }
  scope :by_app, ->(app_name) { where(app_name: app_name) }
  scope :system_stores, -> { where(store_type: 'system') }
  scope :entity_stores, ->(entity) { where(store_type: 'entity', entity: entity) }
  scope :agent_stores, ->(agent) { where(store_type: 'agent', agent_plugin: agent) }
  scope :for_agent, ->(agent) { where(agent_plugin: agent).or(where(store_type: 'system')) }
  scope :accessible_by, ->(entity) {
    where(store_type: 'system').or(where(store_type: 'entity', entity: entity))
  }
  scope :accessible_by_agent, ->(agent, entity) {
    where(store_type: 'system')
      .or(where(store_type: 'entity', entity: entity))
      .or(where(store_type: 'agent', agent_plugin: agent))
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

  # S3 path helpers
  def s3_key_prefix
    if entity_id.present?
      "entities/#{entity_id}"
    else
      "system/#{name.parameterize}"
    end
  end

  def s3_raw_path
    self[:s3_raw_path] || "#{s3_key_prefix}/raw_documents/#{id}"
  end

  def s3_processed_path
    self[:s3_processed_path] || "#{s3_key_prefix}/processed/#{id}"
  end

  def s3_docling_output_path
    self[:s3_docling_output_path] || "#{s3_key_prefix}/docling_output/#{id}"
  end

  # Check if all chunks are embedded
  def all_chunks_embedded?
    return false if rag_chunks.empty?
    rag_chunks.where(embedding: nil).count == 0
  end

  # Track access for cache optimization
  def track_access!
    increment!(:access_count)
    touch(:last_accessed_at)
  end

  # Complete processing and mark as ready
  def complete_processing!
    update!(status: 'ready')
  end

  # Status helpers for new states
  def pending?
    status == "pending"
  end

  def processing?
    status == "processing"
  end

  def ready?
    status == "ready" || status == "active"
  end

  # Document counters
  def document_count
    rag_documents.count
  end

  def has_documents?
    rag_documents.exists?
  end

  def embedding_complete?
    return false unless has_documents?
    all_chunks_embedded?
  end

  # Query analytics
  def cache_hit_rate
    queries = rag_queries.where('created_at > ?', 24.hours.ago)
    return 0.0 if queries.count.zero?

    hits = queries.where(cache_hit: true).count
    (hits.to_f / queries.count * 100).round(2)
  end

  def avg_response_time
    rag_queries.where('created_at > ?', 24.hours.ago).average(:response_time_ms)&.to_i || 0
  end

  def recently_accessed?(within: 7.days)
    last_accessed_at.present? && last_accessed_at > within.ago
  end

  # Query analytics - detailed metrics
  def query_count
    rag_queries.count
  end

  def average_query_time
    queries = rag_queries
    return 0 if queries.count.zero?
    queries.average(:response_time_ms)&.to_i || 0
  end

  def has_queries?
    rag_queries.exists?
  end

  # Processing time helpers
  def processing_time_seconds
    return 0 unless processing_time_ms
    (processing_time_ms.to_f / 1000).round(1)
  end

  private

  def set_defaults
    self.status ||= "pending"
    self.chunk_count ||= 0
    self.metadata ||= {}
    self.store_type ||= 'entity' if store_type.nil?
  end
end