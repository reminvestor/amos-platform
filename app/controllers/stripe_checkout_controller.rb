class StripeCheckoutController < ApplicationController
  include ActionView::Helpers::NumberHelper  # For number formatting

  skip_before_action :authenticate_user!, only: [:create, :success, :cancel]

  def create
    # Get or create Stripe customer
    entity = current_entity
    stripe_customer_id = entity.stripe_customer_id

    if stripe_customer_id.blank?
      customer = Stripe::Customer.create(
        email: current_user.email,
        metadata: {
          entity_id: entity.id,
          entity_name: entity.name
        }
      )
      entity.update!(stripe_customer_id: customer.id)
      stripe_customer_id = customer.id
    end

    # Create checkout session
    price_id = params[:price_id] || ENV['STRIPE_DEFAULT_PRICE_ID']

    session = Stripe::Checkout::Session.create(
      customer: stripe_customer_id,
      payment_method_types: ['card'],
      line_items: [{
        price: price_id,
        quantity: 1
      }],
      mode: 'subscription',
      subscription_data: {
        trial_period_days: 7,
        metadata: {
          entity_id: entity.id
        }
      },
      success_url: stripe_checkout_success_url(session_id: '{CHECKOUT_SESSION_ID}'),
      cancel_url: stripe_checkout_cancel_url,
      allow_promotion_codes: true,
      billing_address_collection: 'required'
    )

    render json: { checkout_url: session.url }
  rescue Stripe::StripeError => e
    Rails.logger.error "Stripe checkout error: #{e.message}"
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def success
    session_id = params[:session_id]

    begin
      session = Stripe::Checkout::Session.retrieve(session_id)
      subscription = Stripe::Subscription.retrieve(session.subscription)

      entity = Entity.find_by(stripe_customer_id: session.customer)

      if entity
        plan_tier = subscription.items.data.first&.price&.lookup_key || 'basic'
        token_limit = determine_token_limit(plan_tier)

        # Capture previous state
        previous_status = entity.subscription_status
        previous_plan = entity.plan_tier

        entity.update!(
          stripe_subscription_id: subscription.id,
          subscription_status: subscription.status,
          trial_ends_at: subscription.trial_end ? Time.at(subscription.trial_end) : nil,
          current_period_end: Time.at(subscription.current_period_end),
          plan_tier: plan_tier,
          token_limit: token_limit
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
            trial_ends_at: subscription.trial_end ? Time.at(subscription.trial_end) : nil,
            current_period_end: Time.at(subscription.current_period_end),
            token_limit: token_limit,
            checkout_session_id: session_id
          },
          triggered_by: 'user_checkout'
        )

        # Create success message with plan details
        plan_name = plan_tier.titleize
        trial_end_date = entity.trial_ends_at ? entity.trial_ends_at.strftime('%B %d, %Y') : 'the trial period ends'
        token_limit_formatted = number_to_human(token_limit, format: '%n%u', units: { thousand: 'K', million: 'M' })

        success_message = "🎉 Subscription confirmed! Your #{plan_name} plan (#{token_limit_formatted} AI tokens/month) 7-day trial has started. You won't be charged until #{trial_end_date}."

        redirect_to app_root_path, notice: success_message
      else
        redirect_to app_root_path, alert: "There was an error finding your account."
      end
    rescue Stripe::StripeError => e
      Rails.logger.error "Error retrieving checkout session: #{e.message}"
      redirect_to app_root_path, alert: "There was an error processing your subscription."
    end
  end

  def cancel
    redirect_to app_root_path, alert: "Checkout cancelled. You can try again anytime."
  end

  def create_portal_session
    # Create a Stripe customer portal session for managing subscription
    entity = current_entity

    return render json: { error: 'No Stripe customer found' }, status: :not_found if entity.stripe_customer_id.blank?

    # Use dashboard URL as return URL since root_url may not be available outside subdomain
    return_url = if defined?(dashboard_path)
      dashboard_url
    else
      "#{request.protocol}#{request.host_with_port}/"
    end

    session = Stripe::BillingPortal::Session.create(
      customer: entity.stripe_customer_id,
      return_url: return_url
    )

    render json: { portal_url: session.url }
  rescue Stripe::StripeError => e
    Rails.logger.error "Error creating portal session: #{e.message}"
    render json: { error: e.message }, status: :unprocessable_entity
  end

  private

  # Helper to get a redirect path since root_path isn't available outside subdomain
  def app_root_path
    # Redirect to the app subdomain dashboard
    if Rails.env.production?
      "https://app.amoslabs.co/"
    elsif Rails.env.staging?
      "https://app.staging.amoslabs.co/"
    else
      "/"
    end
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
      200_000
    end
  end
end
