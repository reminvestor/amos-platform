# frozen_string_literal: true

module AmosChecks
  module Platform
    class FailedBuildsCheck < BaseCheck
      LOOKBACK_WINDOW = 7.days
      FAILURE_SPIKE_THRESHOLD = 5

      def self.check_name = :failed_builds
      def self.category   = :platform_health
      def self.description
        "Detects spikes in failed ApplicationPlans and recurring failure patterns"
      end

      def run(entity: nil)
        scope = ApplicationPlan.where(status: "failed")
                               .where("updated_at > ?", LOOKBACK_WINDOW.ago)
        scope = scope.where(entity_id: entity.id) if entity

        return [] if scope.count < FAILURE_SPIKE_THRESHOLD

        findings = []

        # Check for overall failure spike
        failure_count = scope.count
        if failure_count >= FAILURE_SPIKE_THRESHOLD
          error_patterns = scope.where.not(error_message: [nil, ""])
                                .group(:error_message)
                                .count
                                .sort_by { |_, c| -c }
                                .first(5)
                                .map { |msg, count| { pattern: msg.truncate(120), count: count } }

          findings << build_finding(
            severity: failure_count >= 10 ? :high : :medium,
            summary: "#{failure_count} app build failures in the last #{LOOKBACK_WINDOW.inspect}",
            details: {
              failure_count: failure_count,
              error_patterns: error_patterns,
              affected_entities: scope.distinct.pluck(:entity_id)
            },
            suggested_action: :create_bounty,
            bounty_params: {
              title: "Investigate app build failure spike (#{failure_count} failures in #{LOOKBACK_WINDOW.inspect})",
              description: "#{failure_count} application plans have failed recently.\n\n" \
                           "Top error patterns:\n" +
                           error_patterns.map { |p| "- #{p[:pattern]} (#{p[:count]}x)" }.join("\n"),
              bounty_type: "bug",
              points: failure_count >= 10 ? 200 : 100
            }
          )
        end

        # Check for recurring failures per entity (same entity failing repeatedly)
        per_entity = scope.group(:entity_id).count.select { |_, c| c >= 3 }
        per_entity.each do |entity_id, count|
          entity_name = Entity.find_by(id: entity_id)&.name || entity_id.to_s
          findings << build_finding(
            severity: :medium,
            summary: "#{count} build failures for #{entity_name} in the last week",
            entity_id: entity_id,
            details: {
              entity_name: entity_name,
              failure_count: count
            },
            suggested_action: :investigate
          )
        end

        findings
      rescue => e
        Rails.logger.error "[AmosChecks::FailedBuilds] Failed: #{e.message}"
        []
      end
    end
  end
end
