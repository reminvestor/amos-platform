# frozen_string_literal: true

module Workflows
  # ExecutorJob runs workflow executions asynchronously
  class ExecutorJob < ApplicationJob
    queue_as :workflows

    # Retry with exponential backoff
    retry_on StandardError, wait: :polynomially_longer, attempts: 3

    def perform(execution_id)
      execution = AutomationExecution.find_by(id: execution_id)
      
      unless execution
        Rails.logger.error "[WorkflowExecutorJob] Execution not found: #{execution_id}"
        return
      end

      # Skip if already completed or failed
      if %w[success failed].include?(execution.status)
        Rails.logger.info "[WorkflowExecutorJob] Execution #{execution_id} already #{execution.status}, skipping"
        return
      end

      Rails.logger.info "[WorkflowExecutorJob] Starting execution #{execution_id}"

      executor = Workflows::ExecutorService.new(execution)
      result = executor.execute!

      if result[:success]
        Rails.logger.info "[WorkflowExecutorJob] Execution #{execution_id} completed successfully"
      else
        Rails.logger.error "[WorkflowExecutorJob] Execution #{execution_id} failed: #{result[:error]}"
      end

      result
    rescue => e
      Rails.logger.error "[WorkflowExecutorJob] Execution #{execution_id} error: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
      
      # Update execution status
      execution&.update!(
        status: 'failed',
        error_message: e.message,
        completed_at: Time.current
      )
      
      raise  # Re-raise to trigger retry
    end
  end

  # ResumeJob resumes a delayed workflow execution
  class ResumeJob < ApplicationJob
    queue_as :workflows

    def perform(execution_id, resume_from_step_id)
      execution = AutomationExecution.find_by(id: execution_id)
      
      unless execution
        Rails.logger.error "[WorkflowResumeJob] Execution not found: #{execution_id}"
        return
      end

      Rails.logger.info "[WorkflowResumeJob] Resuming execution #{execution_id} from step #{resume_from_step_id}"

      # For now, just re-run the executor - it will pick up where it left off
      # based on the step_executions in the execution metadata
      executor = Workflows::ExecutorService.new(execution)
      result = executor.execute!

      if result[:success]
        Rails.logger.info "[WorkflowResumeJob] Execution #{execution_id} resumed and completed"
      else
        Rails.logger.error "[WorkflowResumeJob] Execution #{execution_id} failed after resume: #{result[:error]}"
      end

      result
    end
  end

  # ScheduledTriggerJob fires scheduled workflow triggers
  class ScheduledTriggerJob < ApplicationJob
    queue_as :default

    def perform
      # Find all due scheduled triggers
      due_triggers = WorkflowTrigger
        .active
        .scheduled
        .due_to_run
        .includes(:automation_code)

      Rails.logger.info "[ScheduledTriggerJob] Found #{due_triggers.count} due triggers"

      due_triggers.find_each do |trigger|
        begin
          # Fire the trigger
          result = trigger.fire!(
            run_count: trigger.trigger_count + 1,
            scheduled_time: trigger.next_trigger_at
          )

          if result[:success]
            Rails.logger.info "[ScheduledTriggerJob] Fired trigger #{trigger.id}, execution: #{result[:execution_id]}"
          else
            Rails.logger.error "[ScheduledTriggerJob] Failed to fire trigger #{trigger.id}: #{result[:error]}"
          end

          # Update next trigger time
          trigger.update_next_trigger!
        rescue => e
          Rails.logger.error "[ScheduledTriggerJob] Error processing trigger #{trigger.id}: #{e.message}"
          trigger.record_error!(e.message)
        end
      end
    end
  end
end
