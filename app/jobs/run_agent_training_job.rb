# frozen_string_literal: true

# RunAgentTrainingJob
#
# Background job for training agents. Used when creating new integration agents
# or when an agent needs retraining.
#
# Note: Renamed from AgentTrainingJob to avoid name collision with the
# AgentTrainingJob ActiveRecord model (app/models/agent_training_job.rb).
#
# Usage:
#   RunAgentTrainingJob.perform_later(agent.id)
#   RunAgentTrainingJob.perform_later(agent.id, phases: ['research', 'knowledge_building'])
#
class RunAgentTrainingJob < ApplicationJob
  queue_as :default
  
  # Retry configuration
  retry_on StandardError, wait: :polynomially_longer, attempts: 3
  discard_on ActiveRecord::RecordNotFound

  def perform(agent_id, options = {})
    agent = AgentPlugin.find(agent_id)
    
    Rails.logger.info "[RunAgentTrainingJob] Starting training for agent: #{agent.name}"
    
    service = AgentTrainingService.new(agent)
    
    if options[:phases].present?
      # Run specific phases only
      options[:phases].each do |phase|
        Rails.logger.info "[RunAgentTrainingJob] Running phase: #{phase}"
        service.send("#{phase}_phase!")
      end
      
      # Check if we should graduate after partial training
      if options[:graduate_after]
        service.graduate_if_ready!
      end
    else
      # Run full training pipeline
      result = service.start_training!
      
      Rails.logger.info "[RunAgentTrainingJob] Training complete: #{result.inspect}"
      
      # Notify if there's a notification system
      notify_training_complete(agent, result) if result[:success]
    end
  rescue => e
    Rails.logger.error "[RunAgentTrainingJob] Training failed for agent #{agent_id}: #{e.message}"
    Rails.logger.error e.backtrace.first(10).join("\n")
    raise # Re-raise for retry mechanism
  end

  private

  def notify_training_complete(agent, result)
    return unless defined?(HubMessage)
    
    # Post to Hub if available
    HubMessage.create(
      sender: agent,
      thread: agent.hub_participations.first&.hub_thread,
      content: "Training complete! Status: #{result[:status]}. Pass rate: #{result[:pass_rate]}%",
      message_type: 'notification'
    )
  rescue => e
    Rails.logger.debug "[RunAgentTrainingJob] Could not notify: #{e.message}"
  end
end
