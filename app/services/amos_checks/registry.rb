# frozen_string_literal: true

module AmosChecks
  # Registry - Explicit registry of all AMOS health/insight checks
  #
  # Follows the V3 ToolRegistry pattern: simple hash, explicit registration.
  # Adding a new check = create the class + add one line here.
  #
  # Three categories:
  #   :platform_health      — Bugs, stuck records, infrastructure (global)
  #   :platform_improvement — Strategic platform analysis (global)
  #   :entity_insight        — Per-entity analysis (opt-in)
  #
  # Usage:
  #   AmosChecks::Registry.run_all
  #   AmosChecks::Registry.run_health_checks
  #   AmosChecks::Registry.run_entity_checks(entity)
  #
  class Registry
    # All registered checks — add new checks here
    CHECKS = {
      # Platform health: is anything broken?
      stuck_modules:  AmosChecks::Platform::StuckModulesCheck,
      stale_plans:    AmosChecks::Platform::StalePlansCheck,
      failed_builds:  AmosChecks::Platform::FailedBuildsCheck,

      # Platform improvement: how could the platform be better?
      benchmark_regression: AmosChecks::Improvement::BenchmarkRegressionCheck,

      # Entity insight: how can we help this specific user?
      # (future: data_quality, goal_progress, engagement_analysis)
    }.freeze

    class << self
      def run_all(entity: nil, categories: nil)
        applicable_checks(entity: entity, categories: categories).flat_map do |_name, check_class|
          run_check(check_class, entity: entity)
        end
      end

      def run_health_checks(entity: nil)
        run_all(entity: entity, categories: [:platform_health])
      end

      def run_improvement_checks(entity: nil)
        run_all(entity: entity, categories: [:platform_improvement])
      end

      def run_entity_checks(entity)
        run_all(entity: entity, categories: [:entity_insight])
      end

      def registered_checks
        CHECKS.map do |name, klass|
          { name: name, category: klass.category, description: klass.description }
        end
      end

      private

      def applicable_checks(entity: nil, categories: nil)
        CHECKS.select do |_name, check_class|
          next false if categories && !categories.include?(check_class.category)
          next false if check_class.category == :entity_insight && entity.nil?
          next false if entity && !check_class.enabled_for?(entity)
          true
        end
      end

      def run_check(check_class, entity: nil)
        check = check_class.new
        Array(check.run(entity: entity))
      rescue => e
        Rails.logger.error "[AmosChecks] #{check_class.check_name} failed: #{e.message}\n#{e.backtrace&.first(3)&.join("\n")}"
        []
      end
    end
  end
end
