# frozen_string_literal: true

module AmosChecks
  # BaseCheck - Base class for all AMOS health/insight checks
  #
  # Three categories:
  #   :platform_health      — Bugs, stuck records, infrastructure (global)
  #   :platform_improvement — Strategic analysis (global, CEO mindset)
  #   :entity_insight        — Per-entity analysis (opt-in per tenant)
  #
  # To create a new check:
  #   1. Subclass BaseCheck
  #   2. Implement: .check_name, .category, .description, #run
  #   3. Add one line to AmosChecks::Registry::CHECKS
  #
  class BaseCheck
    def self.check_name  = raise(NotImplementedError)
    def self.category    = raise(NotImplementedError)
    def self.description = raise(NotImplementedError)

    def self.enabled_for?(_entity)
      category != :entity_insight
    end

    # Returns Array<AmosChecks::Finding>
    def run(entity: nil)
      raise NotImplementedError, "#{self.class.name}#run"
    end

    private

    def build_finding(severity:, summary:, details: {}, suggested_action: :create_bounty, entity_id: nil, bounty_params: nil)
      Finding.new(
        check_name: self.class.check_name,
        category: self.class.category,
        severity: severity,
        scope: entity_id ? :entity : :platform,
        entity_id: entity_id,
        summary: summary,
        details: details,
        suggested_action: suggested_action,
        bounty_params: bounty_params
      )
    end
  end
end
