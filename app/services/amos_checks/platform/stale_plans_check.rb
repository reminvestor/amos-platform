# frozen_string_literal: true

module AmosChecks
  module Platform
    class StalePlansCheck < BaseCheck
      STALE_THRESHOLD = 1.hour

      def self.check_name = :stale_plans
      def self.category   = :platform_health
      def self.description
        "Detects ApplicationPlans stuck in 'building' or 'paused' status for " \
        "longer than #{STALE_THRESHOLD.inspect}"
      end

      def run(entity: nil)
        scope = ApplicationPlan.where(status: %w[paused building])
                               .where("updated_at < ?", STALE_THRESHOLD.ago)
        scope = scope.where(entity_id: entity.id) if entity

        return [] if scope.count.zero?

        findings = []

        scope.find_each do |plan|
          entity_name = Entity.find_by(id: plan.entity_id)&.name || plan.entity_id.to_s
          completed_phases = plan.build_results&.dig("completed_phases") || []
          active_modules = AppModule.where(entity_id: plan.entity_id, status: "active").count
          hours_stale = ((Time.current - plan.updated_at) / 1.hour).round(1)

          resolvable = completed_phases.include?("modules") && active_modules > 0

          findings << build_finding(
            severity: hours_stale > 24 ? :high : :medium,
            summary: "Plan '#{plan.name}' stuck in '#{plan.status}' for #{hours_stale}h (#{entity_name})",
            entity_id: plan.entity_id,
            details: {
              plan_id: plan.id,
              plan_name: plan.name,
              status: plan.status,
              hours_stale: hours_stale,
              completed_phases: completed_phases,
              active_modules_in_entity: active_modules,
              resolvable: resolvable,
              error_message: plan.error_message
            },
            suggested_action: resolvable ? :auto_recover : :investigate,
            bounty_params: {
              title: "Resolve stale app build plan: #{plan.name}",
              description: "Application plan '#{plan.name}' (id=#{plan.id}) has been in '#{plan.status}' " \
                           "status for #{hours_stale} hours. Completed phases: #{completed_phases.join(', ') || 'none'}. " \
                           "#{resolvable ? 'Has active modules -- likely completable.' : 'Needs investigation.'}",
              bounty_type: "infrastructure",
              points: 100
            }
          )
        end

        findings
      rescue => e
        Rails.logger.error "[AmosChecks::StalePlans] Failed: #{e.message}"
        []
      end
    end
  end
end
