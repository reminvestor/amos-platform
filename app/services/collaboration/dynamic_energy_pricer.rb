# frozen_string_literal: true

# ╔════════════════════════════════════════════════════════════════════════════╗
# ║                           ⚠️ DEPRECATED ⚠️                                  ║
# ╠════════════════════════════════════════════════════════════════════════════╣
# ║ This file is DEPRECATED as of 2026-01-24.                                   ║
# ║                                                                             ║
# ║ With the Plugin Injection architecture, there is no inter-agent             ║
# ║ collaboration that requires energy pricing:                                 ║
# ║ - Amos handles all tasks directly via injected loadouts                     ║
# ║ - No delegation between agents                                              ║
# ║ - No energy/resource management needed                                      ║
# ║                                                                             ║
# ║ REPLACEMENT: None - concept is no longer applicable.                        ║
# ║                                                                             ║
# ║ DO NOT USE THIS FILE FOR NEW CODE.                                          ║
# ╚════════════════════════════════════════════════════════════════════════════╝

module Collaboration
  class DynamicEnergyPricer
    # Base costs for collaboration types
    BASE_COSTS = {
      advice: 2.0,
      review: 2.0,
      subtask: 10.0,
      full_delegation: 15.0
    }.freeze

    # Base rewards for helping
    BASE_REWARDS = {
      advice: 5.0,
      review: 5.0,
      subtask: 15.0,
      full_delegation: 25.0
    }.freeze

    # Task completion rewards - generous to encourage task completion
    # A successful task should recover ~2 failed tasks worth of energy
    TASK_REWARDS = {
      base: 25.0,                  # Guaranteed base reward
      quality_multiplier: 15.0,   # 0-1 quality score * this
      speed_bonus_max: 10.0,
      user_satisfaction_max: 15.0,
      first_success_bonus: 10.0   # Extra bonus for first successful task
    }.freeze

    # Failure penalties - balanced to allow recovery
    # An agent should be able to fail 2-3 times before hitting critical energy
    FAILURE_PENALTIES = {
      base: 15.0,                 # Reduced from 50 - allows ~3 failures before critical
      solo_multiplier: 1.3,      # Slightly higher penalty for solo failures
      with_help_multiplier: 0.7, # Lower penalty if help was sought
      importance_multiplier: 1.5,
      preventability_multiplier: 1.2,
      rookie_protection_tasks: 5, # First N tasks get reduced penalties
      rookie_multiplier: 0.5      # Rookies pay 50% penalty
    }.freeze

    # ============================================
    # COLLABORATION COSTS
    # ============================================

    def advice_cost(requester, helper)
      calculate_collaboration_cost(:advice, requester, helper)
    end

    def review_cost(requester, helper)
      calculate_collaboration_cost(:review, requester, helper)
    end

    def subtask_cost(requester, helper)
      calculate_collaboration_cost(:subtask, requester, helper)
    end

    def delegation_cost(requester, helper)
      calculate_collaboration_cost(:full_delegation, requester, helper)
    end

    def calculate_collaboration_cost(type, requester, helper)
      base = BASE_COSTS[type] || 5.0

      # Factor 1: Helper availability (scarce = expensive)
      availability = calculate_availability_factor(helper)

      # Factor 2: Helper expertise (expert = premium)
      expertise = calculate_expertise_premium(helper, requester)

      # Factor 3: Relationship discount
      relationship_discount = calculate_relationship_discount(requester, helper)

      # Factor 4: System load
      system_load = calculate_system_load_factor(requester.entity)

      cost = base * availability * expertise * system_load * (1 - relationship_discount)

      cost.clamp(1.0, 30.0).round(1)
    end

    # ============================================
    # COLLABORATION REWARDS
    # ============================================

    def helper_reward(type, quality_rating: nil, was_helpful: nil, response_time_ms: nil)
      base = BASE_REWARDS[type.to_sym] || 5.0

      # Quality bonus
      if quality_rating.present? && quality_rating > 4
        base *= 1.2
      end

      # Speed bonus
      if response_time_ms.present? && response_time_ms < 10_000
        base *= 1.1
      end

      # Penalty for unhelpful
      if was_helpful == false
        base *= 0.5
      end

      base.round(1)
    end

    # ============================================
    # TASK COMPLETION REWARDS
    # ============================================

    def task_completion_reward(execution, plan_context: nil)
      base = TASK_REWARDS[:base]

      # Quality multiplier - use output_result metadata if available, otherwise default
      quality = extract_quality_score(execution)
      quality_bonus = quality * TASK_REWARDS[:quality_multiplier]

      # Speed bonus
      speed_bonus = calculate_speed_bonus(execution)

      # User satisfaction (if available from output_result)
      satisfaction_bonus = 0
      user_rating = extract_user_rating(execution)
      if user_rating.present?
        satisfaction_bonus = (user_rating / 5.0) * TASK_REWARDS[:user_satisfaction_max]
      end

      # Plan context bonuses
      plan_bonus = calculate_plan_completion_bonus(execution, plan_context)

      total = base + quality_bonus + speed_bonus + satisfaction_bonus + plan_bonus

      total.round(1)
    end

    # Bonus for completing steps within a plan
    def calculate_plan_completion_bonus(execution, plan_context)
      return 0 unless plan_context

      bonus = 0

      # Completing a step in a plan shows teamwork
      bonus += 5

      # Completing later steps (more value at risk) = higher bonus
      if plan_context[:plan_progress]
        progress = plan_context[:plan_progress].to_f
        bonus += (progress * 10)  # Up to +10 for late-stage completion
      end

      # Completing a phase (all steps in phase done) = extra bonus
      if plan_context[:phase_completed]
        bonus += 15
      end

      # Completing the final plan step = significant bonus
      if plan_context[:plan_completed]
        bonus += 25
      end

      bonus
    end

    def extract_quality_score(execution)
      # Try to get quality from output_result metadata
      execution.output_result&.dig('quality_score') ||
        execution.output_result&.dig('quality') ||
        0.5 # Default quality
    end

    def extract_user_rating(execution)
      # Try to get user rating from output_result metadata
      execution.output_result&.dig('user_rating') ||
        execution.output_result&.dig('rating')
    end

    # ============================================
    # FAILURE PENALTIES
    # ============================================

    def failure_penalty(agent, execution, plan_context: nil)
      base = FAILURE_PENALTIES[:base]

      # Rookie protection - new agents get reduced penalties
      total_tasks = agent.energy_state&.tasks_completed.to_i + agent.energy_state&.tasks_failed.to_i
      is_rookie = total_tasks < FAILURE_PENALTIES[:rookie_protection_tasks]
      rookie_factor = is_rookie ? FAILURE_PENALTIES[:rookie_multiplier] : 1.0

      # Solo vs with help
      had_help = agent.collaboration_requests_made
        .where(agent_plugin_execution: execution)
        .where(was_helpful: true)
        .exists?

      multiplier = had_help ? FAILURE_PENALTIES[:with_help_multiplier] : FAILURE_PENALTIES[:solo_multiplier]

      # Task importance (if available) - use input_context instead of metadata
      importance = execution.input_context&.dig('importance') || 1.0
      importance_factor = 1.0 + (importance - 1.0) * 0.3  # Reduced impact

      # Preventability: was help available but not sought?
      could_have_asked = agent.respond_to?(:can_help_others?) && agent.can_help_others? && !had_help
      preventability_factor = could_have_asked ? FAILURE_PENALTIES[:preventability_multiplier] : 1.0

      # Agent failure trend - only penalize repeat offenders
      trend_factor = calculate_failure_trend_factor(agent)

      # Plan context impact
      plan_factor = calculate_plan_failure_impact(plan_context)

      penalty = base * multiplier * importance_factor * preventability_factor * trend_factor * rookie_factor * plan_factor

      # Ensure failure costs more than asking for help, but not catastrophically
      # Min penalty should allow an agent to fail 2-3 times before hitting critical
      min_penalty = is_rookie ? 8.0 : 12.0
      max_penalty = is_rookie ? 25.0 : 60.0  # Higher max for critical plan failures

      penalty.clamp(min_penalty, max_penalty).round(1)
    end

    # Plan-aware failure impact
    # Failing early in a plan (blocking more work) = higher penalty
    # Failing late in a plan (less work at risk) = lower penalty
    def calculate_plan_failure_impact(plan_context)
      return 1.0 unless plan_context

      # How much of the plan was at risk when this step failed?
      progress = plan_context[:plan_progress].to_f rescue 0
      blocking_steps = plan_context[:blocking_steps].to_i rescue 0
      total_steps = plan_context[:total_steps].to_i rescue 1

      # Early failure (< 20% progress) with many blocked steps = high impact
      if progress < 0.2 && blocking_steps > 3
        1.4
      # Early failure with some blocked steps
      elsif progress < 0.2 && blocking_steps > 0
        1.2
      # Mid-plan failure
      elsif progress < 0.5
        1.1
      # Late-stage failure (most work done) = lower impact
      elsif progress > 0.8
        0.8
      else
        1.0
      end
    end

    private

    # ============================================
    # FACTOR CALCULATIONS
    # ============================================

    def calculate_availability_factor(helper)
      return 1.0 unless helper

      # Based on current load
      active_tasks = helper.active_task_count
      recent_help = helper.collaboration_requests_received
        .where('created_at > ?', 1.hour.ago)
        .count

      factor = 1.0
      factor += 0.2 * active_tasks
      factor += 0.1 * recent_help

      factor.clamp(0.5, 2.0)
    end

    def calculate_expertise_premium(helper, requester)
      return 1.0 unless helper

      # Compare success rates
      helper_rate = helper.energy_state&.success_rate || 0.5
      requester_rate = requester.energy_state&.success_rate || 0.5

      if helper_rate > requester_rate + 0.2
        1.3  # Expert premium
      elsif helper_rate > requester_rate
        1.1  # Slight premium
      else
        1.0
      end
    end

    def calculate_relationship_discount(requester, helper)
      return 0.0 unless helper

      relationship = AgentRelationship.find_by(
        requester: requester,
        helper: helper
      )

      return 0.0 unless relationship

      # Better relationships = bigger discounts (max 40%)
      (relationship.successful_collaborations.to_f / 20).clamp(0.0, 0.4)
    end

    def calculate_system_load_factor(entity)
      return 1.0 unless entity

      # Count active collaboration requests
      active_requests = AgentCollaborationRequest
        .where(entity: entity)
        .where(status: %w[pending accepted in_progress])
        .count

      if active_requests > 20
        1.5  # System overloaded
      elsif active_requests > 10
        1.2
      else
        1.0
      end
    end

    def calculate_speed_bonus(execution)
      return 0 unless execution.duration_ms

      # Compare to average
      agent = execution.agent_plugin
      avg_duration = agent.agent_plugin_executions
        .where(status: 'completed')
        .average(:duration_ms)

      return 0 unless avg_duration && avg_duration > 0

      if execution.duration_ms < avg_duration * 0.5
        TASK_REWARDS[:speed_bonus_max]
      elsif execution.duration_ms < avg_duration * 0.8
        TASK_REWARDS[:speed_bonus_max] * 0.5
      else
        0
      end
    end

    def calculate_failure_trend_factor(agent)
      # Recent failure trend increases penalty
      recent_executions = agent.agent_plugin_executions
        .where('created_at > ?', 7.days.ago)
        .order(created_at: :desc)
        .limit(10)

      return 1.0 if recent_executions.empty?

      recent_failures = recent_executions.count { |e| e.status == 'failed' }
      failure_rate = recent_failures.to_f / recent_executions.count

      if failure_rate > 0.5
        1.5  # High failure trend
      elsif failure_rate > 0.3
        1.2
      else
        1.0
      end
    end
  end
end

