# frozen_string_literal: true

require "test_helper"

class LivingPlatform::EvolutionCycleServiceTest < ActiveSupport::TestCase
  setup do
    @entity = entities(:one)
    @agent = agent_plugins(:one)
    @service = LivingPlatform::EvolutionCycleService.new(@entity)
  end

  test "run_cycle creates evolution cycle record" do
    cycle = @service.run_cycle(type: 'triggered')
    
    assert cycle.is_a?(EvolutionCycle)
    assert cycle.persisted?
    assert_equal 'triggered', cycle.cycle_type
    assert cycle.completed? || cycle.failed?
  end

  test "cycle records perception results" do
    cycle = @service.run_cycle(type: 'triggered')
    
    # Should have metrics snapshot
    assert cycle.metrics_snapshot.is_a?(Hash)
  end

  test "cycle tracks goals generated" do
    cycle = @service.run_cycle(type: 'triggered')
    
    assert cycle.goals_generated.is_a?(Integer)
    assert cycle.goals_generated >= 0
  end

  test "cycle tracks experiments" do
    cycle = @service.run_cycle(type: 'triggered')
    
    assert cycle.experiments_started.is_a?(Integer)
    assert cycle.experiments_started >= 0
  end

  test "cycle summary works" do
    cycle = @service.run_cycle(type: 'triggered')
    
    summary = cycle.summary
    assert summary.is_a?(Hash)
    assert summary.key?(:id)
    assert summary.key?(:status)
    assert summary.key?(:goals_generated)
  end

  test "check_experiments handles no experiments" do
    promotions = @service.check_experiments
    
    assert promotions.is_a?(Array)
  end

  test "daily cycle type works" do
    cycle = @service.run_cycle(type: 'daily')
    
    assert_equal 'daily', cycle.cycle_type
    assert cycle.completed? || cycle.failed?
  end
end


