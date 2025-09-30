class WorkflowStepExecution < ApplicationRecord
  belongs_to :workflow_execution
  has_many :workflow_variables, as: :source, dependent: :destroy
  
  # Status enum
  enum :status, {
    pending: 'pending',
    running: 'running',
    completed: 'completed',
    failed: 'failed',
    skipped: 'skipped'
  }, prefix: true
  
  # Scopes
  scope :completed, -> { where(status: 'completed') }
  scope :failed, -> { where(status: 'failed') }
  scope :by_step_id, ->(step_id) { where(step_id: step_id) }
  
  # Callbacks
  after_update :extract_variables, if: :completed_and_has_output?
  
  # Start execution
  def start!(input_data = {})
    update!(
      status: 'running',
      started_at: Time.current,
      input_data: input_data,
      error_message: nil
    )
  end
  
  # Mark as completed
  def complete!(output_data)
    update!(
      status: 'completed',
      completed_at: Time.current,
      output_data: output_data,
      error_message: nil
    )
  end
  
  # Mark as failed
  def fail!(error_message)
    update!(
      status: 'failed',
      completed_at: Time.current,
      error_message: error_message
    )
  end
  
  # Retry the step
  def retry!
    update!(
      status: 'pending',
      started_at: nil,
      completed_at: nil,
      output_data: {},
      error_message: nil,
      retry_count: retry_count + 1
    )
  end
  
  # Check if can be retried
  def can_retry?
    status_failed? && retry_count < 3
  end
  
  # Duration in seconds
  def duration
    return nil unless started_at && completed_at
    (completed_at - started_at).to_i
  end
  
  private
  
  def completed_and_has_output?
    result = status_completed? && output_data.present?
    Rails.logger.info "WorkflowStepExecution #{id}: completed_and_has_output? = #{result} (status: #{status}, output_data present: #{output_data.present?})"
    result
  end
  
  def extract_variables
    Rails.logger.info "WorkflowStepExecution #{id}: extract_variables callback triggered"
    workflow_execution.extract_variables_from_step(self)
  end
end
