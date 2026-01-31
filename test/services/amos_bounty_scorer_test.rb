# frozen_string_literal: true

require 'test_helper'

class AmosBountyScorerTest < ActiveSupport::TestCase
  # === FALLBACK SCORING ===

  test "returns fallback score for bug" do
    # Mock LLM failure
    AmosBountyScorer.stub(:call_llm, ->(_) { raise "LLM unavailable" }) do
      result = AmosBountyScorer.score(
        title: 'Fix login bug',
        description: 'Login broken',
        bounty_type: 'bug'
      )

      assert_equal 100, result[:points]
      assert_equal 5, result[:effort_score]
      assert result[:rationale].include?('Fallback')
    end
  end

  test "returns different fallback scores by type" do
    AmosBountyScorer.stub(:call_llm, ->(_) { raise "LLM unavailable" }) do
      bug_score = AmosBountyScorer.score(title: 'Bug', description: 'x', bounty_type: 'bug')
      feature_score = AmosBountyScorer.score(title: 'Feature', description: 'x', bounty_type: 'feature')
      doc_score = AmosBountyScorer.score(title: 'Doc', description: 'x', bounty_type: 'documentation')

      assert_equal 100, bug_score[:points]
      assert_equal 200, feature_score[:points]
      assert_equal 50, doc_score[:points]
    end
  end

  test "clamps points to valid range" do
    # Simulate LLM returning extreme values
    extreme_response = {
      'points' => 50000,
      'effort_score' => 15,
      'impact_score' => -5,
      'urgency_score' => 7,
      'complexity_score' => 8,
      'estimated_hours' => 10,
      'rationale' => 'Test'
    }.to_json

    AmosBountyScorer.stub(:call_llm, ->(_) { extreme_response }) do
      result = AmosBountyScorer.score(
        title: 'Test',
        description: 'Test',
        bounty_type: 'feature'
      )

      assert_equal 2000, result[:points]  # Clamped to max
      assert_equal 10, result[:effort_score]  # Clamped to 10
      assert_equal 1, result[:impact_score]  # Clamped to 1
    end
  end

  # === SCORING INTEGRATION ===

  test "score includes all expected fields" do
    mock_response = {
      'points' => 150,
      'effort_score' => 6,
      'impact_score' => 7,
      'urgency_score' => 5,
      'complexity_score' => 6,
      'strategic_score' => 4,
      'estimated_hours' => 4.5,
      'rationale' => 'Medium complexity feature'
    }.to_json

    AmosBountyScorer.stub(:call_llm, ->(_) { mock_response }) do
      result = AmosBountyScorer.score(
        title: 'Add feature',
        description: 'New feature',
        bounty_type: 'feature'
      )

      assert_equal 150, result[:points]
      assert_equal 6, result[:effort_score]
      assert_equal 7, result[:impact_score]
      assert_equal 5, result[:urgency_score]
      assert_equal 6, result[:complexity_score]
      assert_equal 4, result[:strategic_score]
      assert_equal 4.5, result[:estimated_hours]
      assert_equal 'Medium complexity feature', result[:rationale]
    end
  end

  # === TICKET SCORING ===

  test "score_ticket maps category to bounty type" do
    entity = entities(:one)

    ticket = SupportTicket.create!(
      entity: entity,
      title: 'Performance issue',
      description: 'Slow loading',
      source: 'log_monitor',
      priority: 'high',
      category: 'performance'
    )

    AmosBountyScorer.stub(:call_llm, ->(_) { raise "use fallback" }) do
      result = AmosBountyScorer.score_ticket(ticket)

      # Performance maps to 'bug' type
      assert_equal 100, result[:points]  # Bug fallback
    end
  end

  test "score_ticket includes ticket context" do
    entity = entities(:one)

    ticket = SupportTicket.create!(
      entity: entity,
      title: 'Security vulnerability',
      description: 'SQL injection found',
      source: 'user_reported',
      priority: 'critical',
      category: 'security',
      error_class: 'SQLInjection'
    )

    prompt_received = nil

    AmosBountyScorer.stub(:call_llm, ->(prompt) {
      prompt_received = prompt
      raise "check prompt"
    }) do
      AmosBountyScorer.score_ticket(ticket)
    end

    # Prompt should include ticket context
    assert prompt_received.include?('critical')
    assert prompt_received.include?('security')
  end

  # === JSON PARSING ===

  test "handles JSON wrapped in markdown code blocks" do
    markdown_response = <<~RESPONSE
      ```json
      {
        "points": 200,
        "effort_score": 5,
        "impact_score": 6,
        "urgency_score": 4,
        "complexity_score": 5,
        "estimated_hours": 3,
        "rationale": "Test"
      }
      ```
    RESPONSE

    AmosBountyScorer.stub(:call_llm, ->(_) { markdown_response }) do
      result = AmosBountyScorer.score(
        title: 'Test',
        description: 'Test',
        bounty_type: 'feature'
      )

      assert_equal 200, result[:points]
    end
  end

  test "handles invalid JSON gracefully" do
    AmosBountyScorer.stub(:call_llm, ->(_) { "not valid json at all" }) do
      result = AmosBountyScorer.score(
        title: 'Test',
        description: 'Test',
        bounty_type: 'bug'
      )

      # Should return fallback
      assert_equal 100, result[:points]
      assert result[:rationale].include?('Fallback')
    end
  end
end
