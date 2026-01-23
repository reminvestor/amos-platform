# frozen_string_literal: true

# Retries a failed step in an execution plan
class PlanStepRetryJob < ApplicationJob
  queue_as :plans

  def perform(plan_id:, step_id:, retry_number:)
    plan = ExecutionPlan.find_by(id: plan_id)
    return unless plan

    step = plan.find_step(step_id)
    return unless step

    Rails.logger.info "[PlanStepRetry] Retry #{retry_number} for step '#{step['name']}' in plan #{plan_id}"

    # Reset step status for retry
    plan.send(:update_step, step_id, 'status' => 'pending', 'error' => nil)

    # If plan was paused due to failure, resume it
    if plan.status == 'paused'
      plan.resume!
    end

    # Execute the step
    execute_step(plan, step)
  rescue => e
    Rails.logger.error "[PlanStepRetry] Error: #{e.message}"
    
    # Trigger auto-recovery again
    recovery = Planner::AutoRecoveryService.new(plan: plan, step_id: step_id, error: e.message)
    recovery.attempt_recovery
  end

  private

  def execute_step(plan, step)
    step_id = step['id']
    agent_slug = step['agent']

    # Mark step as started
    plan.mark_step_started!(step_id)

    # If no agent, this is an orchestrator step
    unless agent_slug
      plan.send(:log_event, 'step_manual', "Step '#{step['name']}' requires manual handling")
      return
    end

    # Find the agent
    agent = AgentPlugin.find_by(slug: agent_slug, status: 'active')
    
    unless agent
      plan.mark_step_failed!(step_id, error: "Agent '#{agent_slug}' not found")
      return
    end

    # Create execution
    execution = agent.agent_plugin_executions.create!(
      user: plan.user,
      status: 'pending',
      input_context: {
        task_description: step['description'] || step['name'],
        plan_id: plan.id,
        step_id: step_id,
        is_retry: true
      }
    )

    # Queue the agent execution
    AgentPluginExecutionJob.perform_later(
      execution.id,
      step['description'] || step['name'],
      {
        entity: plan.entity,
        session_id: "plan_#{plan.id}",
        plan_id: plan.id,
        step_id: step_id
      }
    )
  end
end





