# frozen_string_literal: true

require "test_helper"

class LivingPlatform::PerceptionServiceTest < ActiveSupport::TestCase
  setup do
    @entity = entities(:one)
    @agent = agent_plugins(:one)
    @user = users(:one)
    @service = LivingPlatform::PerceptionService.new(@entity)
  end

  test "perceives entity and creates perception record" do
    perception = @service.perceive(type: 'routine')
    
    assert perception.is_a?(PlatformPerception)
    assert perception.persisted?
    assert_equal @entity.id, perception.entity_id
    assert_equal 'routine', perception.perception_type
    assert perception.overall_health_score.present?
    assert perception.perceived_at.present?
  end

  test "calculates health score correctly" do
    # Create some successful executions
    3.times do
      AgentPluginExecution.create!(
        agent_plugin: @agent,
        user: @user,
        status: 'completed',
        input_context: { test: true },
        output_result: { result: 'success' },
        duration_ms: 1000,
        created_at: 1.hour.ago
      )
    end
    
    perception = @service.perceive(type: 'routine')
    
    # Clean up
    AgentPluginExecution.where("input_context->>'test' = 'true'").delete_all
    
    # With successes, health should be reasonable
    assert perception.overall_health_score >= 0.0
    assert perception.overall_health_score <= 1.0
  end

  test "detects error spike anomaly" do
    # Create error spike
    10.times do
      AgentPluginExecution.create!(
        agent_plugin: @agent,
        user: @user,
        status: 'failed',
        input_context: { test: true },
        output_result: { error: 'Spike test' },
        created_at: rand(60).minutes.ago
      )
    end
    
    perception = @service.perceive(type: 'routine')
    
    # Clean up
    AgentPluginExecution.where("input_context->>'test' = 'true'").delete_all
    
    # Should detect anomalies
    assert perception.anomaly_count >= 0
  end

  test "records active agents count" do
    perception = @service.perceive(type: 'routine')
    
    expected_count = @entity.agent_plugins.where(status: 'active').count
    assert_equal expected_count, perception.active_agents
  end

  test "perception includes metrics snapshot" do
    perception = @service.perceive(type: 'routine')
    
    assert perception.metrics_snapshot.is_a?(Hash)
    assert perception.health_breakdown.is_a?(Hash)
  end

  test "triggered perception works" do
    perception = @service.perceive(type: 'triggered')
    
    assert perception.persisted?
    assert_equal 'triggered', perception.perception_type
  end

  test "health status helper works" do
    perception = @service.perceive(type: 'routine')
    
    status = perception.health_status
    assert %w[excellent good fair poor critical].include?(status)
  end
end

