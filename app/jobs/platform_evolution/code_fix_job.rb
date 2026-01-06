# frozen_string_literal: true

module PlatformEvolution
  # CodeFixJob - Generates code fix from debug session
  #
  class CodeFixJob < ApplicationJob
    queue_as :default

    def perform(debug_session_id, options = {})
      session = DebugSession.find(debug_session_id)
      ticket = session.support_ticket

      Rails.logger.info "[CodeFixJob] Generating fix for #{ticket.ticket_number}"

      service = CodeFixAgentService.new(session)
      code_fix = service.generate_fix!

      return unless code_fix

      if code_fix.tests_passed && code_fix.lint_passed
        Rails.logger.info "[CodeFixJob] Fix validated for #{ticket.ticket_number}. Creating PR..."

        if options[:auto_create_pr]
          PullRequestJob.perform_later(code_fix.id)
        else
          Rails.logger.info "[CodeFixJob] Fix ready for PR: #{code_fix.fix_id}"
        end
      else
        Rails.logger.warn "[CodeFixJob] Fix failed validation for #{ticket.ticket_number}"
        session.add_agent_message("Generated fix failed tests. Manual review required.")
      end
    rescue => e
      Rails.logger.error "[CodeFixJob] Error generating fix for session #{debug_session_id}: #{e.message}"
      raise if options[:raise_on_error]
    end
  end
end


