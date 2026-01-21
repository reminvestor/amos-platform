# frozen_string_literal: true

module Planner
  # OrchestratorService - Manages multiple plans and their dependencies
  #
  # Responsibilities:
  # - Track cross-plan dependencies
  # - Schedule plan execution order
  # - Manage agent workload across plans
  # - Parallelize independent plans
  # - Handle resource contention
  #
  class OrchestratorService
    attr_reader :entity

    def initialize(entity:)
      @entity = entity
    end

    # ============================================
    # PLAN SCHEDULING
    # ============================================

    # Get the next plan that should be executed
    def next_executable_plan
      active_plans = ExecutionPlan.where(entity: entity)
        .where(status: %w[ready executing])
        .order(priority: :desc, created_at: :asc)

      active_plans.find do |plan|
        dependencies_met?(plan) && !resource_conflict?(plan)
      end
    end

    # Get the next step across all plans
    def next_executable_step
      active_plans = ExecutionPlan.where(entity: entity)
        .where(status: 'executing')
        .order(priority: :desc, created_at: :asc)

      active_plans.each do |plan|
        next unless dependencies_met?(plan)

        step = plan.next_step
        if step && plan.step_ready?(step['id'])
          return { plan: plan, step: step }
        end
      end

      nil
    end

    # Get all steps that can be executed in parallel
    def parallel_executable_steps
      steps = []
      active_agents = Set.new

      active_plans = ExecutionPlan.where(entity: entity)
        .where(status: 'executing')
        .order(priority: :desc, created_at: :asc)

      active_plans.each do |plan|
        next unless dependencies_met?(plan)

        plan.all_steps.select { |s| s['status'] == 'pending' }.each do |step|
          # Skip if dependencies not met
          next unless plan.step_ready?(step['id'])

          # Skip if agent already busy
          agent = step['agent']
          next if agent && active_agents.include?(agent)

          steps << { plan: plan, step: step }
          active_agents << agent if agent
        end
      end

      steps
    end

    # ============================================
    # DEPENDENCY MANAGEMENT
    # ============================================

    # Add a dependency between plans
    def add_dependency(dependent_plan:, depends_on_plan:)
      return false if dependent_plan.id == depends_on_plan.id
      return false if would_create_cycle?(dependent_plan, depends_on_plan)

      # Update dependent plan
      current_deps = dependent_plan.depends_on_plan_ids || []
      unless current_deps.include?(depends_on_plan.id)
        dependent_plan.update!(depends_on_plan_ids: current_deps + [depends_on_plan.id])
      end

      # Update blocker plan
      current_blocks = depends_on_plan.blocks_plan_ids || []
      unless current_blocks.include?(dependent_plan.id)
        depends_on_plan.update!(blocks_plan_ids: current_blocks + [dependent_plan.id])
      end

      true
    end

    # Remove a dependency
    def remove_dependency(dependent_plan:, depends_on_plan:)
      dependent_plan.update!(
        depends_on_plan_ids: (dependent_plan.depends_on_plan_ids || []) - [depends_on_plan.id]
      )
      depends_on_plan.update!(
        blocks_plan_ids: (depends_on_plan.blocks_plan_ids || []) - [dependent_plan.id]
      )
    end

    # Check if all dependencies are met
    def dependencies_met?(plan)
      return true if (plan.depends_on_plan_ids || []).empty?

      plan.depends_on_plan_ids.all? do |dep_id|
        dep_plan = ExecutionPlan.find_by(id: dep_id)
        dep_plan.nil? || dep_plan.status == 'completed'
      end
    end

    # Check if plan would create a dependency cycle
    def would_create_cycle?(dependent_plan, depends_on_plan)
      # DFS to detect if depends_on_plan already depends on dependent_plan
      visited = Set.new
      queue = [depends_on_plan.id]

      while queue.any?
        current_id = queue.shift
        return true if current_id == dependent_plan.id
        next if visited.include?(current_id)

        visited << current_id
        current_plan = ExecutionPlan.find_by(id: current_id)
        next unless current_plan

        queue.concat(current_plan.depends_on_plan_ids || [])
      end

      false
    end

    # ============================================
    # RESOURCE MANAGEMENT
    # ============================================

    # Check if plan would conflict with running plans
    def resource_conflict?(plan)
      running_plans = ExecutionPlan.where(entity: entity)
        .where(status: 'executing')
        .where.not(id: plan.id)

      # Check for agent conflicts
      plan_agents = plan.all_steps.map { |s| s['agent'] }.compact.uniq
      
      running_plans.any? do |running|
        running_agents = running.all_steps
          .select { |s| s['status'] == 'in_progress' }
          .map { |s| s['agent'] }
          .compact

        (plan_agents & running_agents).any?
      end
    end

    # Get current workload by agent
    def agent_workload
      workload = Hash.new { |h, k| h[k] = { running: 0, queued: 0 } }

      ExecutionPlan.where(entity: entity).where(status: 'executing').each do |plan|
        plan.all_steps.each do |step|
          next unless step['agent']

          case step['status']
          when 'in_progress'
            workload[step['agent']][:running] += 1
          when 'pending'
            workload[step['agent']][:queued] += 1
          end
        end
      end

      workload
    end

    # Estimate time to completion for queued plans
    def queue_status
      plans = ExecutionPlan.where(entity: entity).active.order(priority: :desc, created_at: :asc)

      plans.map do |plan|
        blocked_by = (plan.depends_on_plan_ids || []).map do |dep_id|
          dep = ExecutionPlan.find_by(id: dep_id)
          next if dep.nil? || dep.status == 'completed'
          { id: dep_id, title: dep.title, status: dep.status, progress: dep.progress_percentage }
        end.compact

        {
          id: plan.id,
          title: plan.title,
          status: plan.status,
          priority: plan.priority,
          progress: plan.progress_percentage,
          estimated_remaining: estimate_remaining_time(plan),
          blocked_by: blocked_by,
          can_start: dependencies_met?(plan) && !resource_conflict?(plan)
        }
      end
    end

    # ============================================
    # PRIORITY MANAGEMENT
    # ============================================

    # Set plan priority (higher = sooner)
    def set_priority(plan, priority)
      plan.update!(priority: priority.clamp(1, 100))
    end

    # Boost priority of blocked plans when blocker completes
    def on_plan_completed(completed_plan)
      blocked_ids = completed_plan.blocks_plan_ids || []
      return if blocked_ids.empty?

      blocked_ids.each do |blocked_id|
        blocked_plan = ExecutionPlan.find_by(id: blocked_id, status: %w[ready paused])
        next unless blocked_plan

        # Check if all dependencies now met
        if dependencies_met?(blocked_plan)
          # Boost priority
          new_priority = [blocked_plan.priority + 10, 100].min
          blocked_plan.update!(priority: new_priority)

          # Resume if paused waiting for dependency
          if blocked_plan.status == 'paused'
            blocked_plan.resume!
          end

          # Queue execution
          PlanStepExecuteJob.perform_later(plan_id: blocked_plan.id, step_id: blocked_plan.next_step&.dig('id'))
        end
      end
    end

    private

    def estimate_remaining_time(plan)
      return 0 if plan.status == 'completed'

      pending_steps = plan.all_steps.select { |s| s['status'] == 'pending' }
      pending_steps.sum { |s| s['estimated_minutes'] || 5 }
    end
  end
end





