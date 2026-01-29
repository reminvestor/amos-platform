# frozen_string_literal: true

require "test_helper"

class ContributionRewardCalculatorTest < ActiveSupport::TestCase
  setup do
    ENV['AMOS_DEFAULT_PRICE'] = '0.10'  # $0.10 for consistent testing
  end

  test "calculates feature reward at standard complexity" do
    result = ContributionRewardCalculator.calculate(
      contribution_type: :feature,
      complexity: 3
    )

    assert result[:tokens] > 0
    assert_equal 500.0, result[:usd_value]  # Base $500 * 1.0 complexity
    assert_equal 1.0, result[:complexity_multiplier]
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
    # Very small contribution at high token price
    ENV['AMOS_DEFAULT_PRICE'] = '10.0'  # $10 per token

    result = ContributionRewardCalculator.calculate(
      contribution_type: :vote_participation,  # $5 base
      complexity: 1  # 0.5x multiplier = $2.50
    )

    assert result[:tokens] >= ContributionRewardCalculator::MINIMUM_TOKENS
  end

  test "maximum tokens enforced" do
    ENV['AMOS_DEFAULT_PRICE'] = '0.0001'  # Very low price

    result = ContributionRewardCalculator.calculate(
      contribution_type: :feature,
      complexity: 5
    )

    assert result[:tokens] <= ContributionRewardCalculator::MAXIMUM_TOKENS
  end

  test "price band multiplier adjusts for low price" do
    # At very low price ($0.005), multiplier should boost rewards
    ENV['AMOS_DEFAULT_PRICE'] = '0.005'

    multiplier = ContributionRewardCalculator.price_band_multiplier
    assert_equal 2.0, multiplier  # very_low band
  end

  test "price band multiplier adjusts for high price" do
    ENV['AMOS_DEFAULT_PRICE'] = '0.30'

    multiplier = ContributionRewardCalculator.price_band_multiplier
    assert_equal 0.75, multiplier  # high band
  end

  test "price band normal range gives 1.0 multiplier" do
    ENV['AMOS_DEFAULT_PRICE'] = '0.10'

    multiplier = ContributionRewardCalculator.price_band_multiplier
    assert_equal 1.0, multiplier
  end

  test "calculates sales reward correctly" do
    result = ContributionRewardCalculator.calculate_sales_reward(
      sale_amount: 1000,
      is_enterprise: false
    )

    # 10% of $1000 = $100 value
    assert_equal 100.0, result[:usd_value]
    assert result[:tokens] > 0
  end

  test "enterprise deals get higher rate" do
    regular = ContributionRewardCalculator.calculate_sales_reward(
      sale_amount: 1000,
      is_enterprise: false
    )

    enterprise = ContributionRewardCalculator.calculate_sales_reward(
      sale_amount: 1000,
      is_enterprise: true
    )

    # Enterprise (15%) > Regular (10%)
    assert enterprise[:usd_value] > regular[:usd_value]
  end

  test "stats returns comprehensive data" do
    stats = ContributionRewardCalculator.stats

    assert stats[:token_price_usd] > 0
    assert stats[:price_band].present?
    assert stats[:halving_multiplier] > 0
    assert stats[:base_values_usd].is_a?(Hash)
    assert stats[:examples].is_a?(Hash)
  end

  test "returns breakdown for transparency" do
    result = ContributionRewardCalculator.calculate(
      contribution_type: :feature,
      complexity: 3
    )

    assert result[:breakdown][:base_usd] == 500
    assert result[:breakdown][:after_complexity].present?
    assert result[:breakdown][:raw_tokens].present?
  end
end
