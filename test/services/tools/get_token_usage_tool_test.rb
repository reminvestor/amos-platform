require 'test_helper'

class GetTokenUsageToolTest < ActiveSupport::TestCase
  setup do
    @entity = entities(:one)
    @user = users(:one)
    @tool = Tools::GetTokenUsageTool.new(
      entity: @entity,
      user: @user
    )
  end

  test "returns token usage information with healthy status" do
    @entity.update!(
      token_usage: 50_000,
      token_limit: 100_000,
      plan_tier: "starter",
      current_period_end: 1.month.from_now
    )

    result = @tool.execute({})

    assert result[:success]
    assert_equal 50_000, result[:usage_info][:token_usage]
    assert_equal 100_000, result[:usage_info][:token_limit]
    assert_equal 50_000, result[:usage_info][:tokens_remaining]
    assert_equal 50.0, result[:usage_info][:usage_percent]
    assert_equal "healthy", result[:usage_info][:status]
    assert_equal 0, result[:usage_info][:overage_tokens]
    assert_nil result[:usage_info][:estimated_overage_cost]
    assert_includes result[:message], "50,000 tokens remaining"
  end

  test "returns warning status when usage is above 70%" do
    @entity.update!(
      token_usage: 75_000,
      token_limit: 100_000,
      plan_tier: "starter"
    )

    result = @tool.execute({})

    assert result[:success]
    assert_equal 75.0, result[:usage_info][:usage_percent]
    assert_equal "warning", result[:usage_info][:status]
    assert_includes result[:message], "approaching your limit"
  end

  test "returns critical status when usage is above 90%" do
    @entity.update!(
      token_usage: 95_000,
      token_limit: 100_000,
      plan_tier: "starter"
    )

    result = @tool.execute({})

    assert result[:success]
    assert_equal 95.0, result[:usage_info][:usage_percent]
    assert_equal "critical", result[:usage_info][:status]
    assert_includes result[:message], "Consider upgrading your plan"
  end

  test "calculates overage tokens and cost" do
    @entity.update!(
      token_usage: 125_000,
      token_limit: 100_000,
      plan_tier: "starter"
    )

    result = @tool.execute({})

    assert result[:success]
    assert_equal 25_000, result[:usage_info][:overage_tokens]
    assert_equal "$0.25", result[:usage_info][:estimated_overage_cost]
    assert_includes result[:message], "25,000 tokens in overage"
    assert_includes result[:message], "$0.25"
  end

  test "handles large overage amounts correctly" do
    @entity.update!(
      token_usage: 300_000,
      token_limit: 100_000,
      plan_tier: "starter"
    )

    result = @tool.execute({})

    assert result[:success]
    assert_equal 200_000, result[:usage_info][:overage_tokens]
    assert_equal "$2.0", result[:usage_info][:estimated_overage_cost]
  end

  test "handles zero token limit gracefully" do
    @entity.update!(
      token_usage: 1000,
      token_limit: 0,
      plan_tier: "starter"
    )

    result = @tool.execute({})

    assert result[:success]
    assert_equal 0.0, result[:usage_info][:usage_percent]
  end

  test "handles nil token values gracefully" do
    @entity.update!(
      token_usage: nil,
      token_limit: nil,
      plan_tier: "starter"
    )

    result = @tool.execute({})

    assert result[:success]
    assert_equal 0, result[:usage_info][:token_usage]
    assert_equal 100_000, result[:usage_info][:token_limit]
  end

  test "formats large numbers with commas in message" do
    @entity.update!(
      token_usage: 1_234_567,
      token_limit: 2_000_000,
      plan_tier: "enterprise"
    )

    result = @tool.execute({})

    assert result[:success]
    # Check that the message contains properly formatted numbers
    assert_match(/765,433 tokens remaining/, result[:message])
  end
end
