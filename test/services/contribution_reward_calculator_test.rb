# frozen_string_literal: true

require "test_helper"

class ContributionRewardCalculatorTest < ActiveSupport::TestCase
  setup do
    ENV['AMOS_DEFAULT_PRICE'] = '0.10'  # $0.10 for success band testing
  end

  # === POOL-BASED REWARD CALCULATION ===

  test "calculates feature reward using points" do
    result = ContributionRewardCalculator.calculate(
      contribution_type: :feature,
      complexity: 3
    )

    assert result[:tokens] > 0
    assert_equal 500, result[:breakdown][:base_points]  # Base 500 points
    assert_equal 1.0, result[:complexity_multiplier]
    assert result[:points] > 0
  end

  test "complexity multiplier increases reward" do
    standard = ContributionRewardCalculator.calculate(
      contribution_type: :bug_fix,
      complexity: 3
    )

    exceptional = ContributionRewardCalculator.calculate(
      contribution_type: :bug_fix,
      complexity: 5
    )

    # Exceptional (2.5x) should give more than standard (1.0x)
    assert exceptional[:tokens] > standard[:tokens]
    assert_equal 2.5, exceptional[:complexity_multiplier]
  end

  test "minimum tokens enforced" do
    # Very small contribution
    result = ContributionRewardCalculator.calculate(
      contribution_type: :vote_participation,  # 10 base points
      complexity: 1  # 0.5x multiplier = 5 points
    )

    assert result[:tokens] >= ContributionRewardCalculator::MINIMUM_TOKENS
  end

  test "maximum tokens enforced" do
    result = ContributionRewardCalculator.calculate(
      contribution_type: :feature,
      complexity: 5
    )

    assert result[:tokens] <= ContributionRewardCalculator::MAXIMUM_TOKENS
  end

  # === SUCCESS MULTIPLIERS (REWARDING SUCCESS) ===

  test "success multiplier at low price gives baseline protection" do
    ENV['AMOS_DEFAULT_PRICE'] = '0.005'  # Very low

    multiplier = ContributionRewardCalculator.success_multiplier
    assert_equal 1.0, multiplier  # Baseline protection
    assert_equal :struggling, ContributionRewardCalculator.current_success_band
  end

  test "success multiplier increases when token thrives" do
    ENV['AMOS_DEFAULT_PRICE'] = '0.30'  # Thriving range

    multiplier = ContributionRewardCalculator.success_multiplier
    assert_equal 1.5, multiplier  # Share the success!
    assert_equal :thriving, ContributionRewardCalculator.current_success_band
  end

  test "success multiplier highest when soaring" do
    ENV['AMOS_DEFAULT_PRICE'] = '1.00'  # Soaring (>$0.50)

    multiplier = ContributionRewardCalculator.success_multiplier
    assert_equal 2.0, multiplier  # Big success = big rewards
    assert_equal :soaring, ContributionRewardCalculator.current_success_band
  end

  test "success multiplier at growing range gives bonus" do
    ENV['AMOS_DEFAULT_PRICE'] = '0.10'

    multiplier = ContributionRewardCalculator.success_multiplier
    assert_equal 1.25, multiplier  # Success bonus
    assert_equal :growing, ContributionRewardCalculator.current_success_band
  end

  # === SALES REWARDS ===

  test "calculates sales reward correctly" do
    result = ContributionRewardCalculator.calculate_sales_reward(
      sale_value: 1000,
      is_enterprise: false
    )

    # Should get affiliate sale points scaled by value
    assert result[:tokens] > 0
    assert_equal :affiliate_sale, result[:contribution_type]
  end

  test "enterprise deals get higher complexity scaling" do
    regular = ContributionRewardCalculator.calculate_sales_reward(
      sale_value: 1000,
      is_enterprise: false
    )

    enterprise = ContributionRewardCalculator.calculate_sales_reward(
      sale_value: 1000,
      is_enterprise: true
    )

    # Enterprise has higher base points (500 vs 200)
    assert enterprise[:tokens] > regular[:tokens]
  end

  # === DAILY EMISSION ===

  test "daily emission decreases with halving" do
    current_emission = ContributionRewardCalculator.current_daily_emission
    base_emission = ContributionRewardCalculator::BASE_DAILY_EMISSION
    halving_mult = TokenStake.current_halving_multiplier

    assert_equal base_emission * halving_mult, current_emission
  end

  # === STATS AND TRANSPARENCY ===

  test "stats returns comprehensive data" do
    stats = ContributionRewardCalculator.stats

    assert stats[:daily_emission] > 0
    assert stats[:success_band].present?
    assert stats[:halving_multiplier] > 0
    assert stats[:success_multiplier] > 0
    assert stats[:base_points].is_a?(Hash)
    assert stats[:examples].is_a?(Hash)
  end

  test "returns breakdown for transparency" do
    result = ContributionRewardCalculator.calculate(
      contribution_type: :feature,
      complexity: 3
    )

    assert_equal 500, result[:breakdown][:base_points]
    assert result[:breakdown][:after_complexity].present?
    assert result[:breakdown][:after_halving].present?
    assert result[:breakdown][:after_success].present?
    assert result[:breakdown][:token_value].present?
  end

  # === CONTRIBUTION TYPES ===

  test "all contribution types have base points" do
    ContributionRewardCalculator::BASE_POINTS.each do |type, points|
      result = ContributionRewardCalculator.calculate(
        contribution_type: type,
        complexity: 3
      )

      assert result[:tokens] > 0, "#{type} should return tokens"
      assert result[:points] > 0, "#{type} should return points"
    end
  end

  test "unknown contribution type uses default" do
    result = ContributionRewardCalculator.calculate(
      contribution_type: :unknown_type,
      complexity: 3
    )

    # Should use default 50 points
    assert result[:tokens] > 0
    assert_equal 50, result[:breakdown][:base_points]
  end
end
