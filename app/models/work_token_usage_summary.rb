# frozen_string_literal: true

# Daily aggregation of work token usage for reporting
class WorkTokenUsageSummary < ApplicationRecord
  belongs_to :user_billing_account
  belongs_to :user
  belongs_to :entity, optional: true

  # Validations
  validates :summary_date, presence: true
  validates :category, presence: true
  validates :user_billing_account_id, uniqueness: { scope: [:summary_date, :category] }

  # Scopes
  scope :for_date, ->(date) { where(summary_date: date) }
  scope :for_date_range, ->(start_date, end_date) { where(summary_date: start_date..end_date) }
  scope :for_category, ->(cat) { where(category: cat) }
  scope :this_month, -> { where(summary_date: Date.current.beginning_of_month..Date.current) }
  scope :last_30_days, -> { where(summary_date: 30.days.ago.to_date..Date.current) }

  # Class methods
  def self.record_usage!(billing_account:, user:, entity: nil, category:, tokens:, raw_cost_cents: 0, uplifted_cost_cents: 0, breakdown: {})
    summary = find_or_initialize_by(
      user_billing_account: billing_account,
      user: user,
      entity: entity,
      summary_date: Date.current,
      category: category
    )
    
    summary.tokens_used += tokens
    summary.transaction_count += 1
    summary.raw_cost_cents += raw_cost_cents
    summary.uplifted_cost_cents += uplifted_cost_cents
    
    # Merge breakdown (for AI tokens by model)
    if breakdown.present?
      existing = summary.breakdown || {}
      breakdown.each do |key, value|
        existing[key] = (existing[key] || 0) + value
      end
      summary.breakdown = existing
    end
    
    summary.save!
    summary
  end

  # Aggregation methods
  def self.total_tokens
    sum(:tokens_used)
  end

  def self.total_cost_usd
    sum(:uplifted_cost_cents) / 100.0
  end

  def self.by_category
    group(:category).sum(:tokens_used)
  end

  def self.daily_totals
    group(:summary_date).sum(:tokens_used)
  end

  # Instance methods
  def cost_usd
    uplifted_cost_cents / 100.0
  end

  def raw_cost_usd
    raw_cost_cents / 100.0
  end

  def markup_amount_usd
    cost_usd - raw_cost_usd
  end
end

