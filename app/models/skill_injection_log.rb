# frozen_string_literal: true

# SkillInjectionLog - Tracks when skills are injected into conversations
#
# This creates the feedback loop: we know which skills were used,
# whether the subsequent tool calls succeeded, and whether the
# user was satisfied. AMOS uses this data to evolve skills.
#
class SkillInjectionLog < ApplicationRecord
  belongs_to :system_skill
  belongs_to :entity
  belongs_to :user

  scope :recent, -> { where('created_at > ?', 7.days.ago) }
  scope :positive, -> { where(outcome_positive: true) }
  scope :negative, -> { where(outcome_positive: false) }
  scope :for_skill, ->(skill) { where(system_skill: skill) }

  # Update outcome based on tool execution results
  def record_tool_results!(succeeded:, failed:)
    update!(
      tool_calls_count: succeeded + failed,
      tool_calls_succeeded: succeeded,
      tool_calls_failed: failed,
      outcome_positive: failed == 0 && succeeded > 0
    )

    system_skill.record_outcome!(positive: outcome_positive) if outcome_positive != nil
  end
end
