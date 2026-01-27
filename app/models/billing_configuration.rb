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

  # Model pricing per million tokens (in dollars) - AWS BEDROCK pricing
  # Source: BedrockService::AVAILABLE_MODELS and AWS Bedrock pricing page
  # These are the actual prices we pay AWS, not Anthropic direct pricing
  # Updated: December 2024
  MODEL_PRICING = {
    # ============================================
    # Claude 4.5 Series (via Bedrock)
    # ============================================
    # Claude Sonnet 4.5: $3.00/M input, $15.00/M output
    'claude-sonnet-4-5' => { input: 3.00, output: 15.00 },
    'claude-4-5-sonnet' => { input: 3.00, output: 15.00 },
    
    # Claude Haiku 4.5: $1.00/M input, $5.00/M output (AWS Bedrock Jan 2026)
    'claude-haiku-4-5' => { input: 1.00, output: 5.00 },
    'claude-4-5-haiku' => { input: 1.00, output: 5.00 },
    'claude-haiku-4-5-20251001' => { input: 1.00, output: 5.00 },
    
    # Claude Opus 4.5: $5.00/M input, $25.00/M output (AWS Bedrock Jan 2026)
    'claude-opus-4-5' => { input: 5.00, output: 25.00 },
    'claude-4-5-opus' => { input: 5.00, output: 25.00 },
    
    # ============================================
    # Claude 4 Series (via Bedrock)
    # ============================================
    # Claude Opus 4.1: $15.00/M input, $75.00/M output
    'claude-opus-4-1' => { input: 15.00, output: 75.00 },
    'claude-4-1-opus' => { input: 15.00, output: 75.00 },
    
    # Claude Opus 4: $15.00/M input, $75.00/M output
    'claude-opus-4' => { input: 15.00, output: 75.00 },
    'claude-4-opus' => { input: 15.00, output: 75.00 },
    
    # Claude Sonnet 4: $3.00/M input, $15.00/M output
    'claude-sonnet-4' => { input: 3.00, output: 15.00 },
    'claude-4-sonnet' => { input: 3.00, output: 15.00 },
    
    # ============================================
    # Claude 3.5 Series (via Bedrock)
    # ============================================
    # Claude 3.5 Sonnet: $3.00/M input, $15.00/M output
    'claude-3-5-sonnet' => { input: 3.00, output: 15.00 },
    'claude-sonnet-3-5' => { input: 3.00, output: 15.00 },
    
    # Claude 3.5 Haiku: $0.80/M input, $4.00/M output
    'claude-3-5-haiku' => { input: 0.80, output: 4.00 },
    'claude-haiku-3-5' => { input: 0.80, output: 4.00 },
    
    # ============================================
    # Claude 3 Series (via Bedrock)
    # ============================================
    # Claude 3 Opus: $15.00/M input, $75.00/M output
    'claude-3-opus' => { input: 15.00, output: 75.00 },
    'claude-opus-3' => { input: 15.00, output: 75.00 },
    
    # Claude 3 Sonnet: $3.00/M input, $15.00/M output
    'claude-3-sonnet' => { input: 3.00, output: 15.00 },
    'claude-sonnet-3' => { input: 3.00, output: 15.00 },
    
    # Claude 3 Haiku: $0.25/M input, $1.25/M output
    'claude-3-haiku' => { input: 0.25, output: 1.25 },
    'claude-haiku-3' => { input: 0.25, output: 1.25 },
    
    # ============================================
    # Mistral models (via Bedrock)
    # ============================================
    # Mistral Large 3: $0.50/M input, $1.50/M output (AWS Bedrock Jan 2026)
    'mistral-large-3' => { input: 0.50, output: 1.50 },
    
    # Mistral Large 2: $0.50/M input, $1.50/M output (AWS Bedrock Jan 2026)
    'mistral-large-2' => { input: 0.50, output: 1.50 },
    
    # Ministral 3B: $0.04/M input, $0.10/M output
    'ministral-3b' => { input: 0.04, output: 0.10 },
    
    # Ministral 8B: $0.10/M input, $0.20/M output
    'ministral-8b' => { input: 0.10, output: 0.20 },
    
    # ============================================
    # DeepSeek models (via Bedrock)
    # ============================================
    # DeepSeek V3.1: $0.58/M input, $1.68/M output (AWS Bedrock Jan 2026)
    'deepseek-v3' => { input: 0.58, output: 1.68 },
    'deepseek-v3.1' => { input: 0.58, output: 1.68 },
    'deepseek' => { input: 0.58, output: 1.68 },
    
    # DeepSeek R1: $1.35/M input, $5.40/M output (AWS Bedrock Jan 2026) - reasoning model
    'deepseek-r1' => { input: 1.35, output: 5.40 },
    
    # ============================================
    # NVIDIA Nemotron models (via Bedrock)
    # ============================================
    # Nemotron Nano 2: $0.06/M input, $0.23/M output (AWS Bedrock Jan 2026) - CHEAPEST!
    'nemotron-nano-2' => { input: 0.06, output: 0.23 },
    'nemotron-nano-9b' => { input: 0.06, output: 0.23 },
    'nemotron-nano' => { input: 0.06, output: 0.23 },
    
    # Nemotron Nano 12B VL: $0.20/M input, $0.40/M output
    'nemotron-nano-12b-vl' => { input: 0.20, output: 0.40 },
    
    # ============================================
    # Qwen models (via Bedrock)
    # ============================================
    # Qwen 3 32B: $0.15/M input, $0.60/M output (AWS Bedrock Jan 2026) - our default model
    'qwen-3-32b' => { input: 0.15, output: 0.60 },
    'qwen3-32b' => { input: 0.15, output: 0.60 },
    
    # Qwen 3 Coder 30B: $0.20/M input, $0.20/M output (Bedrock pricing)
    'qwen3-coder-30b' => { input: 0.20, output: 0.20 },
    'qwen-3-coder-30b' => { input: 0.20, output: 0.20 },
    
    # Qwen3-Next 80B: $0.15/M input, $1.20/M output - DEFAULT MODEL (131K context)
    'qwen3-next-80b' => { input: 0.15, output: 1.20 },
    'qwen-3-next-80b' => { input: 0.15, output: 1.20 },
    
    # Qwen3-VL 235B: $0.80/M input, $1.50/M output - multimodal
    'qwen3-vl-235b' => { input: 0.80, output: 1.50 },
    
    # Qwen 2.5 Coder 32B: $0.20/M input, $0.20/M output (Bedrock pricing)
    'qwen-2-5-72b' => { input: 0.20, output: 0.20 },
    'qwen-2-5-coder-32b' => { input: 0.20, output: 0.20 },
    
    # ============================================
    # Meta Llama models (via Bedrock)
    # ============================================
    # Llama 3.3 70B Instruct: $0.72/M input, $0.72/M output
    'llama-3-3-70b' => { input: 0.72, output: 0.72 },
    'llama-3.3-70b' => { input: 0.72, output: 0.72 },
    'meta-llama-3-3-70b' => { input: 0.72, output: 0.72 },
    
    # Llama 3.2 90B Vision: $0.90/M input, $0.90/M output (Bedrock pricing)
    'llama-3-2-90b' => { input: 0.90, output: 0.90 },
    'llama-3.2-90b' => { input: 0.90, output: 0.90 },
    'meta-llama-3-2-90b' => { input: 0.90, output: 0.90 },
    
    # ============================================
    # Legacy Claude models
    # ============================================
    'claude-2-1' => { input: 8.00, output: 24.00 },
    'claude-2-0' => { input: 8.00, output: 24.00 },
    'claude-instant' => { input: 0.80, output: 2.40 },
    
    # ============================================
    # GPT models (for reference if ever used)
    # ============================================
    'gpt-4o' => { input: 2.50, output: 10.00 },
    'gpt-4' => { input: 10.00, output: 30.00 },
    'gpt-4-turbo' => { input: 10.00, output: 30.00 },
    'gpt-3.5-turbo' => { input: 0.50, output: 1.50 },
    
    # Default fallback (use Sonnet pricing)
    'default' => { input: 3.00, output: 15.00 }
  }.freeze

  # ============================================
  # AWS SES Pricing (as of Dec 2024)
  # ============================================
  # Outbound email: $0.10 per 1,000 emails = $0.0001 per email
  # Attachments: $0.12 per GB (tracked separately if needed)
  # Inbound email: $0.10 per 1,000 emails (if we receive emails)
  SES_COST_PER_EMAIL = 0.0001  # $0.0001 per email ($0.10 per 1000)
  SES_ATTACHMENT_COST_PER_GB = 0.12  # $0.12 per GB of attachments
  
  # ============================================
  # AWS S3 Pricing (as of Dec 2024)
  # ============================================
  # Standard storage: $0.023 per GB/month
  S3_COST_PER_GB_MONTH = 0.023  # $0.023 per GB/month
  
  # ============================================
  # API Call Pricing
  # ============================================
  # External API calls (HubSpot, Salesforce, etc.) have no direct AWS cost
  # but we charge a small operational overhead for processing
  # This is configurable via the api_call_rate column in the database
  # Default: 0.1 work tokens per call = $0.000001 per call (negligible)
  API_CALL_DEFAULT_RATE = 0.1  # work tokens per API call (fallback if not in DB)

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
    # With 20% uplift: $1.20 buys 100,000 tokens, so $1 buys ~83,333 tokens
    # NO VOLUME DISCOUNTS - margins are already slim at 20% markup
    # All tiers use the same rate: ~83,333 tokens per dollar
    [
      { 'amount_usd' => 20, 'tokens' => 1_670_000, 'bonus_tokens' => 0 },   # 20 × 83,333
      { 'amount_usd' => 50, 'tokens' => 4_170_000, 'bonus_tokens' => 0 },   # 50 × 83,333
      { 'amount_usd' => 100, 'tokens' => 8_330_000, 'bonus_tokens' => 0 },  # 100 × 83,333
      { 'amount_usd' => 200, 'tokens' => 16_670_000, 'bonus_tokens' => 0 }  # 200 × 83,333
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

  # Calculate work tokens for API calls (external integrations)
  # These have no direct AWS cost - just operational overhead
  # Uses the api_call_rate column from DB, or default fallback
  def calculate_api_work_tokens(call_count:)
    rate = api_call_rate || API_CALL_DEFAULT_RATE
    base_work_tokens = (call_count * rate).round
    apply_uplift(base_work_tokens)
  end

  # Calculate work tokens for email with attachments
  def calculate_email_with_attachments_work_tokens(email_count:, attachment_size_gb: 0)
    email_cost = email_count * SES_COST_PER_EMAIL
    attachment_cost = attachment_size_gb * SES_ATTACHMENT_COST_PER_GB
    raw_cost_usd = email_cost + attachment_cost
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
