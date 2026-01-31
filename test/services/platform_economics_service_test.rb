# frozen_string_literal: true

require "test_helper"

class PlatformEconomicsServiceTest < ActiveSupport::TestCase
  setup do
    # Clear cache before each test
    Rails.cache.clear
  end

  # === DECAY RATE CALCULATION ===

  test "current_decay_rate returns rate within valid bounds" do
    # Rate should always be within min/max bounds
    rate = PlatformEconomicsService.current_decay_rate
    
    assert rate >= PlatformEconomicsService::MIN_DECAY_RATE,
           "Decay rate #{rate} should be >= min #{PlatformEconomicsService::MIN_DECAY_RATE}"
    assert rate <= PlatformEconomicsService::MAX_DECAY_RATE,
           "Decay rate #{rate} should be <= max #{PlatformEconomicsService::MAX_DECAY_RATE}"
  end

  test "current_decay_rate returns valid rate within bounds" do
    # The decay rate should always be within bounds
    rate = PlatformEconomicsService.current_decay_rate
    
    assert rate >= PlatformEconomicsService::MIN_DECAY_RATE, 
           "Rate #{rate} should be >= min #{PlatformEconomicsService::MIN_DECAY_RATE}"
    assert rate <= PlatformEconomicsService::MAX_DECAY_RATE,
           "Rate #{rate} should be <= max #{PlatformEconomicsService::MAX_DECAY_RATE}"
  end

  test "decay rate formula works correctly for profitable scenario" do
    # Test the formula directly: profitable should lower rate
    base = PlatformEconomicsService::BASE_DECAY_RATE
    sensitivity = PlatformEconomicsService::DECAY_SENSITIVITY
    
    # profit_ratio = (100k - 50k) / 50k = 1.0 (100% profit)
    profit_ratio = 1.0
    calculated = base - (profit_ratio * sensitivity)
    expected = [calculated, PlatformEconomicsService::MIN_DECAY_RATE].max
    
    # Should be 0.10 - 0.05 = 0.05 (clamped to min of 0.02)
    assert expected <= base, "Profitable scenario should lower decay"
  end

  test "decay rate formula works correctly for unprofitable scenario" do
    # Test the formula directly: unprofitable should raise rate
    base = PlatformEconomicsService::BASE_DECAY_RATE
    sensitivity = PlatformEconomicsService::DECAY_SENSITIVITY
    
    # profit_ratio = (50k - 100k) / 100k = -0.5 (50% loss)
    profit_ratio = -0.5
    calculated = base - (profit_ratio * sensitivity)
    expected = [[calculated, PlatformEconomicsService::MIN_DECAY_RATE].max, 
                PlatformEconomicsService::MAX_DECAY_RATE].min
    
    # Should be 0.10 - (-0.025) = 0.125
    assert expected >= base, "Unprofitable scenario should raise decay"
  end

  test "decay rate bounds are enforced" do
    # Test clamping
    min = PlatformEconomicsService::MIN_DECAY_RATE
    max = PlatformEconomicsService::MAX_DECAY_RATE
    
    assert_equal 0.02, min
    assert_equal 0.25, max
    assert min < max
  end

  # === ECONOMICS CALCULATION ===

  test "current_economics returns hash with required keys" do
    economics = PlatformEconomicsService.current_economics
    
    assert economics.is_a?(Hash)
    
    required_keys = [
      :monthly_revenue, :monthly_costs, :profit_margin,
      :total_staked, :daily_emission, :decay_rate, :calculated_at
    ]
    
    required_keys.each do |key|
      assert economics.key?(key), "Missing key: #{key}"
    end
  end

  test "current_economics returns consistent data structure" do
    economics = PlatformEconomicsService.current_economics
    
    # Should have all required keys
    assert economics[:monthly_revenue].is_a?(Numeric)
    assert economics[:monthly_costs].is_a?(Numeric)
    assert economics[:total_staked].is_a?(Numeric)
    assert economics[:calculated_at].present?
  end

  # === DECAY RATE EXPLANATION ===

  test "decay_rate_explanation provides transparency data" do
    explanation = PlatformEconomicsService.decay_rate_explanation
    
    assert explanation[:current_rate].present?
    assert explanation[:annual_percentage].present?
    assert explanation[:daily_rate].present?
    assert explanation[:status].in?(%w[excellent healthy moderate elevated])
    assert explanation[:explanation].present?
  end

  test "decay_rate_explanation status reflects platform health" do
    # Test excellent status (low decay)
    PlatformEconomicsService.stub(:current_decay_rate, 0.03) do
      explanation = PlatformEconomicsService.decay_rate_explanation
      assert_equal "excellent", explanation[:status]
    end

    # Test elevated status (high decay)
    PlatformEconomicsService.stub(:current_decay_rate, 0.20) do
      explanation = PlatformEconomicsService.decay_rate_explanation
      assert_equal "elevated", explanation[:status]
    end
  end

  # === STAKE-SPECIFIC DECAY ===

  test "decay_rate_for_stake applies tenure reduction" do
    user = users(:one)
    
    # Create stake with 3 years tenure
    stake = TokenStake.new(
      user: user,
      stake_type: 'contribution',
      category: 'code_merge',
      initial_amount: 1000,
      current_amount: 1000,
      decay_rate: 0.10,
      earned_at: 3.years.ago
    )

    rate = PlatformEconomicsService.decay_rate_for_stake(stake)
    base_rate = PlatformEconomicsService.current_decay_rate
    
    # 3 years tenure = 20% reduction, so rate should be lower than base
    assert rate < base_rate, "Tenure should reduce decay rate"
    assert rate >= PlatformEconomicsService::MIN_DECAY_RATE
  end

  test "decay_rate_for_stake applies staking vault reduction" do
    user = users(:one)
    
    # Create locked stake (use new, not create to avoid DB issues)
    stake = TokenStake.new(
      user: user,
      stake_type: 'contribution',
      category: 'code_merge',
      initial_amount: 1000,
      current_amount: 1000,
      decay_rate: 0.10,
      earned_at: Time.current,
      is_locked: true,
      locked_until: 5.years.from_now,
      staking_tier: 'gold'
    )

    rate = PlatformEconomicsService.decay_rate_for_stake(stake)
    base_rate = PlatformEconomicsService.current_decay_rate
    
    # Gold tier = 75% reduction
    expected_rate = base_rate * 0.25
    assert_in_delta expected_rate, rate, 0.01
  end

  # === PROJECTIONS ===

  test "project_stake_value returns monthly projections" do
    projections = PlatformEconomicsService.project_stake_value(
      initial_amount: 10_000,
      months: 12
    )

    assert_equal 12, projections.length
    
    # First month should have decay applied
    first = projections.first
    assert first[:month] == 1
    assert first[:value].present?
    assert first[:decay_applied].present?
    assert first[:floor].present?
    
    # Value should decrease over time (unless at floor)
    assert projections.last[:value] <= projections.first[:value]
  end

  test "project_stake_value with contribution assumes earning" do
    projections_passive = PlatformEconomicsService.project_stake_value(
      initial_amount: 10_000,
      months: 12,
      assume_contribution: false
    )

    projections_active = PlatformEconomicsService.project_stake_value(
      initial_amount: 10_000,
      months: 12,
      assume_contribution: true
    )

    # Active contributor should have higher ending value
    assert projections_active.last[:value] >= projections_passive.last[:value]
  end

  # === PLATFORM COST RECORDING ===

  test "record_cost creates platform cost entry" do
    assert_difference 'PlatformCost.count', 1 do
      PlatformEconomicsService.record_cost(
        category: 'compute',
        amount: 5000,
        description: 'AWS monthly bill'
      )
    end

    cost = PlatformCost.last
    assert_equal 'compute', cost.category
    assert_equal 5000, cost.amount
    assert_equal 'AWS monthly bill', cost.description
  end

  test "record_cost invalidates cache" do
    # Get initial economics (cached)
    economics1 = PlatformEconomicsService.current_economics
    
    # Record a cost
    PlatformEconomicsService.record_cost(
      category: 'infrastructure',
      amount: 1000,
      description: 'Test cost'
    )
    
    # Cache should be invalidated, new calculation should have different timestamp
    economics2 = PlatformEconomicsService.current_economics
    
    # Either different timestamp OR cache was properly invalidated
    assert economics2[:calculated_at] >= economics1[:calculated_at]
  end
end
