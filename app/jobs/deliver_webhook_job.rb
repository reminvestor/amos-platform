class DeliverWebhookJob < ApplicationJob
  queue_as :default

  retry_on Net::ReadTimeout, Net::OpenTimeout, wait: :exponentially_longer, attempts: 3

  def perform(webhook_subscription, event_type, payload)
    return unless webhook_subscription.active?

    # Create webhook event record
    webhook_event = webhook_subscription.webhook_events.create!(
      event_type: event_type,
      payload: payload
    )

    # Prepare webhook payload
    webhook_payload = {
      id: webhook_event.id,
      type: event_type,
      created_at: webhook_event.created_at.iso8601,
      data: payload,
      subscription_id: webhook_subscription.id
    }

    # Make HTTP request
    response = HTTParty.post(
      webhook_subscription.endpoint_url,
      body: webhook_payload.to_json,
      headers: build_headers(webhook_subscription, webhook_payload),
      timeout: 30
    )

    # Check response
    if response.success?
      webhook_event.mark_delivered!(response)
      webhook_subscription.reset_retry_count!
    else
      handle_failed_delivery(webhook_subscription, webhook_event, response)
    end

  rescue => e
    webhook_event.mark_failed!(e.message)
    webhook_subscription.mark_failed!
    raise e if webhook_subscription.retry_count < 3
  end

  private

  def build_headers(subscription, payload)
    headers = {
      "Content-Type" => "application/json",
      "User-Agent" => "Scout-Webhook/1.0",
      "X-Webhook-ID" => subscription.id.to_s,
      "X-Webhook-Event" => payload[:type]
    }

    # Add signature if secret is configured
    if subscription.signing_secret.present?
      headers["X-Webhook-Signature"] = subscription.generate_signature(payload.to_json)
    end

    headers
  end

  def handle_failed_delivery(subscription, event, response)
    event.update!(
      response_status: response.code,
      response_body: response.body&.truncate(10_000),
      error_message: "HTTP #{response.code}: #{response.message}"
    )

    subscription.mark_failed!

    # Raise to trigger retry
    raise "Webhook delivery failed: #{response.code}"
  end
end
