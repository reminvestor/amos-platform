class StripeCheckoutController < ApplicationController
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
        entity.update!(
          stripe_subscription_id: subscription.id,
          subscription_status: subscription.status,
          trial_ends_at: subscription.trial_end ? Time.at(subscription.trial_end) : nil,
          current_period_end: Time.at(subscription.current_period_end),
          plan_tier: subscription.items.data.first&.price&.lookup_key || 'basic',
          token_limit: determine_token_limit(subscription.items.data.first&.price&.lookup_key)
        )
      end

      redirect_to root_path, notice: "Welcome! Your 7-day trial has started."
    rescue Stripe::StripeError => e
      Rails.logger.error "Error retrieving checkout session: #{e.message}"
      redirect_to root_path, alert: "There was an error processing your subscription."
    end
  end

  def cancel
    redirect_to root_path, alert: "Checkout cancelled. You can try again anytime."
  end

  def create_portal_session
    # Create a Stripe customer portal session for managing subscription
    entity = current_entity

    return render json: { error: 'No Stripe customer found' }, status: :not_found if entity.stripe_customer_id.blank?

    session = Stripe::BillingPortal::Session.create(
      customer: entity.stripe_customer_id,
      return_url: root_url
    )

    render json: { portal_url: session.url }
  rescue Stripe::StripeError => e
    Rails.logger.error "Error creating portal session: #{e.message}"
    render json: { error: e.message }, status: :unprocessable_entity
  end

  private

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
