# frozen_string_literal: true

require "test_helper"

class ContributionRewardCalculatorTest < ActiveSupport::TestCase
  # === POOL-BASED REWARD MODEL ===

  test "calculate_pool_share distributes daily pool proportionally" do
    result = ContributionRewardCalculator.calculate_pool_share(
      your_points: 100,
      total_points_today: 1000
    )

    daily_pool = ContributionRewardCalculator.current_daily_emission
    expected_tokens = daily_pool * 0.10  # 10% of pool

    assert_equal expected_tokens.round(4), result[:tokens]
    assert_equal 10.0, result[:share_percentage]
    assert_equal 100, result[:points]
    assert_equal 1000, result[:total_points_today]
  end

  test "calculate_pool_share returns zero for no points" do
    result = ContributionRewardCalculator.calculate_pool_share(
      your_points: 0,
      total_points_today: 1000
    )

    assert_equal 0, result[:tokens]
    assert_equal 0, result[:points]
  end

  test "calculate_pool_share returns zero for no total points" do
    result = ContributionRewardCalculator.calculate_pool_share(
      your_points: 100,
      total_points_today: 0
    )

    assert_equal 0, result[:tokens]
  end

  test "calculate_pool_share handles sole contributor" do
    result = ContributionRewardCalculator.calculate_pool_share(
      your_points: 100,
      total_points_today: 100  # You're the only one
    )

    daily_pool = ContributionRewardCalculator.current_daily_emission
    
    assert_equal daily_pool.round(4), result[:tokens]
    assert_equal 100.0, result[:share_percentage]
  end

  # === REFERRAL REWARDS ===

  test "calculate_referral_reward with email only" do
    result = ContributionRewardCalculator.calculate_referral_reward(
      emails_sent: 5,
      signups: 0,
      conversions: 0
    )

    # 5 emails × 1 point = 5 points
    assert_equal 5, result[:points]
    assert_equal({ emails: 5, signups: 0, conversions: 0 }, result[:breakdown])
  end

  test "calculate_referral_reward with signups" do
    result = ContributionRewardCalculator.calculate_referral_reward(
      emails_sent: 5,
      signups: 2,
      conversions: 0
    )

    # 5 emails × 1 + 2 signups × 5 = 15 points
    assert_equal 15, result[:points]
    assert_equal({ emails: 5, signups: 10, conversions: 0 }, result[:breakdown])
  end

  test "calculate_referral_reward with conversions" do
    result = ContributionRewardCalculator.calculate_referral_reward(
      emails_sent: 3,
      signups: 2,
      conversions: 1
    )

    # 3×1 + 2×5 + 1×10 = 23 points
    assert_equal 23, result[:points]
    assert_equal({ emails: 3, signups: 10, conversions: 10 }, result[:breakdown])
  end

  test "calculate_referral_reward calculates tokens when total provided" do
    result = ContributionRewardCalculator.calculate_referral_reward(
      emails_sent: 5,
      signups: 2,
      conversions: 1,
      total_referral_points_today: 100
    )

    # 5 + 10 + 10 = 25 points / 100 total = 25% of pool
    assert_equal 25, result[:points]
    assert_equal 25.0, result[:share_percentage]
    assert result[:tokens] > 0
  end

  # === SALES REWARDS ===

  test "calculate_sales_reward returns points for users signed up" do
    result = ContributionRewardCalculator.calculate_sales_reward(
      users_signed_up: 10
    )

    assert_equal 10, result[:points]
    assert_nil result[:tokens]  # Not calculated until end of period
  end

  test "calculate_sales_reward calculates tokens when total provided" do
    result = ContributionRewardCalculator.calculate_sales_reward(
      users_signed_up: 50,
      total_users_today: 500
    )

    # 50 users / 500 total = 10% of pool
    assert_equal 50, result[:points]
    assert_equal 10.0, result[:share_percentage]
    assert result[:tokens] > 0
  end

  # === BOUNTY REWARDS ===

  test "calculate_bounty_reward returns points equal to bounty value" do
    result = ContributionRewardCalculator.calculate_bounty_reward(
      bounty_points: 150
    )

    assert_equal 150, result[:points]
    assert_nil result[:tokens]
  end

  test "calculate_bounty_reward calculates tokens when total provided" do
    result = ContributionRewardCalculator.calculate_bounty_reward(
      bounty_points: 100,
      total_bounty_points_today: 1000
    )

    assert_equal 100, result[:points]
    assert_equal 10.0, result[:share_percentage]
    assert result[:tokens] > 0
  end

  # === COMBINED REWARDS ===

  test "calculate_combined_reward uses total points pool" do
    result = ContributionRewardCalculator.calculate_combined_reward(
      your_points: 500,  # Combination of sales + bounties
      total_points_today: 5000
    )

    assert_equal 500, result[:points]
    assert_equal 10.0, result[:share_percentage]
    
    daily_pool = ContributionRewardCalculator.current_daily_emission
    expected = daily_pool * 0.10
    assert_equal expected.round(4), result[:tokens]
  end

  # === DAILY EMISSION & HALVING ===

  test "current_daily_emission applies halving multiplier" do
    current = ContributionRewardCalculator.current_daily_emission
    base = ContributionRewardCalculator::BASE_DAILY_EMISSION
    multiplier = ContributionRewardCalculator.current_halving_multiplier

    assert_equal base * multiplier, current
  end

  test "halving multiplier decreases over time" do
    multiplier = ContributionRewardCalculator.current_halving_multiplier
    
    # Should be 1.0 or less (decreasing over years)
    assert multiplier <= 1.0
    assert multiplier > 0
  end

  # === STATS & TRANSPARENCY ===

  test "stats returns comprehensive model info" do
    stats = ContributionRewardCalculator.stats

    assert stats[:daily_emission] > 0
    assert stats[:halving_multiplier].present?
    assert_equal "pool_based_organic", stats[:model]
    assert stats[:rules].present?
    assert stats[:current_decay_rate].present?
  end

  test "stats includes referral point values" do
    stats = ContributionRewardCalculator.stats

    assert stats[:rules][:referrals].present?
    assert stats[:rules][:referrals].include?("1 email")
    assert stats[:rules][:referrals].include?("signup")
    assert stats[:rules][:referrals].include?("conversion")
  end

  test "estimate_tokens_per_point calculates ratio" do
    estimate = ContributionRewardCalculator.estimate_tokens_per_point(
      average_daily_points: 1000
    )

    daily_emission = ContributionRewardCalculator.current_daily_emission
    expected = daily_emission / 1000.0

    assert_equal expected, estimate
  end

  # === EDGE CASES ===

  test "handles negative points gracefully" do
    result = ContributionRewardCalculator.calculate_pool_share(
      your_points: -10,
      total_points_today: 100
    )

    assert_equal 0, result[:tokens]
  end

  test "handles fractional points" do
    result = ContributionRewardCalculator.calculate_pool_share(
      your_points: 50.5,
      total_points_today: 100
    )

    assert result[:tokens] > 0
    assert_equal 50.5, result[:share_percentage]
  end

  test "referral points constants are correct" do
    points = ContributionRewardCalculator::REFERRAL_POINTS
    
    assert_equal 1, points[:email_sent]
    assert_equal 5, points[:signup]
    assert_equal 10, points[:conversion]
    assert_equal 2, points[:active_month]
  end

  # === INTEGRATION WITH PLATFORM ECONOMICS ===

  test "stats includes current platform decay rate" do
    stats = ContributionRewardCalculator.stats
    platform_rate = PlatformEconomicsService.current_decay_rate

    assert_equal platform_rate, stats[:current_decay_rate]
  end
end
