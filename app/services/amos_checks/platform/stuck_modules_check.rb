# frozen_string_literal: true

module AmosChecks
  module Platform
    class StuckModulesCheck < BaseCheck
      STUCK_THRESHOLD = 1.hour

      def self.check_name = :stuck_modules
      def self.category   = :platform_health
      def self.description
        "Detects AppModules stuck in 'generating' status that have the required " \
        "table and code to be activated"
      end

      def run(entity: nil)
        scope = AppModule.where(status: "generating")
                         .where("updated_at < ?", STUCK_THRESHOLD.ago)
        scope = scope.where(entity_id: entity.id) if entity

        return [] if scope.count.zero?

        by_entity = Hash.new { |h, k| h[k] = { recoverable: [], unrecoverable: [] } }

        scope.find_each do |mod|
          has_table = ActiveRecord::Base.connection.table_exists?(mod.slug.pluralize) rescue false
          has_code = mod.module_codes.where(code_type: "model").exists?

          bucket = (has_table && has_code) ? :recoverable : :unrecoverable
          by_entity[mod.entity_id][bucket] << {
            id: mod.id,
            name: mod.name,
            slug: mod.slug,
            stuck_since: mod.updated_at.iso8601
          }
        end

        by_entity.flat_map do |entity_id, groups|
          findings = []

          if groups[:recoverable].any?
            count = groups[:recoverable].size
            findings << build_finding(
              severity: count >= 5 ? :critical : :high,
              summary: "#{count} app module(s) stuck in 'generating' but recoverable (entity #{entity_id})",
              entity_id: entity_id,
              details: {
                module_ids: groups[:recoverable].map { |m| m[:id] },
                modules: groups[:recoverable],
                recoverable: true
              },
              suggested_action: :auto_recover,
              bounty_params: {
                title: "Recover #{count} stuck app module(s)",
                description: "#{count} module(s) have tables and code but are stuck in 'generating' status. " \
                             "They should be activated. Modules: #{groups[:recoverable].map { |m| m[:name] }.join(', ')}",
                bounty_type: "infrastructure",
                points: count >= 5 ? 150 : 100
              }
            )
          end

          if groups[:unrecoverable].any?
            count = groups[:unrecoverable].size
            findings << build_finding(
              severity: :medium,
              summary: "#{count} app module(s) stuck in 'generating' and missing table or code (entity #{entity_id})",
              entity_id: entity_id,
              details: {
                module_ids: groups[:unrecoverable].map { |m| m[:id] },
                modules: groups[:unrecoverable],
                recoverable: false
              },
              suggested_action: :investigate
            )
          end

          findings
        end
      rescue => e
        Rails.logger.error "[AmosChecks::StuckModules] Failed: #{e.message}"
        []
      end
    end
  end
end
