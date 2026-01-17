# frozen_string_literal: true

# AutomationExecution - Log of each automation run
#
# Used for debugging, auditing, and monitoring automation performance.
#
class AutomationExecution < ApplicationRecord
  # ============================================
  # ASSOCIATIONS
  # ============================================

  belongs_to :automation_code
  belongs_to :entity
  belongs_to :triggered_by, class_name: 'User', optional: true

  # ============================================
  # CONSTANTS
  # ============================================

  STATUSES = %w[pending running success failed timeout].freeze
  TRIGGER_SOURCES = %w[record schedule webhook manual test].freeze

  # ============================================
  # VALIDATIONS
  # ============================================

  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :trigger_source, inclusion: { in: TRIGGER_SOURCES }, allow_nil: true

  # ============================================
  # CALLBACKS
  # ============================================

  before_create :set_started_at

  # ============================================
  # SCOPES
  # ============================================

  scope :recent, -> { order(created_at: :desc) }
  scope :successful, -> { where(status: 'success') }
  scope :failed, -> { where(status: 'failed') }
  scope :for_automation, ->(automation_id) { where(automation_code_id: automation_id) }

  # ============================================
  # STATUS HELPERS
  # ============================================

  def pending?; status == 'pending'; end
  def running?; status == 'running'; end
  def success?; status == 'success'; end
  def failed?; status == 'failed'; end
  def timeout?; status == 'timeout'; end

  def start!
    update!(status: 'running', started_at: Time.current)
  end

  def complete!(result)
    update!(
      status: result[:success] ? 'success' : 'failed',
      execution_result: result,
      error_message: result[:error],
      completed_at: Time.current,
      duration_ms: calculate_duration
    )
  end

  def timeout!
    update!(
      status: 'timeout',
      error_message: 'Execution timed out',
      completed_at: Time.current,
      duration_ms: calculate_duration
    )
  end

  # ============================================
  # SERIALIZATION
  # ============================================

  def to_log_entry
    {
      id: id,
      automation: automation_code.name,
      trigger_source: trigger_source,
      status: status,
      duration_ms: duration_ms,
      started_at: started_at,
      error: error_message
    }
  end

  private

  def set_started_at
    self.started_at ||= Time.current
  end

  def calculate_duration
    return nil unless started_at
    ((Time.current - started_at) * 1000).round(2)
  end
end

