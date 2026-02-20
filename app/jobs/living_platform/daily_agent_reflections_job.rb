# frozen_string_literal: true

module LivingPlatform
  # DailyAgentReflectionsJob - Runs daily reflection for all agents
  #
  # Scheduled to run at end of day to trigger reflection for all
  # active agents in an entity.
  #
  class DailyAgentReflectionsJob < ApplicationJob
    queue_as :living_platform
    
    retry_on StandardError, wait: 5.minutes, attempts: 2

    def perform(entity_id = nil)
      entities = entity_id ? [Entity.find(entity_id)] : Entity.active

      entities.each do |entity|
        run_daily_reflections(entity)
      rescue => e
        Rails.logger.error "[LivingPlatform] Daily reflections failed for entity #{entity.id}: #{e.message}"
      end
    end

    private

    def run_daily_reflections(entity)
      Rails.logger.info "[LivingPlatform] Starting daily reflections for entity #{entity.id}"
      
      agents = entity.agent_plugins.where(status: 'active')
      queued = 0
      
      agents.find_each do |agent|
        had_activity = agent.agent_plugin_executions
          .where('created_at > ?', 24.hours.ago)
          .exists?
        
        next unless had_activity
        
        AgentReflectionJob.perform_later(agent.id, reflection_type: 'daily')
        queued += 1
      end
      
      Rails.logger.info "[LivingPlatform] Queued daily reflections for #{queued} agents in entity #{entity.id}"
    end
  end
end


