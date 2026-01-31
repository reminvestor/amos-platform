# frozen_string_literal: true

# TokenStake represents ownership in the platform's future revenue
# Stakes are earned through contributions (code, distribution, community)
# and decay over time to recycle tokens for platform operations.
#
# ORGANIC ECONOMICS - DECAY TIED TO PLATFORM COSTS:
# Decay isn't arbitrary - it represents the REAL cost of running the platform.
# - Profitable platform → lower decay (rewarding holders)
# - Unprofitable platform → higher decay (recycling tokens to treasury)
# This creates ORGANIC equilibrium: the token economy self-balances.
#
# DECAY TIMELINE:
# - Month 0-12: GRACE PERIOD (no decay at all)
# - Month 12+: Dynamic decay based on platform economics
# - Floor grows with tenure: 5% → 10% → 15% → 25%
#
# WEALTH PRESERVATION FEATURES:
# - 12-month grace period: New stakes have a full year before decay starts
# - Dynamic decay: Adjusts based on platform revenue vs costs
# - Graduated decay floor: 5% (Y0-1), 10% (Y1-3), 15% (Y3-5), 25% (Y5+)
# - Tenure-based reduction: Rate decreases the longer you hold
# - Staking vaults: Lock tokens for reduced/zero decay
#
# SECURITY: Distribution stakes (affiliate/referral) have a 90-day clawback period.
# If the referred customer churns within 90 days, the stake is clawed back.
class TokenStake < ApplicationRecord
  belongs_to :user
  belongs_to :entity, optional: true
  belongs_to :source, polymorphic: true, optional: true # Contribution, Referral, etc.

  # Fixed supply constants
  TOTAL_SUPPLY = 100_000_000  # 100M tokens ever
  
  # GRACE PERIOD: No decay for the first 12 months
  # Gives new contributors time to see value before decay starts
  GRACE_PERIOD_DAYS = 365
  
  # SECURITY: Clawback period for distribution stakes (days)
  # If referred customer churns within this period, stake is clawed back
  CLAWBACK_PERIOD_DAYS = 90
  
  # Clawback statuses for distribution stakes
  CLAWBACK_STATUSES = %w[
    pending_clawback   # Within 90-day period, can be clawed back
    confirmed          # Past 90 days, stake is confirmed permanent
    clawed_back        # Customer churned, stake was revoked
  ].freeze
  
  # GRADUATED DECAY FLOOR - builds over time
  # Prevents early adopters from locking in permanent advantages
  # while still rewarding long-term commitment
  GRADUATED_DECAY_FLOOR = {
    0 => 0.05,   # Year 0-1: 5% floor (earn your security)
    1 => 0.10,   # Year 1-3: 10% floor
    3 => 0.15,   # Year 3-5: 15% floor  
    5 => 0.25    # Year 5+: 25% floor (maximum security)
  }.freeze
  
  # Halving schedule - rewards decrease over time
  HALVING_SCHEDULE = {
    0 => 1.0,    # Year 0-2: Full rewards
    2 => 0.5,    # Year 2-4: 50% rewards
    4 => 0.25,   # Year 4-6: 25% rewards
    6 => 0.125,  # Year 6-8: 12.5% rewards
    8 => 0.0625  # Year 8+: 6.25% rewards
  }.freeze

  # Tenure-based decay REDUCTION (longer hold = lower decay)
  # Applied as multiplier to base rate from PlatformEconomicsService
  TENURE_DECAY_REDUCTION = {
    0 => 0.00,   # Year 0-2: No reduction (full dynamic rate)
    2 => 0.20,   # Year 2-5: 20% reduction from base
    5 => 0.40,   # Year 5-10: 40% reduction from base
    10 => 0.70   # Year 10+: 70% reduction (near-permanent)
  }.freeze

  # Staking vault tiers (lock for reduced decay)
  STAKING_TIERS = {
    none: { decay_reduction: 0.0, min_lock_years: 0 },
    bronze: { decay_reduction: 0.25, min_lock_years: 1 },
    silver: { decay_reduction: 0.50, min_lock_years: 3 },
    gold: { decay_reduction: 0.75, min_lock_years: 5 },
    permanent: { decay_reduction: 1.0, min_lock_years: 10 }
  }.freeze

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
  
  # Clawback-related scopes
  scope :pending_clawback, -> { distribution_stakes.where(clawback_status: 'pending_clawback') }
  scope :eligible_for_confirmation, -> { pending_clawback.where('earned_at < ?', CLAWBACK_PERIOD_DAYS.days.ago) }
  scope :confirmed, -> { where(clawback_status: 'confirmed') }
  scope :clawed_back, -> { where(clawback_status: 'clawed_back') }

  # Callbacks
  before_validation :set_defaults, on: :create
  after_create :record_stake_transaction

  # Instance methods
  
  # Calculate the current decay floor percentage based on tenure
  # Floor grows over time: 5% → 10% → 15% → 25%
  def current_floor_percentage
    years = tenure_years
    
    applicable_floor = GRADUATED_DECAY_FLOOR[0]
    GRADUATED_DECAY_FLOOR.each do |threshold, floor|
      applicable_floor = floor if years >= threshold
    end
    
    applicable_floor
  end

  # Calculate the permanent floor amount (never decays)
  # This grows with tenure - early stakes have smaller floors
  def permanent_floor_amount
    initial_amount * current_floor_percentage
  end

  # Calculate the decayable portion
  def decayable_amount
    initial_amount * (1 - current_floor_percentage)
  end

  # Get tenure in years
  def tenure_years
    return 0 unless earned_at
    ((Time.current - earned_at) / 1.year).floor
  end
  
  # Get tenure in days
  def tenure_days
    return 0 unless earned_at
    ((Time.current - earned_at) / 1.day).floor
  end
  
  # Check if stake is within the 12-month grace period (no decay)
  def within_grace_period?
    tenure_days < GRACE_PERIOD_DAYS
  end
  
  # Days remaining in grace period
  def grace_period_days_remaining
    return 0 unless within_grace_period?
    GRACE_PERIOD_DAYS - tenure_days
  end
  
  # Get the maximum floor this stake will eventually have
  def maximum_floor_percentage
    GRADUATED_DECAY_FLOOR.values.max
  end
  
  # Years until stake reaches maximum floor
  def years_until_max_floor
    max_tenure = GRADUATED_DECAY_FLOOR.keys.max
    [max_tenure - tenure_years, 0].max
  end

  # Get effective decay rate based on platform economics, tenure, and staking
  # DYNAMIC DECAY: Rate adjusts based on platform financial health
  # - Profitable platform → lower decay (rewarding token holders)
  # - Unprofitable platform → higher decay (recycling tokens to fund operations)
  def effective_annual_decay_rate
    # Start with dynamic base rate from platform economics
    base_rate = PlatformEconomicsService.current_decay_rate
    
    # Apply tenure-based reduction (longer hold = lower decay)
    tenure_reduction = tenure_based_decay_reduction
    base_rate = base_rate * (1 - tenure_reduction)
    
    # Apply staking vault reduction if locked
    if locked? && staking_tier.present?
      tier = STAKING_TIERS[staking_tier.to_sym]
      if tier
        vault_reduction = tier[:decay_reduction]
        base_rate = base_rate * (1 - vault_reduction)
      end
    end
    
    base_rate.round(4)
  end

  # Get decay reduction percentage based on how long stake has been held
  # Longer tenure = lower decay (rewarding commitment)
  def tenure_based_decay_reduction
    years = tenure_years
    
    # Find the applicable reduction based on tenure
    applicable_reduction = TENURE_DECAY_REDUCTION[0]
    TENURE_DECAY_REDUCTION.each do |threshold, reduction|
      applicable_reduction = reduction if years >= threshold
    end
    
    applicable_reduction
  end
  
  # Get explanation of current decay rate for transparency
  def decay_rate_explanation
    platform_rate = PlatformEconomicsService.current_decay_rate
    tenure_reduction = tenure_based_decay_reduction
    effective_rate = effective_annual_decay_rate
    
    {
      platform_base_rate: (platform_rate * 100).round(2),
      tenure_reduction_percent: (tenure_reduction * 100).round(1),
      staking_reduction_percent: locked? ? ((STAKING_TIERS[staking_tier.to_sym][:decay_reduction] || 0) * 100).round(1) : 0,
      effective_rate_percent: (effective_rate * 100).round(2),
      within_grace_period: within_grace_period?,
      grace_days_remaining: grace_period_days_remaining,
      platform_health: PlatformEconomicsService.decay_rate_explanation[:status]
    }
  end

  def apply_decay!
    return if fully_decayed?
    return if at_floor? # Already at permanent floor, no more decay
    return if within_grace_period? # 12-month grace period - no decay

    # Calculate days since grace period ended OR last decay (whichever is later)
    grace_period_end = earned_at + GRACE_PERIOD_DAYS.days
    decay_start = [grace_period_end, last_decay_at].compact.max
    
    days_since_last_decay = (Time.current - decay_start) / 1.day
    return if days_since_last_decay < 1

    # Only decay the decayable portion (above the floor)
    floor = permanent_floor_amount
    decayable = current_amount - floor
    
    return if decayable <= 0 # Already at or below floor

    # Calculate decay with tenure-based rate
    daily_rate = 1 - ((1 - effective_annual_decay_rate) ** (1.0 / 365))
    decay_factor = (1 - daily_rate) ** days_since_last_decay.floor
    new_decayable = (decayable * decay_factor).round(4)
    
    new_amount = floor + new_decayable

    update!(
      current_amount: [new_amount, floor].max,
      last_decay_at: Time.current,
      total_decayed: initial_amount - [new_amount, floor].max
    )
  end

  def at_floor?
    current_amount <= permanent_floor_amount
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
    # Convert annual decay rate to daily using effective rate
    1 - ((1 - effective_annual_decay_rate) ** (1.0 / 365))
  end

  def projected_value_at(future_date)
    days_until = (future_date - Time.current) / 1.day
    return current_amount if days_until <= 0

    floor = permanent_floor_amount
    decayable = current_amount - floor
    
    return floor if decayable <= 0
    
    # Account for grace period in projection
    if within_grace_period?
      grace_remaining = grace_period_days_remaining
      if days_until <= grace_remaining
        # Entire projection period is within grace period - no decay
        return current_amount
      else
        # Partial grace period remaining, then decay starts
        decay_days = days_until - grace_remaining
        decay_factor = (1 - daily_decay_rate) ** decay_days
        projected = floor + (decayable * decay_factor)
        return projected.round(4)
      end
    end

    decay_factor = (1 - daily_decay_rate) ** days_until
    projected = floor + (decayable * decay_factor)
    projected.round(4)
  end

  def half_life_days
    rate = effective_annual_decay_rate
    return Float::INFINITY if rate.zero?
    daily_rate = 1 - ((1 - rate) ** (1.0 / 365))
    Math.log(0.5) / Math.log(1 - daily_rate)
  end

  # Lock stake in vault for reduced decay
  def lock_in_vault!(years:)
    tier_name = STAKING_TIERS.find { |name, config| config[:min_lock_years] == years }&.first
    raise ArgumentError, "Invalid lock period: #{years} years. Valid: #{STAKING_TIERS.map { |k, v| v[:min_lock_years] }.join(', ')}" unless tier_name
    
    update!(
      locked_until: years.years.from_now,
      is_locked: true,
      staking_tier: tier_name.to_s
    )
  end

  # Check if stake is currently locked
  def locked?
    is_locked && locked_until.present? && locked_until > Time.current
  end

  # === CLAWBACK METHODS ===
  
  # Check if this stake is within the clawback period
  def within_clawback_period?
    return false unless stake_type == 'distribution'
    return false unless earned_at
    earned_at > CLAWBACK_PERIOD_DAYS.days.ago
  end

  # Check if stake can be clawed back
  def clawbackable?
    stake_type == 'distribution' && 
      clawback_status == 'pending_clawback' &&
      within_clawback_period?
  end

  # Confirm the stake after clawback period passes
  def confirm_stake!
    return false unless stake_type == 'distribution'
    return false if within_clawback_period?
    return false if clawback_status == 'clawed_back'
    
    update!(clawback_status: 'confirmed')
    Rails.logger.info "[TOKEN_STAKE] Stake ##{id} confirmed after #{CLAWBACK_PERIOD_DAYS}-day clawback period"
    true
  end

  # Clawback the stake (customer churned)
  # Returns tokens to treasury
  def clawback!(reason: nil)
    return false unless clawbackable?
    
    clawed_amount = current_amount
    
    update!(
      clawback_status: 'clawed_back',
      current_amount: 0,
      total_decayed: initial_amount,
      metadata: (metadata || {}).merge(
        clawback_reason: reason,
        clawback_at: Time.current,
        clawed_amount: clawed_amount
      )
    )
    
    # Record the clawback transaction
    TokenStakeTransaction.create!(
      token_stake: self,
      user: user,
      transaction_type: 'clawback',
      amount: -clawed_amount,
      balance_before: clawed_amount,
      balance_after: 0,
      description: "Clawback: #{reason || 'Customer churned within 90 days'}",
      metadata: { clawed_amount: clawed_amount }
    )
    
    Rails.logger.info "[TOKEN_STAKE] Stake ##{id} clawed back: #{clawed_amount} AMOS returned to treasury"
    true
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
    # SECURITY: All distribution stakes start in pending_clawback status
    # and are confirmed after 90 days if the customer doesn't churn
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
        clawback_status: 'pending_clawback', # SECURITY: Subject to 90-day clawback
        metadata: metadata.merge(clawback_eligible_until: (Time.current + CLAWBACK_PERIOD_DAYS.days).iso8601)
      )
    end
    
    # Confirm all distribution stakes that have passed the clawback period
    def confirm_eligible_stakes!
      count = 0
      eligible_for_confirmation.find_each do |stake|
        stake.confirm_stake! && count += 1
      end
      Rails.logger.info "[TOKEN_STAKE] Confirmed #{count} stakes after clawback period"
      count
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
      # DYNAMIC DECAY: Rate comes from platform economics, not fixed values
      # All stake types use same base rate (reduces with tenure)
      # This ensures decay is tied to REAL platform costs, not arbitrary numbers
      PlatformEconomicsService.current_decay_rate
    end

    # Get current halving multiplier based on platform age
    def current_halving_multiplier
      # Assuming platform launch date - adjust as needed
      platform_launch = Time.parse('2024-01-01')
      years_since_launch = ((Time.current - platform_launch) / 1.year).floor
      
      applicable_multiplier = 1.0
      HALVING_SCHEDULE.each do |threshold, multiplier|
        applicable_multiplier = multiplier if years_since_launch >= threshold
      end
      
      applicable_multiplier
    end

    # Calculate stake amount with halving applied
    def calculate_stake_with_halving(base_amount)
      (base_amount * current_halving_multiplier).round(4)
    end

    # Check remaining treasury supply
    def treasury_remaining
      total_issued = active.sum(:initial_amount)
      TOTAL_SUPPLY * 0.60 - total_issued # 60% allocated to treasury
    end

    def treasury_depleted?
      treasury_remaining <= 0
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
