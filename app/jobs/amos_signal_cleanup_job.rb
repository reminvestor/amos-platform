# frozen_string_literal: true

# AmosSignalCleanupJob - Expire old unprocessed signals
#
# Runs hourly to clean up signals that weren't acted on.
# Prevents signal table from growing unbounded.
#
class AmosSignalCleanupJob < ApplicationJob
  queue_as :living_platform

  def perform
    expired = AmosSignal.expire_old!(older_than: 24.hours)
    Rails.logger.info "[AmosSignalCleanup] Expired old pending signals"

    # Also decay working memory salience for all entities
    Entity.active.find_each do |entity|
      AmosWorkingMemory.apply_salience_decay!(entity)
    rescue => e
      Rails.logger.warn "[AmosSignalCleanup] Memory decay failed for entity #{entity.id}: #{e.message}"
    end
  end
end
