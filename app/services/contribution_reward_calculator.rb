# frozen_string_literal: true

# ContributionRewardCalculator determines token rewards based on:
# - Contribution type and complexity
# - Current token price (USD-denominated fairness)
# - Halving schedule
# - Platform operating conditions
#
# This ensures contributors are fairly compensated regardless of:
# - Token price fluctuations
# - Compute cost changes
# - Market conditions
class ContributionRewardCalculator
  # Base USD values for contribution types (pre-multipliers)
  BASE_VALUES_USD = {
    # Code contributions
    feature: 500,           # $500 for a new feature
    bug_fix: 100,           # $100 for bug fix
    security_fix: 300,      # $300 for security fix
    refactor: 150,          # $150 for refactoring
    documentation: 50,      # $50 for docs
    code_review: 25,        # $25 per review

    # Distribution (sales/referrals)
    affiliate_sale: 0.10,   # 10% of sale value
    enterprise_deal: 0.15,  # 15% of deal value
    referral: 20,           # $20 per converted referral

    # Community
    support_ticket: 10,     # $10 per resolved ticket
    content_post: 25,       # $25 per content piece
    tutorial: 75,           # $75 per tutorial
    translation: 100,       # $100 per language
    
    # Governance
    proposal: 50,           # $50 for governance proposal
    vote_participation: 5   # $5 per vote (encourages participation)
  }.freeze

  # Complexity multipliers (1-5 scale)
  COMPLEXITY_MULTIPLIERS = {
    1 => 0.5,   # Trivial
    2 => 0.75,  # Simple
    3 => 1.0,   # Standard
    4 => 1.5,   # Complex
    5 => 2.5    # Exceptional
  }.freeze

  # Price bands for dynamic adjustment
  PRICE_BANDS = {
    very_low: { max_price: 0.01, multiplier: 2.0 },    # Under $0.01 - boost rewards
    low: { max_price: 0.05, multiplier: 1.5 },          # $0.01-$0.05
    normal: { max_price: 0.20, multiplier: 1.0 },       # $0.05-$0.20 (target range)
    high: { max_price: 0.50, multiplier: 0.75 },        # $0.20-$0.50
    very_high: { max_price: Float::INFINITY, multiplier: 0.5 }  # Over $0.50
  }.freeze

  # Minimum token reward (prevent dust amounts)
  MINIMUM_TOKENS = 10

  # Maximum single reward (prevent gaming)
  MAXIMUM_TOKENS = 1_000_000

  class << self
    # Calculate token reward for a contribution
    # @param contribution_type [Symbol] Type of contribution
    # @param complexity [Integer] 1-5 complexity scale
    # @param value [Numeric] Optional value (for sales/referrals)
    # @return [Hash] Reward details including token amount
    def calculate(contribution_type:, complexity: 3, value: nil)
      base_usd = get_base_usd_value(contribution_type, value)
      complexity_mult = COMPLEXITY_MULTIPLIERS[complexity] || 1.0
      halving_mult = TokenStake.current_halving_multiplier
      price_mult = price_band_multiplier

      # Calculate USD value after multipliers
      usd_value = base_usd * complexity_mult

      # Convert to tokens at current price
      token_price = current_token_price
      raw_tokens = usd_value / token_price

      # Apply halving and price band adjustments
      adjusted_tokens = raw_tokens * halving_mult * price_mult

      # Apply bounds
      final_tokens = [
        [adjusted_tokens, MINIMUM_TOKENS].max,
        MAXIMUM_TOKENS
      ].min.round(4)

      {
        tokens: final_tokens,
        usd_value: usd_value.round(2),
        token_price: token_price,
        halving_multiplier: halving_mult,
        price_band_multiplier: price_mult,
        complexity_multiplier: complexity_mult,
        breakdown: {
          base_usd: base_usd,
          after_complexity: base_usd * complexity_mult,
          raw_tokens: raw_tokens.round(4),
          after_halving: (raw_tokens * halving_mult).round(4),
          after_price_band: final_tokens
        }
      }
    end

    # Get current token price in USD
    def current_token_price
      # Try to get live price from Jupiter
      price = JupiterSwapService.amos_price_usdc
      return price if price && price > 0

      # Fallback to configured price or default
      ENV.fetch('AMOS_DEFAULT_PRICE', '0.05').to_f
    rescue => e
      Rails.logger.warn "[REWARD_CALC] Failed to get price: #{e.message}"
      0.05  # Default $0.05
    end

    # Determine price band multiplier
    def price_band_multiplier
      price = current_token_price

      PRICE_BANDS.each do |_band, config|
        return config[:multiplier] if price < config[:max_price]
      end

      1.0  # Fallback
    end

    # Get current price band name
    def current_price_band
      price = current_token_price

      PRICE_BANDS.each do |band, config|
        return band if price < config[:max_price]
      end

      :normal
    end

    # Calculate reward for a sales commission
    def calculate_sales_reward(sale_amount:, is_enterprise: false)
      type = is_enterprise ? :enterprise_deal : :affiliate_sale
      rate = BASE_VALUES_USD[type]
      value = sale_amount * rate

      calculate(contribution_type: type, value: value, complexity: 3)
    end

    # Get summary stats for transparency
    def stats
      {
        token_price_usd: current_token_price,
        price_band: current_price_band,
        price_band_multiplier: price_band_multiplier,
        halving_multiplier: TokenStake.current_halving_multiplier,
        base_values_usd: BASE_VALUES_USD,
        examples: {
          feature_standard: calculate(contribution_type: :feature, complexity: 3),
          feature_exceptional: calculate(contribution_type: :feature, complexity: 5),
          bug_fix_simple: calculate(contribution_type: :bug_fix, complexity: 2),
          sale_100: calculate_sales_reward(sale_amount: 100),
          sale_1000_enterprise: calculate_sales_reward(sale_amount: 1000, is_enterprise: true)
        }
      }
    end

    private

    def get_base_usd_value(contribution_type, value)
      base = BASE_VALUES_USD[contribution_type.to_sym]

      if base.nil?
        Rails.logger.warn "[REWARD_CALC] Unknown contribution type: #{contribution_type}"
        return 50  # Default $50
      end

      # For percentage-based rewards (sales), use provided value
      if base < 1 && value
        value  # The 'value' should already be the calculated amount
      else
        base
      end
    end
  end
end
