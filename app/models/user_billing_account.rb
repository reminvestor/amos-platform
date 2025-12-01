# frozen_string_literal: true

# User's billing account for AMOS Work Tokens
# Each user has their own token balance and payment settings
class UserBillingAccount < ApplicationRecord
  belongs_to :user

  has_many :work_token_transactions, dependent: :destroy
  has_many :work_token_purchases, dependent: :destroy
  has_many :work_token_usage_summaries, dependent: :destroy

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
    
    transaction do
      balance_before = work_token_balance
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
        description: "Purchased #{token_info[:tokens].to_s(:delimited)} tokens" + 
                     (token_info[:bonus] > 0 ? " (+#{token_info[:bonus].to_s(:delimited)} bonus)" : ""),
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
    
    credit_tokens!(
      amount: bonus_amount,
      transaction_type: 'bonus',
      category: 'signup_bonus',
      description: "Welcome bonus: #{bonus_amount.to_s(:delimited)} free AMOS Work Tokens!"
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

