# frozen_string_literal: true

# AmosThinkingSession - Records of AMOS's nightly reflection and bounty generation
#
# Each session represents a period where AMOS:
# 1. Analyzes platform state (logs, errors, metrics, feedback)
# 2. Reflects on what could be improved
# 3. Generates bounty ideas
# 4. Scores and creates bounties
#
class AmosThinkingSession < ApplicationRecord
  belongs_to :entity

  # Session types
  SESSION_TYPES = %w[nightly triggered autonomous reactive weekly_review monthly_review].freeze

  # Statuses
  STATUSES = %w[running completed failed].freeze

  validates :session_type, inclusion: { in: SESSION_TYPES }
  validates :status, inclusion: { in: STATUSES }

  scope :completed, -> { where(status: 'completed') }
  scope :recent, -> { order(created_at: :desc) }
  scope :nightly, -> { where(session_type: 'nightly') }

  before_create :set_started_at

  def complete!(summary:, bounties_created:, total_points:, thinking_log: nil)
    update!(
      status: 'completed',
      reflection_summary: summary,
      bounties_created: bounties_created,
      total_points_allocated: total_points,
      thinking_log: thinking_log,
      completed_at: Time.current,
      duration_seconds: (Time.current - started_at).to_i
    )
  end

  def fail!(error_message)
    update!(
      status: 'failed',
      thinking_log: "FAILED: #{error_message}\n\n#{thinking_log}",
      completed_at: Time.current,
      duration_seconds: (Time.current - started_at).to_i
    )
  end

  def running?
    status == 'running'
  end

  def completed?
    status == 'completed'
  end

  def duration_display
    return nil unless duration_seconds

    if duration_seconds < 60
      "#{duration_seconds}s"
    elsif duration_seconds < 3600
      "#{(duration_seconds / 60).round}m"
    else
      "#{(duration_seconds / 3600.0).round(1)}h"
    end
  end

  private

  def set_started_at
    self.started_at ||= Time.current
  end
end
