# frozen_string_literal: true

# == Schema Information
#
# Table name: factory_test_runs
#
#  id                        :bigint           not null, primary key
#  factory_test_criteria_id  :bigint           not null
#  factory_test_session_id   :bigint
#  entity_id                 :bigint           not null
#  user_id                   :bigint           not null
#  attempt_number            :integer          default(1)
#  status                    :string           default("pending")
#  passed                    :boolean          default(FALSE)
#  actual_output             :text
#  actual_values             :jsonb            default({})
#  error_message             :text
#  diff_summary              :text
#  similarity_score          :float
#  ai_evaluation             :text
#  actual_status_code        :integer
#  actual_headers            :jsonb            default({})
#  response_time_ms          :float
#  duration_ms               :integer
#  tokens_used               :integer
#  ai_feedback               :text
#  fix_suggestion            :text
#  metadata                  :jsonb            default({})
#  started_at                :datetime
#  completed_at              :datetime
#  created_at                :datetime         not null
#  updated_at                :datetime         not null
#
class FactoryTestRun < ApplicationRecord
  # ============================================
  # ASSOCIATIONS
  # ============================================
  
  belongs_to :factory_test_criteria
  belongs_to :factory_test_session, optional: true
  belongs_to :entity
  belongs_to :user

  # Delegate to criteria for convenience
  delegate :name, :test_type, :testable, :is_required, :weight, to: :factory_test_criteria, prefix: :criteria

  # ============================================
  # VALIDATIONS
  # ============================================
  
  VALID_STATUSES = %w[pending running passed failed skipped error].freeze

  validates :status, presence: true, inclusion: { in: VALID_STATUSES }
  validates :attempt_number, numericality: { greater_than: 0 }

  # ============================================
  # SCOPES
  # ============================================
  
  scope :pending, -> { where(status: 'pending') }
  scope :running, -> { where(status: 'running') }
  scope :passed, -> { where(status: 'passed') }
  scope :failed, -> { where(status: 'failed') }
  scope :completed, -> { where(status: %w[passed failed skipped error]) }
  scope :by_attempt, ->(n) { where(attempt_number: n) }
  scope :recent, -> { order(created_at: :desc) }
  scope :for_session, ->(session) { where(factory_test_session: session) }

  # ============================================
  # STATE MACHINE
  # ============================================
  
  def start!
    update!(status: 'running', started_at: Time.current)
  end

  def pass!(output: nil, values: {}, score: nil, evaluation: nil, duration: nil)
    update!(
      status: 'passed',
      passed: true,
      actual_output: output,
      actual_values: values,
      similarity_score: score,
      ai_evaluation: evaluation,
      duration_ms: duration,
      completed_at: Time.current
    )
  end

  def fail!(output: nil, error: nil, diff: nil, score: nil, evaluation: nil, feedback: nil, fix: nil, duration: nil)
    update!(
      status: 'failed',
      passed: false,
      actual_output: output,
      error_message: error,
      diff_summary: diff,
      similarity_score: score,
      ai_evaluation: evaluation,
      ai_feedback: feedback,
      fix_suggestion: fix,
      duration_ms: duration,
      completed_at: Time.current
    )
  end

  def skip!(reason: nil)
    update!(
      status: 'skipped',
      passed: false,
      error_message: reason,
      completed_at: Time.current
    )
  end

  def error!(message)
    update!(
      status: 'error',
      passed: false,
      error_message: message,
      completed_at: Time.current
    )
  end

  # ============================================
  # INSTANCE METHODS
  # ============================================
  
  def completed?
    status.in?(%w[passed failed skipped error])
  end

  def success?
    status == 'passed'
  end

  # Calculate score contribution
  def score
    return 0 unless passed
    factory_test_criteria.max_score
  end

  # Get status emoji
  def status_emoji
    case status
    when 'passed' then '✅'
    when 'failed' then '❌'
    when 'skipped' then '⏭️'
    when 'error' then '💥'
    when 'running' then '🔄'
    else '⏳'
    end
  end

  # Format for display
  def summary
    "#{status_emoji} #{criteria_name}: #{status}"
  end

  def detailed_summary
    parts = [summary]
    
    if passed && similarity_score
      parts << "Score: #{(similarity_score * 100).round}%"
    end
    
    if !passed && error_message.present?
      parts << "Error: #{error_message.truncate(100)}"
    end
    
    if ai_evaluation.present?
      parts << "AI says: #{ai_evaluation.truncate(150)}"
    end
    
    parts.join("\n")
  end
end

