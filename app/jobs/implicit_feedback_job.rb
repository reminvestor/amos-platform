# frozen_string_literal: true

# ImplicitFeedbackJob - Process conversation for implicit feedback signals
#
# This job analyzes a conversation session to detect implicit signals like:
# - "Thanks, perfect!" (positive)
# - "No, that's wrong" (negative)
# - User retrying the same request (negative)
#
# Runs after conversation turns to extract learning signals without
# requiring explicit thumbs up/down feedback.
#
class ImplicitFeedbackJob < ApplicationJob
  queue_as :learning

  # Best-effort - don't retry on failure
  discard_on StandardError do |job, error|
    Rails.logger.error "[ImplicitFeedbackJob] Failed: #{error.message}"
  end

  def perform(entity_id:, session_id:, message_ids: nil)
    entity = Entity.find_by(id: entity_id)
    return unless entity

    # Get messages to analyze
    messages = if message_ids.present?
                 ScoutMessage.where(id: message_ids).order(:created_at)
               else
                 # Get recent messages from this session
                 ScoutMessage.where(session_id: session_id)
                             .order(created_at: :desc)
                             .limit(10)
                             .reverse
               end

    return if messages.count < 2

    # Run implicit feedback detection
    detector = Learning::ImplicitFeedbackDetector.new(entity: entity, session_id: session_id)
    signals = detector.analyze_and_process!(messages)

    Rails.logger.info "[ImplicitFeedbackJob] Detected #{signals.count} signals in session #{session_id}"
  end
end
