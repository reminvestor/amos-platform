# frozen_string_literal: true

require 'test_helper'

class AmosThinkingServiceTest < ActiveSupport::TestCase
  setup do
    @entity = entities(:one)
    @service = AmosThinkingService.new(@entity)
  end

  # === CONTEXT GATHERING ===

  test "gather_context returns platform state" do
    # Create some data
    SupportTicket.create!(
      entity: @entity,
      title: 'Test ticket',
      description: 'Test',
      source: 'log_monitor',
      priority: 'medium',
      category: 'bug'
    )

    context = @service.gather_context

    assert context[:open_tickets] >= 0
    assert context[:critical_tickets].is_a?(Array)
    assert context[:feature_requests].is_a?(Array)
    assert context[:metrics].is_a?(Hash)
    assert context[:summary].present?
  end

  test "context summary includes key metrics" do
    context = @service.gather_context

    assert context[:summary].include?('PLATFORM STATE')
    assert context[:summary].include?('ISSUES')
    assert context[:summary].include?('ACTIVITY')
    assert context[:summary].include?('METRICS')
  end

  # === THINKING SESSION ===

  test "think! creates session and bounties" do
    # Mock the LLM to return a reflection
    mock_reflection = {
      reflection_summary: 'Platform is healthy but needs dark mode',
      observations: ['Good uptime', 'User requests for dark mode'],
      priorities: ['Dark mode feature'],
      bounty_ideas: [
        {
          title: 'Add dark mode',
          description: 'Implement dark theme for UI',
          type: 'feature',
          rationale: 'Highly requested feature'
        }
      ]
    }.to_json

    AmosBountyScorer.stub(:score, ->(**_args) {
      { points: 200, rationale: 'Test', effort_score: 5, impact_score: 7, urgency_score: 4, complexity_score: 5, estimated_hours: 8 }
    }) do
      @service.stub(:call_llm, ->(_) { mock_reflection }) do
        # Also stub integration service
        BountyIntegrationService.any_instance.stub(:sync_all!, ->() { { from_tickets: [], from_goals: [], from_anomalies: [], from_features: [] } }) do
          result = @service.think!

          assert result[:session].completed?
          assert result[:bounties].any?
          assert_equal 'Add dark mode', result[:bounties].first.title
          assert_equal 'feature', result[:bounties].first.bounty_type
        end
      end
    end
  end

  test "think! handles LLM failure gracefully" do
    @service.stub(:call_llm, ->(_) { raise "LLM unavailable" }) do
      BountyIntegrationService.any_instance.stub(:sync_all!, ->() { { from_tickets: [], from_goals: [], from_anomalies: [], from_features: [] } }) do
        assert_raises(RuntimeError) do
          @service.think!
        end

        # Session should be marked as failed
        session = AmosThinkingSession.last
        assert_equal 'failed', session.status
        assert session.thinking_log.include?('LLM unavailable')
      end
    end
  end

  test "think! records session duration" do
    mock_reflection = {
      reflection_summary: 'All good',
      observations: [],
      priorities: [],
      bounty_ideas: []
    }.to_json

    @service.stub(:call_llm, ->(_) { mock_reflection }) do
      BountyIntegrationService.any_instance.stub(:sync_all!, ->() { { from_tickets: [], from_goals: [], from_anomalies: [], from_features: [] } }) do
        result = @service.think!

        session = result[:session]
        assert session.duration_seconds >= 0
        assert session.completed_at > session.started_at
      end
    end
  end

  # === BOUNTY TYPE NORMALIZATION ===

  test "normalizes common bounty type variations" do
    variations = {
      'code' => 'feature',
      'coding' => 'feature',
      'docs' => 'documentation',
      'doc' => 'documentation',
      'blog' => 'content',
      'article' => 'content',
      'ads' => 'marketing',
      'help' => 'support',
      'community' => 'support',
      'ui' => 'design',
      'ux' => 'design',
      'test' => 'testing',
      'qa' => 'testing',
      'devops' => 'infrastructure',
      'infra' => 'infrastructure'
    }

    variations.each do |input, expected|
      result = @service.send(:normalize_bounty_type, input)
      assert_equal expected, result, "#{input} should normalize to #{expected}"
    end
  end

  test "preserves valid bounty types" do
    Bounty::BOUNTY_TYPES.each do |type|
      result = @service.send(:normalize_bounty_type, type)
      assert_equal type, result
    end
  end

  # === INTEGRATION WITH SYSTEMS ===

  test "sync_existing_systems_to_bounties calls integration service" do
    integration_called = false

    BountyIntegrationService.any_instance.stub(:sync_all!, -> {
      integration_called = true
      { from_tickets: [], from_goals: [], from_anomalies: [], from_features: [] }
    }) do
      @service.send(:sync_existing_systems_to_bounties)
      assert integration_called
    end
  end
end
