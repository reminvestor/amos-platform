class SubscriptionsController < ApplicationController
  before_action :authenticate_user!
  skip_before_action :check_subscription_status, only: [:new, :create]

  def new
    # Show plan selection page
    @entity = current_entity

    # If already has active subscription, redirect to onboarding or chat
    if @entity.subscription_status == 'active' || @entity.subscription_status == 'trialing'
      redirect_to onboarding_path and return
    end
  end

  def create
    # Create Stripe checkout session
    entity = current_entity
    price_id = params[:price_id]

    # Validate price_id
    unless valid_price_id?(price_id)
      redirect_to new_subscription_path, alert: "Invalid plan selected" and return
    end

    # Create or get Stripe customer
    if entity.stripe_customer_id.blank?
      customer = Stripe::Customer.create(
        email: current_user.email,
        metadata: {
          entity_id: entity.id,
          entity_name: entity.name,
          user_id: current_user.id
        }
      )
      entity.update!(stripe_customer_id: customer.id)
    end

    # Create checkout session with 7-day trial
    session = Stripe::Checkout::Session.create(
      customer: entity.stripe_customer_id,
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
      success_url: success_subscriptions_url(session_id: '{CHECKOUT_SESSION_ID}'),
      cancel_url: cancel_subscriptions_url,
      allow_promotion_codes: true,
      billing_address_collection: 'required'
    )

    redirect_to session.url, allow_other_host: true
  rescue Stripe::StripeError => e
    Rails.logger.error "Stripe checkout error: #{e.message}"
    redirect_to new_subscription_path, alert: "Payment setup failed. Please try again."
  end

  def success
    session_id = params[:session_id]

    begin
      checkout_session = Stripe::Checkout::Session.retrieve(session_id)
      subscription = Stripe::Subscription.retrieve(checkout_session.subscription)

      entity = current_entity

      # Update entity with subscription info
      entity.update!(
        stripe_subscription_id: subscription.id,
        subscription_status: subscription.status,
        trial_ends_at: subscription.trial_end ? Time.at(subscription.trial_end) : nil,
        current_period_end: Time.at(subscription.current_period_end),
        plan_tier: subscription.items.data.first&.price&.lookup_key || 'starter',
        token_limit: determine_token_limit(subscription.items.data.first&.price&.lookup_key)
      )

      # Redirect to onboarding
      redirect_to onboarding_path, notice: "Welcome! Your 7-day trial has started."
    rescue Stripe::StripeError => e
      Rails.logger.error "Error retrieving checkout session: #{e.message}"
      redirect_to new_subscription_path, alert: "There was an error processing your subscription."
    end
  end

  def cancel
    redirect_to new_subscription_path, alert: "Checkout cancelled. Choose a plan to continue."
  end

  private

  def valid_price_id?(price_id)
    [
      ENV['STRIPE_STARTER_PRICE_ID'],
      ENV['STRIPE_PROFESSIONAL_PRICE_ID'],
      ENV['STRIPE_BUSINESS_PRICE_ID']
    ].include?(price_id)
  end

  def determine_token_limit(price_lookup_key)
    case price_lookup_key
    when 'starter', 'basic'
      200_000
    when 'professional', 'pro'
      1_000_000
    when 'business'
      2_000_000
    else
      200_000
    end
  end
end
