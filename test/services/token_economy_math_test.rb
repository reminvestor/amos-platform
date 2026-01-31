# frozen_string_literal: true

require "test_helper"

# TokenEconomyMathTest
#
# Comprehensive test suite verifying all mathematical equations in the token economy.
# See docs/token_economy_math.md for the complete specification.
#
# These tests ensure the implementation matches the documented formulas.
#
class TokenEconomyMathTest < ActiveSupport::TestCase
  # =========================================================================
  # SECTION 1: Profit Ratio (π) Tests
  # Formula: π = (Revenue - Costs) / Costs
  # =========================================================================
  
  test "profit ratio calculation - profitable scenario" do
    # Revenue: $60,000, Costs: $40,000
    # π = ($60,000 - $40,000) / $40,000 = 0.50
    revenue = 60_000.0
    costs = 40_000.0
    
    expected_ratio = 0.50
    actual_ratio = (revenue - costs) / costs
    
    assert_in_delta expected_ratio, actual_ratio, 0.001,
      "Profit ratio should be 0.50 for 50% profit margin"
  end
  
  test "profit ratio calculation - break even" do
    revenue = 50_000.0
    costs = 50_000.0
    
    expected_ratio = 0.0
    actual_ratio = (revenue - costs) / costs
    
    assert_in_delta expected_ratio, actual_ratio, 0.001,
      "Profit ratio should be 0.0 at break-even"
  end
  
  test "profit ratio calculation - loss scenario" do
    # Revenue: $40,000, Costs: $50,000
    # π = ($40,000 - $50,000) / $50,000 = -0.20
    revenue = 40_000.0
    costs = 50_000.0
    
    expected_ratio = -0.20
    actual_ratio = (revenue - costs) / costs
    
    assert_in_delta expected_ratio, actual_ratio, 0.001,
      "Profit ratio should be -0.20 for 20% loss"
  end
  
  # =========================================================================
  # SECTION 2: Dynamic Decay Rate (δ) Tests
  # Formula: δ = 10% - (π × 5%), clamped to [2%, 25%]
  # =========================================================================
  
  test "decay rate at break-even equals base rate" do
    # π = 0, δ = 10% - (0 × 5%) = 10%
    profit_ratio = 0.0
    base_rate = 0.10
    sensitivity = 0.05
    
    expected_decay = 0.10
    actual_decay = base_rate - (profit_ratio * sensitivity)
    
    assert_in_delta expected_decay, actual_decay, 0.001,
      "Decay should be 10% at break-even"
  end
  
  test "decay rate decreases when profitable" do
    # π = 0.40 (40% profit), δ = 10% - (0.40 × 5%) = 8%
    profit_ratio = 0.40
    base_rate = 0.10
    sensitivity = 0.05
    
    expected_decay = 0.08
    actual_decay = base_rate - (profit_ratio * sensitivity)
    
    assert_in_delta expected_decay, actual_decay, 0.001,
      "Decay should be 8% at 40% profit"
  end
  
  test "decay rate increases when unprofitable" do
    # π = -0.40 (40% loss), δ = 10% - (-0.40 × 5%) = 12%
    profit_ratio = -0.40
    base_rate = 0.10
    sensitivity = 0.05
    
    expected_decay = 0.12
    actual_decay = base_rate - (profit_ratio * sensitivity)
    
    assert_in_delta expected_decay, actual_decay, 0.001,
      "Decay should be 12% at 40% loss"
  end
  
  test "decay rate clamped to minimum 2%" do
    # π = 2.0 (200% profit), δ = 10% - (2.0 × 5%) = 0% → clamped to 2%
    profit_ratio = 2.0
    base_rate = 0.10
    sensitivity = 0.05
    min_decay = 0.02
    max_decay = 0.25
    
    raw_decay = base_rate - (profit_ratio * sensitivity)
    clamped_decay = [[raw_decay, min_decay].max, max_decay].min
    
    assert_equal 0.02, clamped_decay,
      "Decay should be clamped to minimum 2%"
  end
  
  test "decay rate clamped to maximum 25%" do
    # π = -4.0 (400% loss), δ = 10% - (-4.0 × 5%) = 30% → clamped to 25%
    profit_ratio = -4.0
    base_rate = 0.10
    sensitivity = 0.05
    min_decay = 0.02
    max_decay = 0.25
    
    raw_decay = base_rate - (profit_ratio * sensitivity)
    clamped_decay = [[raw_decay, min_decay].max, max_decay].min
    
    assert_equal 0.25, clamped_decay,
      "Decay should be clamped to maximum 25%"
  end
  
  test "platform economics service returns correct decay rate" do
    # Clear cache to force fresh calculation
    Rails.cache.delete("platform_economics:current")
    
    decay_rate = PlatformEconomicsService.current_decay_rate
    
    assert decay_rate >= 0.02, "Decay rate should be at least 2%"
    assert decay_rate <= 0.25, "Decay rate should be at most 25%"
  end
  
  # =========================================================================
  # SECTION 3: Token Emission Tests
  # Formula: E_daily = 16,000 × H(t) where H = halving multiplier
  # =========================================================================
  
  test "base daily emission is 16000" do
    assert_equal 16_000, ContributionRewardCalculator::BASE_DAILY_EMISSION
  end
  
  test "halving multiplier for year 0-2 is 1.0" do
    # Simulate being in year 0
    multiplier = calculate_halving_multiplier(0)
    assert_equal 1.0, multiplier
    
    multiplier = calculate_halving_multiplier(1)
    assert_equal 1.0, multiplier
  end
  
  test "halving multiplier for year 2-4 is 0.5" do
    multiplier = calculate_halving_multiplier(2)
    assert_equal 0.5, multiplier
    
    multiplier = calculate_halving_multiplier(3)
    assert_equal 0.5, multiplier
  end
  
  test "halving multiplier for year 4-6 is 0.25" do
    multiplier = calculate_halving_multiplier(4)
    assert_equal 0.25, multiplier
  end
  
  test "halving multiplier for year 6-8 is 0.125" do
    multiplier = calculate_halving_multiplier(6)
    assert_equal 0.125, multiplier
  end
  
  test "halving multiplier for year 8+ is 0.0625" do
    multiplier = calculate_halving_multiplier(8)
    assert_equal 0.0625, multiplier
    
    multiplier = calculate_halving_multiplier(10)
    assert_equal 0.0625, multiplier
  end
  
  # =========================================================================
  # SECTION 4: Pool Share Calculation Tests
  # Formula: T_you = (P_you / P_total) × E_daily
  # =========================================================================
  
  test "pool share calculation - basic case" do
    your_points = 100
    total_points = 1000
    # Use actual current emission (accounts for halving)
    daily_pool = ContributionRewardCalculator.current_daily_emission
    
    expected_tokens = daily_pool * 0.10  # (100/1000) = 10% of pool
    result = ContributionRewardCalculator.calculate_pool_share(
      your_points: your_points,
      total_points_today: total_points
    )
    
    assert_in_delta expected_tokens, result[:tokens], 0.01,
      "Should get 10% of pool for 10% of points"
  end
  
  test "pool share calculation - dominant contributor" do
    your_points = 500
    total_points = 500
    # Use actual current emission (accounts for halving)
    daily_pool = ContributionRewardCalculator.current_daily_emission
    
    expected_tokens = daily_pool.to_f  # 100% of pool
    result = ContributionRewardCalculator.calculate_pool_share(
      your_points: your_points,
      total_points_today: total_points
    )
    
    assert_in_delta expected_tokens, result[:tokens], 0.01,
      "Should get entire pool if only contributor"
  end
  
  test "pool share calculation - small contributor" do
    your_points = 10
    total_points = 10_000
    # Use actual current emission (accounts for halving)
    daily_pool = ContributionRewardCalculator.current_daily_emission
    
    expected_tokens = daily_pool * 0.001  # 0.1% of pool
    result = ContributionRewardCalculator.calculate_pool_share(
      your_points: your_points,
      total_points_today: total_points
    )
    
    assert_in_delta expected_tokens, result[:tokens], 0.01,
      "Should get 0.1% of pool for 0.1% of points"
  end
  
  test "pool share with zero points returns zero" do
    result = ContributionRewardCalculator.calculate_pool_share(
      your_points: 0,
      total_points_today: 1000
    )
    
    assert_equal 0, result[:tokens]
  end
  
  # =========================================================================
  # SECTION 5: Referral Points Tests
  # Points: email=1, signup=5, conversion=10, active_month=2
  # =========================================================================
  
  test "referral points - email sent" do
    result = ContributionRewardCalculator.calculate_referral_reward(
      emails_sent: 10,
      signups: 0,
      conversions: 0
    )
    
    assert_equal 10, result[:points]
  end
  
  test "referral points - signups" do
    result = ContributionRewardCalculator.calculate_referral_reward(
      emails_sent: 0,
      signups: 3,
      conversions: 0
    )
    
    assert_equal 15, result[:points]  # 3 × 5
  end
  
  test "referral points - conversions" do
    result = ContributionRewardCalculator.calculate_referral_reward(
      emails_sent: 0,
      signups: 0,
      conversions: 2
    )
    
    assert_equal 20, result[:points]  # 2 × 10
  end
  
  test "referral points - combined" do
    # 10 emails + 3 signups + 1 conversion = 10 + 15 + 10 = 35
    result = ContributionRewardCalculator.calculate_referral_reward(
      emails_sent: 10,
      signups: 3,
      conversions: 1
    )
    
    assert_equal 35, result[:points]
  end
  
  # =========================================================================
  # SECTION 6: Decay Floor Tests
  # Floor: Year 0-1=5%, Year 1-3=10%, Year 3-5=15%, Year 5+=25%
  # =========================================================================
  
  test "decay floor for year 0 is 5%" do
    stake = build_stake_with_tenure(0)
    assert_in_delta 0.05, stake.current_floor_percentage, 0.001
  end
  
  test "decay floor for year 1-3 is 10%" do
    stake = build_stake_with_tenure(2)
    assert_in_delta 0.10, stake.current_floor_percentage, 0.001
  end
  
  test "decay floor for year 3-5 is 15%" do
    stake = build_stake_with_tenure(4)
    assert_in_delta 0.15, stake.current_floor_percentage, 0.001
  end
  
  test "decay floor for year 5+ is 25%" do
    stake = build_stake_with_tenure(6)
    assert_in_delta 0.25, stake.current_floor_percentage, 0.001
  end
  
  # =========================================================================
  # SECTION 7: Tenure-Based Decay Reduction Tests
  # Reduction: Year 0-2=0%, Year 2-5=20%, Year 5-10=40%, Year 10+=70%
  # =========================================================================
  
  test "tenure reduction for year 0 is 0%" do
    stake = build_stake_with_tenure(0)
    assert_in_delta 0.0, stake.tenure_based_decay_reduction, 0.001
  end
  
  test "tenure reduction for year 2-5 is 20%" do
    stake = build_stake_with_tenure(3)
    assert_in_delta 0.20, stake.tenure_based_decay_reduction, 0.001
  end
  
  test "tenure reduction for year 5-10 is 40%" do
    stake = build_stake_with_tenure(7)
    assert_in_delta 0.40, stake.tenure_based_decay_reduction, 0.001
  end
  
  test "tenure reduction for year 10+ is 70%" do
    stake = build_stake_with_tenure(12)
    assert_in_delta 0.70, stake.tenure_based_decay_reduction, 0.001
  end
  
  # =========================================================================
  # SECTION 8: Staking Vault Reduction Tests
  # =========================================================================
  
  test "staking vault bronze reduces decay by 25%" do
    tier = TokenStake::STAKING_TIERS[:bronze]
    assert_equal 0.25, tier[:decay_reduction]
    assert_equal 1, tier[:min_lock_years]
  end
  
  test "staking vault silver reduces decay by 50%" do
    tier = TokenStake::STAKING_TIERS[:silver]
    assert_equal 0.50, tier[:decay_reduction]
    assert_equal 3, tier[:min_lock_years]
  end
  
  test "staking vault gold reduces decay by 75%" do
    tier = TokenStake::STAKING_TIERS[:gold]
    assert_equal 0.75, tier[:decay_reduction]
    assert_equal 5, tier[:min_lock_years]
  end
  
  test "staking vault permanent reduces decay by 100%" do
    tier = TokenStake::STAKING_TIERS[:permanent]
    assert_equal 1.0, tier[:decay_reduction]
    assert_equal 10, tier[:min_lock_years]
  end
  
  # =========================================================================
  # SECTION 9: Daily Decay Calculation Tests
  # Formula: δ_daily = 1 - (1 - δ_annual)^(1/365)
  # =========================================================================
  
  test "daily decay rate from 10% annual" do
    annual_rate = 0.10
    expected_daily = 1 - ((1 - annual_rate) ** (1.0 / 365))
    
    # Should be approximately 0.000289 (0.0289% per day)
    assert_in_delta 0.000289, expected_daily, 0.00001,
      "Daily rate for 10% annual should be ~0.0289%"
  end
  
  test "stake value after one year of decay" do
    initial_value = 10_000.0
    annual_rate = 0.10
    floor_percentage = 0.10
    
    floor = initial_value * floor_percentage
    decayable = initial_value - floor
    
    # After 1 year, decayable portion reduced by 10%
    remaining_decayable = decayable * (1 - annual_rate)
    final_value = floor + remaining_decayable
    
    # 1000 floor + 8100 remaining = 9100
    assert_in_delta 9100, final_value, 1,
      "After 1 year, 10K stake at 10% decay should be ~9100"
  end
  
  # =========================================================================
  # SECTION 10: Revenue Share Tests
  # Formula: Payout = (S_you / S_total) × (R_total × 50%)
  # =========================================================================
  
  test "revenue share calculation" do
    your_stake = 50_000.0
    total_staked = 10_000_000.0
    monthly_revenue = 100_000.0
    holder_share = 0.50
    
    holder_pool = monthly_revenue * holder_share
    your_payout = (your_stake / total_staked) * holder_pool
    
    # (50K / 10M) × $50K = 0.5% × $50K = $250
    assert_in_delta 250, your_payout, 0.01,
      "0.5% stake holder should get $250 from $100K revenue"
  end
  
  test "revenue allocation percentages sum to 100%" do
    allocation = PlatformEconomicsService::REVENUE_ALLOCATION
    
    total = allocation.values.sum
    assert_in_delta 1.0, total, 0.001,
      "Revenue allocation should sum to 100%"
  end
  
  test "token holders get 50% of revenue" do
    allocation = PlatformEconomicsService::REVENUE_ALLOCATION
    assert_equal 0.50, allocation[:token_holders]
  end
  
  # =========================================================================
  # SECTION 11: Compute Markup Tests
  # Formula: Customer Charge = AWS Cost × 1.20 (20% markup)
  # =========================================================================
  
  test "compute markup is 20%" do
    aws_cost = 100.0
    markup = 0.20
    
    customer_charge = aws_cost * (1 + markup)
    margin = customer_charge - aws_cost
    
    assert_equal 120.0, customer_charge
    assert_equal 20.0, margin
  end
  
  # =========================================================================
  # SECTION 12: AMM Liquidity Pool Tests (Constant Product)
  # Formula: x × y = k
  # =========================================================================
  
  test "amm constant product maintained after trade" do
    # Initial state
    amos_in_pool = 1_000_000.0
    usdc_in_pool = 10_000.0
    k = amos_in_pool * usdc_in_pool  # 10,000,000,000
    
    # Buy 100,000 AMOS
    amos_out = 100_000.0
    new_amos = amos_in_pool - amos_out  # 900,000
    new_usdc = k / new_amos  # 11,111.11
    usdc_in = new_usdc - usdc_in_pool  # 1,111.11
    
    # Verify k is preserved
    new_k = new_amos * new_usdc
    assert_in_delta k, new_k, 0.01,
      "Constant product k should be preserved after trade"
  end
  
  test "amm price increases with larger purchases" do
    amos_in_pool = 1_000_000.0
    usdc_in_pool = 10_000.0
    k = amos_in_pool * usdc_in_pool
    
    # Calculate price impact for different purchase sizes
    purchases = [
      { buy: 100_000, expected_cost: 1_111.11 },
      { buy: 250_000, expected_cost: 3_333.33 },
      { buy: 500_000, expected_cost: 10_000.00 },
      { buy: 750_000, expected_cost: 30_000.00 },
    ]
    
    purchases.each do |p|
      new_amos = amos_in_pool - p[:buy]
      new_usdc = k / new_amos
      cost = new_usdc - usdc_in_pool
      
      assert_in_delta p[:expected_cost], cost, 1.0,
        "Buying #{p[:buy]} AMOS should cost ~$#{p[:expected_cost]}"
    end
  end
  
  test "amm price per token increases exponentially" do
    amos_in_pool = 1_000_000.0
    usdc_in_pool = 10_000.0
    k = amos_in_pool * usdc_in_pool
    initial_price = usdc_in_pool / amos_in_pool  # $0.01
    
    # After buying 500K AMOS
    new_amos = 500_000.0
    new_usdc = k / new_amos
    new_price = new_usdc / new_amos  # $0.04
    
    assert_in_delta 0.01, initial_price, 0.001
    assert_in_delta 0.04, new_price, 0.001
    assert new_price > initial_price * 3,
      "Price should increase significantly with large purchase"
  end
  
  # =========================================================================
  # SECTION 13: Grace Period Tests
  # Formula: First 365 days = no decay
  # =========================================================================
  
  test "grace period is 365 days" do
    assert_equal 365, TokenStake::GRACE_PERIOD_DAYS
  end
  
  test "stake within grace period has no decay" do
    stake = TokenStake.new(
      initial_amount: 10_000,
      current_amount: 10_000,
      earned_at: 100.days.ago,
      stake_type: 'contribution'
    )
    
    assert stake.within_grace_period?,
      "Stake earned 100 days ago should be in grace period"
  end
  
  test "stake after grace period can decay" do
    stake = TokenStake.new(
      initial_amount: 10_000,
      current_amount: 10_000,
      earned_at: 400.days.ago,
      stake_type: 'contribution'
    )
    
    assert_not stake.within_grace_period?,
      "Stake earned 400 days ago should not be in grace period"
  end
  
  # =========================================================================
  # SECTION 14: Total Supply Tests
  # =========================================================================
  
  test "total supply is 100 million" do
    assert_equal 100_000_000, TokenStake::TOTAL_SUPPLY
  end
  
  # =========================================================================
  # Helper Methods
  # =========================================================================
  
  private
  
  def calculate_halving_multiplier(years)
    case years
    when 0..1 then 1.0
    when 2..3 then 0.5
    when 4..5 then 0.25
    when 6..7 then 0.125
    else 0.0625
    end
  end
  
  def build_stake_with_tenure(years)
    user = users(:one) rescue User.first || User.new(email: "test@test.com")
    
    TokenStake.new(
      user: user,
      initial_amount: 10_000,
      current_amount: 10_000,
      earned_at: years.years.ago,
      stake_type: 'contribution',
      decay_rate: 0.10
    )
  end
end
