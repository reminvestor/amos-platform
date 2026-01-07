# frozen_string_literal: true

module PlatformEvolution
  # DebugAgentJob - Runs automated debugging for a ticket
  #
  class DebugAgentJob < ApplicationJob
    queue_as :default

    def perform(ticket_id, options = {})
      ticket = SupportTicket.find(ticket_id)

      Rails.logger.info "[DebugAgentJob] Starting debug for #{ticket.ticket_number}"

      # Create and run debug session
      service = DebugAgentService.new(ticket)
      session = service.start_debugging!

      return unless session

      # If we have a high-confidence fix, automatically proceed to code generation
      # This enables the full automated pipeline for bugs
      if session.status == 'awaiting_approval' && session.confidence_score.to_f >= 0.7
        Rails.logger.info "[DebugAgentJob] High confidence fix (#{(session.confidence_score * 100).round}%) - auto-generating code fix"
        CodeFixJob.perform_later(session.id)
      elsif session.status == 'awaiting_approval'
        Rails.logger.info "[DebugAgentJob] Fix proposed with confidence #{(session.confidence_score.to_f * 100).round}%. " \
                          "Awaiting manual review for #{ticket.ticket_number}"
      else
        Rails.logger.info "[DebugAgentJob] Debug session status: #{session.status}. Further investigation may be needed."
      end
    rescue => e
      Rails.logger.error "[DebugAgentJob] Error debugging #{ticket_id}: #{e.message}"
      Rails.logger.error e.backtrace.first(10).join("\n")
      raise if options[:raise_on_error]
    end
  end
end

