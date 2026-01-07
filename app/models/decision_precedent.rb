# frozen_string_literal: true

# DecisionPrecedent - Links decisions to their precedents
#
# This is the "edge" in our context graph, connecting a new decision
# to past decisions that influenced it.
#
class DecisionPrecedent < ApplicationRecord
  belongs_to :decision_trace
  belongs_to :precedent_decision, class_name: 'DecisionTrace'

  INFLUENCE_TYPES = %w[
    exception_precedent  # This exception was justified by a past exception
    success_pattern      # Following a pattern that worked before
    failure_avoidance    # Avoiding a pattern that failed before
    context_similarity   # Similar context, used for reference
    policy_interpretation # How a policy was interpreted in similar case
  ].freeze

  validates :influence_type, inclusion: { in: INFLUENCE_TYPES }
  validates :similarity_score, numericality: { greater_than: 0, less_than_or_equal_to: 1 }

  scope :strong, -> { where('similarity_score >= ?', 0.8) }
  scope :by_type, ->(type) { where(influence_type: type) }

  # Did the current decision have a similar outcome to the precedent?
  def outcome_matched?
    outcome_matches == true
  end
end


