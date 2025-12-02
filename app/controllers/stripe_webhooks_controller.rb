class StripeWebhooksController < ApplicationController
  skip_before_action :verify_authenticity_token
  skip_before_action :authenticate_user!

  def create
    payload = request.body.read
    sig_header = request.headers['Stripe-Signature']
    endpoint_secret = ENV['STRIPE_WEBHOOK_SECRET']

    # NEVER skip signature verification - fail fast if not configured
    if endpoint_secret.blank?
      Rails.logger.error("STRIPE_WEBHOOK_SECRET not configured - cannot process webhooks")
      return render json: { error: "Webhook not configured" }, status: 500
    end

    begin
      # Always verify signature (no test environment bypass)
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
    when 'setup_intent.succeeded'
      handle_setup_intent_succeeded(event.data.object)
    when 'payment_method.attached'
      handle_payment_method_attached(event.data.object)
    when 'charge.succeeded', 'payment_intent.succeeded', 'payment_intent.created'
      # These are informational - the actual handling is done in handle_invoice_payment_succeeded
      Rails.logger.info "Stripe event #{event.type} received for customer"
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

  def handle_setup_intent_succeeded(setup_intent)
    # Extract metadata to find the billing account
    billing_account_id = setup_intent.metadata&.[]('billing_account_id')
    user_id = setup_intent.metadata&.[]('user_id')
    
    billing_account = if billing_account_id.present?
      UserBillingAccount.find_by(id: billing_account_id)
    elsif user_id.present?
      UserBillingAccount.find_by(user_id: user_id)
    elsif setup_intent.customer.present?
      UserBillingAccount.find_by(stripe_customer_id: setup_intent.customer)
    end
    
    return unless billing_account
    
    # Update the payment method if provided
    if setup_intent.payment_method.present?
      billing_account.update!(
        stripe_payment_method_id: setup_intent.payment_method,
        payment_method_last4: fetch_payment_method_last4(setup_intent.payment_method),
        payment_method_brand: fetch_payment_method_brand(setup_intent.payment_method)
      )
      Rails.logger.info "✅ Setup intent succeeded - payment method saved for billing account #{billing_account.id}"
    end
  end

  def handle_payment_method_attached(payment_method)
    # Find billing account by customer ID
    billing_account = UserBillingAccount.find_by(stripe_customer_id: payment_method.customer)
    return unless billing_account
    
    # Update with the new payment method details
    billing_account.update!(
      stripe_payment_method_id: payment_method.id,
      payment_method_last4: payment_method.card&.last4,
      payment_method_brand: payment_method.card&.brand&.capitalize
    )
    
    Rails.logger.info "✅ Payment method attached for billing account #{billing_account.id}: #{payment_method.card&.brand} ending in #{payment_method.card&.last4}"
  end

  def fetch_payment_method_last4(payment_method_id)
    pm = Stripe::PaymentMethod.retrieve(payment_method_id)
    pm.card&.last4
  rescue Stripe::StripeError => e
    Rails.logger.error "Failed to fetch payment method details: #{e.message}"
    nil
  end

  def fetch_payment_method_brand(payment_method_id)
    pm = Stripe::PaymentMethod.retrieve(payment_method_id)
    pm.card&.brand&.capitalize
  rescue Stripe::StripeError => e
    Rails.logger.error "Failed to fetch payment method details: #{e.message}"
    nil
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
