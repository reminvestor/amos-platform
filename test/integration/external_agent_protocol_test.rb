# frozen_string_literal: true

require 'test_helper'

# End-to-end integration test for the External Agent Protocol (EAP)
#
# Tests the full lifecycle:
#   Register → Discover Bounties → Claim → Execute Tools → Submit → Review → Approve
#
class ExternalAgentProtocolTest < ActionDispatch::IntegrationTest
  setup do
    @entity = entities(:one)
    @user = users(:one)
    @user.update!(entity: @entity) if @user.respond_to?(:entity=)

    # Create operator API key for registration
    @operator_api_key = @user.api_keys.create!(
      key: "test_op_key_#{SecureRandom.hex(8)}",
      entity: @entity,
      active: true
    ) if @user.respond_to?(:api_keys) && defined?(ApiKey)

    # Create a bounty for the agent to work on
    @bounty = Bounty.create!(
      entity: @entity,
      title: "Write getting started guide for EAP API",
      description: "Create a beginner-friendly guide for external agents to get started with the EAP API.",
      bounty_type: 'documentation',
      points: 100,
      status: 'open',
      urgency_score: 7,
      impact_score: 8,
      source: 'admin_created',
      estimated_hours: 2
    )
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # REGISTRATION
  # ═══════════════════════════════════════════════════════════════════════════

  test "registers a new external agent" do
    agent = register_test_agent
    assert agent.present?, "Agent should be created"
    assert_equal 'active', agent.status
    assert_equal 1, agent.trust_level
    assert_includes agent.allowed_bounty_types, 'documentation'
    assert agent.api_key.starts_with?('ext_')
  end

  test "prevents duplicate agent registration" do
    agent = register_test_agent

    # Try registering same identifier again
    duplicate = ExternalAgentService.new(user: @user, entity: @entity).register_agent(
      agent_identifier: 'test_agent_001',
      agent_name: 'Duplicate Agent',
      agent_platform: 'custom',
      capabilities: { 'documentation' => { 'confidence' => 0.9 } }
    )

    assert_equal false, duplicate[:success]
    assert_match(/already registered/, duplicate[:error])
  end

  test "limits operator to 5 active agents" do
    5.times do |i|
      register_test_agent(identifier: "agent_#{i}")
    end

    # 6th should fail
    result = ExternalAgentService.new(user: @user, entity: @entity).register_agent(
      agent_identifier: 'agent_overflow',
      agent_name: 'Overflow Agent',
      agent_platform: 'custom',
      capabilities: { 'documentation' => { 'confidence' => 0.8 } }
    )

    assert_equal false, result[:success]
    assert_match(/maximum/, result[:error])
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # BOUNTY DISCOVERY
  # ═══════════════════════════════════════════════════════════════════════════

  test "discovers bounties matching agent capabilities" do
    agent = register_test_agent
    service = ExternalAgentService.new(agent: agent)

    result = service.discover_bounties
    assert result[:success]
    assert result[:bounties].is_a?(Array)
    assert result[:meta][:your_daily_remaining] > 0
  end

  test "filters bounties by agent trust level" do
    agent = register_test_agent

    # Create a high-point bounty (beyond trust level 1 limit)
    high_bounty = Bounty.create!(
      entity: @entity,
      title: "Major feature implementation",
      bounty_type: 'feature',
      points: 500,
      status: 'open',
      urgency_score: 5,
      impact_score: 9,
      source: 'admin_created'
    )

    service = ExternalAgentService.new(agent: agent)
    result = service.discover_bounties

    # Trust level 1 can only see documentation/content and max 100 points
    bounty_ids = result[:bounties].map { |b| b[:id] }
    assert_not_includes bounty_ids, high_bounty.id, "High-point bounty should be filtered out"
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # BOUNTY CLAIMING
  # ═══════════════════════════════════════════════════════════════════════════

  test "claims a bounty successfully" do
    agent = register_test_agent
    service = ExternalAgentService.new(agent: agent)

    result = service.claim_bounty(
      bounty: @bounty,
      approach: "I will research the API and write a comprehensive guide",
      estimated_completion: "2h"
    )

    assert result[:success], "Should claim bounty: #{result[:error]}"
    assert_equal 'in_progress', result[:execution].status
    assert result[:execution].expires_at > Time.current
  end

  test "prevents claiming beyond daily limit" do
    agent = register_test_agent
    service = ExternalAgentService.new(agent: agent)

    # Claim up to daily limit
    agent.daily_bounty_limit.times do |i|
      bounty = Bounty.create!(
        entity: @entity,
        title: "Bounty #{i}",
        bounty_type: 'documentation',
        points: 50,
        status: 'open',
        urgency_score: 5,
        impact_score: 5,
        source: 'admin_created'
      )
      service.claim_bounty(bounty: bounty)
    end

    # Next claim should fail
    extra_bounty = Bounty.create!(
      entity: @entity,
      title: "Extra bounty",
      bounty_type: 'documentation',
      points: 50,
      status: 'open',
      urgency_score: 5,
      impact_score: 5,
      source: 'admin_created'
    )
    result = service.claim_bounty(bounty: extra_bounty)
    assert_equal false, result[:success]
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # TOOL EXECUTION
  # ═══════════════════════════════════════════════════════════════════════════

  test "executes allowed tools during bounty work" do
    agent = register_test_agent
    service = ExternalAgentService.new(agent: agent)

    claim_result = service.claim_bounty(bounty: @bounty)
    execution = claim_result[:execution]

    # Execute a read-only tool (allowed at trust level 1)
    result = service.execute_tool(
      execution: execution,
      tool_name: 'web_search',
      args: { query: 'amos api documentation' }
    )

    # Should succeed (tool execution may fail if external API not available, but should not error)
    assert result.key?(:success)
    assert_equal 1, execution.reload.tool_calls_count
  end

  test "blocks dangerous tools for external agents" do
    agent = register_test_agent
    service = ExternalAgentService.new(agent: agent)

    claim_result = service.claim_bounty(bounty: @bounty)
    execution = claim_result[:execution]

    result = service.execute_tool(
      execution: execution,
      tool_name: 'send_email',
      args: { to: 'test@test.com', subject: 'test' }
    )

    assert_equal false, result[:success]
    assert_match(/not available|blocked|policy/i, result[:error])
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # WORK SUBMISSION
  # ═══════════════════════════════════════════════════════════════════════════

  test "submits completed work" do
    agent = register_test_agent
    service = ExternalAgentService.new(agent: agent)

    claim_result = service.claim_bounty(bounty: @bounty)
    execution = claim_result[:execution]

    result = service.submit_work(
      execution: execution,
      work_summary: "Created comprehensive getting started guide with 5 sections",
      deliverables: {
        content: "# Getting Started with EAP\n\nThis guide covers...",
        format: 'markdown'
      },
      work_log: "1. Researched API docs\n2. Wrote guide\n3. Added examples"
    )

    assert result[:success], "Should submit work: #{result[:error]}"
    assert_equal 'submitted', execution.reload.status
  end

  test "prevents submission after expiration" do
    agent = register_test_agent
    service = ExternalAgentService.new(agent: agent)

    claim_result = service.claim_bounty(bounty: @bounty)
    execution = claim_result[:execution]

    # Force expiration
    execution.update!(expires_at: 1.hour.ago)

    result = service.submit_work(
      execution: execution,
      work_summary: "Late submission",
      deliverables: { content: "test" }
    )

    assert_equal false, result[:success]
    assert_match(/expired/i, result[:error])
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # TRUST PROGRESSION
  # ═══════════════════════════════════════════════════════════════════════════

  test "upgrades trust level after sufficient completions" do
    agent = register_test_agent
    assert_equal 1, agent.trust_level

    # Simulate 3 completions with good reputation
    agent.update!(
      total_bounties_completed: 3,
      total_bounties_rejected: 0,
      reputation_score: 60.0
    )
    agent.check_trust_level_upgrade!

    assert_equal 2, agent.reload.trust_level
    assert_includes agent.allowed_bounty_types, 'support'
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # WEBHOOKS
  # ═══════════════════════════════════════════════════════════════════════════

  test "configures webhook for agent" do
    agent = register_test_agent
    agent.configure_webhook!(
      url: 'https://example.com/webhook',
      events: ['bounty.recommended', 'execution.approved']
    )

    assert_equal 'https://example.com/webhook', agent.webhook_url
    assert agent.webhook_secret.present?
    assert agent.webhook_enabled_for?('bounty.recommended')
    assert agent.webhook_enabled_for?('execution.approved')
    assert_not agent.webhook_enabled_for?('trust.level_up')
  end

  test "webhook enabled for all events when events array is empty" do
    agent = register_test_agent
    agent.configure_webhook!(url: 'https://example.com/webhook', events: [])

    assert agent.webhook_enabled_for?('bounty.recommended')
    assert agent.webhook_enabled_for?('execution.approved')
    assert agent.webhook_enabled_for?('trust.level_up')
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # MATCHING SERVICE
  # ═══════════════════════════════════════════════════════════════════════════

  test "matches bounties to best-suited agents" do
    agent = register_test_agent
    matching = ExternalAgentMatchingService.new(@entity)

    matches = matching.find_agents_for_bounty(@bounty)
    assert matches.is_a?(Array)

    if matches.any?
      match = matches.first
      assert match[:score] > 0
      assert match[:agent][:id] == agent.id
    end
  end

  test "provides AMOS context with agent summary" do
    register_test_agent
    matching = ExternalAgentMatchingService.new(@entity)

    context = matching.context_for_amos
    assert context[:external_agents_available]
    assert_equal 1, context[:total_agents]
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # FULL LIFECYCLE
  # ═══════════════════════════════════════════════════════════════════════════

  test "full EAP lifecycle: register → discover → claim → submit → review" do
    # 1. Register
    agent = register_test_agent
    assert_equal 'active', agent.status

    # 2. Discover bounties
    service = ExternalAgentService.new(agent: agent)
    bounties = service.discover_bounties
    assert bounties[:success]
    assert bounties[:bounties].any?, "Should find at least one bounty"

    # 3. Claim bounty
    claim = service.claim_bounty(bounty: @bounty, approach: "Will write docs")
    assert claim[:success]
    execution = claim[:execution]

    # 4. Submit work
    submit = service.submit_work(
      execution: execution,
      work_summary: "Comprehensive EAP guide created",
      deliverables: { content: "# EAP Guide\n\n## Setup\n\n..." }
    )
    assert submit[:success]
    assert_equal 'submitted', execution.reload.status

    # 5. Verify the bounty is in reviewing state
    assert_equal 'submitted', @bounty.reload.status
  end

  private

  def register_test_agent(identifier: 'test_agent_001', name: 'Test Agent')
    service = ExternalAgentService.new(user: @user, entity: @entity)
    result = service.register_agent(
      agent_identifier: identifier,
      agent_name: name,
      agent_platform: 'custom',
      capabilities: {
        'documentation' => { 'description' => 'Can write docs', 'confidence' => 0.9 },
        'content' => { 'description' => 'Can write content', 'confidence' => 0.85 }
      }
    )

    if result[:success]
      result[:agent]
    else
      raise "Failed to register agent: #{result[:error]}"
    end
  end
end
