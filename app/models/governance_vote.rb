# frozen_string_literal: true

# GovernanceVote represents a single vote on a governance proposal
class GovernanceVote < ApplicationRecord
  belongs_to :governance_proposal
  belongs_to :user

  VOTE_OPTIONS = %w[for against abstain].freeze

  validates :vote, presence: true, inclusion: { in: VOTE_OPTIONS }
  validates :voting_power, presence: true, numericality: { greater_than: 0 }
  validates :user_id, uniqueness: { scope: :governance_proposal_id, message: 'has already voted on this proposal' }

  scope :for_votes, -> { where(vote: 'for') }
  scope :against_votes, -> { where(vote: 'against') }
  scope :abstain_votes, -> { where(vote: 'abstain') }
  scope :recent, -> { order(voted_at: :desc) }
end
