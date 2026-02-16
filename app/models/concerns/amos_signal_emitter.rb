# frozen_string_literal: true

# AmosSignalEmitter - Concern for models that should emit signals to AMOS
#
# Include this in any model that should trigger AMOS awareness.
# Signals are recorded asynchronously and never block the main request.
#
# Usage:
#   class SupportTicket < ApplicationRecord
#     include AmosSignalEmitter
#     after_create :emit_ticket_signal
#
#     private
#     def emit_ticket_signal
#       emit_amos_signal!(
#         signal_type: is_critical? ? 'critical_ticket' : 'error_spike',
#         source: 'support_ticket',
#         strength: is_critical? ? 0.95 : 0.5,
#         summary: "New ticket: #{title}",
#         data: { ticket_id: id, priority: priority, category: category }
#       )
#     end
#   end
#
module AmosSignalEmitter
  extend ActiveSupport::Concern

  private

  def emit_amos_signal!(signal_type:, source:, strength:, summary:, data: {})
    # Determine entity from the record
    record_entity = resolve_signal_entity
    return unless record_entity

    # Non-blocking: enqueue signal recording
    AmosSignalMonitor.emit!(
      entity: record_entity,
      signal_type: signal_type,
      source: source,
      strength: strength,
      summary: summary,
      data: data
    )
  rescue => e
    # NEVER let signal emission break the calling code
    Rails.logger.debug "[AmosSignalEmitter] Signal emission failed (non-fatal): #{e.message}"
  end

  def resolve_signal_entity
    if respond_to?(:entity) && entity.present?
      entity
    elsif respond_to?(:entity_id) && entity_id.present?
      Entity.find_by(id: entity_id)
    else
      nil
    end
  end
end
