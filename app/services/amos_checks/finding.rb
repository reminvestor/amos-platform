# frozen_string_literal: true

module AmosChecks
  # Structured result from a health/insight check.
  #
  # Fields:
  #   check_name       - identifier of the check that produced this (e.g., "stuck_modules")
  #   category         - :platform_health, :platform_improvement, or :entity_insight
  #   severity         - :critical, :high, :medium, :low
  #   scope            - :platform (global) or :entity (scoped to one tenant)
  #   entity_id        - nil for platform-wide findings, entity id for scoped
  #   summary          - human-readable one-liner
  #   details          - hash with structured data (ids, counts, etc.)
  #   suggested_action - :create_bounty, :investigate, :flag_for_humans, :auto_recover
  #   bounty_params    - optional hash with pre-built bounty fields for direct creation
  #
  Finding = Struct.new(
    :check_name,
    :category,
    :severity,
    :scope,
    :entity_id,
    :summary,
    :details,
    :suggested_action,
    :bounty_params,
    keyword_init: true
  ) do
    def actionable?
      suggested_action == :create_bounty && severity.in?([:critical, :high])
    end

    def signal_strength
      case severity
      when :critical then 0.95
      when :high then 0.8
      when :medium then 0.5
      when :low then 0.3
      else 0.3
      end
    end

    def signal_type
      case category
      when :platform_health then 'platform_health_issue'
      when :platform_improvement then 'platform_improvement'
      when :entity_insight then 'entity_insight'
      else 'platform_health_issue'
      end
    end

    def to_signal_data
      {
        'check_name' => check_name.to_s,
        'severity' => severity.to_s,
        'scope' => scope.to_s,
        'summary' => summary,
        'details' => details&.transform_keys(&:to_s) || {},
        'suggested_action' => suggested_action.to_s
      }
    end
  end
end
