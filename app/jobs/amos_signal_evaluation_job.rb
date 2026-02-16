# frozen_string_literal: true

# AmosSignalEvaluationJob - Evaluates accumulated signals for an entity
#
# Called asynchronously after a signal is emitted so we don't block
# the request/response cycle. Runs the signal monitor to decide
# whether to trigger a reactive session.
#
class AmosSignalEvaluationJob < ApplicationJob
  queue_as :living_platform

  # Deduplicate: if multiple signals fire in quick succession,
  # we only need to evaluate once
  def perform(entity_id:)
    entity = Entity.find(entity_id)
    monitor = AmosSignalMonitor.new(entity)
    result = monitor.evaluate!

    if result[:triggered]
      Rails.logger.info "[AmosSignalEvaluation] Triggered #{result[:trigger_type]} session " \
                        "for #{entity.name}: #{result[:reason]}"
    else
      Rails.logger.debug "[AmosSignalEvaluation] No trigger for #{entity.name}: #{result[:reason]}"
    end
  rescue ActiveRecord::RecordNotFound => e
    Rails.logger.warn "[AmosSignalEvaluation] Entity not found: #{entity_id}"
  rescue => e
    Rails.logger.error "[AmosSignalEvaluation] Failed: #{e.message}"
  end
end
