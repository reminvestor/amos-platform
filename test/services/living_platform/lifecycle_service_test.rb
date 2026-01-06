# frozen_string_literal: true

require "test_helper"

class LivingPlatform::LifecycleServiceTest < ActiveSupport::TestCase
  setup do
    @entity = entities(:one)
    @agent = agent_plugins(:one)
    @service = LivingPlatform::LifecycleService.new(@entity)
  end

  test "evaluate_for_retirement returns evaluation hash" do
    evaluation = @service.evaluate_for_retirement(@agent)
    
    assert evaluation.is_a?(Hash)
    assert evaluation.key?(:agent)
    assert evaluation.key?(:should_retire)
    assert evaluation.key?(:reasons)
    assert evaluation.key?(:metrics)
  end

  test "evaluate_all_agents returns array" do
    evaluations = @service.evaluate_all_agents
    
    assert evaluations.is_a?(Array)
  end

  test "agent design from need" do
    need = {
      description: 'Test agent for data analysis',
      request_count: 10,
      sample_requests: ['Analyze my data']
    }
    
    design = @service.send(:design_agent_from_need, need, [])
    
    assert design.is_a?(Hash)
    assert design[:name].present?
    assert design[:system_prompt].present?
    assert design[:tools].is_a?(Array)
  end

  test "generation calculation with no parents" do
    generation = @service.send(:calculate_generation, [])
    assert_equal 1, generation
  end

  test "generation calculation with parents" do
    parent1 = @agent.dup
    parent1.generation = 2
    parent2 = @agent.dup
    parent2.generation = 3
    
    generation = @service.send(:calculate_generation, [parent1, parent2])
    assert_equal 4, generation  # Max parent generation + 1
  end

  test "retirement metrics gathering" do
    metrics = @service.send(:gather_retirement_metrics, @agent)
    
    assert metrics.is_a?(Hash)
    assert metrics.key?(:total_executions)
    assert metrics.key?(:success_rate)
    assert metrics.key?(:days_inactive)
    assert metrics.key?(:generation)
  end

  test "stale agent detection" do
    # Agent with no recent activity should be detected
    metrics = @service.send(:gather_retirement_metrics, @agent)
    
    # Days inactive should be a number
    assert metrics[:days_inactive].is_a?(Integer)
  end
end


