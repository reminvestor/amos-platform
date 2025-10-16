require 'test_helper'

class GetBillingInfoToolTest < ActiveSupport::TestCase
  setup do
    @entity = entities(:one)
    @user = users(:one)
    @tool = Tools::GetBillingInfoTool.new(
      entity: @entity,
      user: @user
    )

    @entity.update!(
      stripe_customer_id: "cus_test123",
      stripe_subscription_id: "sub_test123",
      subscription_status: "active",
      plan_tier: "professional",
      token_usage: 250_000,
      token_limit: 500_000,
      trial_ends_at: nil,
      current_period_end: 1.month.from_now
    )
  end

  test "returns billing information successfully" do
    customer = mock_stripe_customer
    subscription = mock_stripe_subscription
    payment_method = mock_stripe_payment_method

    Stripe::Customer.stubs(:retrieve).with("cus_test123").returns(customer)
    Stripe::Subscription.stubs(:retrieve).with("sub_test123").returns(subscription)
    Stripe::PaymentMethod.stubs(:retrieve).returns(payment_method)
    Stripe::Invoice.stubs(:upcoming).returns(mock_stripe_invoice)

    result = @tool.execute({})

    assert result[:success]
    assert_equal "active", result[:billing_info][:subscription_status]
    assert_equal "Professional", result[:billing_info][:plan_tier]
    assert_equal 250_000, result[:billing_info][:token_usage]
    assert_equal 500_000, result[:billing_info][:token_limit]
    assert_equal 50.0, result[:billing_info][:token_usage_percent]
    assert result[:billing_info][:payment_method].present?
    assert_equal "visa", result[:billing_info][:payment_method][:card_brand]
    assert_equal "4242", result[:billing_info][:payment_method][:last4]
  end

  test "returns error when no stripe customer exists" do
    @entity.update!(stripe_customer_id: nil)

    result = @tool.execute({})

    assert_not result[:success]
    assert_includes result[:error], "No billing information available"
  end

  test "handles missing payment method gracefully" do
    customer = OpenStruct.new(
      email: "test@example.com",
      invoice_settings: OpenStruct.new(default_payment_method: nil)
    )

    Stripe::Customer.stubs(:retrieve).returns(customer)
    Stripe::Subscription.stubs(:retrieve).returns(mock_stripe_subscription)
    Stripe::Invoice.stubs(:upcoming).raises(Stripe::InvalidRequestError.new("No upcoming invoice", "invoice"))

    result = @tool.execute({})

    assert result[:success]
    assert_nil result[:billing_info][:payment_method]
  end

  test "handles stripe errors gracefully" do
    Stripe::Customer.stubs(:retrieve).raises(
      Stripe::InvalidRequestError.new("Customer not found", "customer")
    )

    result = @tool.execute({})

    assert_not result[:success]
    assert_includes result[:error], "Failed to retrieve billing information"
  end

  test "calculates token usage percentage correctly" do
    @entity.update!(token_usage: 475_000, token_limit: 500_000)

    customer = mock_stripe_customer
    Stripe::Customer.stubs(:retrieve).returns(customer)
    Stripe::Subscription.stubs(:retrieve).returns(mock_stripe_subscription)
    Stripe::PaymentMethod.stubs(:retrieve).returns(mock_stripe_payment_method)
    Stripe::Invoice.stubs(:upcoming).raises(Stripe::InvalidRequestError.new("No upcoming invoice", "invoice"))

    result = @tool.execute({})

    assert result[:success]
    assert_equal 95.0, result[:billing_info][:token_usage_percent]
  end

  private

  def mock_stripe_customer
    OpenStruct.new(
      email: "test@example.com",
      invoice_settings: OpenStruct.new(
        default_payment_method: "pm_test123"
      )
    )
  end

  def mock_stripe_subscription
    OpenStruct.new(
      id: "sub_test123",
      status: "active"
    )
  end

  def mock_stripe_payment_method
    OpenStruct.new(
      type: "card",
      card: OpenStruct.new(
        brand: "visa",
        last4: "4242",
        exp_month: 12,
        exp_year: 2025
      )
    )
  end

  def mock_stripe_invoice
    OpenStruct.new(
      amount_due: 5000,
      currency: "usd",
      period_start: Time.now.to_i,
      period_end: 1.month.from_now.to_i
    )
  end
end
