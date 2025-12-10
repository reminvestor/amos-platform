# frozen_string_literal: true

# Entity's shared billing account for AMOS Work Tokens
# Allows teams to share a token pool instead of individual accounts
class EntityBillingAccount < ApplicationRecord
  belongs_to :entity

  has_many :work_token_transactions, dependent: :destroy
  has_many :work_token_usage_summaries, dependent: :destroy

  # Token usage threshold notifications
  USAGE_THRESHOLDS = [25, 50, 75, 90].freeze

  # Validations
  validates :entity_id, uniqueness: true
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

  # Errors
  class InsufficientBalanceError < StandardError; end
  class PaymentFailedError < StandardError; end

  # Class methods
  def self.for_entity(entity)
    find_or_create_by!(entity: entity) do |account|
      config = BillingConfiguration.current
      account.auto_replenish_amount_usd = config.default_auto_replenish_amount_usd
      account.monthly_limit_usd = config.default_monthly_limit_usd
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
    return true if monthly_limit_usd.zero?

    potential_spend = current_month_spend_usd + auto_replenish_amount_usd
    potential_spend <= monthly_limit_usd
  end

  def current_month_spend_usd
    (current_month_spend_cents || 0) / 100.0
  end

  # Debit tokens allowing negative balance (for tracking all usage)
  def debit_tokens_allow_negative!(amount:, category:, description:, user:, source: nil, metadata: {})
    balance_before = work_token_balance

    transaction do
      new_balance = work_token_balance - amount

      update_columns(
        work_token_balance: new_balance,
        lifetime_tokens_used: lifetime_tokens_used + amount,
        last_usage_at: Time.current,
        updated_at: Time.current
      )

      work_token_transactions.create!(
        user: user,
        entity: entity,
        transaction_type: 'usage',
        category: category,
        token_amount: -amount,
        balance_before: balance_before,
        balance_after: new_balance,
        description: description,
        source: source,
        metadata: metadata.merge(
          shared_pool: true,
          allowed_negative: new_balance < 0
        )
      )
    end

    # Check for threshold notifications
    check_usage_threshold_notification!(balance_before) unless has_payment_method?

    # Check if auto-replenishment is needed
    check_auto_replenishment! if low_balance?

    true
  end

  # Credit tokens to balance
  def credit_tokens!(amount:, transaction_type:, category:, description:, user: nil, stripe_payment_intent_id: nil, metadata: {})
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
        entity: entity,
        transaction_type: transaction_type,
        category: category,
        token_amount: amount,
        balance_before: balance_before,
        balance_after: new_balance,
        description: description,
        metadata: metadata.merge(
          stripe_payment_intent_id: stripe_payment_intent_id,
          shared_pool: true
        ).compact
      )
    end

    # Reset threshold notifications when tokens are added
    update_column(:last_threshold_notified, nil) if work_token_balance > 0

    true
  end

  # Ensure Stripe customer exists for entity
  def ensure_stripe_customer!
    return if stripe_customer_id.present?

    customer = Stripe::Customer.create(
      name: entity.name,
      email: entity.entity_users.where(role: 'owner').first&.user&.email,
      metadata: {
        entity_id: entity.id,
        entity_name: entity.name,
        billing_type: 'entity_shared_pool'
      }
    )

    update!(stripe_customer_id: customer.id)
    customer
  end

  # Attach payment method to entity billing
  def attach_payment_method!(payment_method_id)
    ensure_stripe_customer!

    # Attach the payment method to the customer
    Stripe::PaymentMethod.attach(
      payment_method_id,
      { customer: stripe_customer_id }
    )

    # Set as default payment method
    Stripe::Customer.update(
      stripe_customer_id,
      { invoice_settings: { default_payment_method: payment_method_id } }
    )

    update!(
      stripe_default_payment_method_id: payment_method_id,
      has_payment_method: true
    )

    true
  rescue Stripe::StripeError => e
    Rails.logger.error "❌ Entity attach payment method failed: #{e.message}"
    raise PaymentFailedError, e.message
  end

  # Get payment method details
  def payment_method_details
    return nil unless has_payment_method? && stripe_default_payment_method_id.present?

    begin
      pm = Stripe::PaymentMethod.retrieve(stripe_default_payment_method_id)
      {
        brand: pm.card&.brand&.capitalize,
        last4: pm.card&.last4,
        exp_month: pm.card&.exp_month,
        exp_year: pm.card&.exp_year
      }
    rescue Stripe::StripeError
      nil
    end
  end

  # Purchase tokens via Stripe
  def purchase_tokens!(amount_usd:, trigger: 'manual', user: nil)
    raise PaymentFailedError, "No payment method on file" unless has_payment_method?
    raise PaymentFailedError, "Amount must be positive" if amount_usd <= 0

    config = BillingConfiguration.current
    tokens_to_add = config.usd_to_tokens(amount_usd)
    amount_cents = (amount_usd * 100).to_i

    # Create Stripe payment intent
    payment_intent = Stripe::PaymentIntent.create(
      amount: amount_cents,
      currency: 'usd',
      customer: stripe_customer_id,
      payment_method: stripe_default_payment_method_id,
      off_session: true,
      confirm: true,
      metadata: {
        entity_id: entity_id,
        tokens: tokens_to_add,
        trigger: trigger,
        shared_pool: true
      }
    )

    if payment_intent.status == 'succeeded'
      credit_tokens!(
        amount: tokens_to_add,
        transaction_type: 'purchase',
        category: 'token_purchase',
        description: "Purchased #{tokens_to_add.to_s(:delimited)} tokens for $#{amount_usd}",
        user: user,
        stripe_payment_intent_id: payment_intent.id,
        metadata: { trigger: trigger, amount_usd: amount_usd }
      )

      # Update monthly spend
      update_column(:current_month_spend_cents, current_month_spend_cents + amount_cents)

      Rails.logger.info "💳 Entity token purchase successful: #{tokens_to_add} tokens for $#{amount_usd}"
      true
    else
      raise PaymentFailedError, "Payment not completed: #{payment_intent.status}"
    end
  rescue Stripe::CardError => e
    Rails.logger.error "❌ Entity Stripe card error: #{e.message}"
    raise PaymentFailedError, e.message
  rescue Stripe::StripeError => e
    Rails.logger.error "❌ Entity Stripe error: #{e.message}"
    raise PaymentFailedError, "Payment processing error"
  end

  # Get usage percentage
  def usage_percentage
    initial_tokens = initial_tokens_granted || BillingConfiguration.current.free_tokens_on_signup
    return 0 if initial_tokens.zero?

    used = initial_tokens - work_token_balance
    ((used.to_f / initial_tokens) * 100).round(1)
  end

  # Check if entity is blocked due to negative balance and no payment method
  def blocked?
    work_token_balance < 0 && !has_payment_method?
  end

  private

  def check_usage_threshold_notification!(balance_before)
    return if Rails.env.development? # Skip billing notifications in development
    initial_tokens = initial_tokens_granted || BillingConfiguration.current.free_tokens_on_signup
    return if initial_tokens.zero?

    usage_before = ((initial_tokens - balance_before).to_f / initial_tokens * 100).round
    usage_after = ((initial_tokens - work_token_balance).to_f / initial_tokens * 100).round

    USAGE_THRESHOLDS.each do |threshold|
      if usage_before < threshold && usage_after >= threshold
        trigger_threshold_notification!(threshold)
        break
      end
    end
  end

  def trigger_threshold_notification!(threshold)
    return if last_threshold_notified.to_i >= threshold

    update_column(:last_threshold_notified, threshold)

    # Notify all admins/owners of the entity
    entity.entity_users.where(role: %w[owner admin]).find_each do |entity_user|
      ActionCable.server.broadcast(
        "user_notifications_#{entity_user.user_id}",
        {
          type: 'billing_reminder',
          level: threshold >= 90 ? 'danger' : 'warning',
          title: "Team token usage at #{threshold}%",
          message: "Your team has used #{threshold}% of shared tokens. Add more tokens to continue.",
          action_url: '/billing/setup_payment',
          action_text: 'Add Tokens',
          dismissable: threshold < 90
        }
      )
    end

    Rails.logger.info "💳 Entity billing threshold: Entity #{entity.id} reached #{threshold}% usage"
  end

  def check_auto_replenishment!
    return unless can_auto_replenish?

    AutoReplenishEntityTokensJob.perform_later(id)
  end
end
