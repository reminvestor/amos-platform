# frozen_string_literal: true

# Triggers automatic recovery for a failed step
class PlanAutoRecoveryJob < ApplicationJob
  queue_as :plans

  def perform(plan_id, step_id, error)
    plan = ExecutionPlan.find_by(id: plan_id)
    return unless plan

    Rails.logger.info "[PlanAutoRecovery] Attempting recovery for step #{step_id} in plan #{plan_id}"

    recovery = Planner::AutoRecoveryService.new(
      plan: plan,
      step_id: step_id,
      error: error
    )

    result = recovery.attempt_recovery

    Rails.logger.info "[PlanAutoRecovery] Recovery result: #{result[:strategy]} - #{result[:message]}"

    # Track recovery analytics
    track_recovery_attempt(plan, step_id, result)
  rescue => e
    Rails.logger.error "[PlanAutoRecovery] Error: #{e.message}"
    Rails.logger.error e.backtrace.first(5).join("\n")
  end

  private

  def track_recovery_attempt(plan, step_id, result)
    # Log for analytics
    plan.send(:log_event, 'recovery_attempt', 
      "Strategy: #{result[:strategy]}, Success: #{result[:success]}, Message: #{result[:message]}")

    # Could also store in a dedicated table for learning
    Rails.cache.increment("plan_recovery:#{result[:strategy]}:attempts")
    Rails.cache.increment("plan_recovery:#{result[:strategy]}:#{result[:success] ? 'success' : 'failure'}")
  end
end





