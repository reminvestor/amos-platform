# frozen_string_literal: true

# == Schema Information
#
# Table name: scheduled_task_runs
#
#  id                       :bigint           not null, primary key
#  scheduled_agent_task_id  :bigint           not null
#  agent_plugin_execution_id :bigint
#  user_id                  :bigint           not null
#  status                   :string           not null, default("pending")
#  started_at               :datetime
#  completed_at             :datetime
#  duration_ms              :integer
#  result_summary           :text
#  result_data              :jsonb            default({})
#  error_message            :text
#  notification_sent        :boolean          default(FALSE)
#  notification_sent_at     :datetime
#  notification_method      :string
#  created_at               :datetime         not null
#  updated_at               :datetime         not null
#
class ScheduledTaskRun < ApplicationRecord
  belongs_to :scheduled_agent_task
  belongs_to :agent_plugin_execution, optional: true
  belongs_to :user
  
  has_one :entity, through: :scheduled_agent_task
  has_many :agent_work_items, dependent: :nullify
  has_one :user_notification, dependent: :nullify
  
  # Validations
  validates :status, presence: true, inclusion: { 
    in: %w[pending running completed failed cancelled]
  }
  
  # Scopes
  scope :pending, -> { where(status: 'pending') }
  scope :running, -> { where(status: 'running') }
  scope :completed, -> { where(status: 'completed') }
  scope :failed, -> { where(status: 'failed') }
  scope :recent, -> { order(created_at: :desc) }
  scope :for_task, ->(task) { where(scheduled_agent_task: task) }
  scope :needs_notification, -> { where(notification_sent: false).where(status: %w[completed failed]) }
  scope :today, -> { where(created_at: Time.current.beginning_of_day..Time.current.end_of_day) }
  scope :this_week, -> { where(created_at: Time.current.beginning_of_week..Time.current.end_of_week) }
  
  # Stuck tasks: running for more than 10 minutes or pending for more than 5 minutes
  STUCK_RUNNING_THRESHOLD = 10.minutes
  STUCK_PENDING_THRESHOLD = 5.minutes
  
  scope :stuck, -> {
    running.where('started_at < ?', STUCK_RUNNING_THRESHOLD.ago)
      .or(pending.where('created_at < ?', STUCK_PENDING_THRESHOLD.ago))
  }
  
  # Class method to clean up stuck runs
  def self.cleanup_stuck_runs!
    stuck_count = 0
    
    stuck.find_each do |run|
      Rails.logger.warn "🔧 Cleaning up stuck run ##{run.id} for task '#{run.scheduled_agent_task.name}'"
      run.fail!("Task timed out - was stuck in '#{run.status}' status for too long")
      stuck_count += 1
    end
    
    Rails.logger.info "🧹 Cleaned up #{stuck_count} stuck task runs" if stuck_count > 0
    stuck_count
  end
  
  # Callbacks
  after_update :create_notification, if: :should_notify?
  after_update :create_work_item, if: :just_completed?
  
  # Instance methods
  def start!
    update!(
      status: 'running',
      started_at: Time.current
    )
  end
  
  def complete!(result_summary: nil, result_data: {})
    update!(
      status: 'completed',
      completed_at: Time.current,
      duration_ms: calculate_duration,
      result_summary: result_summary,
      result_data: result_data
    )
    
    scheduled_agent_task.record_run!(success: true, run: self)
  end
  
  def fail!(error_message)
    update!(
      status: 'failed',
      completed_at: Time.current,
      duration_ms: calculate_duration,
      error_message: error_message
    )
    
    scheduled_agent_task.record_run!(success: false, run: self)
  end
  
  def cancel!
    update!(
      status: 'cancelled',
      completed_at: Time.current
    )
  end
  
  def success?
    status == 'completed'
  end
  
  def duration_in_seconds
    return nil unless duration_ms
    duration_ms / 1000.0
  end
  
  def send_notification!
    return if notification_sent?
    
    method = scheduled_agent_task.output_method
    
    case method
    when 'email'
      send_email_notification
    when 'notification'
      create_in_app_notification
    when 'both'
      send_email_notification
      create_in_app_notification
    end
    
    update!(
      notification_sent: true,
      notification_sent_at: Time.current,
      notification_method: method
    )
  end
  
  private
  
  def calculate_duration
    return nil unless started_at
    ((Time.current - started_at) * 1000).to_i
  end
  
  def should_notify?
    saved_change_to_status? && status.in?(%w[completed failed]) && !notification_sent?
  end
  
  def just_completed?
    saved_change_to_status? && status == 'completed'
  end
  
  def create_notification
    return if notification_sent?
    
    notification_type = status == 'completed' ? 'task_completed' : 'task_failed'
    title = status == 'completed' ? 
      "✅ #{scheduled_agent_task.name} completed" : 
      "❌ #{scheduled_agent_task.name} failed"
    
    UserNotification.create!(
      entity: scheduled_agent_task.entity,
      user: user,
      scheduled_task_run: self,
      notification_type: notification_type,
      title: title,
      body: result_summary || error_message,
      icon: status == 'completed' ? '✅' : '❌',
      channel: scheduled_agent_task.output_method == 'email' ? 'email' : 'in_app',
      priority: status == 'failed' ? 'high' : 'normal',
      action_url: "/scout?view=scheduled_tasks&run_id=#{id}",
      action_type: 'view'
    )
  end
  
  def create_work_item
    AgentWorkItem.create!(
      entity: scheduled_agent_task.entity,
      user: user,
      agent_plugin: scheduled_agent_task.agent_plugin,
      scheduled_task_run: self,
      agent_plugin_execution: agent_plugin_execution,
      work_type: 'scheduled_task_completed',
      title: "#{scheduled_agent_task.name} completed",
      summary: result_summary,
      details: result_data.to_json,
      priority: 'normal'
    )
  end
  
  def send_email_notification
    # TODO: Implement email sending via ActionMailer
    Rails.logger.info "Would send email notification for run #{id} to #{scheduled_agent_task.output_email}"
  end
  
  def create_in_app_notification
    # Handled by the after_update callback
  end
end

