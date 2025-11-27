# frozen_string_literal: true

class AgentSchoolEnrollment < ApplicationRecord
  belongs_to :agent_plugin
  belongs_to :student_agent, class_name: 'AgentPlugin', optional: true
  belongs_to :entity
  has_one :graduation_test, class_name: 'AgentAbTest', foreign_key: :enrollment_id

  STATUSES = %w[enrolled diagnosing curriculum testing graduated retry probation expelled].freeze
  OUTCOMES = %w[success failure irreplaceable_failure inconclusive].freeze
  ENROLLMENT_REASONS = %w[zero_energy poor_performance manual].freeze

  MAX_RETRY_ATTEMPTS = 3

  # Validations
  validates :status, inclusion: { in: STATUSES }
  validates :enrollment_reason, inclusion: { in: ENROLLMENT_REASONS }
  validates :outcome, inclusion: { in: OUTCOMES }, allow_nil: true

  # Scopes
  scope :active, -> { where(status: %w[enrolled diagnosing curriculum testing]) }
  scope :completed, -> { where(status: %w[graduated retry probation expelled]) }
  scope :for_agent, ->(agent) { where(agent_plugin: agent) }
  scope :recent, ->(days = 30) { where('created_at > ?', days.days.ago) }

  # Callbacks
  before_create :set_enrolled_at

  # ============================================
  # STATUS CHECKS
  # ============================================

  def enrolled?
    status == 'enrolled'
  end

  def in_progress?
    %w[enrolled diagnosing curriculum testing].include?(status)
  end

  def completed?
    %w[graduated retry probation expelled].include?(status)
  end

  def can_retry?
    attempt_number < MAX_RETRY_ATTEMPTS
  end

  # ============================================
  # LIFECYCLE
  # ============================================

  def start_diagnosis!
    update!(status: 'diagnosing')
  end

  def complete_diagnosis!(diagnosis_data)
    update!(
      status: 'curriculum',
      diagnosis: diagnosis_data,
      diagnosis_completed_at: Time.current
    )
  end

  def complete_curriculum!(curriculum_data)
    update!(
      curriculum_applied: curriculum_data,
      curriculum_completed_at: Time.current,
      status: 'testing'
    )
  end

  def start_testing!(test)
    update!(
      status: 'testing',
      testing_started_at: Time.current
    )
  end

  def graduate!(comparison_results)
    update!(
      status: 'graduated',
      outcome: 'success',
      comparison_results: comparison_results,
      completed_at: Time.current
    )
  end

  def retry!(comparison_results)
    update!(
      status: 'retry',
      outcome: 'inconclusive',
      comparison_results: comparison_results,
      completed_at: Time.current
    )
  end

  def probation!(comparison_results, irreplaceability)
    update!(
      status: 'probation',
      outcome: 'irreplaceable_failure',
      comparison_results: comparison_results,
      irreplaceability_assessment: irreplaceability,
      completed_at: Time.current
    )
  end

  def expel!(comparison_results)
    update!(
      status: 'expelled',
      outcome: 'failure',
      comparison_results: comparison_results,
      completed_at: Time.current
    )
  end

  # ============================================
  # STATISTICS
  # ============================================

  def duration
    return nil unless completed_at
    completed_at - enrolled_at
  end

  def diagnosis_summary
    return {} if diagnosis.blank?

    {
      total_failures: diagnosis['total_failures'],
      top_failure_types: diagnosis.dig('failure_by_task_type')&.sort_by { |_, v| -v['count'] }&.first(3),
      collaboration_gaps: diagnosis['collaboration_gaps']&.size || 0,
      root_causes: diagnosis['root_causes']
    }
  end

  def curriculum_summary
    return [] if curriculum_applied.blank?

    curriculum_applied.map do |module_data|
      {
        module: module_data['module'],
        changes_made: module_data['changes']&.size || 0
      }
    end
  end

  private

  def set_enrolled_at
    self.enrolled_at = Time.current
  end
end

