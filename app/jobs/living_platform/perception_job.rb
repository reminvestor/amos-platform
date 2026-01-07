# frozen_string_literal: true

module LivingPlatform
  # PerceptionJob - Runs platform perception
  #
  # Gathers metrics, detects anomalies, and triggers autonomous
  # actions for critical issues.
  #
  # Scheduled to run every hour for routine perception,
  # with deeper scans less frequently.
  #
  class PerceptionJob < ApplicationJob
    queue_as :default
    
    retry_on StandardError, wait: 5.minutes, attempts: 3

    def perform(entity_id = nil, perception_type: 'routine')
      if entity_id
        entity = Entity.find(entity_id)
        run_entity_perception(entity, perception_type)
      else
        run_global_perception(perception_type)
      end
    end

    private

    def run_entity_perception(entity, perception_type)
      Rails.logger.info "[LivingPlatform] Running #{perception_type} perception for entity #{entity.id}"
      
      service = PerceptionService.new(entity)
      perception = service.perceive(type: perception_type)
      
      Rails.logger.info "[LivingPlatform] Perception complete: " \
                        "health=#{(perception.overall_health_score * 100).round}%, " \
                        "anomalies=#{perception.anomaly_count}"
      
      # If critical issues, trigger immediate actions
      if perception.critical_anomalies > 0
        Rails.logger.warn "[LivingPlatform] #{perception.critical_anomalies} critical anomalies detected"
        
        # Trigger desire engine for immediate goals
        DesireEngineJob.perform_later(entity.id, triggered: true)
      end
    end

    def run_global_perception(perception_type)
      Rails.logger.info "[LivingPlatform] Running global perception"
      
      service = PerceptionService.new
      perception = service.perceive(type: perception_type)
      
      Rails.logger.info "[LivingPlatform] Global perception complete"
    end
  end
end


