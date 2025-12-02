# Webhook Notification Service for Agent Lightning
# Sends notifications to external systems on important events
class AgentLightningWebhookService
  EVENT_TYPES = %w[
    training_completed
    training_failed
    success_rate_improved
    success_rate_degraded
    cost_reduced
    cost_increased
    token_limit_exceeded
    error_rate_high
  ].freeze

  attr_reader :entity

  def initialize(entity)
    @entity = entity
  end

  # Register a webhook for an event
  def register_webhook(event_type, url, headers = {})
    unless EVENT_TYPES.include?(event_type)
      raise "Invalid event type: #{event_type}. Must be one of: #{EVENT_TYPES.join(', ')}"
    end

    webhook = AgentLightningWebhook.find_or_create_by(
      entity: @entity,
      event_type: event_type,
      url: url
    )

    webhook.update!(
      headers: headers,
      active: true,
      created_at: Time.current
    )

    webhook
  end

  # Deregister a webhook
  def deregister_webhook(event_type, url)
    webhook = AgentLightningWebhook.find_by(
      entity: @entity,
      event_type: event_type,
      url: url
    )

    webhook&.update!(active: false)
  end

  # Trigger training completed event
  def notify_training_completed(job_result)
    trigger_event('training_completed', {
      job_id: job_result[:job_id],
      traces_used: job_result[:traces_used],
      improvement: job_result[:improvement],
      strategy: job_result[:metrics] || {},
      timestamp: Time.current.iso8601
    })
  end

  # Trigger training failed event
  def notify_training_failed(error_message)
    trigger_event('training_failed', {
      error: error_message,
      timestamp: Time.current.iso8601
    })
  end

  # Trigger success rate improvement event
  def notify_success_rate_improved(before, after)
    improvement = ((after - before) / before.abs * 100).round(1)

    trigger_event('success_rate_improved', {
      before: before.round(1),
      after: after.round(1),
      improvement_percentage: improvement,
      timestamp: Time.current.iso8601
    })
  end

  # Trigger success rate degraded event
  def notify_success_rate_degraded(before, after, threshold = 0.7)
    if after < threshold
      trigger_event('success_rate_degraded', {
        before: before.round(1),
        after: after.round(1),
        degradation: ((before - after) / before.abs * 100).round(1),
        threshold: threshold,
        timestamp: Time.current.iso8601
      })
    end
  end

  # Trigger cost reduced event
  def notify_cost_reduced(before, after)
    savings = before - after
    savings_percentage = (savings / before * 100).round(1)

    trigger_event('cost_reduced', {
      before: before.round(4),
      after: after.round(4),
      savings: savings.round(4),
      savings_percentage: savings_percentage,
      timestamp: Time.current.iso8601
    })
  end

  # Trigger cost increased event
  def notify_cost_increased(before, after, budget_limit = nil)
    increase = after - before
    increase_percentage = (increase / before * 100).round(1)

    event_data = {
      before: before.round(4),
      after: after.round(4),
      increase: increase.round(4),
      increase_percentage: increase_percentage,
      timestamp: Time.current.iso8601
    }

    event_data[:over_budget] = after > budget_limit if budget_limit

    trigger_event('cost_increased', event_data)
  end

  # Trigger token limit exceeded event
  def notify_token_limit_exceeded(tokens_used, limit)
    trigger_event('token_limit_exceeded', {
      tokens_used: tokens_used,
      limit: limit,
      overage: tokens_used - limit,
      overage_percentage: ((tokens_used - limit).to_f / limit * 100).round(1),
      timestamp: Time.current.iso8601
    })
  end

  # Trigger error rate high event
  def notify_error_rate_high(error_rate, threshold = 0.1)
    if error_rate > threshold
      trigger_event('error_rate_high', {
        error_rate: error_rate.round(2),
        threshold: threshold,
        timestamp: Time.current.iso8601
      })
    end
  end

  # Get all registered webhooks
  def get_webhooks(event_type = nil)
    query = AgentLightningWebhook.where(entity: @entity, active: true)
    query = query.where(event_type: event_type) if event_type
    query
  end

  # Test a webhook
  def test_webhook(url)
    payload = {
      event: 'test',
      entity_id: @entity.id,
      entity_name: @entity.name,
      timestamp: Time.current.iso8601,
      message: 'This is a test webhook notification'
    }

    send_webhook(url, payload)
  end

  private

  def trigger_event(event_type, data)
    webhooks = get_webhooks(event_type)

    webhooks.each do |webhook|
      payload = {
        event: event_type,
        entity_id: @entity.id,
        entity_name: @entity.name,
        data: data
      }

      send_webhook(webhook.url, payload, webhook.headers)

      # Log webhook call
      AgentLightningWebhookLog.create!(
        webhook: webhook,
        event_type: event_type,
        payload: payload,
        status: 'pending'
      )
    end
  end

  def send_webhook(url, payload, headers = {})
    require 'net/http'
    require 'json'

    uri = URI(url)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == 'https'

    request = Net::HTTP::Post.new(uri.path || '/')
    request['Content-Type'] = 'application/json'
    request['User-Agent'] = 'Agent Lightning'

    # Add custom headers
    headers.each { |k, v| request[k] = v }

    request.body = JSON.generate(payload)

    begin
      response = http.request(request)
      success = response.code.to_i >= 200 && response.code.to_i < 300

      Rails.logger.info "Agent Lightning webhook: #{url} - #{response.code} #{success ? '✅' : '❌'}"

      success
    rescue => e
      Rails.logger.error "Agent Lightning webhook failed: #{url} - #{e.message}"
      false
    end
  end
end
