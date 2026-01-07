# frozen_string_literal: true

module LivingPlatform
  # DesireEngineJob - Generates autonomous goals
  #
  # Runs the Desire Engine to analyze the platform state and
  # generate goals that the platform should pursue on its own.
  #
  # Scheduled to run daily, with triggered runs for urgent situations.
  #
  class DesireEngineJob < ApplicationJob
    queue_as :default
    
    retry_on StandardError, wait: 5.minutes, attempts: 3

    def perform(entity_id, triggered: false)
      entity = Entity.find(entity_id)
      
      Rails.logger.info "[LivingPlatform] Running desire engine for entity #{entity_id}" \
                        "#{triggered ? ' (triggered)' : ''}"
      
      engine = DesireEngine.new(entity)
      result = engine.generate_daily_goals
      
      Rails.logger.info "[LivingPlatform] Generated #{result[:goals_generated]} goals: " \
                        "improvement=#{result[:breakdown][:improvement]}, " \
                        "expansion=#{result[:breakdown][:expansion]}, " \
                        "maintenance=#{result[:breakdown][:maintenance]}"
      
      # Schedule high-priority goals
      if triggered
        engine.schedule_pending_goals
      end
    end
  end
end


