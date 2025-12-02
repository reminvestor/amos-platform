# frozen_string_literal: true

# Job to automatically rollback Agent Lightning optimizations if performance degrades
# This runs periodically to check recent performance against pre-optimization baselines
class AgentLightningAutoRollbackJob < ApplicationJob
  queue_as :agent_lightning

  # Rollback threshold - if performance drops by more than this %, rollback
  ROLLBACK_THRESHOLD = 0.10 # 10%

  # Minimum number of traces needed to evaluate performance
  MIN_TRACES_FOR_EVALUATION = 20

  # Time window to evaluate post-optimization performance
  EVALUATION_WINDOW = 24.hours

  def perform(entity_id: nil)
    entities = if entity_id
      Entity.where(id: entity_id)
    else
      Entity.joins(:agent_lightning_config).where(agent_lightning_configs: { enabled: true })
    end

    entities.find_each do |entity|
      check_and_rollback_if_needed(entity)
    end
  end

  private

  def check_and_rollback_if_needed(entity)
    # Get recent applied optimizations
    recent_optimizations = AgentLightningOptimization
      .where(entity: entity)
      .applied
      .where('applied_at > ?', EVALUATION_WINDOW.ago)
      .order(applied_at: :desc)

    return if recent_optimizations.empty?

    recent_optimizations.each do |optimization|
      evaluate_and_maybe_rollback(optimization)
    end
  end

  def evaluate_and_maybe_rollback(optimization)
    entity = optimization.entity

    # Get traces from before the optimization
    pre_optimization_traces = AgentLightningTrace
      .where(entity: entity)
      .where('created_at < ?', optimization.applied_at)
      .where('created_at > ?', optimization.applied_at - 7.days)
      .completed

    # Get traces after the optimization
    post_optimization_traces = AgentLightningTrace
      .where(entity: entity)
      .where('created_at > ?', optimization.applied_at)
      .completed

    # Need enough data to evaluate
    if pre_optimization_traces.count < MIN_TRACES_FOR_EVALUATION ||
       post_optimization_traces.count < MIN_TRACES_FOR_EVALUATION
      Rails.logger.info "[AutoRollback] Not enough traces to evaluate optimization #{optimization.optimization_id}"
      return
    end

    # Calculate performance metrics
    pre_performance = calculate_performance(pre_optimization_traces)
    post_performance = calculate_performance(post_optimization_traces)

    # Compare and decide
    performance_delta = (post_performance - pre_performance) / [pre_performance, 0.01].max

    Rails.logger.info "[AutoRollback] Optimization #{optimization.optimization_id}: " \
                      "pre=#{pre_performance.round(3)}, post=#{post_performance.round(3)}, " \
                      "delta=#{(performance_delta * 100).round(1)}%"

    if performance_delta < -ROLLBACK_THRESHOLD
      Rails.logger.warn "[AutoRollback] Performance degraded by #{(-performance_delta * 100).round(1)}% - triggering rollback"
      perform_rollback(optimization, pre_performance, post_performance, performance_delta)
    else
      Rails.logger.info "[AutoRollback] Performance acceptable - no rollback needed"
    end
  end

  def calculate_performance(traces)
    return 0.0 if traces.empty?

    # Weighted performance score based on:
    # - Success rate (40%)
    # - Average reward signal (40%)
    # - Response time efficiency (20%)

    total = traces.count.to_f
    success_count = traces.where(status: 'completed').count
    success_rate = success_count / total

    avg_reward = traces.where.not(reward_signal: nil).average(:reward_signal)&.to_f || 0.5

    # Calculate time efficiency (faster is better, normalize to 0-1)
    avg_duration = traces.average(:duration_ms)&.to_f || 10000
    time_efficiency = [1.0 - (avg_duration / 30000.0), 0.0].max # 30s baseline

    # Weighted combination
    (success_rate * 0.4) + (avg_reward * 0.4) + (time_efficiency * 0.2)
  end

  def perform_rollback(optimization, pre_performance, post_performance, delta)
    # Record the rollback reason
    optimization.update!(
      metadata: optimization.metadata.merge(
        auto_rollback: true,
        rollback_reason: "Performance degraded by #{(-delta * 100).round(1)}%",
        pre_optimization_performance: pre_performance.round(4),
        post_optimization_performance: post_performance.round(4),
        rollback_triggered_at: Time.current.iso8601
      )
    )

    # Attempt rollback via Python service
    if PythonAgentLightningClient.available?
      result = PythonAgentLightningClient.rollback_optimization(optimization.optimization_id)
      
      if result[:success]
        optimization.mark_rolled_back!
        Rails.logger.info "[AutoRollback] Successfully rolled back optimization #{optimization.optimization_id}"
      else
        Rails.logger.error "[AutoRollback] Failed to rollback via Python service: #{result[:error]}"
        # Still mark as rolled back in Rails
        optimization.mark_rolled_back!
      end
    else
      # Service unavailable - mark as rolled back anyway
      optimization.mark_rolled_back!
      Rails.logger.warn "[AutoRollback] Python service unavailable - marked as rolled back locally"
    end
  rescue => e
    Rails.logger.error "[AutoRollback] Error during rollback: #{e.message}"
    Rails.logger.error e.backtrace.first(5).join("\n")
  end
end

