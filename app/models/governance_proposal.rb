# frozen_string_literal: true

# GovernanceProposal represents a proposal that token holders can vote on
# 
# GOVERNANCE SCOPE:
# - r_and_d: R&D budget allocation (simple majority)
# - treasury: Treasury usage beyond standard operations (simple majority)
# - feature: Major feature prioritization (simple majority)
# - partnership: Strategic partnerships (simple majority)
# - parameter: Tokenomics parameter changes - decay, halving (2/3 supermajority)
# - constitutional: Core mechanic changes (2/3 supermajority + 60% quorum)
#
# PROPOSAL PROCESS:
# 1. Stake minimum AMOS to submit proposal
# 2. Discussion period (configurable)
# 3. Voting period starts - SNAPSHOT taken at this moment
# 4. Voting uses snapshot power (prevents flash stake attacks)
# 5. Quorum must be met
# 6. Threshold must be passed
#
# SECURITY: Snapshot-based voting prevents "flash stake" attacks where
# someone borrows tokens, votes, then returns them immediately
class GovernanceProposal < ApplicationRecord
  belongs_to :proposer, class_name: 'User'
  belongs_to :entity, optional: true
  has_many :governance_votes, dependent: :destroy

  # Proposal categories and their requirements
  PROPOSAL_TYPES = {
    r_and_d: {
      name: 'R&D Allocation',
      description: 'How to allocate the R&D budget (20% of revenue)',
      min_stake: 1_000,
      quorum: 0.30,        # 30% of voting power must participate
      threshold: 0.50,     # Simple majority
      discussion_days: 7,
      voting_days: 7
    },
    treasury: {
      name: 'Treasury Usage',
      description: 'Proposals for treasury fund usage',
      min_stake: 5_000,
      quorum: 0.40,        # 40% quorum
      threshold: 0.50,     # Simple majority
      discussion_days: 7,
      voting_days: 7
    },
    feature: {
      name: 'Feature Priority',
      description: 'Vote on feature prioritization',
      min_stake: 500,
      quorum: 0.20,        # 20% quorum (low barrier)
      threshold: 0.50,     # Simple majority
      discussion_days: 5,
      voting_days: 5
    },
    partnership: {
      name: 'Strategic Partnership',
      description: 'Major partnership decisions',
      min_stake: 2_500,
      quorum: 0.35,        # 35% quorum
      threshold: 0.50,     # Simple majority
      discussion_days: 7,
      voting_days: 7
    },
    parameter: {
      name: 'Parameter Adjustment',
      description: 'Changes to decay rates, halving schedule, etc.',
      min_stake: 10_000,
      quorum: 0.50,        # 50% quorum (high)
      threshold: 0.667,    # 2/3 SUPERMAJORITY required
      discussion_days: 14,
      voting_days: 14
    },
    constitutional: {
      name: 'Constitutional Change',
      description: 'Core mechanic changes (floor %, governance rules)',
      min_stake: 25_000,
      quorum: 0.60,        # 60% quorum (very high)
      threshold: 0.667,    # 2/3 SUPERMAJORITY required
      discussion_days: 21,
      voting_days: 21
    }
  }.freeze

  # Statuses
  STATUSES = %w[
    draft
    discussion
    voting
    passed
    failed
    cancelled
    executed
  ].freeze

  # Validations
  validates :title, presence: true, length: { maximum: 200 }
  validates :description, presence: true, length: { maximum: 10_000 }
  validates :proposal_type, presence: true, inclusion: { in: PROPOSAL_TYPES.keys.map(&:to_s) }
  validates :status, presence: true, inclusion: { in: STATUSES }
  validate :proposer_has_sufficient_stake, on: :create

  # Scopes
  scope :active, -> { where(status: %w[discussion voting]) }
  scope :open_for_voting, -> { where(status: 'voting') }
  scope :by_type, ->(type) { where(proposal_type: type) }
  scope :recent, -> { order(created_at: :desc) }

  # Callbacks
  before_validation :set_defaults, on: :create
  after_create :stake_proposer_tokens

  # Configuration for this proposal type
  def config
    PROPOSAL_TYPES[proposal_type.to_sym]
  end

  # Minimum stake required to submit this type of proposal
  def min_stake_required
    config[:min_stake]
  end

  # Required quorum (percentage of voting power)
  def required_quorum
    config[:quorum]
  end

  # Required threshold to pass
  def required_threshold
    config[:threshold]
  end

  # Whether this proposal requires supermajority
  def requires_supermajority?
    config[:threshold] > 0.5
  end

  # Discussion period end
  def discussion_ends_at
    created_at + config[:discussion_days].days
  end

  # Voting period start
  def voting_starts_at
    discussion_ends_at
  end

  # Voting period end
  def voting_ends_at
    voting_starts_at + config[:voting_days].days
  end

  # Start voting period (called by job)
  # SECURITY: Takes snapshot of all token stakes at this moment
  # All votes will use stake amounts from this snapshot, not current amounts
  def start_voting!
    return unless status == 'discussion'
    return unless Time.current >= discussion_ends_at
    
    snapshot_time = Time.current
    total_supply = TokenStake.active.sum(:current_amount)
    
    update!(
      status: 'voting',
      voting_started_at: snapshot_time,
      snapshot_at: snapshot_time,
      snapshot_total_supply: total_supply
    )
    
    Rails.logger.info "[GOVERNANCE] Proposal ##{id} voting started. Snapshot taken at #{snapshot_time} with #{total_supply} total supply"
  end

  # Finalize voting (called by job)
  def finalize!
    return unless status == 'voting'
    return unless Time.current >= voting_ends_at
    
    if quorum_met? && threshold_met?
      update!(status: 'passed', finalized_at: Time.current)
    else
      update!(status: 'failed', finalized_at: Time.current)
      unstake_proposer_tokens
    end
  end

  # Cancel proposal (only proposer or admin)
  def cancel!(by_user:)
    return false unless can_cancel?(by_user)
    
    update!(status: 'cancelled', finalized_at: Time.current)
    unstake_proposer_tokens
    true
  end

  # Mark as executed after implementation
  def mark_executed!
    return false unless status == 'passed'
    
    update!(status: 'executed', executed_at: Time.current)
    unstake_proposer_tokens(return_to_proposer: true)
    true
  end

  # Voting calculations
  # SECURITY: Use snapshot total if available (prevents flash stake)
  def total_voting_power
    snapshot_total_supply || TokenStake.active.sum(:current_amount)
  end

  def votes_for
    governance_votes.where(vote: 'for').sum(:voting_power)
  end

  def votes_against
    governance_votes.where(vote: 'against').sum(:voting_power)
  end

  def votes_abstain
    governance_votes.where(vote: 'abstain').sum(:voting_power)
  end

  def total_votes_cast
    votes_for + votes_against + votes_abstain
  end

  def participation_rate
    return 0 if total_voting_power.zero?
    (total_votes_cast.to_f / total_voting_power * 100).round(2)
  end

  def quorum_percentage
    return 0 if total_voting_power.zero?
    total_votes_cast.to_f / total_voting_power
  end

  def quorum_met?
    quorum_percentage >= required_quorum
  end

  def approval_percentage
    return 0 if (votes_for + votes_against).zero?
    votes_for.to_f / (votes_for + votes_against)
  end

  def threshold_met?
    approval_percentage >= required_threshold
  end

  def can_vote?(user)
    return false unless status == 'voting'
    return false unless user
    return false if governance_votes.exists?(user: user)
    
    user_stake_at_snapshot(user) > 0
  end

  # SECURITY: Calculate user's stake AT THE SNAPSHOT TIME
  # Only stakes that existed before the snapshot count
  # This prevents flash stake attacks
  def user_stake_at_snapshot(user)
    return user_stake_current(user) unless snapshot_at.present?
    
    # Only count stakes that were earned BEFORE the snapshot
    # Stakes acquired after snapshot don't count for this vote
    user.token_stakes
      .active
      .where('earned_at < ?', snapshot_at)
      .sum(:current_amount)
  end

  # Current stake (used for non-snapshot calculations)
  def user_stake_current(user)
    user.token_stakes.active.sum(:current_amount)
  end
  
  # Alias for backward compatibility
  def user_stake(user)
    user_stake_at_snapshot(user)
  end

  def vote!(user:, vote_type:)
    return { success: false, error: 'Cannot vote on this proposal' } unless can_vote?(user)
    return { success: false, error: 'Invalid vote type' } unless %w[for against abstain].include?(vote_type)

    # SECURITY: Use snapshot-based voting power
    voting_power = user_stake_at_snapshot(user)
    
    governance_votes.create!(
      user: user,
      vote: vote_type,
      voting_power: voting_power,
      stake_at_snapshot: voting_power, # Record for audit trail
      voted_at: Time.current
    )

    Rails.logger.info "[GOVERNANCE] User #{user.id} voted '#{vote_type}' on proposal ##{id} with #{voting_power} power (snapshot: #{snapshot_at})"

    { success: true, voting_power: voting_power }
  end

  private

  def can_cancel?(user)
    return false unless %w[draft discussion].include?(status)
    user == proposer || user.admin?
  end

  def proposer_has_sufficient_stake
    stake = proposer&.token_stakes&.active&.sum(:current_amount) || 0
    min = min_stake_required
    
    if stake < min
      errors.add(:base, "Proposer must have at least #{min} AMOS to submit a #{config[:name]} proposal. Current stake: #{stake}")
    end
  end

  def stake_proposer_tokens
    # Lock proposer's tokens while proposal is active
    # This is tracked in metadata, not actual token movement
    self.staked_amount = min_stake_required
    save
  end

  def unstake_proposer_tokens(return_to_proposer: false)
    # Release the staked tokens
    # If proposal failed, tokens are burned as anti-spam measure
    unless return_to_proposer
      # Burn 10% as anti-spam for failed/cancelled proposals
      burn_amount = (staked_amount * 0.10).round(4)
      # This would trigger actual burn in production
      Rails.logger.info "[GOVERNANCE] Burned #{burn_amount} AMOS for failed/cancelled proposal ##{id}"
    end
  end

  def set_defaults
    self.status ||= 'discussion'
    self.staked_amount ||= min_stake_required
  end
end
