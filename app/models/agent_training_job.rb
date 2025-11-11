class AgentTrainingJob < ApplicationRecord
  belongs_to :entity

  validates :job_id, presence: true, uniqueness: true
  validates :job_type, presence: true, inclusion: { in: %w[prompt_optimization supervised_finetuning rl_training] }
  validates :status, presence: true, inclusion: { in: %w[pending running completed failed] }

  scope :active, -> { where(status: %w[pending running]) }
  scope :completed, -> { where(status: "completed") }
  scope :recent, -> { order(created_at: :desc) }
  scope :by_type, ->(type) { where(job_type: type) }

  # Is job still running
  def running?
    status == "running"
  end

  # Has job completed
  def completed?
    status == "completed"
  end

  # Did job fail
  def failed?
    status == "failed"
  end

  # Get job progress
  def progress_percentage
    return 0 if total_traces_available.zero?
    ((traces_used.to_f / total_traces_available) * 100).round(2)
  end

  # Mark job as completed
  def mark_completed(results = {}, improvement = 0)
    update!(
      status: "completed",
      completed_at: Time.current,
      training_results: results,
      improvement_score: improvement
    )
  end

  # Mark job as failed
  def mark_failed(error_msg)
    update!(
      status: "failed",
      completed_at: Time.current,
      error_message: error_msg
    )
  end
end
