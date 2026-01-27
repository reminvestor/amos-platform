require 'test_helper'

class UpdateSubscriptionToolTest < ActiveSupport::TestCase
  setup do
    @entity = entities(:one)
    @user = users(:one)
    @tool = Tools::UpdateSubscriptionTool.new(
      entity: @entity,
      user: @user
    )

    @entity.update!(
      stripe_customer_id: "cus_test123",
      stripe_subscription_id: "sub_test123",
      subscription_status: "active",
      plan_tier: "starter",
      token_limit: 100_000
    )

    ENV['STRIPE_PROFESSIONAL_PRICE_ID'] = 'price_professional'
    ENV['STRIPE_ENTERPRISE_PRICE_ID'] = 'price_enterprise'
  end

  teardown do
    ENV.delete('STRIPE_PROFESSIONAL_PRICE_ID')
    ENV.delete('STRIPE_ENTERPRISE_PRICE_ID')
  end

  test "upgrades subscription to professional plan" do
    subscription = mock_stripe_subscription

    Stripe::Subscription.stubs(:retrieve).with("sub_test123").returns(subscription)
    Stripe::Subscription.stubs(:update).returns(
      OpenStruct.new(
        id: "sub_test123",
        status: "active",
        items: OpenStruct.new(
          data: [
            OpenStruct.new(
              price: OpenStruct.new(lookup_key: "professional")
            )
          ]
        )
      )
    )

    result = @tool.execute({ plan_tier: "professional" })

    assert result[:success]
    assert_equal "professional", result[:subscription][:plan_tier]
    assert_equal 500_000, result[:subscription][:token_limit]
    assert_includes result[:message], "Professional"

    @entity.reload
    assert_equal "professional", @entity.plan_tier
    assert_equal 500_000, @entity.token_limit
  end

  test "upgrades subscription to enterprise plan" do
    subscription = mock_stripe_subscription

    Stripe::Subscription.stubs(:retrieve).returns(subscription)
    Stripe::Subscription.stubs(:update).returns(
      OpenStruct.new(
        id: "sub_test123",
        status: "active",
        items: OpenStruct.new(
          data: [
            OpenStruct.new(
              price: OpenStruct.new(lookup_key: "enterprise")
            )
          ]
        )
      )
    )

    result = @tool.execute({ plan_tier: "enterprise" })

    assert result[:success]
    assert_equal 2_000_000, result[:subscription][:token_limit]

    @entity.reload
    assert_equal "enterprise", @entity.plan_tier
    assert_equal 2_000_000, @entity.token_limit
  end

  test "returns error when no active subscription" do
    @entity.update!(stripe_subscription_id: nil)

    result = @tool.execute({ plan_tier: "professional" })

    assert_not result[:success]
    assert_includes result[:error], "No active subscription found"
  end

  test "returns error for invalid plan tier" do
    subscription = mock_stripe_subscription
    Stripe::Subscription.stubs(:retrieve).returns(subscription)

    result = @tool.execute({ plan_tier: "invalid_plan" })

    assert_not result[:success]
    assert_includes result[:error], "Invalid plan tier"
  end

  test "returns error when plan_tier is missing" do
    result = @tool.execute({})

    assert_not result[:success]
    assert_includes result[:error], "Missing required fields: plan_tier"
  end

  test "handles stripe errors gracefully" do
    Stripe::Subscription.stubs(:retrieve).raises(
      Stripe::InvalidRequestError.new("Subscription not found", "subscription")
    )

    result = @tool.execute({ plan_tier: "professional" })

    assert_not result[:success]
    assert_includes result[:error], "Failed to update subscription"
  end

  private

  def mock_stripe_subscription
    OpenStruct.new(
      id: "sub_test123",
      items: OpenStruct.new(
        data: [
          OpenStruct.new(id: "si_test123")
        ]
      )
    )
  end
end
