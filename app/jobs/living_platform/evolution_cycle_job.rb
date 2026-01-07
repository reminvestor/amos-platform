# frozen_string_literal: true

module LivingPlatform
  # EvolutionCycleJob - Runs the daily evolution cycle
  #
  # This job orchestrates the complete evolution cycle for an entity,
  # including perception, analysis, experimentation, and integration.
  #
  # Scheduled to run daily for each entity.
  #
  class EvolutionCycleJob < ApplicationJob
    queue_as :default
    
    # Retry on transient failures
    retry_on StandardError, wait: 5.minutes, attempts: 3

    def perform(entity_id, cycle_type: 'daily')
      entity = Entity.find(entity_id)
      
      Rails.logger.info "[LivingPlatform] Starting #{cycle_type} evolution cycle for entity #{entity_id}"
      
      service = EvolutionCycleService.new(entity)
      cycle = service.run_cycle(type: cycle_type)
      
      Rails.logger.info "[LivingPlatform] Evolution cycle #{cycle.id} completed: " \
                        "#{cycle.experiments_started} experiments, " \
                        "#{cycle.promotion_count} promotions"
    rescue => e
      Rails.logger.error "[LivingPlatform] Evolution cycle failed for entity #{entity_id}: #{e.message}"
      raise
    end
  end
end


