# frozen_string_literal: true

# TokenStake represents ownership in the platform's future revenue
# Stakes are earned through contributions (code, distribution, community)
# and decay over time to incentivize continued participation
class TokenStake < ApplicationRecord
  belongs_to :user
  belongs_to :entity, optional: true
  belongs_to :source, polymorphic: true, optional: true # Contribution, Referral, etc.

  # Stake types
  STAKE_TYPES = %w[
    distribution
    contribution
    community
    founding
    investor
    bonus
  ].freeze

  # Stake categories for distribution type
  DISTRIBUTION_CATEGORIES = %w[
    affiliate_sale
    referral_conversion
    enterprise_deal
  ].freeze

  # Stake categories for contribution type
  CONTRIBUTION_CATEGORIES = %w[
    code_merge
    bug_fix
    feature
    documentation
    review
  ].freeze

  # Stake categories for community type
  COMMUNITY_CATEGORIES = %w[
    support
    content
    evangelism
    feedback
  ].freeze

  # Validations
  validates :stake_type, presence: true, inclusion: { in: STAKE_TYPES }
  validates :initial_amount, presence: true, numericality: { greater_than: 0 }
  validates :current_amount, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :decay_rate, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 1 }

  # Scopes
  scope :active, -> { where('current_amount > 0') }
  scope :by_type, ->(type) { where(stake_type: type) }
  scope :distribution_stakes, -> { by_type('distribution') }
  scope :contribution_stakes, -> { by_type('contribution') }
  scope :community_stakes, -> { by_type('community') }
  scope :for_user, ->(user) { where(user: user) }
  scope :for_entity, ->(entity) { where(entity: entity) }
  scope :earned_between, ->(start_date, end_date) { where(earned_at: start_date..end_date) }
  scope :recent, -> { order(earned_at: :desc) }

  # Callbacks
  before_validation :set_defaults, on: :create
  after_create :record_stake_transaction

  # Instance methods
  def apply_decay!
    return if fully_decayed?

    days_since_last_decay = (Time.current - (last_decay_at || earned_at)) / 1.day
    return if days_since_last_decay < 1

    # Calculate decay: amount * (1 - decay_rate)^days
    decay_factor = (1 - daily_decay_rate) ** days_since_last_decay.floor
    new_amount = (initial_amount * decay_factor).round(4)

    update!(
      current_amount: [new_amount, 0].max,
      last_decay_at: Time.current,
      total_decayed: initial_amount - [new_amount, 0].max
    )
  end

  def fully_decayed?
    current_amount <= 0
  end

  def decay_percentage
    return 100.0 if initial_amount.zero?
    ((initial_amount - current_amount) / initial_amount * 100).round(2)
  end

  def remaining_percentage
    100.0 - decay_percentage
  end

  def daily_decay_rate
    # Convert annual decay rate to daily
    # Formula: daily_rate = 1 - (1 - annual_rate)^(1/365)
    1 - ((1 - decay_rate) ** (1.0 / 365))
  end

  def projected_value_at(future_date)
    days_until = (future_date - Time.current) / 1.day
    return current_amount if days_until <= 0

    decay_factor = (1 - daily_decay_rate) ** days_until
    (current_amount * decay_factor).round(4)
  end

  def half_life_days
    return Float::INFINITY if decay_rate.zero?
    # t_half = ln(0.5) / ln(1 - daily_rate)
    Math.log(0.5) / Math.log(1 - daily_decay_rate)
  end

  # Class methods
  class << self
    def total_supply
      active.sum(:current_amount)
    end

    def total_by_type
      active.group(:stake_type).sum(:current_amount)
    end

    def ownership_distribution
      total = total_supply
      return {} if total.zero?

      active
        .joins(:user)
        .group('users.id', 'users.email')
        .sum(:current_amount)
        .transform_values { |amount| (amount / total * 100).round(4) }
    end

    def top_stakeholders(limit: 20)
      active
        .joins(:user)
        .select('users.id as user_id, users.email, users.first_name, users.last_name, SUM(token_stakes.current_amount) as total_stake')
        .group('users.id', 'users.email', 'users.first_name', 'users.last_name')
        .order('total_stake DESC')
        .limit(limit)
    end

    def apply_decay_to_all!
      active.find_each(&:apply_decay!)
    end

    # Create stake for distribution (affiliate sale, referral, etc.)
    def create_distribution_stake!(user:, amount:, category:, source: nil, metadata: {})
      create!(
        user: user,
        entity: user.entity,
        stake_type: 'distribution',
        category: category,
        initial_amount: amount,
        current_amount: amount,
        decay_rate: default_decay_rate_for('distribution'),
        source: source,
        earned_at: Time.current,
        metadata: metadata
      )
    end

    # Create stake for code/community contribution
    def create_contribution_stake!(user:, amount:, category:, source: nil, metadata: {})
      create!(
        user: user,
        entity: user.entity,
        stake_type: 'contribution',
        category: category,
        initial_amount: amount,
        current_amount: amount,
        decay_rate: default_decay_rate_for('contribution'),
        source: source,
        earned_at: Time.current,
        metadata: metadata
      )
    end

    def default_decay_rate_for(stake_type)
      case stake_type
      when 'distribution' then 0.50    # 50% annual decay
      when 'contribution' then 0.40    # 40% annual decay (code becomes legacy)
      when 'community' then 0.30       # 30% annual decay
      when 'founding' then 0.10        # 10% annual decay (founders vest slower)
      when 'investor' then 0.05        # 5% annual decay
      else 0.50
      end
    end
  end

  private

  def set_defaults
    self.current_amount ||= initial_amount
    self.decay_rate ||= self.class.default_decay_rate_for(stake_type)
    self.earned_at ||= Time.current
    self.total_decayed ||= 0
  end

  def record_stake_transaction
    TokenStakeTransaction.create!(
      token_stake: self,
      user: user,
      transaction_type: 'earn',
      amount: initial_amount,
      balance_before: 0,
      balance_after: initial_amount,
      description: "Earned #{stake_type} stake: #{category}",
      metadata: metadata
    )
  end
end
