# frozen_string_literal: true

# Tracks contributions to the platform (code, community, content)
# Used to calculate token stake rewards
class Contribution < ApplicationRecord
  belongs_to :user
  belongs_to :entity, optional: true
  belongs_to :reviewed_by, class_name: 'User', optional: true
  has_one :token_stake, as: :source, dependent: :nullify

  # Contribution types
  CONTRIBUTION_TYPES = %w[
    code
    documentation
    bug_fix
    feature
    review
    support
    content
    translation
    testing
    design
    community
  ].freeze

  # Status flow: submitted → under_review → approved/rejected
  enum :status, { submitted: 0, under_review: 1, approved: 2, rejected: 3, merged: 4 }

  # Validations
  validates :contribution_type, presence: true, inclusion: { in: CONTRIBUTION_TYPES }
  validates :title, presence: true
  validates :description, presence: true
  validates :stake_value, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true

  # Scopes
  scope :by_type, ->(type) { where(contribution_type: type) }
  scope :code_contributions, -> { where(contribution_type: %w[code bug_fix feature]) }
  scope :community_contributions, -> { where(contribution_type: %w[support content community]) }
  scope :pending_review, -> { where(status: [:submitted, :under_review]) }
  scope :accepted, -> { where(status: [:approved, :merged]) }
  scope :for_user, ->(user) { where(user: user) }
  scope :recent, -> { order(created_at: :desc) }

  # Callbacks - only award stake on initial approval, not subsequent updates
  after_update :award_stake_if_approved, if: -> { saved_change_to_status? && !stake_awarded? }

  # Instance methods
  def approve!(reviewer, stake_value: nil)
    self.stake_value = stake_value if stake_value
    self.stake_value ||= calculate_default_stake_value

    update!(
      status: :approved,
      reviewed_by: reviewer,
      reviewed_at: Time.current
    )
  end

  def reject!(reviewer, reason: nil)
    update!(
      status: :rejected,
      reviewed_by: reviewer,
      reviewed_at: Time.current,
      review_notes: reason
    )
  end

  def mark_merged!(external_reference: nil)
    update!(
      status: :merged,
      external_reference: external_reference,
      merged_at: Time.current
    )
  end

  def stake_awarded?
    token_stake.present?
  end

  # Parse external reference to get bounty, PR, and commit info
  def parsed_reference
    return {} if external_reference.blank?

    refs = external_reference.split('|')
    parsed = {}

    refs.each do |ref|
      key, value = ref.split(':', 2)
      parsed[key.to_sym] = value if key && value
    end

    parsed
  end

  def bounty_id
    parsed_reference[:bounty]&.to_i
  end

  def pr_url
    parsed_reference[:pr]
  end

  def commit_sha
    parsed_reference[:commit]
  end

  def work_url
    parsed_reference[:work]
  end

  def has_code_evidence?
    pr_url.present? || commit_sha.present?
  end

  def work_evidence_display
    evidence = []
    evidence << "PR: #{pr_url}" if pr_url.present?
    evidence << "Commit: #{commit_sha[0..7]}" if commit_sha.present?
    evidence << "Work: #{work_url}" if work_url.present?
    evidence.join(' | ')
  end

  def calculate_default_stake_value
    base_value = case contribution_type
    when 'feature' then 1000
    when 'bug_fix' then 500
    when 'code' then 300
    when 'documentation' then 200
    when 'review' then 100
    when 'support' then 150
    when 'content' then 250
    when 'community' then 100
    when 'testing' then 200
    when 'design' then 400
    when 'translation' then 150
    else 100
    end

    # Apply complexity multiplier if set
    base_value * (complexity_multiplier || 1.0)
  end

  # Class methods
  class << self
    def total_contributions_by_user
      accepted
        .group(:user_id)
        .count
    end

    def total_stake_by_user
      accepted
        .where.not(stake_value: nil)
        .group(:user_id)
        .sum(:stake_value)
    end

    def leaderboard(limit: 20)
      accepted
        .joins(:user)
        .select(
          'users.id as user_id',
          'users.email',
          'users.first_name',
          'users.last_name',
          'COUNT(*) as contribution_count',
          'COALESCE(SUM(contributions.stake_value), 0) as total_stake'
        )
        .group('users.id', 'users.email', 'users.first_name', 'users.last_name')
        .order('total_stake DESC')
        .limit(limit)
    end

    def contribution_stats(days: 30)
      recent = where('created_at >= ?', days.days.ago)
      {
        total_submitted: recent.count,
        pending_review: recent.pending_review.count,
        approved: recent.accepted.count,
        rejected: recent.rejected.count,
        total_stake_awarded: recent.accepted.sum(:stake_value),
        by_type: recent.group(:contribution_type).count
      }
    end
  end

  private

  def award_stake_if_approved
    return unless approved? || merged?
    return if stake_awarded?
    return if stake_value.nil? || stake_value.zero?

    TokenStake.create_contribution_stake!(
      user: user,
      amount: stake_value,
      category: contribution_type,
      source: self,
      metadata: {
        contribution_id: id,
        title: title,
        contribution_type: contribution_type
      }
    )
  end
end
