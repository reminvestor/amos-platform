# frozen_string_literal: true

# Record of each work token purchase
class WorkTokenPurchase < ApplicationRecord
  belongs_to :user_billing_account
  belongs_to :user
  belongs_to :work_token_transaction, optional: true

  # Status values
  STATUSES = %w[pending completed failed refunded].freeze
  
  # Trigger values
  TRIGGERS = %w[manual auto_replenish admin].freeze

  # Validations
  validates :amount_usd_cents, presence: true, numericality: { greater_than: 0 }
  validates :tokens_purchased, presence: true, numericality: { greater_than: 0 }
  validates :status, inclusion: { in: STATUSES }
  validates :trigger, inclusion: { in: TRIGGERS }

  # Scopes
  scope :completed, -> { where(status: 'completed') }
  scope :pending, -> { where(status: 'pending') }
  scope :failed, -> { where(status: 'failed') }
  scope :recent, -> { order(created_at: :desc) }
  scope :auto_replenish, -> { where(trigger: 'auto_replenish') }
  scope :manual, -> { where(trigger: 'manual') }

  # Instance methods
  def amount_usd
    amount_usd_cents / 100.0
  end

  def total_tokens
    tokens_purchased + (bonus_tokens || 0)
  end

  def completed?
    status == 'completed'
  end

  def pending?
    status == 'pending'
  end

  def failed?
    status == 'failed'
  end

  def refunded?
    status == 'refunded'
  end

  def auto_replenish?
    trigger == 'auto_replenish'
  end

  # Process refund
  def refund!(reason: nil)
    return false unless completed?
    
    transaction do
      # Refund via Stripe
      if stripe_charge_id.present?
        Stripe::Refund.create(charge: stripe_charge_id)
      elsif stripe_payment_intent_id.present?
        Stripe::Refund.create(payment_intent: stripe_payment_intent_id)
      end
      
      # Debit the tokens back
      user_billing_account.debit_tokens!(
        amount: total_tokens,
        category: 'refund',
        description: "Refund for purchase ##{id}" + (reason ? ": #{reason}" : ""),
        metadata: { purchase_id: id, reason: reason }
      )
      
      update!(status: 'refunded')
    end
    
    true
  rescue Stripe::StripeError => e
    Rails.logger.error "Refund failed for purchase #{id}: #{e.message}"
    false
  end
end

