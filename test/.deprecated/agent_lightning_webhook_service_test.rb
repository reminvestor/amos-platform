require "test_helper"

class AgentLightningWebhookServiceTest < ActiveSupport::TestCase
  setup do
    @entity = entities(:one)
    @service = AgentLightningWebhookService.new(@entity)
  end

  test "should register webhook" do
    webhook = @service.register_webhook(
      event_type: "training_completed",
      url: "https://example.com/webhook",
      headers: { "X-API-Key" => "secret" }
    )

    assert webhook.persisted?
    assert_equal "training_completed", webhook.event_type
    assert_equal "https://example.com/webhook", webhook.url
    assert webhook.active?
  end

  test "should not allow duplicate webhooks for same event" do
    @service.register_webhook(
      event_type: "training_completed",
      url: "https://example.com/webhook"
    )

    webhook2 = @service.register_webhook(
      event_type: "training_completed",
      url: "https://example.com/webhook"
    )

    assert_not webhook2.persisted?
  end

  test "should deregister webhook" do
    webhook = @service.register_webhook(
      event_type: "training_completed",
      url: "https://example.com/webhook"
    )

    @service.deregister_webhook(webhook.id)

    assert_not AgentLightningWebhook.exists?(webhook.id)
  end

  test "should notify training completed" do
    webhook = @service.register_webhook(
      event_type: "training_completed",
      url: "https://example.com/webhook"
    )

    training_data = {
      job_id: "job_123",
      traces_used: 100,
      improvement: 15.5,
      metrics: { success_rate: 0.85 }
    }

    @service.notify_training_completed(training_data)

    log = webhook.agent_lightning_webhook_logs.last
    assert log.present?
    assert_equal "training_completed", log.event_type
    assert_equal training_data, log.payload
  end

  test "should notify success rate improved" do
    webhook = @service.register_webhook(
      event_type: "success_rate_improved",
      url: "https://example.com/webhook"
    )

    @service.notify_success_rate_improved(0.85, 0.90)

    log = webhook.agent_lightning_webhook_logs.last
    assert log.present?
    assert_equal "success_rate_improved", log.event_type
  end

  test "should notify success rate degraded" do
    webhook = @service.register_webhook(
      event_type: "success_rate_degraded",
      url: "https://example.com/webhook"
    )

    @service.notify_success_rate_degraded(0.90, 0.75)

    log = webhook.agent_lightning_webhook_logs.last
    assert log.present?
    assert_equal "success_rate_degraded", log.event_type
  end

  test "should notify cost reduced" do
    webhook = @service.register_webhook(
      event_type: "cost_reduced",
      url: "https://example.com/webhook"
    )

    @service.notify_cost_reduced(100.0, 85.0)

    log = webhook.agent_lightning_webhook_logs.last
    assert log.present?
    assert_equal "cost_reduced", log.event_type
  end

  test "should notify cost increased" do
    webhook = @service.register_webhook(
      event_type: "cost_increased",
      url: "https://example.com/webhook"
    )

    @service.notify_cost_increased(100.0, 120.0)

    log = webhook.agent_lightning_webhook_logs.last
    assert log.present?
    assert_equal "cost_increased", log.event_type
  end

  test "should notify token limit exceeded" do
    webhook = @service.register_webhook(
      event_type: "token_limit_exceeded",
      url: "https://example.com/webhook"
    )

    @service.notify_token_limit_exceeded(1000000, 950000)

    log = webhook.agent_lightning_webhook_logs.last
    assert log.present?
    assert_equal "token_limit_exceeded", log.event_type
  end

  test "should notify error rate high" do
    webhook = @service.register_webhook(
      event_type: "error_rate_high",
      url: "https://example.com/webhook"
    )

    @service.notify_error_rate_high(0.15)

    log = webhook.agent_lightning_webhook_logs.last
    assert log.present?
    assert_equal "error_rate_high", log.event_type
  end

  test "webhook should track call statistics" do
    webhook = @service.register_webhook(
      event_type: "training_completed",
      url: "https://example.com/webhook"
    )

    # Simulate successful deliveries
    3.times do
      @service.notify_training_completed({ job_id: "job_#{SecureRandom.uuid}" })
    end

    webhook.reload
    assert_equal 3, webhook.total_calls
  end

  test "webhook success rate calculation" do
    webhook = @service.register_webhook(
      event_type: "training_completed",
      url: "https://example.com/webhook"
    )

    # Create some logs
    AgentLightningWebhookLog.create!(
      agent_lightning_webhook: webhook,
      event_type: "training_completed",
      payload: {},
      status: "success"
    )

    AgentLightningWebhookLog.create!(
      agent_lightning_webhook: webhook,
      event_type: "training_completed",
      payload: {},
      status: "failed"
    )

    success_rate = webhook.success_rate
    assert_in_delta 0.5, success_rate, 0.01
  end

  test "webhook should handle inactive webhooks" do
    webhook = @service.register_webhook(
      event_type: "training_completed",
      url: "https://example.com/webhook"
    )

    webhook.update!(active: false)

    @service.notify_training_completed({ job_id: "job_123" })

    # Should not create logs for inactive webhooks
    assert_equal 0, webhook.agent_lightning_webhook_logs.count
  end

  test "webhook should include custom headers in payload" do
    headers = { "X-API-Key" => "secret", "X-Custom" => "value" }
    webhook = @service.register_webhook(
      event_type: "training_completed",
      url: "https://example.com/webhook",
      headers: headers
    )

    assert_equal headers, webhook.headers
  end
end
