# frozen_string_literal: true

# ContributionRewardCalculator determines token rewards using a
# POOL-BASED RELATIVE SCORING model (no USD denomination)
#
# How it works:
# 1. Daily/weekly emission pool = fixed AMOS allocated for period
# 2. Each contribution earns "points" based on type & complexity
# 3. Your reward = (your points / total platform points) × emission pool
#
# This ensures:
# - No dependency on external prices (no USD reference)
# - Collaborative distribution (everyone shares the pool)
# - Self-balancing economics
# - Simple to understand: more contribution = bigger slice
class ContributionRewardCalculator
  # Base contribution points (internal scoring, not USD)
  BASE_POINTS = {
    # Code contributions
    feature: 500,           # Major feature implementation
    bug_fix: 100,           # Bug fix
    security_fix: 300,      # Security vulnerability fix
    refactor: 150,          # Code refactoring
    documentation: 50,      # Documentation improvement
    code_review: 25,        # Code review participation

    # Distribution (sales/referrals)
    affiliate_sale: 200,    # Brought in a paying customer
    enterprise_deal: 500,   # Enterprise sale
    referral: 50,           # Referred user who became active

    # Community
    support_ticket: 25,     # Resolved community question
    content_post: 50,       # Created helpful content
    tutorial: 150,          # Created comprehensive tutorial
    translation: 100,       # Translated content to new language
    
    # Governance
    proposal: 100,          # Submitted governance proposal
    vote_participation: 10  # Participated in governance vote
  }.freeze

  # Complexity multipliers (1-5 scale)
  COMPLEXITY_MULTIPLIERS = {
    1 => 0.5,   # Trivial
    2 => 0.75,  # Simple
    3 => 1.0,   # Standard
    4 => 1.5,   # Complex
    5 => 2.5    # Exceptional
  }.freeze

  # Daily emission pool from treasury (decreases via halving)
  # 60M tokens for rewards over ~10 years
  # Year 1: ~16,000 AMOS/day → Year 10: ~1,000 AMOS/day
  BASE_DAILY_EMISSION = 16_000

  # SUCCESS REWARD MULTIPLIERS (flip of old logic)
  # When token price rises, we INCREASE recognition, not decrease it
  # When price falls, we maintain baseline (protect contributors)
  SUCCESS_MULTIPLIERS = {
    # price_threshold => { point_multiplier, rationale }
    struggling: { max_price: 0.01, multiplier: 1.0 },     # Baseline protection
    building: { max_price: 0.05, multiplier: 1.1 },       # Slight boost
    growing: { max_price: 0.20, multiplier: 1.25 },       # Success bonus
    thriving: { max_price: 0.50, multiplier: 1.5 },       # Share the success!
    soaring: { max_price: Float::INFINITY, multiplier: 2.0 }  # Big success = big rewards
  }.freeze

  # Minimum token reward (prevent dust amounts)
  MINIMUM_TOKENS = 10

  # Maximum single reward (prevent gaming)
  MAXIMUM_TOKENS = 100_000

  class << self
    # Calculate token reward for a contribution
    # @param contribution_type [Symbol] Type of contribution
    # @param complexity [Integer] 1-5 complexity scale
    # @param period_contributions [Integer] Total contributions this period (for pool calc)
    # @return [Hash] Reward details including token amount
    def calculate(contribution_type:, complexity: 3, period_contributions: nil)
      # Get base points for contribution type
      base_points = BASE_POINTS[contribution_type.to_sym]
      if base_points.nil?
        Rails.logger.warn "[REWARD_CALC] Unknown contribution type: #{contribution_type}"
        base_points = 50  # Default
      end

      # Apply complexity multiplier
      complexity_mult = COMPLEXITY_MULTIPLIERS[complexity] || 1.0
      contribution_points = base_points * complexity_mult

      # Apply halving schedule
      halving_mult = TokenStake.current_halving_multiplier
      adjusted_points = contribution_points * halving_mult

      # Apply success multiplier (rewards success, not punishes it)
      success_mult = success_multiplier
      final_points = adjusted_points * success_mult

      # Calculate share of daily emission pool
      # If we don't have period data, use single contribution model
      daily_emission = current_daily_emission
      
      if period_contributions && period_contributions > 0
        # Pool-based: your share of the daily pool
        share_of_pool = final_points.to_f / period_contributions
        tokens = (daily_emission * share_of_pool).round(4)
      else
        # Single contribution model: points directly convert
        # This is used when calculating individual rewards
        tokens = point_to_token_ratio * final_points
      end

      # Apply bounds
      final_tokens = [[tokens, MINIMUM_TOKENS].max, MAXIMUM_TOKENS].min.round(4)

      {
        tokens: final_tokens,
        points: final_points.round(2),
        contribution_type: contribution_type,
        halving_multiplier: halving_mult,
        success_multiplier: success_mult,
        complexity_multiplier: complexity_mult,
        breakdown: {
          base_points: base_points,
          after_complexity: (base_points * complexity_mult).round(2),
          after_halving: (base_points * complexity_mult * halving_mult).round(2),
          after_success: final_points.round(2),
          token_value: final_tokens
        }
      }
    end

    # Calculate daily emission pool with halving applied
    def current_daily_emission
      BASE_DAILY_EMISSION * TokenStake.current_halving_multiplier
    end

    # Simple point-to-token ratio for individual calculations
    # Approximately: 1 point = 1 AMOS (with halving applied)
    def point_to_token_ratio
      # Ratio decreases with halving
      TokenStake.current_halving_multiplier
    end

    # Get current success multiplier (rewards success)
    def success_multiplier
      price = current_token_price

      SUCCESS_MULTIPLIERS.each do |_band, config|
        return config[:multiplier] if price < config[:max_price]
      end

      1.0  # Fallback
    end

    # Get current success band name
    def current_success_band
      price = current_token_price

      SUCCESS_MULTIPLIERS.each do |band, config|
        return band if price < config[:max_price]
      end

      :growing
    end

    # Get current token price (for success multiplier only)
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

    # Calculate reward for a sales commission (percentage-based)
    def calculate_sales_reward(sale_value:, is_enterprise: false)
      # Sales rewards are based on bringing value to platform
      # More valuable sales = more points
      base_type = is_enterprise ? :enterprise_deal : :affiliate_sale
      
      # Scale points by sale value (every $100 = base points)
      value_multiplier = [(sale_value / 100.0), 0.5].max
      scaled_complexity = [[value_multiplier.ceil, 5].min, 1].max

      calculate(contribution_type: base_type, complexity: scaled_complexity)
    end

    # Calculate total points earned in a period
    def total_period_points(start_date: 1.day.ago, end_date: Time.current)
      TokenStake.earned_between(start_date, end_date).sum(:initial_amount)
    end

    # Get summary stats for transparency
    def stats
      {
        daily_emission: current_daily_emission,
        halving_multiplier: TokenStake.current_halving_multiplier,
        success_band: current_success_band,
        success_multiplier: success_multiplier,
        token_price_reference: current_token_price,
        base_points: BASE_POINTS,
        examples: example_calculations
      }
    end

    private

    def example_calculations
      {
        feature_standard: calculate(contribution_type: :feature, complexity: 3),
        feature_exceptional: calculate(contribution_type: :feature, complexity: 5),
        bug_fix_simple: calculate(contribution_type: :bug_fix, complexity: 2),
        affiliate_sale: calculate(contribution_type: :affiliate_sale, complexity: 3),
        enterprise_deal: calculate(contribution_type: :enterprise_deal, complexity: 4)
      }
    end
  end
end
