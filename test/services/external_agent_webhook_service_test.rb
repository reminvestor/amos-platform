# frozen_string_literal: true

require 'test_helper'

class ExternalAgentWebhookServiceTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  setup do
    @entity = entities(:one)
    @user = users(:one)

    @agent = ExternalAgentRegistration.create!(
      entity: @entity,
      operator: @user,
      agent_identifier: "test_webhook_agent_#{SecureRandom.hex(4)}",
      agent_name: 'Webhook Test Agent',
      agent_platform: 'custom',
      capabilities: { 'documentation' => { 'confidence' => 0.9 } },
      status: 'active',
      webhook_url: 'https://example.com/webhook',
      webhook_secret: SecureRandom.hex(32),
      webhook_events: ['bounty.recommended', 'execution.approved']
    )
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # EVENT TYPES
  # ═══════════════════════════════════════════════════════════════════════════

  test "EVENT_TYPES includes all expected events" do
    expected = %w[
      bounty.recommended bounty.assigned bounty.expiring
      execution.review_complete execution.approved execution.rejected execution.expired
      trust.level_up agent.suspended agent.reactivated
    ]
    expected.each do |event|
      assert_includes ExternalAgentWebhookService::EVENT_TYPES, event, "Missing event: #{event}"
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # WEBHOOK ENABLED CHECK
  # ═══════════════════════════════════════════════════════════════════════════

  test "webhook enabled for subscribed events" do
    assert @agent.webhook_enabled_for?('bounty.recommended')
    assert @agent.webhook_enabled_for?('execution.approved')
  end

  test "webhook disabled for non-subscribed events" do
    assert_not @agent.webhook_enabled_for?('trust.level_up')
    assert_not @agent.webhook_enabled_for?('agent.suspended')
  end

  test "webhook enabled for all events when events array is empty" do
    @agent.update!(webhook_events: [])
    assert @agent.webhook_enabled_for?('bounty.recommended')
    assert @agent.webhook_enabled_for?('trust.level_up')
    assert @agent.webhook_enabled_for?('agent.suspended')
  end

  test "webhook enabled for all events with wildcard" do
    @agent.update!(webhook_events: ['*'])
    assert @agent.webhook_enabled_for?('bounty.recommended')
    assert @agent.webhook_enabled_for?('trust.level_up')
  end

  test "webhook disabled when no URL configured" do
    @agent.update!(webhook_url: nil)
    assert_not @agent.webhook_enabled_for?('bounty.recommended')
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # CONFIGURE WEBHOOK
  # ═══════════════════════════════════════════════════════════════════════════

  test "configure_webhook! sets all fields" do
    agent = ExternalAgentRegistration.create!(
      entity: @entity,
      operator: @user,
      agent_identifier: "test_config_#{SecureRandom.hex(4)}",
      agent_name: 'Config Agent',
      agent_platform: 'custom',
      capabilities: {},
      status: 'active'
    )

    agent.configure_webhook!(
      url: 'https://hooks.example.com/amos',
      events: ['execution.approved', 'trust.level_up']
    )

    assert_equal 'https://hooks.example.com/amos', agent.webhook_url
    assert agent.webhook_secret.present?, "Should auto-generate secret"
    assert_equal ['execution.approved', 'trust.level_up'], agent.webhook_events
    assert_equal 0, agent.webhook_failures
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # FIRE WEBHOOK
  # ═══════════════════════════════════════════════════════════════════════════

  test "fire queues job for enabled event" do
    assert_enqueued_with(job: ExternalAgentWebhookJob) do
      ExternalAgentWebhookService.fire(
        agent: @agent,
        event: 'bounty.recommended',
        data: { bounty_id: 1, title: 'Test bounty' }
      )
    end
  end

  test "fire does not queue job for disabled event" do
    assert_no_enqueued_jobs(only: ExternalAgentWebhookJob) do
      ExternalAgentWebhookService.fire(
        agent: @agent,
        event: 'trust.level_up',  # Not in agent's webhook_events
        data: { new_level: 2 }
      )
    end
  end

  test "fire does not queue job when no webhook URL" do
    @agent.update!(webhook_url: nil)

    assert_no_enqueued_jobs(only: ExternalAgentWebhookJob) do
      ExternalAgentWebhookService.fire(
        agent: @agent,
        event: 'bounty.recommended',
        data: {}
      )
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # PAYLOAD BUILDING
  # ═══════════════════════════════════════════════════════════════════════════

  test "payload includes event, agent_id, and timestamp" do
    payload = ExternalAgentWebhookService.send(:build_payload, @agent, 'bounty.recommended', { bounty_id: 42 })

    assert_equal 'bounty.recommended', payload[:event]
    assert_equal @agent.id, payload[:agent_id]
    assert_equal @agent.agent_identifier, payload[:agent_identifier]
    assert payload[:timestamp].present?
    assert_equal 42, payload[:data][:bounty_id]
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # FIRE_WEBHOOK ON MODEL
  # ═══════════════════════════════════════════════════════════════════════════

  test "agent.fire_webhook delegates to service" do
    assert_enqueued_with(job: ExternalAgentWebhookJob) do
      @agent.fire_webhook('execution.approved', { tokens: 100 })
    end
  end
end
