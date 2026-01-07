# frozen_string_literal: true

module PlatformEvolution
  # LogMonitorJob - Periodic job to scan logs and create tickets
  #
  # This should be scheduled to run every 15-30 minutes
  #
  class LogMonitorJob < ApplicationJob
    queue_as :default

    def perform(entity_id = nil)
      entities = entity_id ? [Entity.find(entity_id)] : Entity.all

      entities.each do |entity|
        Rails.logger.info "[LogMonitorJob] Scanning logs for entity #{entity.id}"

        service = LogMonitorService.new(entity)
        result = service.monitor_once

        Rails.logger.info "[LogMonitorJob] Entity #{entity.id}: " \
                          "processed #{result[:processed]}, " \
                          "tickets created #{result[:tickets_created]}, " \
                          "unique errors #{result[:unique_errors]}"
      rescue => e
        Rails.logger.error "[LogMonitorJob] Error scanning entity #{entity.id}: #{e.message}"
      end
    end
  end
end


