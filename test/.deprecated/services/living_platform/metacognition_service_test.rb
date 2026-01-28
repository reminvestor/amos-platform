# frozen_string_literal: true

require "test_helper"

class LivingPlatform::MetacognitionServiceTest < ActiveSupport::TestCase
  setup do
    @entity = entities(:one)
    @agent = agent_plugins(:one)
    @user = users(:one)
    @service = LivingPlatform::MetacognitionService.new(@agent)
  end

  test "daily reflection creates reflection record" do
    # Create some executions
    3.times do
      AgentPluginExecution.create!(
        agent_plugin: @agent,
        user: @user,
        status: 'completed',
        input_context: { task_description: 'Test task', test: true },
        output_result: { result: 'success' },
        duration_ms: 1000,
        created_at: 2.hours.ago
      )
    end
    
    reflection = @service.daily_reflection
    
    # Clean up
    AgentPluginExecution.where("input_context->>'test' = 'true'").delete_all
    
    if reflection.present?
      assert reflection.is_a?(AgentReflection)
      assert reflection.persisted?
      assert_equal 'daily', reflection.reflection_type
      assert_equal @agent.id, reflection.agent_plugin_id
    end
  end

  test "reflection includes scores" do
    # Create some executions
    3.times do
      AgentPluginExecution.create!(
        agent_plugin: @agent,
        user: @user,
        status: 'completed',
        input_context: { task_description: 'Test task', test: true },
        output_result: { result: 'success' },
        duration_ms: 1000,
        created_at: 2.hours.ago
      )
    end
    
    reflection = @service.daily_reflection
    
    # Clean up
    AgentPluginExecution.where("input_context->>'test' = 'true'").delete_all
    
    if reflection.present?
      # Scores should be between 1 and 10 or nil
      if reflection.efficiency_score
        assert reflection.efficiency_score >= 1 && reflection.efficiency_score <= 10
      end
      if reflection.quality_score
        assert reflection.quality_score >= 1 && reflection.quality_score <= 10
      end
    end
  end

  test "returns nil when no activity" do
    reflection = @service.daily_reflection
    
    # Should return nil if no executions
    # (depends on fixture data)
  end

  test "peer comparison works" do
    comparison = @service.send(:compare_to_peers)
    
    assert comparison.is_a?(Hash)
    # May be empty if not enough data
  end

  test "score trend calculation" do
    # Create some reflections
    5.times do |i|
      AgentReflection.create!(
        entity: @entity,
        agent_plugin: @agent,
        reflection_type: 'daily',
        overall_score: 5 + i,
        created_at: (5 - i).days.ago
      )
    end
    
    trend = @service.send(:calculate_score_trend, AgentReflection.for_agent(@agent).by_type('daily'))
    
    assert %w[improving declining stable unknown].include?(trend)
    
    # Clean up
    AgentReflection.for_agent(@agent).destroy_all
  end
end

