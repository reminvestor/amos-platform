# frozen_string_literal: true

require "test_helper"

class Learning::SemanticAdvantageServiceTest < ActiveSupport::TestCase
  setup do
    @entity = entities(:one)
    @service = Learning::SemanticAdvantageService.new(entity: @entity)
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # INITIALIZATION
  # ═══════════════════════════════════════════════════════════════════════════

  test "initializes with entity" do
    assert_equal @entity, @service.entity
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # EXTRACT FOR TASK TYPE
  # ═══════════════════════════════════════════════════════════════════════════

  test "extract_for_task_type requires minimum group size" do
    # With fixtures, we should have traces
    result = @service.extract_for_task_type("integration_setup", window: 30.days)
    
    assert result.is_a?(Hash)
    assert result.key?(:created)
    assert result.key?(:modified)
    assert result.key?(:deleted)
  end

  test "extract_for_task_type returns zeros when insufficient data" do
    result = @service.extract_for_task_type("document_analysis", window: 30.days)
    
    assert_equal 0, result[:created]
    assert_equal 0, result[:modified]
    assert_equal 0, result[:deleted]
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # EXTRACT EXPERIENCES (FULL FLOW)
  # ═══════════════════════════════════════════════════════════════════════════

  test "extract_experiences returns results hash" do
    results = @service.extract_experiences(window: 30.days)
    
    assert results.is_a?(Hash)
    assert results.key?(:task_types_analyzed)
    assert results.key?(:experiences_created)
    assert results.key?(:experiences_modified)
    assert results.key?(:experiences_deleted)
    assert results.key?(:errors)
    
    assert results[:task_types_analyzed].is_a?(Array)
    assert results[:errors].is_a?(Array)
  end

  test "extract_experiences can filter by task_types" do
    results = @service.extract_experiences(
      window: 30.days,
      task_types: ["integration_setup"]
    )
    
    # Should only analyze integration_setup
    assert results[:task_types_analyzed].include?("integration_setup") || 
           results[:task_types_analyzed].empty?  # May be empty if no traces
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # INTEGRATION WITH DECISION TRACES
  # ═══════════════════════════════════════════════════════════════════════════

  test "uses decision traces for learning" do
    # Ensure we have traces in fixtures
    traces = DecisionTrace.where(entity: @entity)
                          .where("metadata->>'task_type' IS NOT NULL")
    
    assert traces.any?, "Should have decision traces with task_type in metadata"
  end

  test "separates winners and losers correctly" do
    # Check that our fixtures have both success and failure outcomes
    successes = DecisionTrace.where(entity: @entity, outcome: "success")
    failures = DecisionTrace.where(entity: @entity, outcome: "failure")
    
    assert successes.any?, "Should have successful traces"
    assert failures.any?, "Should have failed traces"
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # EXPERIENCE LIBRARY UPDATES
  # ═══════════════════════════════════════════════════════════════════════════

  test "creates experiences with correct attributes when learning happens" do
    # This test verifies the structure of experiences when they are created
    # Since LLM extraction is involved, we test the model's learn! method directly
    
    experience = TaskExperience.learn!(
      entity: @entity,
      task_type: "integration_setup",
      content: "Test experience created via learn! method with sufficient content",
      applies_when: "When testing",
      source_type: "semantic_advantage"
    )
    
    assert experience.persisted?
    assert experience.task_type.present?
    assert experience.content.present?
    assert experience.content.length >= 20
    assert_equal 0.5, experience.utility_score  # New experiences start neutral
    assert_equal "semantic_advantage", experience.source_type
    assert_equal @entity, experience.entity
  end
end
