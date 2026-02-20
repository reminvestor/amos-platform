# frozen_string_literal: true

module LivingPlatform
  # WeeklyAgentReflectionsJob - Runs weekly reflection for all agents
  #
  # Scheduled to run weekly for comprehensive performance reviews.
  #
  class WeeklyAgentReflectionsJob < ApplicationJob
    queue_as :living_platform
    
    retry_on StandardError, wait: 10.minutes, attempts: 2

    def perform(entity_id = nil)
      entities = entity_id ? [Entity.find(entity_id)] : Entity.active

      entities.each do |entity|
        run_weekly_reflections(entity)
      rescue => e
        Rails.logger.error "[LivingPlatform] Weekly reflections failed for entity #{entity.id}: #{e.message}"
      end
    end

    private

    def run_weekly_reflections(entity)
      Rails.logger.info "[LivingPlatform] Starting weekly reflections for entity #{entity.id}"
      
      agents = entity.agent_plugins.where(status: 'active')
      queued = 0
      
      agents.find_each do |agent|
        activity_count = agent.agent_plugin_executions
          .where('created_at > ?', 7.days.ago)
          .count
        
        next unless activity_count >= 5
        
        AgentReflectionJob.perform_later(agent.id, reflection_type: 'weekly')
        queued += 1
      end
      
      Rails.logger.info "[LivingPlatform] Queued weekly reflections for #{queued} agents in entity #{entity.id}"
    end
  end
end


