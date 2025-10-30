module Notifiers
  class SlackNotifier
    def send_interaction_notification(pipeline_interaction)
      # TODO: Implement Slack notification via webhook
      Rails.logger.info "📢 Slack notification: #{pipeline_interaction.question}"
      true
    end

    def send_state_change_notification(pipeline_execution, new_state)
      # TODO: Implement state change notification
      Rails.logger.info "📢 Pipeline #{pipeline_execution.id} → #{new_state}"
      true
    end
  end
end
