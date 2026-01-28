require "test_helper"

class StripeWebhooksControllerTest < ActionDispatch::IntegrationTest
  setup do
    @entity = entities(:one)
    @entity.update!(stripe_customer_id: "cus_test123")

    # Set a test webhook secret
    @original_webhook_secret = ENV['STRIPE_WEBHOOK_SECRET']
    ENV['STRIPE_WEBHOOK_SECRET'] = 'whsec_test_secret'

    # Stub Stripe webhook signature verification to bypass it in tests
    Stripe::Webhook.stubs(:construct_event).with(anything, anything, anything).returns(nil)
  end

  teardown do
    ENV['STRIPE_WEBHOOK_SECRET'] = @original_webhook_secret
  end

  # Helper to create and stub a Stripe event
  def stub_stripe_event(event_hash)
    event = Stripe::Event.construct_from(event_hash)
    Stripe::Webhook.stubs(:construct_event).returns(event)
    event
  end

  test "should handle subscription created event" do
    event = create_stripe_event(
      type: "customer.subscription.created",
      object: {
        id: "sub_test123",
        customer: "cus_test123",
        status: "active",
        current_period_end: 1.month.from_now.to_i,
        trial_end: 7.days.from_now.to_i,
        items: {
          data: [
            {
              price: {
                lookup_key: "professional"
              }
            }
          ]
        }
      }
    )

    post stripe_webhooks_path, params: event.to_json, headers: stripe_headers(event.to_json)

    assert_response :success
    @entity.reload
    assert_equal "sub_test123", @entity.stripe_subscription_id
    assert_equal "active", @entity.subscription_status
    assert_equal "professional", @entity.plan_tier
  end

  test "should handle subscription updated event" do
    @entity.update!(
      stripe_subscription_id: "sub_test123",
      subscription_status: "active",
      plan_tier: "starter"
    )

    event = create_stripe_event(
      type: "customer.subscription.updated",
      object: {
        id: "sub_test123",
        customer: "cus_test123",
        status: "active",
        current_period_end: 1.month.from_now.to_i,
        trial_end: nil,
        items: {
          data: [
            {
              price: {
                lookup_key: "professional"
              }
            }
          ]
        }
      }
    )

    post stripe_webhooks_path, params: event.to_json, headers: stripe_headers(event.to_json)

    assert_response :success
    @entity.reload
    assert_equal "professional", @entity.plan_tier
    assert_equal 1_000_000, @entity.token_limit
  end

  test "should handle subscription deleted event" do
    @entity.update!(
      stripe_subscription_id: "sub_test123",
      subscription_status: "active"
    )

    event = create_stripe_event(
      type: "customer.subscription.deleted",
      object: {
        id: "sub_test123",
        customer: "cus_test123"
      }
    )

    post stripe_webhooks_path, params: event.to_json, headers: stripe_headers(event.to_json)

    assert_response :success
    @entity.reload
    assert_equal "cancelled", @entity.subscription_status
    assert_nil @entity.stripe_subscription_id
  end

  test "should handle invoice payment succeeded event" do
    @entity.update!(
      token_usage: 50_000,
      subscription_status: "past_due"
    )

    event = create_stripe_event(
      type: "invoice.payment_succeeded",
      object: {
        id: "inv_test123",
        customer: "cus_test123",
        billing_reason: "subscription_cycle",
        period_end: 1.month.from_now.to_i,
        amount_paid: 2999  # $29.99 in cents
      }
    )

    post stripe_webhooks_path, params: event.to_json, headers: stripe_headers(event.to_json)

    assert_response :success
    @entity.reload
    assert_equal 0, @entity.token_usage
    assert_equal "active", @entity.subscription_status
  end

  test "should handle invoice payment failed event" do
    @entity.update!(subscription_status: "active")

    event = create_stripe_event(
      type: "invoice.payment_failed",
      object: {
        id: "inv_fail123",
        customer: "cus_test123",
        amount_due: 2999,  # $29.99 in cents
        attempt_count: 1,
        next_payment_attempt: 3.days.from_now.to_i
      }
    )

    post stripe_webhooks_path, params: event.to_json, headers: stripe_headers(event.to_json)

    assert_response :success
    @entity.reload
    assert_equal "past_due", @entity.subscription_status
  end

  test "should reject webhook with invalid signature" do
    ENV['STRIPE_WEBHOOK_SECRET'] = 'whsec_test'

    # Unstub to test actual signature verification
    Stripe::Webhook.unstub(:construct_event)
    
    # Stub to raise signature verification error
    Stripe::Webhook.stubs(:construct_event).raises(Stripe::SignatureVerificationError.new("Invalid signature", "sig_header"))

    event_payload = { type: "customer.subscription.created", data: { object: { customer: "cus_test123" } } }.to_json

    post stripe_webhooks_path, params: event_payload, headers: { "Stripe-Signature" => "invalid" }

    assert_response :unauthorized
  end

  private

  def create_stripe_event(type:, object:)
    event_hash = {
      id: "evt_#{SecureRandom.hex(12)}",
      type: type,
      data: {
        object: object
      }
    }

    # Stub Stripe::Webhook.construct_event to return a proper event object
    event = Stripe::Event.construct_from(event_hash)
    Stripe::Webhook.stubs(:construct_event).returns(event)

    event_hash
  end

  def stripe_headers(payload)
    {
      "Content-Type" => "application/json",
      "Stripe-Signature" => "t=#{Time.now.to_i},v1=test_signature"
    }
  end
end
