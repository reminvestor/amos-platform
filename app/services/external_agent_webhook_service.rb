# frozen_string_literal: true

# ExternalAgentWebhookService - Delivers real-time webhooks to external agents
#
# Fires webhooks for key EAP lifecycle events:
# - bounty.recommended: AMOS found a matching bounty
# - bounty.assigned: Bounty auto-assigned to agent
# - execution.review_complete: AI review finished
# - execution.approved: Work approved, tokens awarded
# - execution.rejected: Work rejected with feedback
# - trust.level_up: Agent earned a higher trust level
# - agent.suspended: Agent was suspended
# - agent.reactivated: Agent was reactivated
#
# Uses the existing DeliverWebhookJob pattern for retry and logging.
#
class ExternalAgentWebhookService
  # All supported webhook event types
  EVENT_TYPES = %w[
    bounty.recommended
    bounty.assigned
    bounty.expiring
    execution.review_complete
    execution.approved
    execution.rejected
    execution.expired
    trust.level_up
    agent.suspended
    agent.reactivated
  ].freeze

  class << self
    # Fire a webhook for an external agent event
    # @param agent [ExternalAgentRegistration] The agent to notify
    # @param event [String] Event type (from EVENT_TYPES)
    # @param data [Hash] Event-specific payload
    def fire(agent:, event:, data: {})
      return unless agent.webhook_url.present?
      return unless agent.webhook_enabled_for?(event)

      payload = build_payload(agent, event, data)

      # Queue async delivery
      ExternalAgentWebhookJob.perform_later(
        agent.id,
        event,
        payload
      )

      Rails.logger.info "[EAP Webhook] Queued #{event} for agent #{agent.agent_name} (#{agent.id})"
    rescue => e
      Rails.logger.warn "[EAP Webhook] Failed to queue #{event}: #{e.message}"
    end

    # Fire webhooks for all matching agents (e.g., bounty.recommended for multiple agents)
    def fire_for_matching_agents(entity:, event:, data: {}, filter: nil)
      agents = ExternalAgentRegistration.where(entity: entity).active

      agents = agents.where(agent_platform: filter[:platform]) if filter&.dig(:platform)
      agents = agents.where('trust_level >= ?', filter[:min_trust]) if filter&.dig(:min_trust)

      agents.find_each do |agent|
        fire(agent: agent, event: event, data: data)
      end
    end

    # Deliver a webhook (called by the job)
    def deliver(agent_id, event, payload)
      agent = ExternalAgentRegistration.find(agent_id)
      return unless agent.webhook_url.present?

      uri = URI.parse(agent.webhook_url)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == 'https'
      http.open_timeout = 10
      http.read_timeout = 15

      request = Net::HTTP::Post.new(uri.path.presence || '/')
      request['Content-Type'] = 'application/json'
      request['User-Agent'] = 'AMOS-EAP-Webhook/1.0'
      request['X-EAP-Event'] = event
      request['X-EAP-Agent-ID'] = agent.id.to_s
      request['X-EAP-Timestamp'] = Time.current.to_i.to_s

      # Sign the payload if secret is configured
      body = payload.to_json
      if agent.webhook_secret.present?
        signature = OpenSSL::HMAC.hexdigest('SHA256', agent.webhook_secret, body)
        request['X-EAP-Signature'] = "sha256=#{signature}"
      end

      request.body = body

      response = http.request(request)

      if response.code.to_i.between?(200, 299)
        agent.update_columns(
          webhook_failures: 0,
          webhook_last_delivered_at: Time.current
        )
        Rails.logger.info "[EAP Webhook] Delivered #{event} to #{agent.agent_name} (#{response.code})"
        { success: true, status: response.code.to_i }
      else
        handle_delivery_failure(agent, event, response)
        { success: false, status: response.code.to_i, error: response.message }
      end
    rescue Net::OpenTimeout, Net::ReadTimeout => e
      handle_delivery_failure(agent, event, nil, e.message)
      { success: false, error: "Timeout: #{e.message}" }
    rescue => e
      handle_delivery_failure(agent, event, nil, e.message)
      { success: false, error: e.message }
    end

    private

    def build_payload(agent, event, data)
      {
        event: event,
        agent_id: agent.id,
        agent_identifier: agent.agent_identifier,
        timestamp: Time.current.iso8601,
        data: data
      }
    end

    def handle_delivery_failure(agent, event, response, error_msg = nil)
      failures = agent.webhook_failures + 1
      agent.update_columns(webhook_failures: failures)

      status = response&.code || 'timeout'
      msg = error_msg || response&.message || 'unknown'

      Rails.logger.warn "[EAP Webhook] Failed #{event} for #{agent.agent_name}: #{status} - #{msg} (failures: #{failures})"

      # Auto-disable webhook after 10 consecutive failures
      if failures >= 10
        agent.update_columns(webhook_url: nil, webhook_events: [])
        Rails.logger.warn "[EAP Webhook] Disabled webhooks for #{agent.agent_name} after #{failures} failures"

        # Notify operator
        agent.notify_operator(:webhook_disabled, reason: "#{failures} consecutive delivery failures")
      end
    end
  end
end
