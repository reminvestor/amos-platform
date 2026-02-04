class Integration < ApplicationRecord
  # Associations
  belongs_to :entity, optional: true  # NULL = global/system integration
  belongs_to :created_by, class_name: 'User', optional: true
  has_many :connections, dependent: :destroy
  has_many :integration_operations, dependent: :destroy
  has_many :integration_actions, dependent: :destroy
  has_many :entities, through: :connections
  has_many :oauth_configurations, dependent: :destroy
  has_many :module_integrations, dependent: :destroy
  has_many :app_modules, through: :module_integrations

  # Validations
  validates :name, :slug, presence: true
  validates :slug, uniqueness: { scope: :entity_id }  # Unique per entity (or globally if entity_id is nil)
  validates :auth_type, :api_base_url, presence: true
  validates :category, inclusion: { in: %w[payment ecommerce crm communication productivity marketing analytics accounting custom] }

  # Enums
  enum :auth_type, {
    api_key: 0,
    bearer_token: 1,
    basic_auth: 2,
    oauth2: 3,
    no_auth: 4,  # No authentication required (can't use 'none' - conflicts with AR)
    custom: 5  # Reserved for user-managed OAuth apps (future)
  }

  # Scopes
  scope :active, -> { where(is_active: true) }
  scope :verified, -> { where(is_verified: true) }
  scope :by_category, ->(category) { where(category: category) }
  scope :global, -> { where(entity_id: nil) }
  # for_entity: Returns all integrations visible to entity (entity-owned + globals + public)
  # Use for discovery/listing
  scope :for_entity, ->(entity) { where(entity_id: [nil, entity.id]).or(where(is_public: true)) }
  # owned_by_entity: Returns ONLY integrations owned by this entity (not globals)
  # Use when checking if entity has their own version
  scope :owned_by_entity, ->(entity) { where(entity_id: entity.id) }
  scope :user_created, -> { where.not(entity_id: nil) }
  scope :public_integrations, -> { where(is_public: true) }
  # templates: Global integrations that can be copied to create entity-specific versions
  scope :templates, -> { where(entity_id: nil, is_public: false) }

  # Default values
  after_initialize :set_defaults, if: :new_record?

  def oauth?
    oauth2?
  end

  def requires_admin_config?
    # All auth types can be configured by admin
    true
  end

  # Get current auth configuration from database
  def current_auth_params
    oauth_config = OauthConfiguration.find_by(integration: self)
    
    return [] unless oauth_config
    
    oauth_config.auth_configs.order(:position).map do |ac|
      {
        key: ac.auth_key,
        value: ac.auth_value,
        placement: ac.auth_placement
      }
    end
  end

  def connected_for?(user)
    connections.joins(:integration_credentials)
               .where(entity_id: user.entity_ids)
               .where(integration_credentials: { status: :active })
               .exists?
  end

  def host_allowed?(host)
    return true if allowed_hosts.blank?

    allowed_hosts.any? do |pattern|
      if pattern.include?("*")
        # Convert wildcard to regex
        regex_pattern = pattern.gsub(".", '\.').gsub("*", ".*")
        host.match?(/\A#{regex_pattern}\z/)
      else
        host == pattern
      end
    end
  end

  # Vector search configuration
  has_neighbors :embedding

  # Update embedding when relevant fields change
  after_save :update_embedding, if: -> { saved_change_to_name? || saved_change_to_description? || saved_change_to_category? }

  # Class methods
  def self.search_by_similarity(query, limit: 5)
    # Generate embedding for the query
    query_embedding = AiAgents::VectorStore.instance.generate_embedding(query)
    
    # Use pgvector nearest_neighbors search
    active.nearest_neighbors(:embedding, query_embedding, distance: "cosine").first(limit)
  rescue => e
    Rails.logger.error "Vector search failed: #{e.message}"
    # Fallback to keyword search if vector search fails
    active.where("description ILIKE ? OR name ILIKE ?", "%#{query}%", "%#{query}%").limit(limit)
  end

  private

  def update_embedding
    # Construct a rich text representation of the integration
    embedding_text = <<~TEXT
      Integration: #{name}
      Category: #{category}
      Description: #{description}
      Operations: #{integration_operations.pluck(:name).join(", ")}
    TEXT
    
    # Generate embedding using VectorStore service
    vector = AiAgents::VectorStore.instance.generate_embedding(embedding_text)
    
    # Update the column directly to avoid triggering callbacks again
    update_column(:embedding, vector)
  rescue => e
    Rails.logger.error "Failed to update embedding for integration #{id}: #{e.message}"
  end

  def set_defaults
    self.is_active = true if is_active.nil?
    self.is_verified = false if is_verified.nil?
    self.is_public = false if is_public.nil?
    self.allowed_hosts ||= []
    self.auth_config ||= {}
    self.metadata ||= {}
  end

  # Is this a global/system integration (available to all)?
  def global?
    entity_id.nil?
  end

  # Is this a template that can be instantiated?
  def template?
    global? && !is_public?
  end

  # Is this integration visible to the given entity?
  def visible_to?(entity)
    global? || is_public? || entity_id == entity.id
  end

  # Status helpers for display purposes
  # Status can be: 'available' (default), 'coming_soon', 'beta', 'deprecated'
  def status
    metadata&.dig('status') || 'available'
  end

  def coming_soon?
    status == 'coming_soon'
  end

  def beta?
    status == 'beta'
  end

  def mark_as_coming_soon!
    update!(metadata: (metadata || {}).merge('status' => 'coming_soon'))
  end

  def mark_as_beta!
    update!(metadata: (metadata || {}).merge('status' => 'beta'))
  end

  def mark_as_available!
    new_metadata = (metadata || {}).dup
    new_metadata.delete('status')
    update!(metadata: new_metadata)
  end

  # Scopes for status filtering
  scope :coming_soon, -> { where("metadata->>'status' = ?", 'coming_soon') }
  scope :beta, -> { where("metadata->>'status' = ?", 'beta') }
  scope :available, -> { where("metadata->>'status' IS NULL OR metadata->>'status' = ?", 'available') }

  # Find the entity-specific version of this integration, or self if already entity-specific
  # Prefer entity-owned integrations over globals for actual use
  def self.find_for_use(identifier, entity)
    # First try to find entity-owned version
    owned = owned_by_entity(entity).find_by(slug: identifier) ||
            owned_by_entity(entity).find_by(id: identifier) ||
            owned_by_entity(entity).find_by(name: identifier)
    return owned if owned

    # Fall back to global/public (for truly shared integrations like no-auth public APIs)
    for_entity(entity).find_by(slug: identifier) ||
      for_entity(entity).find_by(id: identifier) ||
      for_entity(entity).find_by(name: identifier)
  end

  # Create an entity-specific copy of a global template
  def instantiate_for_entity(entity, user, overrides = {})
    raise "Cannot instantiate a non-global integration" unless global?
    
    # Check if entity already has this integration
    existing = Integration.owned_by_entity(entity).find_by(slug: slug)
    return existing if existing

    # Create a copy for the entity
    Integration.create!(
      entity: entity,
      created_by: user,
      name: overrides[:name] || name,
      slug: overrides[:slug] || slug,
      description: overrides[:description] || description,
      category: category,
      auth_type: auth_type,
      api_base_url: overrides[:api_base_url] || api_base_url,
      auth_config: overrides[:auth_config] || {},  # Entity must provide their own credentials
      metadata: metadata.merge(template_id: id),  # Track which template it came from
      allowed_hosts: allowed_hosts,
      is_active: true,
      is_verified: false,  # Entity's version starts unverified
      is_public: false
    )
  end
end
