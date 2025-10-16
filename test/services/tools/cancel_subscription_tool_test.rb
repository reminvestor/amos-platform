require 'test_helper'

class CancelSubscriptionToolTest < ActiveSupport::TestCase
  setup do
    @entity = entities(:one)
    @user = users(:one)
    @tool = Tools::CancelSubscriptionTool.new(
      entity: @entity,
      user: @user
    )

    @entity.update!(
      stripe_customer_id: "cus_test123",
      stripe_subscription_id: "sub_test123",
      subscription_status: "active"
    )
  end

  test "cancels subscription at period end" do
    subscription = OpenStruct.new(
      id: "sub_test123",
      current_period_end: 1.month.from_now.to_i
    )

    Stripe::Subscription.stubs(:retrieve).with("sub_test123").returns(subscription)
    Stripe::Subscription.stubs(:update).returns(
      OpenStruct.new(
        id: "sub_test123",
        status: "active",
        cancel_at_period_end: true,
        current_period_end: 1.month.from_now.to_i
      )
    )

    result = @tool.execute({ confirm: true })

    assert result[:success]
    assert result[:subscription][:cancel_at_period_end]
    assert_includes result[:message], "cancelled on"
  end

  test "includes feedback in cancellation" do
    subscription = OpenStruct.new(id: "sub_test123", current_period_end: 1.month.from_now.to_i)

    Stripe::Subscription.stubs(:retrieve).returns(subscription)
    Stripe::Subscription.expects(:update).with(
      "sub_test123",
      has_entries(
        cancel_at_period_end: true,
        cancellation_details: has_entries(comment: "Too expensive")
      )
    ).returns(
      OpenStruct.new(
        id: "sub_test123",
        status: "active",
        cancel_at_period_end: true,
        current_period_end: 1.month.from_now.to_i
      )
    )

    result = @tool.execute({ confirm: true, feedback: "Too expensive" })

    assert result[:success]
  end

  test "returns error when confirm is false" do
    result = @tool.execute({ confirm: false })

    assert_not result[:success]
    assert_includes result[:error], "Cancellation must be confirmed"
  end

  test "returns error when confirm is missing" do
    result = @tool.execute({})

    assert_not result[:success]
    assert_includes result[:error], "Missing required fields: confirm"
  end

  test "returns error when no active subscription" do
    @entity.update!(stripe_subscription_id: nil)

    result = @tool.execute({ confirm: true })

    assert_not result[:success]
    assert_includes result[:error], "No active subscription found"
  end

  test "handles stripe errors gracefully" do
    Stripe::Subscription.stubs(:retrieve).raises(
      Stripe::InvalidRequestError.new("Subscription not found", "subscription")
    )

    result = @tool.execute({ confirm: true })

    assert_not result[:success]
    assert_includes result[:error], "Failed to cancel subscription"
  end
end
