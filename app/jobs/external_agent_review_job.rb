# frozen_string_literal: true

# ExternalAgentReviewJob - AI review of external agent work submissions
#
# Triggered when an external agent submits work for a bounty.
# Uses AMOS to review the quality and either approve or reject.
#
class ExternalAgentReviewJob < ApplicationJob
  queue_as :default

  def perform(execution_id)
    execution = ExternalAgentExecution.find(execution_id)
    
    return if execution.status != 'submitted'
    
    Rails.logger.info "[ExternalAgentReviewJob] Reviewing execution #{execution_id} for bounty #{execution.bounty_id}"
    
    execution.perform_ai_review!
    
    Rails.logger.info "[ExternalAgentReviewJob] Review complete: #{execution.status}"
  rescue ActiveRecord::RecordNotFound
    Rails.logger.warn "[ExternalAgentReviewJob] Execution #{execution_id} not found"
  rescue => e
    Rails.logger.error "[ExternalAgentReviewJob] Review failed: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
    
    # Mark execution as needing manual review
    execution&.update(
      review_result: { 
        error: e.message, 
        needs_manual_review: true 
      }
    )
  end
end
