class IntegrationEmbedding < ApplicationRecord
  belongs_to :entity
  belongs_to :integration
  
  has_neighbors :embedding
  
  validates :resource_type, presence: true
  validates :resource_id, presence: true
  validates :content, presence: true
  
  scope :by_integration, ->(integration) { where(integration: integration) }
  scope :by_resource_type, ->(type) { where(resource_type: type) }
  
  # Common resource types
  RESOURCE_TYPES = {
    quickbooks: %w[customer invoice estimate payment item vendor bill],
    hubspot: %w[contact company deal ticket],
    stripe: %w[customer subscription invoice payment product],
    salesforce: %w[account contact opportunity lead case]
  }.freeze
  
  # Store integration data with embedding
  def self.store_resource(entity:, integration:, resource:)
    content = build_content(integration, resource)
    embedding = generate_embedding(content) # Would call embedding service
    
    create!(
      entity: entity,
      integration: integration,
      resource_type: resource[:type],
      resource_id: resource[:id],
      content: content,
      embedding: embedding,
      metadata: resource[:metadata] || {}
    )
  end
  
  # Search across all integration data
  def self.search_integrations(query_embedding, entity_id:, integration_ids: nil, limit: 10)
    scope = where(entity_id: entity_id)
    scope = scope.where(integration_id: integration_ids) if integration_ids.present?
    
    scope.includes(:integration)
         .nearest_neighbors(:embedding, query_embedding, distance: "cosine")
         .limit(limit)
  end
  
  private
  
  def self.build_content(integration, resource)
    # Format resource data into searchable text
    # This would be customized per integration type
    case integration.slug
    when 'quickbooks'
      "#{resource[:type].capitalize}: #{resource[:name]} (#{resource[:id]})\n" \
      "#{resource[:description]}\n" \
      "Details: #{resource[:details]}"
    when 'hubspot'
      "#{resource[:type].capitalize}: #{resource[:name]}\n" \
      "Properties: #{resource[:properties]}"
    else
      resource.to_json
    end
  end
  
  def self.generate_embedding(content)
    # Placeholder - would call embedding service (OpenAI/Bedrock)
    # EmbeddingService.new.generate(content)
    nil
  end
end
