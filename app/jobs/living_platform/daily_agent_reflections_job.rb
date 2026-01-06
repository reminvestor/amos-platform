# frozen_string_literal: true

module LivingPlatform
  # DailyAgentReflectionsJob - Runs daily reflection for all agents
  #
  # Scheduled to run at end of day to trigger reflection for all
  # active agents in an entity.
  #
  class DailyAgentReflectionsJob < ApplicationJob
    queue_as :default
    
    retry_on StandardError, wait: 5.minutes, attempts: 2

    def perform(entity_id)
      entity = Entity.find(entity_id)
      
      Rails.logger.info "[LivingPlatform] Starting daily reflections for entity #{entity_id}"
      
      agents = entity.agent_plugins.where(status: 'active')
      
      agents.find_each do |agent|
        # Check if agent had any activity today
        had_activity = agent.agent_plugin_executions
          .where('created_at > ?', 24.hours.ago)
          .exists?
        
        next unless had_activity
        
        # Queue reflection job
        AgentReflectionJob.perform_later(agent.id, reflection_type: 'daily')
      end
      
      Rails.logger.info "[LivingPlatform] Queued daily reflections for #{agents.count} agents"
    end
  end
end


