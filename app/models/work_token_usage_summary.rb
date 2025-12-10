# frozen_string_literal: true

# Daily aggregation of work token usage for reporting
# Supports both individual user billing and shared entity token pools
class WorkTokenUsageSummary < ApplicationRecord
  belongs_to :user_billing_account, optional: true
  belongs_to :entity_billing_account, optional: true
  belongs_to :user
  belongs_to :entity, optional: true

  # Validations
  validates :summary_date, presence: true
  validates :category, presence: true
  validate :has_billing_account

  # Scopes
  scope :for_date, ->(date) { where(summary_date: date) }
  scope :for_date_range, ->(start_date, end_date) { where(summary_date: start_date..end_date) }
  scope :for_category, ->(cat) { where(category: cat) }
  scope :this_month, -> { where(summary_date: Date.current.beginning_of_month..Date.current) }
  scope :last_30_days, -> { where(summary_date: 30.days.ago.to_date..Date.current) }
  scope :for_user_account, ->(account) { where(user_billing_account: account) }
  scope :for_entity_account, ->(account) { where(entity_billing_account: account) }

  # Class methods - supports both billing account types
  def self.record_usage!(user:, entity: nil, category:, tokens:, raw_cost_cents: 0, uplifted_cost_cents: 0, breakdown: {}, billing_account: nil, entity_billing_account: nil)
    find_params = {
      user: user,
      entity: entity,
      summary_date: Date.current,
      category: category
    }
    
    # Determine which billing account type to use
    if entity_billing_account
      find_params[:entity_billing_account] = entity_billing_account
    elsif billing_account
      find_params[:user_billing_account] = billing_account
    end
    
    summary = find_or_initialize_by(find_params)
    
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
  
  # Check if using shared pool
  def shared_pool?
    entity_billing_account_id.present?
  end
  
  private
  
  def has_billing_account
    unless user_billing_account_id.present? || entity_billing_account_id.present?
      errors.add(:base, "Must have either a user or entity billing account")
    end
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

