# frozen_string_literal: true

module LivingPlatform
  # LifecycleEvaluationJob - Evaluates agent lifecycle
  #
  # Periodically evaluates agents for:
  # - Training completion (maturation)
  # - Retirement candidates
  # - Knowledge preservation
  #
  # Scheduled to run daily.
  #
  class LifecycleEvaluationJob < ApplicationJob
    queue_as :default
    
    retry_on StandardError, wait: 5.minutes, attempts: 2

    def perform(entity_id)
      entity = Entity.find(entity_id)
      
      Rails.logger.info "[LivingPlatform] Running lifecycle evaluation for entity #{entity_id}"
      
      service = LifecycleService.new(entity)
      
      # Check training agents
      training_agents = entity.agent_plugins.where(lifecycle_stage: 'training')
      graduated = 0
      
      training_agents.find_each do |agent|
        if service.evaluate_training_completion(agent)
          graduated += 1
          Rails.logger.info "[LivingPlatform] Agent #{agent.name} graduated from training"
        end
      end
      
      # Check for retirement candidates
      evaluations = service.evaluate_all_agents
      retirement_candidates = evaluations.select { |e| e[:should_retire] }
      
      # Auto-retire agents with multiple high-severity reasons
      retired = 0
      retirement_candidates.each do |candidate|
        high_severity = candidate[:reasons].count { |r| r[:severity] == :high }
        
        if high_severity >= 1 || candidate[:reasons].count >= 3
          agent = entity.agent_plugins.find_by(slug: candidate[:agent])
          if agent
            service.retire_agent(agent, reasons: candidate[:reasons], trigger: 'lifecycle_evaluation')
            retired += 1
            Rails.logger.info "[LivingPlatform] Agent #{agent.name} retired: " \
                              "#{candidate[:reasons].map { |r| r[:type] }.join(', ')}"
          end
        end
      end
      
      Rails.logger.info "[LivingPlatform] Lifecycle evaluation complete: " \
                        "graduated=#{graduated}, retired=#{retired}"
    end
  end
end


