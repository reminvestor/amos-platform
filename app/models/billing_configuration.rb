# frozen_string_literal: true

# System-wide billing configuration for AMOS Work Tokens
# Work tokens are based on ACTUAL AWS/provider costs, then marked up by uplift_percentage
#
# 1 work token = $0.00001 (0.001 cents)
# So $1 = 100,000 work tokens (before uplift)
# With 20% uplift, users pay $1.20 for $1 of raw compute
#
class BillingConfiguration < ApplicationRecord
  # Work token conversion: 1 work token = this many dollars
  WORK_TOKEN_VALUE = 0.00001  # $0.00001 per work token = 100,000 tokens per dollar

  # Model pricing per million tokens (in dollars) - Bedrock pricing
  MODEL_PRICING = {
    # Claude Sonnet 4.5 / 3.5
    'claude-sonnet-4-5' => { input: 3.00, output: 15.00 },
    'claude-4-5-sonnet' => { input: 3.00, output: 15.00 },
    'claude-3-5-sonnet' => { input: 3.00, output: 15.00 },
    'claude-sonnet-3.5' => { input: 3.00, output: 15.00 },
    
    # Claude Opus
    'claude-3-opus' => { input: 15.00, output: 75.00 },
    'claude-opus-4' => { input: 15.00, output: 75.00 },
    
    # Claude Haiku
    'claude-3-haiku' => { input: 0.25, output: 1.25 },
    'claude-3-5-haiku' => { input: 0.80, output: 4.00 },
    
    # GPT models
    'gpt-4o' => { input: 2.50, output: 10.00 },
    'gpt-4' => { input: 10.00, output: 30.00 },
    'gpt-4-turbo' => { input: 10.00, output: 30.00 },
    'gpt-3.5-turbo' => { input: 0.50, output: 1.50 },
    
    # Default fallback
    'default' => { input: 3.00, output: 15.00 }
  }.freeze

  # SES pricing
  SES_COST_PER_EMAIL = 0.0001  # $0.0001 per email ($0.10 per 1000)
  
  # S3 pricing (per GB per month)
  S3_COST_PER_GB_MONTH = 0.023  # $0.023 per GB/month

  # Validations
  validates :name, presence: true, uniqueness: true
  validates :uplift_percentage, presence: true, 
            numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 200 }
  validates :free_tokens_on_signup, :default_auto_replenish_amount_usd, :default_monthly_limit_usd,
            numericality: { greater_than_or_equal_to: 0 }

  # Scopes
  scope :active, -> { where(is_active: true) }

  # Get the current active configuration
  def self.current
    active.order(created_at: :desc).first || create_default!
  end

  # Create default configuration if none exists
  def self.create_default!
    create!(
      name: 'default',
      uplift_percentage: 20.0,
      purchase_tiers: default_purchase_tiers,
      free_tokens_on_signup: 200_000,  # ~$2 worth of compute
      default_auto_replenish_amount_usd: 20,
      default_monthly_limit_usd: 100,
      is_active: true
    )
  end

  def self.default_purchase_tiers
    # Based on 100,000 work tokens = $1 raw cost
    # With 20% uplift built into pricing, $20 buys ~$16.67 of raw compute = 1,666,667 tokens
    # We round to nice numbers and add bonuses for larger purchases
    [
      { 'amount_usd' => 20, 'tokens' => 2_000_000, 'bonus_tokens' => 0 },
      { 'amount_usd' => 50, 'tokens' => 5_500_000, 'bonus_tokens' => 500_000 },
      { 'amount_usd' => 100, 'tokens' => 12_000_000, 'bonus_tokens' => 2_000_000 },
      { 'amount_usd' => 200, 'tokens' => 26_000_000, 'bonus_tokens' => 6_000_000 }
    ]
  end

  # Calculate work tokens for AI usage based on ACTUAL model pricing
  def calculate_ai_work_tokens(input_tokens:, output_tokens:, model:)
    pricing = model_pricing_for(model)
    
    # Calculate raw cost in dollars
    input_cost = (input_tokens.to_f / 1_000_000) * pricing[:input]
    output_cost = (output_tokens.to_f / 1_000_000) * pricing[:output]
    raw_cost_usd = input_cost + output_cost
    
    # Convert to work tokens (before uplift)
    base_work_tokens = (raw_cost_usd / WORK_TOKEN_VALUE).round
    
    # Apply uplift
    apply_uplift(base_work_tokens)
  end

  # Get the raw cost in cents for AI usage (for tracking)
  def calculate_ai_raw_cost_cents(input_tokens:, output_tokens:, model:)
    pricing = model_pricing_for(model)
    input_cost = (input_tokens.to_f / 1_000_000) * pricing[:input]
    output_cost = (output_tokens.to_f / 1_000_000) * pricing[:output]
    ((input_cost + output_cost) * 100).round(4)  # Convert to cents
  end

  # Calculate work tokens for email sending
  def calculate_email_work_tokens(email_count:)
    raw_cost_usd = email_count * SES_COST_PER_EMAIL
    base_work_tokens = (raw_cost_usd / WORK_TOKEN_VALUE).round
    apply_uplift(base_work_tokens)
  end

  # Calculate work tokens for storage
  def calculate_storage_work_tokens(megabytes:)
    gigabytes = megabytes / 1024.0
    raw_cost_usd = gigabytes * S3_COST_PER_GB_MONTH
    base_work_tokens = (raw_cost_usd / WORK_TOKEN_VALUE).round
    apply_uplift(base_work_tokens)
  end

  # Calculate work tokens for other AWS compute
  # cost_usd is the raw AWS cost in dollars
  def calculate_other_compute_work_tokens(cost_usd:)
    base_work_tokens = (cost_usd / WORK_TOKEN_VALUE).round
    apply_uplift(base_work_tokens)
  end

  # Legacy method - convert cost_cents to cost_usd
  def calculate_other_compute_work_tokens_from_cents(cost_cents:)
    calculate_other_compute_work_tokens(cost_usd: cost_cents / 100.0)
  end

  # Get model pricing
  def model_pricing_for(model)
    return MODEL_PRICING['default'] unless model.present?
    
    normalized = model.to_s.downcase
    
    # Try exact match first
    MODEL_PRICING.each do |key, pricing|
      return pricing if normalized.include?(key) || key.include?(normalized)
    end
    
    # Default fallback
    MODEL_PRICING['default']
  end

  # Apply uplift percentage
  def apply_uplift(base_tokens)
    ((base_tokens * (1 + uplift_percentage / 100.0))).round
  end

  # Get purchase tier for amount
  def tier_for_amount(amount_usd)
    sorted_tiers = purchase_tiers.sort_by { |t| -t['amount_usd'] }
    sorted_tiers.find { |t| amount_usd >= t['amount_usd'] } || sorted_tiers.last
  end

  # Calculate tokens for purchase amount
  def tokens_for_purchase(amount_usd)
    tier = tier_for_amount(amount_usd)
    return { tokens: 0, bonus: 0, total: 0 } unless tier
    
    base_tokens = tier['tokens']
    bonus_tokens = tier['bonus_tokens'] || 0
    
    # Pro-rate if amount is higher than tier
    if amount_usd > tier['amount_usd']
      rate = base_tokens.to_f / tier['amount_usd']
      base_tokens = (amount_usd * rate).round
    end
    
    { tokens: base_tokens, bonus: bonus_tokens, total: base_tokens + bonus_tokens }
  end

  # Convert work tokens to approximate USD value (what user paid)
  def tokens_to_usd(tokens)
    # Work tokens include uplift, so divide by (1 + uplift) to get raw, then convert
    raw_tokens = tokens / (1 + uplift_percentage / 100.0)
    raw_usd = raw_tokens * WORK_TOKEN_VALUE
    (raw_usd * (1 + uplift_percentage / 100.0)).round(2)
  end

  # Convert work tokens to raw cost (what we pay AWS)
  def tokens_to_raw_cost_usd(tokens)
    raw_tokens = tokens / (1 + uplift_percentage / 100.0)
    (raw_tokens * WORK_TOKEN_VALUE).round(4)
  end

  # Convert USD to work tokens
  def usd_to_tokens(usd)
    result = tokens_for_purchase(usd)
    result[:total]
  end

  # Helper to show cost breakdown for a model
  def self.model_cost_info(model)
    config = current
    pricing = config.model_pricing_for(model)
    
    {
      model: model,
      input_per_million: "$#{pricing[:input]}",
      output_per_million: "$#{pricing[:output]}",
      example_1k_input_500_output: {
        raw_cost: ((1000.0 / 1_000_000 * pricing[:input]) + (500.0 / 1_000_000 * pricing[:output])).round(6),
        work_tokens: config.calculate_ai_work_tokens(input_tokens: 1000, output_tokens: 500, model: model)
      }
    }
  end
end
