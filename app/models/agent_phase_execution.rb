class AgentPhaseExecution < ApplicationRecord
  belongs_to :entity
  belongs_to :workflow_execution, optional: true

  validates :phase_id, presence: true
  validates :phase_type, presence: true
  validates :status, presence: true, inclusion: { in: %w[pending running success failed awaiting_input] }

  scope :successful, -> { where(status: "success") }
  scope :by_phase, ->(phase_type) { where(phase_type: phase_type) }
  scope :recent, -> { order(started_at: :desc) }

  # Was phase successful
  def successful?
    status == "success"
  end

  # Get retry count
  def retry_count
    attempts - 1
  end

  # Get phase execution summary for training
  def execution_summary
    {
      phase_id: phase_id,
      type: phase_type,
      status: status,
      duration_ms: duration_ms,
      attempts: attempts,
      success: successful?,
      success_score: phase_success_score,
      timestamp: started_at&.to_i
    }
  end
end
