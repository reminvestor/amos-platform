class ObservabilityEvent < ApplicationRecord
  belongs_to :entity, optional: true
  belongs_to :user, optional: true

  # Event types for observability
  EVENT_TYPES = %w[
    ai_request
    ai_response
    ai_error
    tool_call
    workflow_start
    workflow_complete
    workflow_error
    api_call
    integration_call
    integration_error
    tts_request
    stt_request
    cache_hit
    cache_miss
  ].freeze

  validates :event_type, presence: true, inclusion: { in: EVENT_TYPES }
  
  # Scopes
  scope :recent, -> { order(created_at: :desc) }
  scope :for_entity, ->(entity_id) { where(entity_id: entity_id) }
  scope :for_user, ->(user_id) { where(user_id: user_id) }
  scope :by_type, ->(type) { where(event_type: type) }
  scope :successful, -> { where(status: 'success') }
  scope :failed, -> { where(status: ['error', 'failed']) }
  scope :within, ->(time_range) { where('created_at > ?', time_range.ago) }
  
  # Helper methods
  def ai_event?
    event_type.in?(%w[ai_request ai_response ai_error])
  end
  
  def workflow_event?
    event_type.start_with?('workflow_')
  end
  
  def integration_event?
    event_type.start_with?('integration_')
  end
  
  def successful?
    status == 'success'
  end
  
  def failed?
    status.in?(%w[error failed])
  end
  
  # Extract common metadata fields
  def model_name
    metadata&.dig('model')
  end
  
  def tokens_used
    (metadata&.dig('input_tokens').to_i + metadata&.dig('output_tokens').to_i)
  end
  
  def cost
    metadata&.dig('cost')&.to_f || 0
  end
  
  # Class method to log events
  def self.log_event(event_type:, entity: nil, user: nil, resource: nil, 
                     status: 'success', duration_ms: nil, error_message: nil, metadata: {})
    create(
      event_type: event_type,
      entity: entity,
      user: user,
      resource_type: resource&.class&.name,
      resource_id: resource&.id,
      status: status,
      duration_ms: duration_ms,
      error_message: error_message,
      metadata: metadata
    )
  rescue => e
    Rails.logger.error "Failed to log observability event: #{e.message}"
    nil
  end
end
