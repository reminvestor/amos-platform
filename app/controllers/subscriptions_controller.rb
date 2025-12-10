class SubscriptionsController < ApplicationController
  before_action :authenticate_user!
  skip_before_action :check_token_balance, only: [:new, :create]

  def new
    # Show plan selection page
    @entity = current_entity

    # If already has active subscription, redirect to onboarding or chat
    if @entity.subscription_status == 'active' || @entity.subscription_status == 'trialing'
      redirect_to onboarding_path and return
    end
  end

  def create
    # TESTING MODE: Skip Stripe and just set trial status
    entity = current_entity
    price_id = params[:price_id]

    # Validate price_id - for testing, allow empty or any value
    if price_id.blank?
      # Default to starter plan for testing
      price_id = 'starter'
    end

    # TESTING: Set trial status directly without Stripe
    plan_tier = case price_id
    when 'starter', ENV['STRIPE_STARTER_PRICE_ID']
      'starter'
    when 'professional', ENV['STRIPE_PROFESSIONAL_PRICE_ID']
      'professional'
    when 'business', ENV['STRIPE_BUSINESS_PRICE_ID']
      'business'
    else
      'starter'
    end

    token_limit = case plan_tier
    when 'starter'
      200_000
    when 'professional'
      1_000_000
    when 'business'
      2_000_000
    else
      200_000
    end

    # Update entity with trial status
    entity.update!(
      subscription_status: 'trialing',
      trial_ends_at: 7.days.from_now,
      plan_tier: plan_tier,
      token_limit: token_limit
    )

    # Set session flag to show subscription confirmation in onboarding
    session[:show_subscription_confirmation] = true

    # Redirect to onboarding
    redirect_to onboarding_path, notice: "Welcome! Your 7-day trial has started."
  end

  def success
    session_id = params[:session_id]

    # Handle case where Stripe doesn't replace the template variable
    # This happens when user cancels checkout or session expires
    if session_id.blank? || session_id == '{CHECKOUT_SESSION_ID}'
      Rails.logger.warn "Invalid session_id received: #{session_id.inspect}"
      redirect_to new_subscription_path, alert: "Checkout was cancelled or expired. Please try again."
      return
    end

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

      # Set session flag to show subscription confirmation in onboarding
      session[:show_subscription_confirmation] = true

      # Redirect to onboarding
      redirect_to onboarding_path, notice: "Welcome! Your 7-day trial has started."
    rescue Stripe::StripeError => e
      Rails.logger.error "Error retrieving checkout session: #{e.message}"
      redirect_to new_subscription_path, alert: "There was an error processing your subscription."
    end
  end

  def cancel
    redirect_to new_subscription_path
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
