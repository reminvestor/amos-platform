require "test_helper"

class StripeWebhooksControllerTest < ActionDispatch::IntegrationTest
  setup do
    @entity = entities(:one)
    @entity.update!(stripe_customer_id: "cus_test123")

    # Stub Stripe webhook signature verification
    @original_webhook_secret = ENV['STRIPE_WEBHOOK_SECRET']
    ENV['STRIPE_WEBHOOK_SECRET'] = nil  # Disable signature verification for tests
  end

  teardown do
    ENV['STRIPE_WEBHOOK_SECRET'] = @original_webhook_secret
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
        customer: "cus_test123",
        billing_reason: "subscription_cycle",
        period_end: 1.month.from_now.to_i
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
        customer: "cus_test123"
      }
    )

    post stripe_webhooks_path, params: event.to_json, headers: stripe_headers(event.to_json)

    assert_response :success
    @entity.reload
    assert_equal "past_due", @entity.subscription_status
  end

  test "should reject webhook with invalid signature" do
    ENV['STRIPE_WEBHOOK_SECRET'] = 'whsec_test'

    event = create_stripe_event(
      type: "customer.subscription.created",
      object: { customer: "cus_test123" }
    )

    post stripe_webhooks_path, params: event.to_json, headers: { "Stripe-Signature" => "invalid" }

    assert_response :unauthorized

    ENV['STRIPE_WEBHOOK_SECRET'] = nil
  end

  private

  def create_stripe_event(type:, object:)
    {
      id: "evt_#{SecureRandom.hex(12)}",
      type: type,
      data: {
        object: object
      }
    }
  end

  def stripe_headers(payload)
    {
      "Content-Type" => "application/json",
      "Stripe-Signature" => "t=#{Time.now.to_i},v1=test_signature"
    }
  end
end
