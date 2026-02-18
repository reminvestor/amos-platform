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
    # Pricing per million tokens in cents (AWS Bedrock pricing - Jan 2026)
    pricing = case model
    # Our primary models
    when /qwen3.*next.*80b|qwen-3-next-80b|qwen3-next-80b/i
      { input: 15, output: 120 }   # $0.15/M input, $1.20/M output - DEFAULT MODEL
    when /qwen.*3.*32b|qwen3.*32b/i
      { input: 15, output: 60 }    # $0.15/M input, $0.60/M output
    when /nemotron.*nano|nemotron-nano/i
      { input: 6, output: 23 }     # $0.06/M input, $0.23/M output (cheapest!)
    when /mistral.*large.*3|mistral-large-3/i
      { input: 50, output: 150 }   # $0.50/M input, $1.50/M output
    when /deepseek.*r1|deepseek-r1/i
      { input: 135, output: 540 }  # $1.35/M input, $5.40/M output
    when /deepseek.*v3|deepseek-v3|deepseek\.v3/i
      { input: 58, output: 168 }   # $0.58/M input, $1.68/M output
    # Claude 4.5 series
    when /claude.*haiku.*4.*5|claude-haiku-4-5/i
      { input: 100, output: 500 }  # $1.00/M input, $5.00/M output
    # Claude 4.6 series
    when /claude.*sonnet.*4.*6|claude-sonnet-4-6/i
      { input: 300, output: 1500 } # $3.00/M input, $15.00/M output
    when /claude.*opus.*4.*6|claude-opus-4-6/i
      { input: 500, output: 2500 } # $5.00/M input, $25.00/M output
    # Claude 4.5 series (legacy)
    when /claude.*sonnet.*4.*5|claude-sonnet-4-5/i
      { input: 300, output: 1500 } # $3.00/M input, $15.00/M output
    when /claude.*opus.*4.*5|claude-opus-4-5/i
      { input: 500, output: 2500 } # $5.00/M input, $25.00/M output
    # Claude 3.5 series (legacy)
    when /claude-3-5-sonnet|claude-sonnet-3.5/i
      { input: 300, output: 1500 } # $3/M input, $15/M output
    when /claude-3-5-haiku/i
      { input: 80, output: 400 }   # $0.80/M input, $4/M output
    # Claude 3 series (legacy)
    when /claude-3-opus/i
      { input: 1500, output: 7500 } # $15/M input, $75/M output
    when /claude-3-haiku/i
      { input: 25, output: 125 }    # $0.25/M input, $1.25/M output
    # GPT models
    when /gpt-4o/i
      { input: 250, output: 1000 } # $2.50/M input, $10/M output
    when /gpt-4/i
      { input: 1000, output: 3000 } # ~$10/M input, $30/M output
    else
      { input: 15, output: 120 } # Default to Qwen3-Next-80B (our default model)
    end
    
    input_cost = (input_tokens.to_f / 1_000_000) * pricing[:input]
    output_cost = (output_tokens.to_f / 1_000_000) * pricing[:output]
    
    (input_cost + output_cost).round(4)
  end
end




