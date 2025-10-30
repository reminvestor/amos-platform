module Notifiers
  class EmailNotifier
    def send_interaction_notification(pipeline_interaction)
      # TODO: Implement email notification via Mailgun
      Rails.logger.info "📧 Email notification: #{pipeline_interaction.question}"
      true
    end

    def send_state_change_notification(pipeline_execution, new_state)
      # TODO: Implement state change email
      Rails.logger.info "📧 Pipeline #{pipeline_execution.id} → #{new_state}"
      true
    end
  end
end
