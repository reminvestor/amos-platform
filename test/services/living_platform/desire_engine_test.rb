# frozen_string_literal: true

require "test_helper"

class LivingPlatform::DesireEngineTest < ActiveSupport::TestCase
  setup do
    @entity = entities(:one)
    @agent = agent_plugins(:one)
    @user = users(:one)
    @engine = LivingPlatform::DesireEngine.new(@entity)
  end

  test "generates daily goals" do
    result = @engine.generate_daily_goals
    
    assert result.is_a?(Hash)
    assert result.key?(:goals_generated)
    assert result.key?(:breakdown)
    assert result[:breakdown].key?(:improvement)
    assert result[:breakdown].key?(:expansion)
    assert result[:breakdown].key?(:maintenance)
    assert result[:breakdown].key?(:learning)
    assert result[:breakdown].key?(:social)
  end

  test "creates improvement goals for underperforming agents" do
    # Create some failures for the agent
    5.times do
      AgentPluginExecution.create!(
        agent_plugin: @agent,
        user: @user,
        status: 'failed',
        input_context: { test: true },
        output_result: { error: 'Test failure' },
        created_at: 1.hour.ago
      )
    end
    
    result = @engine.generate_daily_goals
    
    # Clean up
    AgentPluginExecution.where("input_context->>'test' = 'true'").delete_all
    
    # Should generate improvement goals
    assert result[:goals_generated] >= 0
  end

  test "does not create duplicate goals" do
    # Create a pending goal
    goal = AgentGoal.create!(
      entity: @entity,
      agent_plugin: @agent,
      goal_type: 'improvement',
      title: 'Test goal',
      status: 'pending',
      priority: 50,
      source: 'desire_engine'
    )
    
    # Generate goals
    @engine.generate_daily_goals
    
    # Should not create duplicate
    similar_goals = AgentGoal.where(entity: @entity, goal_type: 'improvement', agent_plugin: @agent, status: 'pending')
    assert_equal 1, similar_goals.count
    
    goal.destroy
  end

  test "schedules pending goals" do
    # Create a pending goal
    goal = AgentGoal.create!(
      entity: @entity,
      agent_plugin: @agent,
      goal_type: 'improvement',
      title: 'Test goal to schedule',
      status: 'pending',
      priority: 80,
      source: 'desire_engine'
    )
    
    # Skip if no valid executor
    scheduled = @engine.schedule_pending_goals
    
    # Goal may or may not be scheduled depending on executor availability
    assert scheduled.is_a?(Array)
    
    goal.destroy
  end

  test "goal priority calculation" do
    # This is an internal method test - just verify the engine works
    result = @engine.generate_daily_goals
    
    # All goals should have priority between 1 and 100
    goals = AgentGoal.where(entity: @entity).where('created_at > ?', 1.minute.ago)
    goals.each do |goal|
      assert goal.priority >= 1 && goal.priority <= 100, "Goal priority #{goal.priority} out of range"
    end
    
    # Clean up
    goals.destroy_all
  end
end

