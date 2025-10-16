class StripeWebhooksController < ApplicationController
  skip_before_action :verify_authenticity_token
  skip_before_action :authenticate_user!

  def create
    payload = request.body.read
    sig_header = request.headers['Stripe-Signature']
    endpoint_secret = ENV['STRIPE_WEBHOOK_SECRET']

    begin
      # In test environment without webhook secret, parse JSON directly
      if Rails.env.test? && endpoint_secret.blank?
        event_data = JSON.parse(payload)
        event = Stripe::Event.construct_from(event_data)
      else
        event = Stripe::Webhook.construct_event(payload, sig_header, endpoint_secret)
      end
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

    # Safely get current_period_end and trial_end
    period_end = subscription.try(:current_period_end) || subscription['current_period_end']
    trial_end = subscription.try(:trial_end) || subscription['trial_end']
    plan_tier = subscription.items.data.first&.price&.lookup_key || 'basic'

    # Capture previous state
    previous_status = entity.subscription_status
    previous_plan = entity.plan_tier

    entity.update!(
      stripe_subscription_id: subscription.id,
      subscription_status: subscription.status,
      current_period_end: period_end ? Time.at(period_end) : nil,
      trial_ends_at: trial_end ? Time.at(trial_end) : nil,
      plan_tier: plan_tier
    )

    # Log subscription event
    SubscriptionEvent.log_event(
      entity: entity,
      event_type: 'subscription_created',
      previous_status: previous_status,
      new_status: subscription.status,
      previous_plan: previous_plan,
      new_plan: plan_tier,
      stripe_event_id: subscription.id,
      metadata: {
        trial_ends_at: trial_end ? Time.at(trial_end) : nil,
        current_period_end: period_end ? Time.at(period_end) : nil
      },
      triggered_by: 'stripe_webhook'
    )

    Rails.logger.info "Subscription created for entity #{entity.id}"
  end

  def handle_subscription_updated(subscription)
    entity = Entity.find_by(stripe_customer_id: subscription.customer)
    return unless entity

    # Determine token limit based on plan tier
    price_lookup_key = subscription.items.data.first&.price&.lookup_key
    token_limit = determine_token_limit(price_lookup_key)

    # Safely get current_period_end and trial_end
    period_end = subscription.try(:current_period_end) || subscription['current_period_end']
    trial_end = subscription.try(:trial_end) || subscription['trial_end']

    # Capture previous state
    previous_status = entity.subscription_status
    previous_plan = entity.plan_tier

    entity.update!(
      stripe_subscription_id: subscription.id,
      subscription_status: subscription.status,
      current_period_end: period_end ? Time.at(period_end) : nil,
      trial_ends_at: trial_end ? Time.at(trial_end) : nil,
      plan_tier: price_lookup_key || entity.plan_tier,
      token_limit: token_limit
    )

    # Log subscription event
    event_type = previous_plan != price_lookup_key ? 'plan_changed' : 'subscription_updated'
    SubscriptionEvent.log_event(
      entity: entity,
      event_type: event_type,
      previous_status: previous_status,
      new_status: subscription.status,
      previous_plan: previous_plan,
      new_plan: price_lookup_key || entity.plan_tier,
      stripe_event_id: subscription.id,
      metadata: {
        token_limit: token_limit,
        trial_ends_at: trial_end ? Time.at(trial_end) : nil,
        current_period_end: period_end ? Time.at(period_end) : nil
      },
      triggered_by: 'stripe_webhook'
    )

    Rails.logger.info "Subscription updated for entity #{entity.id}"
  end

  def handle_subscription_deleted(subscription)
    entity = Entity.find_by(stripe_customer_id: subscription.customer)
    return unless entity

    # Capture previous state
    previous_status = entity.subscription_status
    previous_plan = entity.plan_tier

    entity.update!(
      subscription_status: 'cancelled',
      stripe_subscription_id: nil
    )

    # Log subscription event
    SubscriptionEvent.log_event(
      entity: entity,
      event_type: 'subscription_cancelled',
      previous_status: previous_status,
      new_status: 'cancelled',
      previous_plan: previous_plan,
      new_plan: nil,
      stripe_event_id: subscription.id,
      metadata: {
        cancelled_at: Time.current
      },
      triggered_by: 'stripe_webhook'
    )

    Rails.logger.info "Subscription cancelled for entity #{entity.id}"
  end

  def handle_invoice_payment_succeeded(invoice)
    entity = Entity.find_by(stripe_customer_id: invoice.customer)
    return unless entity

    previous_status = entity.subscription_status

    # Reset token usage at the start of each billing period
    if invoice.billing_reason == 'subscription_cycle'
      entity.update!(
        token_usage: 0,
        current_period_end: Time.at(invoice.period_end)
      )
      Rails.logger.info "Token usage reset for entity #{entity.id}"
    end

    # Update subscription status to active
    if entity.subscription_status != 'active'
      entity.update!(subscription_status: 'active')

      # Log payment success event
      SubscriptionEvent.log_event(
        entity: entity,
        event_type: 'payment_succeeded',
        previous_status: previous_status,
        new_status: 'active',
        stripe_event_id: invoice.id,
        metadata: {
          amount_paid: invoice.amount_paid,
          invoice_id: invoice.id,
          billing_reason: invoice.billing_reason
        },
        triggered_by: 'stripe_webhook'
      )
    end

    Rails.logger.info "Payment succeeded for entity #{entity.id}"
  end

  def handle_invoice_payment_failed(invoice)
    entity = Entity.find_by(stripe_customer_id: invoice.customer)
    return unless entity

    previous_status = entity.subscription_status

    entity.update!(subscription_status: 'past_due')

    # Log payment failure event
    SubscriptionEvent.log_event(
      entity: entity,
      event_type: 'payment_failed',
      previous_status: previous_status,
      new_status: 'past_due',
      stripe_event_id: invoice.id,
      metadata: {
        amount_due: invoice.amount_due,
        invoice_id: invoice.id,
        attempt_count: invoice.attempt_count
      },
      triggered_by: 'stripe_webhook'
    )

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
