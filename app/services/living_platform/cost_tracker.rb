# frozen_string_literal: true

module LivingPlatform
  # CostTracker - Token and Cost Monitoring for Living Platform
  #
  # Tracks the cost of Living Platform autonomous operations to ensure
  # the platform remains economically viable while self-evolving.
  #
  # Integration:
  # - Uses AiUsageLog for tracking
  # - Provides cost limits and alerts
  # - Supports cost-per-improvement calculations
  #
  class CostTracker
    attr_reader :entity

    # Default cost limits per day (in dollars)
    DEFAULT_DAILY_LIMIT = 10.0
    DEFAULT_PERCEPTION_LIMIT = 0.10
    DEFAULT_REFLECTION_LIMIT = 0.50
    DEFAULT_EVOLUTION_LIMIT = 2.00

    LIVING_PLATFORM_SOURCES = %w[
      perception
      desire_engine
      metacognition
      evolution_cycle
      lifecycle
      agent_school_evolution
    ].freeze

    def initialize(entity)
      @entity = entity
    end

    # ═══════════════════════════════════════════════════════════════════════════
    # USAGE TRACKING
    # ═══════════════════════════════════════════════════════════════════════════

    # Get token usage for Living Platform operations
    def get_usage(period: 7.days)
      logs = AiUsageLog.where(entity: entity)
        .where('created_at > ?', period.ago)
        .where("metadata->>'source' IN (?)", LIVING_PLATFORM_SOURCES)
      
      total_input = logs.sum(:input_tokens)
      total_output = logs.sum(:output_tokens)
      total_cost = logs.sum(:cost_cents) / 100.0
      
      by_source = logs.group("metadata->>'source'")
        .select("metadata->>'source' as source, SUM(input_tokens) as input, SUM(output_tokens) as output, SUM(cost_cents) as cost")
        .map do |row|
          {
            source: row.source,
            input_tokens: row.input.to_i,
            output_tokens: row.output.to_i,
            cost: row.cost.to_f / 100
          }
        end
      
      {
        period_days: (period / 1.day).round,
        total_input_tokens: total_input,
        total_output_tokens: total_output,
        total_cost: total_cost.round(2),
        by_source: by_source,
        daily_average: (total_cost / (period / 1.day)).round(4)
      }
    end

    # Get cost comparison between Living Platform and all usage
    def cost_breakdown(period: 7.days)
      all_logs = AiUsageLog.where(entity: entity)
        .where('created_at > ?', period.ago)
      
      living_platform_logs = all_logs.where("metadata->>'source' IN (?)", LIVING_PLATFORM_SOURCES)
      
      all_cost = all_logs.sum(:cost_cents) / 100.0
      living_platform_cost = living_platform_logs.sum(:cost_cents) / 100.0
      other_cost = all_cost - living_platform_cost
      
      {
        period_days: (period / 1.day).round,
        total_cost: all_cost.round(2),
        living_platform_cost: living_platform_cost.round(2),
        other_cost: other_cost.round(2),
        living_platform_percentage: all_cost > 0 ? ((living_platform_cost / all_cost) * 100).round(1) : 0
      }
    end

    # ═══════════════════════════════════════════════════════════════════════════
    # COST LIMITS
    # ═══════════════════════════════════════════════════════════════════════════

    # Check if daily limit exceeded
    def daily_limit_exceeded?
      usage = get_usage(period: 1.day)
      usage[:total_cost] > daily_limit
    end

    # Check if specific operation is within budget
    def can_afford?(operation:, estimated_tokens: 1000)
      return true unless budget_enforcement_enabled?
      
      limit = limit_for_operation(operation)
      current = usage_for_operation(operation, period: 1.day)
      estimated_cost = estimate_cost(estimated_tokens)
      
      (current + estimated_cost) <= limit
    end

    # Get remaining budget for today
    def remaining_budget
      usage = get_usage(period: 1.day)
      [daily_limit - usage[:total_cost], 0].max.round(2)
    end

    # ═══════════════════════════════════════════════════════════════════════════
    # COST TRACKING HELPERS
    # ═══════════════════════════════════════════════════════════════════════════

    # Log Living Platform AI usage
    def self.log_usage(entity:, user:, source:, model:, input_tokens:, output_tokens:, duration_ms: nil, metadata: {})
      AiUsageLog.log_usage(
        entity: entity,
        user: user || entity.users.first,
        model: model,
        input_tokens: input_tokens,
        output_tokens: output_tokens,
        duration_ms: duration_ms,
        request_type: 'workflow',
        metadata: metadata.merge(source: source, living_platform: true)
      )
    end

    # ═══════════════════════════════════════════════════════════════════════════
    # EFFICIENCY METRICS
    # ═══════════════════════════════════════════════════════════════════════════

    # Calculate cost per evolution (promotions made)
    def cost_per_evolution(period: 30.days)
      usage = get_usage(period: period)
      promotions = EvolutionCycle.where(entity: entity)
        .where('started_at > ?', period.ago)
        .sum { |c| c.promotion_count }
      
      return nil if promotions.zero?
      
      (usage[:total_cost] / promotions).round(2)
    end

    # Calculate cost per goal completed
    def cost_per_goal(period: 30.days)
      usage = get_usage(period: period)
      completed_goals = AgentGoal.where(entity: entity, status: 'completed')
        .where('completed_at > ?', period.ago)
        .count
      
      return nil if completed_goals.zero?
      
      (usage[:total_cost] / completed_goals).round(2)
    end

    # Calculate cost per anomaly detected
    def cost_per_anomaly_detected(period: 30.days)
      perception_cost = usage_for_operation('perception', period: period)
      anomalies_detected = PlatformAnomaly.where(entity: entity)
        .where('created_at > ?', period.ago)
        .count
      
      return nil if anomalies_detected.zero?
      
      (perception_cost / anomalies_detected).round(4)
    end

    # Calculate ROI (improvement value vs cost)
    def calculate_roi(period: 30.days)
      usage = get_usage(period: period)
      cost = usage[:total_cost]
      
      return nil if cost.zero?
      
      # Estimate value: each successful evolution saves X hours of manual work
      # Assume 1 promotion = 2 hours saved, at $50/hour = $100 value
      promotions = EvolutionCycle.where(entity: entity)
        .where('started_at > ?', period.ago)
        .sum { |c| c.promotion_count }
      
      estimated_value = promotions * 100.0
      
      {
        cost: cost,
        estimated_value: estimated_value,
        roi: cost > 0 ? ((estimated_value - cost) / cost * 100).round(1) : 0,
        roi_positive: estimated_value > cost
      }
    end

    # ═══════════════════════════════════════════════════════════════════════════
    # ALERTS AND NOTIFICATIONS
    # ═══════════════════════════════════════════════════════════════════════════

    # Check for cost alerts
    def check_alerts
      alerts = []
      
      usage = get_usage(period: 1.day)
      
      # Alert if approaching daily limit
      if usage[:total_cost] > daily_limit * 0.8
        alerts << {
          type: 'approaching_limit',
          severity: 'warning',
          message: "Living Platform is at #{(usage[:total_cost] / daily_limit * 100).round}% of daily budget",
          current_cost: usage[:total_cost],
          limit: daily_limit
        }
      end
      
      # Alert if daily limit exceeded
      if usage[:total_cost] > daily_limit
        alerts << {
          type: 'limit_exceeded',
          severity: 'critical',
          message: "Living Platform exceeded daily budget ($#{usage[:total_cost]} / $#{daily_limit})",
          current_cost: usage[:total_cost],
          limit: daily_limit
        }
      end
      
      # Alert if ROI is negative
      roi = calculate_roi(period: 7.days)
      if roi && !roi[:roi_positive]
        alerts << {
          type: 'negative_roi',
          severity: 'warning',
          message: "Living Platform ROI is negative (#{roi[:roi]}%)",
          details: roi
        }
      end
      
      alerts
    end

    private

    def daily_limit
      # Could be configurable per entity
      DEFAULT_DAILY_LIMIT
    end

    def limit_for_operation(operation)
      case operation.to_s
      when 'perception' then DEFAULT_PERCEPTION_LIMIT
      when 'metacognition' then DEFAULT_REFLECTION_LIMIT
      when 'evolution_cycle' then DEFAULT_EVOLUTION_LIMIT
      else DEFAULT_DAILY_LIMIT / 10
      end
    end

    def usage_for_operation(operation, period:)
      AiUsageLog.where(entity: entity)
        .where('created_at > ?', period.ago)
        .where("metadata->>'source' = ?", operation.to_s)
        .sum(:cost_cents) / 100.0
    end

    def estimate_cost(tokens)
      # Assume Claude Sonnet pricing: $3/M input, $15/M output
      # Rough estimate: 70% input, 30% output
      input_tokens = tokens * 0.7
      output_tokens = tokens * 0.3
      
      input_cost = (input_tokens / 1_000_000.0) * 3.0
      output_cost = (output_tokens / 1_000_000.0) * 15.0
      
      input_cost + output_cost
    end

    def budget_enforcement_enabled?
      # Could be configurable
      true
    end
  end
end


