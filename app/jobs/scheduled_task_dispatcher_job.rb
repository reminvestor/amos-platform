# frozen_string_literal: true

class ScheduledTaskDispatcherJob < ApplicationJob
  queue_as :default
  
  # This job runs every minute to check for due scheduled tasks
  def perform
    Rails.logger.info "🕐 Checking for due scheduled tasks..."
    
    due_tasks = ScheduledAgentTask.due_now.includes(:user, :entity, :agent_plugin)
    
    if due_tasks.empty?
      Rails.logger.info "No scheduled tasks due at this time"
      return
    end
    
    Rails.logger.info "Found #{due_tasks.count} due tasks"
    
    due_tasks.find_each do |task|
      begin
        # Skip if task is already running (check for recent pending/running runs)
        if task.scheduled_task_runs.where(status: %w[pending running]).where('created_at > ?', 5.minutes.ago).exists?
          Rails.logger.info "Skipping task #{task.id} - already running"
          next
        end
        
        # Enqueue the execution job
        ExecuteScheduledAgentTaskJob.perform_later(task.id)
        
        Rails.logger.info "Enqueued execution for task: #{task.name} (#{task.id})"
        
      rescue => e
        Rails.logger.error "Failed to enqueue task #{task.id}: #{e.message}"
      end
    end
  end
end

