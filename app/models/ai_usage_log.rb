class AiUsageLog < ApplicationRecord
  belongs_to :entity
  belongs_to :user
  belongs_to :scout_message, optional: true

  # Request types
  REQUEST_TYPES = %w[chat workflow tool_call image_generation].freeze

  validates :model, presence: true
  validates :request_type, inclusion: { in: REQUEST_TYPES }
  
  # Scopes for efficient querying
  scope :recent, -> { order(created_at: :desc) }
  scope :for_entity, ->(entity_id) { where(entity_id: entity_id) }
  scope :for_user, ->(user_id) { where(user_id: user_id) }
  scope :by_model, ->(model) { where(model: model) }
  scope :within, ->(time_range) { where('created_at > ?', time_range.ago) }
  scope :chat_requests, -> { where(request_type: 'chat') }
  
  # Callbacks
  before_save :calculate_totals
  
  # Class method to log AI usage
  def self.log_usage(entity:, user:, model:, input_tokens: 0, output_tokens: 0, 
                     duration_ms: nil, request_type: 'chat', scout_message: nil, metadata: {})
    create!(
      entity: entity,
      user: user,
      scout_message: scout_message,
      model: model,
      input_tokens: input_tokens,
      output_tokens: output_tokens,
      duration_ms: duration_ms,
      request_type: request_type,
      metadata: metadata
    )
  rescue => e
    Rails.logger.error "Failed to log AI usage: #{e.message}"
    nil
  end
  
  # Aggregate statistics
  def self.total_tokens_in_range(time_range)
    within(time_range).sum(:total_tokens)
  end
  
  def self.total_cost_in_range(time_range)
    within(time_range).sum(:cost_cents) / 100.0 # Convert cents to dollars
  end
  
  def self.average_duration_in_range(time_range)
    within(time_range).where.not(duration_ms: nil).average(:duration_ms)&.round(2) || 0
  end
  
  def self.usage_by_entity(time_range)
    within(time_range)
      .group(:entity_id)
      .sum(:total_tokens)
  end
  
  def self.usage_by_model(time_range)
    within(time_range)
      .group(:model)
      .sum(:total_tokens)
  end
  
  private
  
  def calculate_totals
    self.total_tokens = (input_tokens || 0) + (output_tokens || 0)
    
    # Calculate cost based on model pricing
    self.cost_cents = calculate_cost_for_model
  end
  
  def calculate_cost_for_model
    # Pricing per million tokens in cents
    pricing = case model
    when /claude-3-5-sonnet|claude-sonnet-3.5/i
      { input: 300, output: 1500 } # $3/M input, $15/M output
    when /claude-3-opus/i
      { input: 1500, output: 7500 } # $15/M input, $75/M output
    when /claude-3-haiku/i
      { input: 25, output: 125 } # $0.25/M input, $1.25/M output
    when /gpt-4/i
      { input: 1000, output: 3000 } # ~$10/M input, $30/M output
    else
      { input: 300, output: 1500 } # Default to Sonnet pricing
    end
    
    input_cost = (input_tokens.to_f / 1_000_000) * pricing[:input]
    output_cost = (output_tokens.to_f / 1_000_000) * pricing[:output]
    
    (input_cost + output_cost).round(4)
  end
end




