# frozen_string_literal: true

# System-wide billing configuration for AMOS Work Tokens
# Managed by admins to set uplift percentages and token rates
class BillingConfiguration < ApplicationRecord
  # Validations
  validates :name, presence: true, uniqueness: true
  validates :uplift_percentage, presence: true, 
            numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }
  validates :ai_tokens_rate, :email_rate, :storage_rate_mb, :api_call_rate, :other_compute_rate,
            numericality: { greater_than: 0 }
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
      ai_tokens_rate: 1.0,
      email_rate: 10.0,
      storage_rate_mb: 1.0,
      api_call_rate: 0.1,
      other_compute_rate: 100.0,
      model_multipliers: default_model_multipliers,
      purchase_tiers: default_purchase_tiers,
      free_tokens_on_signup: 200_000,
      default_auto_replenish_amount_usd: 20,
      default_monthly_limit_usd: 100,
      is_active: true
    )
  end

  def self.default_model_multipliers
    {
      'claude-sonnet-4-5' => 1.0,
      'claude-4-5-sonnet' => 1.0,
      'claude-3-5-sonnet' => 1.0,
      'claude-3-opus' => 3.0,
      'claude-3-haiku' => 0.1,
      'claude-3-5-haiku' => 0.15,
      'gpt-4o' => 0.8,
      'gpt-4' => 2.0
    }
  end

  def self.default_purchase_tiers
    [
      { 'amount_usd' => 20, 'tokens' => 200_000, 'bonus_tokens' => 0 },
      { 'amount_usd' => 50, 'tokens' => 550_000, 'bonus_tokens' => 50_000 },
      { 'amount_usd' => 100, 'tokens' => 1_200_000, 'bonus_tokens' => 200_000 },
      { 'amount_usd' => 200, 'tokens' => 2_600_000, 'bonus_tokens' => 600_000 }
    ]
  end

  # Calculate work tokens for AI usage
  def calculate_ai_work_tokens(input_tokens:, output_tokens:, model:)
    # Get model multiplier
    multiplier = model_multiplier_for(model)
    
    # Output tokens cost more than input (typically 3x)
    base_tokens = (input_tokens * ai_tokens_rate) + (output_tokens * ai_tokens_rate * 3)
    
    # Apply model multiplier
    work_tokens = (base_tokens * multiplier).round
    
    # Apply uplift
    apply_uplift(work_tokens)
  end

  # Calculate work tokens for email sending
  def calculate_email_work_tokens(email_count:)
    work_tokens = (email_count * email_rate).round
    apply_uplift(work_tokens)
  end

  # Calculate work tokens for storage
  def calculate_storage_work_tokens(megabytes:)
    work_tokens = (megabytes * storage_rate_mb).round
    apply_uplift(work_tokens)
  end

  # Calculate work tokens for API calls
  def calculate_api_work_tokens(call_count:)
    work_tokens = (call_count * api_call_rate).round
    apply_uplift(work_tokens)
  end

  # Calculate work tokens for other AWS compute (Lambda, Textract, Rekognition, etc.)
  # cost_cents is the raw AWS cost in cents
  def calculate_other_compute_work_tokens(cost_cents:)
    # Rate is work tokens per cent of AWS cost
    work_tokens = (cost_cents * other_compute_rate / 100.0).round
    apply_uplift(work_tokens)
  end

  # Get model multiplier
  def model_multiplier_for(model)
    return 1.0 unless model.present?
    
    # Normalize model name for lookup
    normalized = model.to_s.downcase.gsub(/[^a-z0-9-]/, '')
    
    # Try exact match first
    return model_multipliers[model] if model_multipliers[model]
    
    # Try partial matches
    model_multipliers.each do |key, value|
      return value if normalized.include?(key.downcase) || key.downcase.include?(normalized)
    end
    
    # Default to 1.0
    1.0
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
    return { tokens: 0, bonus: 0 } unless tier
    
    base_tokens = tier['tokens']
    bonus_tokens = tier['bonus_tokens'] || 0
    
    # Pro-rate if amount is higher than tier
    if amount_usd > tier['amount_usd']
      rate = base_tokens.to_f / tier['amount_usd']
      base_tokens = (amount_usd * rate).round
      # Bonus doesn't pro-rate
    end
    
    { tokens: base_tokens, bonus: bonus_tokens, total: base_tokens + bonus_tokens }
  end

  # Convert work tokens to approximate USD value
  def tokens_to_usd(tokens)
    # Use the base tier rate
    base_tier = purchase_tiers.find { |t| t['amount_usd'] == 20 } || purchase_tiers.first
    rate = base_tier['tokens'].to_f / base_tier['amount_usd']
    (tokens / rate).round(2)
  end

  # Convert USD to work tokens
  def usd_to_tokens(usd)
    result = tokens_for_purchase(usd)
    result[:total]
  end
end

