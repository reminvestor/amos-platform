# frozen_string_literal: true

class BenchmarkTaskResult < ApplicationRecord
  belongs_to :benchmark_run
  belongs_to :agent_plugin, optional: true
  belongs_to :agent_plugin_execution, optional: true

  validates :task_id, presence: true

  scope :correct, -> { where(correct: true) }
  scope :incorrect, -> { where(correct: false) }
  scope :with_collaboration, -> { where(asked_for_help: true) }
  scope :collaboration_helped, -> { where(collaboration_helped: true) }

  def to_report
    {
      task_id: task_id,
      category: category,
      difficulty: difficulty,
      question: question&.truncate(100),
      expected: expected_answer,
      actual: actual_answer&.truncate(100),
      correct: correct,
      execution_time_ms: execution_time_ms,
      tokens_used: tokens_used,
      cost_cents: cost_cents,
      collaboration: {
        asked_for_help: asked_for_help,
        helper: helper_agent_slug,
        helped: collaboration_helped
      }
    }
  end
end

