# frozen_string_literal: true

# Executes a specific step in an execution plan
class PlanStepExecuteJob < ApplicationJob
  queue_as :plans

  def perform(plan_id:, step_id:)
    plan = ExecutionPlan.find_by(id: plan_id)
    return unless plan

    step = plan.find_step(step_id)
    return unless step

    # Check if plan is still in a runnable state
    unless plan.status.in?(%w[ready executing])
      Rails.logger.info "[PlanStepExecute] Plan #{plan_id} not in runnable state (#{plan.status})"
      return
    end

    # Check dependencies
    unless plan.step_ready?(step_id)
      Rails.logger.info "[PlanStepExecute] Step #{step_id} not ready - dependencies incomplete"
      return
    end

    Rails.logger.info "[PlanStepExecute] Executing step '#{step['name']}' in plan #{plan_id}"

    execute_step(plan, step)
  rescue => e
    Rails.logger.error "[PlanStepExecute] Error: #{e.message}"
    
    plan = ExecutionPlan.find_by(id: plan_id)
    if plan
      plan.mark_step_failed!(step_id, error: e.message)
      
      # Trigger auto-recovery
      recovery = Planner::AutoRecoveryService.new(plan: plan, step_id: step_id, error: e.message)
      recovery.attempt_recovery
    end
  end

  private

  def execute_step(plan, step)
    step_id = step['id']
    agent_slug = step['agent']

    # Mark step as started
    plan.mark_step_started!(step_id)

    # If no agent, this is an orchestrator step
    unless agent_slug
      Rails.logger.info "[PlanStepExecute] Step '#{step['name']}' requires orchestrator handling"
      
      # Notify through Hub
      bridge = Hub::PlanBridgeService.new(plan: plan)
      bridge.on_user_input_needed(step, step['description'] || "This step requires your input.")
      
      plan.pause!(reason: "Waiting for input on step '#{step['name']}'")
      return
    end

    # Find the agent
    agent = AgentPlugin.find_by(slug: agent_slug, status: 'active')
    
    unless agent
      plan.mark_step_failed!(step_id, error: "Agent '#{agent_slug}' not found")
      trigger_auto_recovery(plan, step_id, "Agent not found")
      return
    end

    # Build enriched context
    context_builder = build_plan_context(plan, step)

    # Create execution
    execution = agent.agent_plugin_executions.create!(
      user: plan.user,
      status: 'pending',
      input_context: {
        task_description: context_builder[:enriched_description],
        plan_id: plan.id,
        step_id: step_id,
        plan_context: context_builder[:context]
      }
    )

    # Queue the agent execution
    AgentPluginExecutionJob.perform_later(
      execution.id,
      context_builder[:enriched_description],
      {
        entity: plan.entity,
        session_id: "plan_#{plan.id}",
        plan_id: plan.id,
        step_id: step_id,
        plan_context: context_builder[:context]
      }
    )

    Rails.logger.info "[PlanStepExecute] Queued agent #{agent_slug} for step #{step_id}"
  end

  def build_plan_context(plan, step)
    # Get completed steps with results
    completed_steps = plan.all_steps.select { |s| s['status'] == 'completed' }.map do |s|
      {
        name: s['name'],
        result: s['result']
      }
    end

    context = {
      plan_goal: plan.original_request,
      plan_title: plan.title,
      progress: "#{plan.completed_steps}/#{plan.total_steps} steps",
      completed_steps: completed_steps.map { |s| "#{s[:name]}: #{s[:result].to_s.truncate(100)}" },
      remaining_steps: plan.all_steps.select { |s| s['status'] == 'pending' }.map { |s| s['name'] }
    }

    enriched_description = build_enriched_description(step, context)

    { context: context, enriched_description: enriched_description }
  end

  def build_enriched_description(step, context)
    parts = ["TASK: #{step['description'] || step['name']}"]
    
    parts << "\n## PLAN CONTEXT"
    parts << "Goal: #{context[:plan_goal]}"
    parts << "Progress: #{context[:progress]}"
    
    if context[:completed_steps].any?
      parts << "\n## COMPLETED STEPS"
      context[:completed_steps].each { |s| parts << "- #{s}" }
    end
    
    parts.join("\n")
  end

  def trigger_auto_recovery(plan, step_id, error)
    recovery = Planner::AutoRecoveryService.new(plan: plan, step_id: step_id, error: error)
    recovery.attempt_recovery
  end
end





