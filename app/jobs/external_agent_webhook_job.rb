# frozen_string_literal: true

# ExternalAgentWebhookJob - Delivers EAP webhooks asynchronously
#
# Retries with exponential backoff on transient failures.
# After 3 failed attempts, increments the agent's failure counter
# (which auto-disables webhooks at 10 consecutive failures).
#
class ExternalAgentWebhookJob < ApplicationJob
  queue_as :default

  retry_on Net::ReadTimeout, Net::OpenTimeout, wait: :exponentially_longer, attempts: 3

  def perform(agent_id, event, payload)
    ExternalAgentWebhookService.deliver(agent_id, event, payload)
  end
end
