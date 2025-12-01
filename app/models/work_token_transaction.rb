# frozen_string_literal: true

# Ledger entry for all work token movements
# Provides complete audit trail of token credits and debits
class WorkTokenTransaction < ApplicationRecord
  belongs_to :user_billing_account
  belongs_to :user
  belongs_to :entity, optional: true
  belongs_to :source, polymorphic: true, optional: true

  # Transaction types
  TRANSACTION_TYPES = %w[purchase usage refund bonus adjustment expiry].freeze
  
  # Categories
  CATEGORIES = %w[
    token_purchase
    signup_bonus
    referral_bonus
    promo_credit
    ai_tokens
    email
    storage
    api_call
    other_compute
    refund
    admin_adjustment
    expiry
  ].freeze

  # Validations
  validates :transaction_type, presence: true, inclusion: { in: TRANSACTION_TYPES }
  validates :token_amount, presence: true
  validates :balance_before, presence: true
  validates :balance_after, presence: true

  # Scopes
  scope :credits, -> { where('token_amount > 0') }
  scope :debits, -> { where('token_amount < 0') }
  scope :purchases, -> { where(transaction_type: 'purchase') }
  scope :usage, -> { where(transaction_type: 'usage') }
  scope :recent, -> { order(created_at: :desc) }
  scope :for_category, ->(cat) { where(category: cat) }
  scope :in_date_range, ->(start_date, end_date) { where(created_at: start_date..end_date) }
  scope :this_month, -> { where('created_at >= ?', Time.current.beginning_of_month) }
  scope :today, -> { where('created_at >= ?', Time.current.beginning_of_day) }

  # Instance methods
  def credit?
    token_amount.positive?
  end

  def debit?
    token_amount.negative?
  end

  def absolute_amount
    token_amount.abs
  end

  def formatted_amount
    prefix = credit? ? '+' : ''
    "#{prefix}#{token_amount.to_s(:delimited)}"
  end

  def category_icon
    case category
    when 'ai_tokens' then '🤖'
    when 'email' then '📧'
    when 'storage' then '💾'
    when 'api_call' then '🔌'
    when 'other_compute' then '☁️'
    when 'token_purchase' then '💳'
    when 'signup_bonus', 'referral_bonus', 'promo_credit' then '🎁'
    when 'refund' then '↩️'
    else '📊'
    end
  end

  def category_label
    case category
    when 'ai_tokens' then 'AI Usage'
    when 'email' then 'Email Sending'
    when 'storage' then 'Storage'
    when 'api_call' then 'API Calls'
    when 'other_compute' then 'Other Compute'
    when 'token_purchase' then 'Token Purchase'
    when 'signup_bonus' then 'Signup Bonus'
    when 'referral_bonus' then 'Referral Bonus'
    when 'promo_credit' then 'Promotional Credit'
    when 'refund' then 'Refund'
    when 'admin_adjustment' then 'Admin Adjustment'
    else category&.titleize || 'Other'
    end
  end

  # Class methods for aggregation
  def self.total_credits
    credits.sum(:token_amount)
  end

  def self.total_debits
    debits.sum(:token_amount).abs
  end

  def self.net_change
    sum(:token_amount)
  end

  def self.by_category
    group(:category).sum('ABS(token_amount)')
  end

  def self.daily_usage(days = 30)
    usage
      .where('created_at >= ?', days.days.ago)
      .group('DATE(created_at)')
      .sum('ABS(token_amount)')
  end
end

