class StripeWebhooksController < ApplicationController
  skip_before_action :verify_authenticity_token
  skip_before_action :authenticate_user!

  def create
    payload = request.body.read
    sig_header = request.headers['Stripe-Signature']
    endpoint_secret = ENV['STRIPE_WEBHOOK_SECRET']

    begin
      event = Stripe::Webhook.construct_event(payload, sig_header, endpoint_secret)
    rescue JSON::ParserError => e
      Rails.logger.error "Stripe webhook JSON parse error: #{e.message}"
      return head :bad_request
    rescue Stripe::SignatureVerificationError => e
      Rails.logger.error "Stripe webhook signature verification failed: #{e.message}"
      return head :unauthorized
    end

    # Handle the event
    case event.type
    when 'customer.subscription.created'
      handle_subscription_created(event.data.object)
    when 'customer.subscription.updated'
      handle_subscription_updated(event.data.object)
    when 'customer.subscription.deleted'
      handle_subscription_deleted(event.data.object)
    when 'invoice.payment_succeeded'
      handle_invoice_payment_succeeded(event.data.object)
    when 'invoice.payment_failed'
      handle_invoice_payment_failed(event.data.object)
    when 'customer.subscription.trial_will_end'
      handle_trial_will_end(event.data.object)
    else
      Rails.logger.info "Unhandled Stripe event type: #{event.type}"
    end

    head :ok
  end

  private

  def handle_subscription_created(subscription)
    entity = Entity.find_by(stripe_customer_id: subscription.customer)
    return unless entity

    entity.update!(
      stripe_subscription_id: subscription.id,
      subscription_status: subscription.status,
      current_period_end: Time.at(subscription.current_period_end),
      trial_ends_at: subscription.trial_end ? Time.at(subscription.trial_end) : nil,
      plan_tier: subscription.items.data.first&.price&.lookup_key || 'basic'
    )

    Rails.logger.info "Subscription created for entity #{entity.id}"
  end

  def handle_subscription_updated(subscription)
    entity = Entity.find_by(stripe_customer_id: subscription.customer)
    return unless entity

    # Determine token limit based on plan tier
    price_lookup_key = subscription.items.data.first&.price&.lookup_key
    token_limit = determine_token_limit(price_lookup_key)

    entity.update!(
      stripe_subscription_id: subscription.id,
      subscription_status: subscription.status,
      current_period_end: Time.at(subscription.current_period_end),
      trial_ends_at: subscription.trial_end ? Time.at(subscription.trial_end) : nil,
      plan_tier: price_lookup_key || entity.plan_tier,
      token_limit: token_limit
    )

    Rails.logger.info "Subscription updated for entity #{entity.id}"
  end

  def handle_subscription_deleted(subscription)
    entity = Entity.find_by(stripe_customer_id: subscription.customer)
    return unless entity

    entity.update!(
      subscription_status: 'cancelled',
      stripe_subscription_id: nil
    )

    Rails.logger.info "Subscription cancelled for entity #{entity.id}"
  end

  def handle_invoice_payment_succeeded(invoice)
    entity = Entity.find_by(stripe_customer_id: invoice.customer)
    return unless entity

    # Reset token usage at the start of each billing period
    if invoice.billing_reason == 'subscription_cycle'
      entity.update!(
        token_usage: 0,
        current_period_end: Time.at(invoice.period_end)
      )
      Rails.logger.info "Token usage reset for entity #{entity.id}"
    end

    # Update subscription status to active
    entity.update!(subscription_status: 'active') if entity.subscription_status != 'active'

    Rails.logger.info "Payment succeeded for entity #{entity.id}"
  end

  def handle_invoice_payment_failed(invoice)
    entity = Entity.find_by(stripe_customer_id: invoice.customer)
    return unless entity

    entity.update!(subscription_status: 'past_due')

    Rails.logger.info "Payment failed for entity #{entity.id}"

    # TODO: Send notification to user about failed payment
  end

  def handle_trial_will_end(subscription)
    entity = Entity.find_by(stripe_customer_id: subscription.customer)
    return unless entity

    Rails.logger.info "Trial ending soon for entity #{entity.id}"

    # TODO: Send reminder email to user about trial ending
  end

  def determine_token_limit(price_lookup_key)
    case price_lookup_key
    when 'starter', 'basic'
      200_000
    when 'professional', 'pro'
      1_000_000
    when 'business'
      2_000_000
    when 'enterprise'
      2_000_000
    else
      200_000 # Default to starter tier
    end
  end
end
