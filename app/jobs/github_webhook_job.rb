# frozen_string_literal: true

# GitHubWebhookJob - Processes GitHub webhook events asynchronously
#
# Delegates to GitHubWebhookService for the actual processing.
# Retries on transient failures.
#
class GitHubWebhookJob < ApplicationJob
  queue_as :default

  retry_on StandardError, wait: :exponentially_longer, attempts: 3

  def perform(event_type, payload, delivery_id)
    GitHubWebhookService.process(
      event_type: event_type,
      payload: payload,
      delivery_id: delivery_id
    )
  end
end
