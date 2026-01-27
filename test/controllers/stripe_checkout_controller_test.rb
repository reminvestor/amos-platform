require "test_helper"

class StripeCheckoutControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @entity = entities(:one)
    host! "app.example.com"  # Required for subdomain routing
    sign_in @user
  end

  test "should create checkout session for new customer" do
    Stripe::Customer.stubs(:create).returns(
      OpenStruct.new(id: "cus_new123")
    )

    Stripe::Checkout::Session.stubs(:create).returns(
      OpenStruct.new(url: "https://checkout.stripe.com/session123")
    )

    post stripe_checkout_path, params: { price_id: "price_123" }

    assert_response :success
    json_response = JSON.parse(response.body)
    assert_equal "https://checkout.stripe.com/session123", json_response["checkout_url"]

    @entity.reload
    assert_equal "cus_new123", @entity.stripe_customer_id
  end

  test "should create checkout session for existing customer" do
    @entity.update!(stripe_customer_id: "cus_existing123")

    Stripe::Checkout::Session.stubs(:create).returns(
      OpenStruct.new(url: "https://checkout.stripe.com/session456")
    )

    post stripe_checkout_path, params: { price_id: "price_456" }

    assert_response :success
    json_response = JSON.parse(response.body)
    assert_equal "https://checkout.stripe.com/session456", json_response["checkout_url"]
  end

  test "should handle stripe error during checkout" do
    Stripe::Checkout::Session.stubs(:create).raises(
      Stripe::InvalidRequestError.new("Invalid price", "price")
    )

    post stripe_checkout_path, params: { price_id: "invalid_price" }

    assert_response :unprocessable_entity
    json_response = JSON.parse(response.body)
    assert json_response["error"].present?
  end

  test "should handle successful checkout" do
    @entity.update!(stripe_customer_id: "cus_123")

    session = OpenStruct.new(
      customer: "cus_123",
      subscription: "sub_123"
    )

    subscription = OpenStruct.new(
      id: "sub_123",
      status: "trialing",
      trial_end: 7.days.from_now.to_i,
      current_period_end: 1.month.from_now.to_i,
      items: OpenStruct.new(
        data: [
          OpenStruct.new(
            price: OpenStruct.new(lookup_key: "professional")
          )
        ]
      )
    )

    Stripe::Checkout::Session.stubs(:retrieve).returns(session)
    Stripe::Subscription.stubs(:retrieve).returns(subscription)

    get stripe_checkout_success_path, params: { session_id: "cs_test123" }

    assert_redirected_to "/"
    # Check for key parts of the success message (includes dynamic date)
    assert_match /Subscription confirmed/, flash[:notice]
    assert_match /Professional plan/, flash[:notice]
    assert_match /1M AI tokens/, flash[:notice]
    assert_match /7-day trial/, flash[:notice]

    @entity.reload
    assert_equal "sub_123", @entity.stripe_subscription_id
    assert_equal "trialing", @entity.subscription_status
    assert_equal "professional", @entity.plan_tier
    assert_equal 1_000_000, @entity.token_limit  # Professional plan = 1M tokens
  end

  test "should handle checkout cancellation" do
    get stripe_checkout_cancel_path

    assert_redirected_to "/"
    assert_equal "Checkout cancelled. You can try again anytime.", flash[:alert]
  end

  test "should create customer portal session" do
    @entity.update!(stripe_customer_id: "cus_123")

    Stripe::BillingPortal::Session.stubs(:create).returns(
      OpenStruct.new(url: "https://billing.stripe.com/session123")
    )

    post stripe_portal_path

    assert_response :success
    json_response = JSON.parse(response.body)
    assert_equal "https://billing.stripe.com/session123", json_response["portal_url"]
  end

  test "should handle missing customer for portal" do
    @entity.update!(stripe_customer_id: nil)

    post stripe_portal_path

    assert_response :not_found
    json_response = JSON.parse(response.body)
    assert_equal "No Stripe customer found", json_response["error"]
  end

  test "should handle stripe error during portal creation" do
    @entity.update!(stripe_customer_id: "cus_123")

    Stripe::BillingPortal::Session.stubs(:create).raises(
      Stripe::InvalidRequestError.new("Customer not found", "customer")
    )

    post stripe_portal_path

    assert_response :unprocessable_entity
    json_response = JSON.parse(response.body)
    assert json_response["error"].present?
  end
end
