# frozen_string_literal: true

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

    # Task completion rewards
    TASK_REWARDS = {
      base: 35.0,
      quality_multiplier: 30.0,  # 0-1 quality score * this
      speed_bonus_max: 15.0,
      user_satisfaction_max: 25.0
    }.freeze

    # Failure penalties
    FAILURE_PENALTIES = {
      base: 50.0,
      solo_multiplier: 1.5,      # Higher penalty for solo failures
      with_help_multiplier: 0.8, # Lower penalty if help was sought
      importance_multiplier: 2.0,
      preventability_multiplier: 1.5
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

    def task_completion_reward(execution)
      base = TASK_REWARDS[:base]

      # Quality multiplier
      quality = execution.quality_score || 0.5
      quality_bonus = quality * TASK_REWARDS[:quality_multiplier]

      # Speed bonus
      speed_bonus = calculate_speed_bonus(execution)

      # User satisfaction (if available)
      satisfaction_bonus = 0
      if execution.user_rating.present?
        satisfaction_bonus = (execution.user_rating / 5.0) * TASK_REWARDS[:user_satisfaction_max]
      end

      total = base + quality_bonus + speed_bonus + satisfaction_bonus

      total.round(1)
    end

    # ============================================
    # FAILURE PENALTIES
    # ============================================

    def failure_penalty(agent, execution)
      base = FAILURE_PENALTIES[:base]

      # Solo vs with help
      had_help = agent.collaboration_requests_made
        .where(agent_plugin_execution: execution)
        .where(was_helpful: true)
        .exists?

      multiplier = had_help ? FAILURE_PENALTIES[:with_help_multiplier] : FAILURE_PENALTIES[:solo_multiplier]

      # Task importance (if available) - use input_context instead of metadata
      importance = execution.input_context&.dig('importance') || 1.0
      importance_factor = 1.0 + (importance - 1.0) * 0.5

      # Preventability: was help available but not sought?
      could_have_asked = agent.can_help_others? && !had_help
      preventability_factor = could_have_asked ? FAILURE_PENALTIES[:preventability_multiplier] : 1.0

      # Agent failure trend
      trend_factor = calculate_failure_trend_factor(agent)

      penalty = base * multiplier * importance_factor * preventability_factor * trend_factor

      # Ensure failure always costs more than asking for help would have
      min_penalty = 25.0  # More than max collaboration cost
      [penalty, min_penalty].max.clamp(20.0, 100.0).round(1)
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

