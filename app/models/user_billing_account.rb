# frozen_string_literal: true

# User's billing account for AMOS Work Tokens
# Each user has their own token balance and payment settings
class UserBillingAccount < ApplicationRecord
  belongs_to :user

  has_many :work_token_transactions, dependent: :destroy
  has_many :work_token_purchases, dependent: :destroy
  has_many :work_token_usage_summaries, dependent: :destroy

  # Token usage threshold notifications (percentage of initial free tokens used)
  # Users without payment methods get reminded at these thresholds
  USAGE_THRESHOLDS = [25, 50, 75, 90].freeze

  # Validations
  validates :user_id, uniqueness: true
  validates :work_token_balance, numericality: { greater_than_or_equal_to: 0 }
  validates :auto_replenish_amount_usd, numericality: { greater_than_or_equal_to: 0 }
  validates :monthly_limit_usd, numericality: { greater_than_or_equal_to: 0 }
  validates :status, inclusion: { in: %w[active suspended closed] }

  # Scopes
  scope :active, -> { where(status: 'active') }
  scope :needs_replenishment, -> { 
    active
      .where(auto_replenish_enabled: true)
      .where(has_payment_method: true)
      .where('work_token_balance <= auto_replenish_threshold')
  }
  scope :low_balance, -> { where('work_token_balance < ?', 10_000) }

  # Callbacks
  after_create :grant_signup_bonus

  # Class methods
  def self.for_user(user)
    find_or_create_by!(user: user) do |account|
      config = BillingConfiguration.current
      account.auto_replenish_amount_usd = config.default_auto_replenish_amount_usd
      account.monthly_limit_usd = config.default_monthly_limit_usd
      account.free_tokens_remaining = config.free_tokens_on_signup
    end
  end

  # Balance methods
  def available_balance
    work_token_balance
  end

  def has_sufficient_balance?(tokens_needed)
    work_token_balance >= tokens_needed
  end

  def low_balance?
    work_token_balance < auto_replenish_threshold
  end

  def can_auto_replenish?
    auto_replenish_enabled? && 
      has_payment_method? && 
      status == 'active' &&
      within_monthly_limit?
  end

  def within_monthly_limit?
    return true if monthly_limit_usd.zero? # No limit set
    
    potential_spend = current_month_spend_usd + auto_replenish_amount_usd
    potential_spend <= monthly_limit_usd
  end

  # Debit tokens from balance
  def debit_tokens!(amount:, category:, description:, source: nil, metadata: {})
    raise InsufficientBalanceError, "Insufficient balance" unless has_sufficient_balance?(amount)
    
    balance_before = work_token_balance
    
    transaction do
      new_balance = work_token_balance - amount
      
      update!(
        work_token_balance: new_balance,
        lifetime_tokens_used: lifetime_tokens_used + amount,
        last_usage_at: Time.current
      )
      
      work_token_transactions.create!(
        user: user,
        transaction_type: 'usage',
        category: category,
        token_amount: -amount,
        balance_before: balance_before,
        balance_after: new_balance,
        description: description,
        source: source,
        metadata: metadata
      )
    end
    
    # Check for threshold notifications (only if no payment method)
    check_usage_threshold_notification!(balance_before) unless has_payment_method?
    
    # Check if auto-replenishment is needed
    check_auto_replenishment! if low_balance?
    
    true
  end

  # Credit tokens to balance
  def credit_tokens!(amount:, transaction_type:, category:, description:, stripe_payment_intent_id: nil, metadata: {})
    transaction do
      balance_before = work_token_balance
      new_balance = work_token_balance + amount
      
      update!(
        work_token_balance: new_balance,
        lifetime_tokens_purchased: transaction_type == 'purchase' ? lifetime_tokens_purchased + amount : lifetime_tokens_purchased,
        last_purchase_at: transaction_type == 'purchase' ? Time.current : last_purchase_at
      )
      
      work_token_transactions.create!(
        user: user,
        transaction_type: transaction_type,
        category: category,
        token_amount: amount,
        balance_before: balance_before,
        balance_after: new_balance,
        description: description,
        stripe_payment_intent_id: stripe_payment_intent_id,
        metadata: metadata
      )
    end
    
    true
  end

  # Purchase tokens
  def purchase_tokens!(amount_usd:, stripe_payment_intent_id: nil, trigger: 'manual')
    config = BillingConfiguration.current
    token_info = config.tokens_for_purchase(amount_usd)
    
    purchase = work_token_purchases.create!(
      user: user,
      amount_usd_cents: (amount_usd * 100).to_i,
      tokens_purchased: token_info[:tokens],
      bonus_tokens: token_info[:bonus],
      purchase_tier: config.tier_for_amount(amount_usd)['amount_usd'].to_s,
      stripe_payment_intent_id: stripe_payment_intent_id,
      status: 'pending',
      trigger: trigger
    )
    
    begin
      # Process Stripe payment if needed
      if stripe_payment_intent_id.nil? && has_payment_method?
        payment_intent = create_stripe_payment(amount_usd)
        purchase.update!(stripe_payment_intent_id: payment_intent.id)
        
        # Confirm the payment
        payment_intent.confirm
      end
      
      # Credit the tokens
      credit_tokens!(
        amount: token_info[:total],
        transaction_type: 'purchase',
        category: 'token_purchase',
        description: "Purchased #{ActiveSupport::NumberHelper.number_to_delimited(token_info[:tokens])} tokens" + 
                     (token_info[:bonus] > 0 ? " (+#{ActiveSupport::NumberHelper.number_to_delimited(token_info[:bonus])} bonus)" : ""),
        stripe_payment_intent_id: purchase.stripe_payment_intent_id,
        metadata: { purchase_id: purchase.id, amount_usd: amount_usd }
      )
      
      purchase.update!(status: 'completed')
      
      # Update monthly spend
      update!(current_month_spend_usd: current_month_spend_usd + amount_usd)
      
      purchase
    rescue Stripe::StripeError => e
      purchase.update!(status: 'failed', failure_reason: e.message)
      raise PaymentFailedError, e.message
    end
  end

  # Trigger auto-replenishment check
  def check_auto_replenishment!
    return unless can_auto_replenish? && low_balance?
    
    AutoReplenishTokensJob.perform_later(id)
  end

  # Check if we've crossed a usage threshold and need to notify user
  def check_usage_threshold_notification!(balance_before)
    return if has_payment_method? # Users with payment methods don't need reminders
    
    initial_tokens = free_tokens_granted || BillingConfiguration.current.free_tokens_on_signup
    return if initial_tokens.zero?
    
    # Calculate usage percentages before and after
    usage_before = ((initial_tokens - balance_before).to_f / initial_tokens * 100).round
    usage_after = ((initial_tokens - work_token_balance).to_f / initial_tokens * 100).round
    
    # Find thresholds we just crossed
    USAGE_THRESHOLDS.each do |threshold|
      if usage_before < threshold && usage_after >= threshold
        # We just crossed this threshold - trigger notification
        trigger_threshold_notification!(threshold)
        break # Only trigger one notification at a time
      end
    end
    
    # Check for 100% usage (out of tokens)
    if work_token_balance <= 0 && balance_before > 0
      trigger_threshold_notification!(100)
    end
  end

  # Trigger a threshold notification
  def trigger_threshold_notification!(threshold)
    # Store the last notified threshold to avoid duplicate notifications
    return if last_threshold_notified.to_i >= threshold
    
    update_column(:last_threshold_notified, threshold)
    
    # Broadcast notification via ActionCable
    broadcast_billing_notification(threshold)
    
    # Log for debugging
    Rails.logger.info "💳 Billing threshold notification: User #{user_id} reached #{threshold}% usage"
  end

  # Broadcast billing notification to user
  def broadcast_billing_notification(threshold)
    message = case threshold
    when 25
      {
        type: 'billing_reminder',
        level: 'info',
        title: "You've used 25% of your free tokens",
        message: "Add a payment method to ensure uninterrupted service when your free tokens run out.",
        action_url: '/billing/setup_payment',
        action_text: 'Add Payment Method',
        dismissable: true
      }
    when 50
      {
        type: 'billing_reminder',
        level: 'warning',
        title: "50% of free tokens used",
        message: "You're halfway through your free tokens. Add a payment method now to avoid any interruption.",
        action_url: '/billing/setup_payment',
        action_text: 'Add Payment Method',
        dismissable: true
      }
    when 75
      {
        type: 'billing_reminder',
        level: 'warning',
        title: "75% of free tokens used",
        message: "You're running low on free tokens! Add a payment method to continue using AMOS without interruption.",
        action_url: '/billing/setup_payment',
        action_text: 'Add Payment Method',
        dismissable: true
      }
    when 90
      {
        type: 'billing_reminder',
        level: 'danger',
        title: "Almost out of tokens!",
        message: "You've used 90% of your free tokens. Add a payment method now to avoid losing access.",
        action_url: '/billing/setup_payment',
        action_text: 'Add Payment Method Now',
        dismissable: false
      }
    when 100
      {
        type: 'billing_required',
        level: 'danger',
        title: "Out of tokens",
        message: "You've used all your free tokens. Please add a payment method to continue using AMOS.",
        action_url: '/billing/setup_payment',
        action_text: 'Add Payment Method',
        dismissable: false,
        blocking: true
      }
    end
    
    return unless message
    
    # Broadcast to user's notification channel
    ActionCable.server.broadcast(
      "user_notifications_#{user_id}",
      message.merge(timestamp: Time.current.iso8601)
    )
    
    # Also store as a persistent notification
    create_billing_notification!(threshold, message)
  end

  # Create a persistent notification record
  def create_billing_notification!(threshold, message)
    # Use the Notification model if it exists, otherwise just log
    if defined?(Notification)
      Notification.create(
        user: user,
        notification_type: message[:type],
        title: message[:title],
        message: message[:message],
        action_url: message[:action_url],
        level: message[:level],
        metadata: { threshold: threshold, billing_account_id: id }
      )
    end
  rescue => e
    Rails.logger.warn "Could not create billing notification: #{e.message}"
  end

  # Get current usage percentage
  def usage_percentage
    initial_tokens = free_tokens_granted || BillingConfiguration.current.free_tokens_on_signup
    return 0 if initial_tokens.zero?
    
    used = initial_tokens - work_token_balance
    ((used.to_f / initial_tokens) * 100).round(1)
  end

  # Get remaining percentage
  def remaining_percentage
    100 - usage_percentage
  end

  # Check if user is blocked due to no tokens and no payment method
  def blocked?
    work_token_balance <= 0 && !has_payment_method?
  end

  # Reset threshold notifications (e.g., after adding payment method)
  def reset_threshold_notifications!
    update_column(:last_threshold_notified, nil)
  end

  # Stripe integration
  def ensure_stripe_customer!
    return stripe_customer_id if stripe_customer_id.present?
    
    customer = Stripe::Customer.create(
      email: user.email,
      name: user.full_name,
      metadata: {
        user_id: user.id,
        billing_account_id: id
      }
    )
    
    update!(stripe_customer_id: customer.id)
    customer.id
  end

  def attach_payment_method!(payment_method_id)
    ensure_stripe_customer!
    
    # Attach the payment method to the customer
    Stripe::PaymentMethod.attach(
      payment_method_id,
      { customer: stripe_customer_id }
    )
    
    # Set as default
    Stripe::Customer.update(
      stripe_customer_id,
      { invoice_settings: { default_payment_method: payment_method_id } }
    )
    
    update!(
      stripe_default_payment_method_id: payment_method_id,
      has_payment_method: true
    )
    
    # Reset threshold notifications since user now has payment method
    reset_threshold_notifications!
    
    # Broadcast that user has added payment method (clears any blocking notifications)
    ActionCable.server.broadcast(
      "user_notifications_#{user_id}",
      {
        type: 'billing_resolved',
        level: 'success',
        title: 'Payment method added!',
        message: 'Your payment method has been saved. Auto-replenishment is now available.',
        dismissable: true,
        timestamp: Time.current.iso8601
      }
    )
    
    true
  end

  def remove_payment_method!
    if stripe_default_payment_method_id.present?
      Stripe::PaymentMethod.detach(stripe_default_payment_method_id)
    end
    
    update!(
      stripe_default_payment_method_id: nil,
      has_payment_method: false,
      auto_replenish_enabled: false
    )
    
    true
  end

  def payment_method_details
    return nil unless stripe_default_payment_method_id.present?
    
    pm = Stripe::PaymentMethod.retrieve(stripe_default_payment_method_id)
    {
      brand: pm.card.brand,
      last4: pm.card.last4,
      exp_month: pm.card.exp_month,
      exp_year: pm.card.exp_year
    }
  rescue Stripe::StripeError
    nil
  end

  # Suspend account
  def suspend!(reason:)
    update!(
      status: 'suspended',
      suspended_at: Time.current,
      suspension_reason: reason,
      auto_replenish_enabled: false
    )
  end

  # Reactivate account
  def reactivate!
    update!(
      status: 'active',
      suspended_at: nil,
      suspension_reason: nil
    )
  end

  # Usage statistics
  def usage_this_month
    work_token_transactions
      .where(transaction_type: 'usage')
      .where('created_at >= ?', Time.current.beginning_of_month)
      .sum(:token_amount)
      .abs
  end

  def usage_by_category_this_month
    work_token_transactions
      .where(transaction_type: 'usage')
      .where('created_at >= ?', Time.current.beginning_of_month)
      .group(:category)
      .sum('ABS(token_amount)')
  end

  def spending_this_month_usd
    config = BillingConfiguration.current
    config.tokens_to_usd(usage_this_month)
  end

  private

  def grant_signup_bonus
    config = BillingConfiguration.current
    bonus_amount = config.free_tokens_on_signup
    
    return if bonus_amount.zero?
    
    # Track how many free tokens were granted for threshold calculations
    update_column(:free_tokens_granted, bonus_amount)
    
    credit_tokens!(
      amount: bonus_amount,
      transaction_type: 'bonus',
      category: 'signup_bonus',
      description: "Welcome bonus: #{ActiveSupport::NumberHelper.number_to_delimited(bonus_amount)} free AMOS Work Tokens!"
    )
  end

  def create_stripe_payment(amount_usd)
    Stripe::PaymentIntent.create(
      amount: (amount_usd * 100).to_i, # Convert to cents
      currency: 'usd',
      customer: stripe_customer_id,
      payment_method: stripe_default_payment_method_id,
      off_session: true,
      confirm: false,
      metadata: {
        user_id: user.id,
        billing_account_id: id,
        type: 'work_token_purchase'
      }
    )
  end

  # Custom errors
  class InsufficientBalanceError < StandardError; end
  class PaymentFailedError < StandardError; end
end

