# frozen_string_literal: true

# CRM Automation Job
# Runs CRM automations for all active entities
# Should be scheduled to run daily or hourly
class CrmAutomationJob < ApplicationJob
  queue_as :default
  
  def perform(entity_id = nil)
    if entity_id
      # Process single entity
      entity = Entity.find_by(id: entity_id)
      return unless entity
      
      CrmAutomationService.process_entity(entity)
    else
      # Process all active entities
      Entity.where(status: "active").find_each do |entity|
        CrmAutomationService.process_entity(entity)
      rescue StandardError => e
        Rails.logger.error "[CRM Automation] Error processing entity #{entity.id}: #{e.message}"
        Rails.logger.error e.backtrace.first(10).join("\n")
      end
    end
  end
end
