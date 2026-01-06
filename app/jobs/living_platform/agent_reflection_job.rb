# frozen_string_literal: true

module LivingPlatform
  # AgentReflectionJob - Runs agent metacognition
  #
  # Enables agents to reflect on their performance:
  # - Execution reflections (sampled after task completion)
  # - Daily reflections (end of day summary)
  # - Weekly reflections (comprehensive review)
  #
  class AgentReflectionJob < ApplicationJob
    queue_as :default
    
    retry_on StandardError, wait: 5.minutes, attempts: 2

    def perform(agent_id, reflection_type: 'daily', execution_id: nil)
      agent = AgentPlugin.find(agent_id)
      
      Rails.logger.info "[LivingPlatform] Running #{reflection_type} reflection for #{agent.name}"
      
      service = MetacognitionService.new(agent)
      
      reflection = case reflection_type
                   when 'execution'
                     execution = AgentPluginExecution.find(execution_id)
                     service.reflect_on_execution(execution)
                   when 'daily'
                     service.daily_reflection
                   when 'weekly'
                     service.weekly_reflection
                   else
                     Rails.logger.warn "[LivingPlatform] Unknown reflection type: #{reflection_type}"
                     nil
                   end
      
      if reflection
        Rails.logger.info "[LivingPlatform] Reflection complete for #{agent.name}: " \
                          "score=#{reflection.overall_score}, " \
                          "issues=#{reflection.identified_issues&.count || 0}"
      end
    end
  end
end


