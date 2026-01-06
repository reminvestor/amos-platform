# frozen_string_literal: true

module LivingPlatform
  # WeeklyAgentReflectionsJob - Runs weekly reflection for all agents
  #
  # Scheduled to run weekly for comprehensive performance reviews.
  #
  class WeeklyAgentReflectionsJob < ApplicationJob
    queue_as :default
    
    retry_on StandardError, wait: 10.minutes, attempts: 2

    def perform(entity_id)
      entity = Entity.find(entity_id)
      
      Rails.logger.info "[LivingPlatform] Starting weekly reflections for entity #{entity_id}"
      
      agents = entity.agent_plugins.where(status: 'active')
      
      agents.find_each do |agent|
        # Check if agent had meaningful activity this week
        activity_count = agent.agent_plugin_executions
          .where('created_at > ?', 7.days.ago)
          .count
        
        next unless activity_count >= 5  # Need meaningful data
        
        # Queue reflection job
        AgentReflectionJob.perform_later(agent.id, reflection_type: 'weekly')
      end
      
      Rails.logger.info "[LivingPlatform] Queued weekly reflections for #{agents.count} agents"
    end
  end
end


