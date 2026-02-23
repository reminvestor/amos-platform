# frozen_string_literal: true

module Benchmarks
  module V2
    module Scenarios
      class AppBuildMultiModule
        MODULE_SLUG_PATTERNS = %w[client% appointment% invoice%].freeze

        def self.cleanup!(entity)
          app_ids = App.where(entity: entity)
            .where("name ILIKE ? OR slug LIKE ? OR slug LIKE ?",
                    "%client management%", "client_management%", "client-management%")
            .pluck(:id)

          # Also find orphaned modules (app_id nil) that match benchmark slug patterns
          orphan_ids = AppModule.where(entity: entity, app_id: nil)
            .where("slug LIKE ? OR slug LIKE ? OR slug LIKE ?", *MODULE_SLUG_PATTERNS)
            .pluck(:id)

          mod_ids = if app_ids.any?
            AppModule.where(app_id: app_ids).pluck(:id) + orphan_ids
          else
            orphan_ids
          end
          mod_ids.uniq!

          delete_module_dependencies!(mod_ids) if mod_ids.any?
          AppModule.where(id: mod_ids).delete_all if mod_ids.any?
          AgentPlugin.where(app_id: app_ids).delete_all if app_ids.any?
          App.where(id: app_ids).delete_all if app_ids.any?

          ApplicationPlan.where(entity: entity)
            .where("name ILIKE ?", "%client management%")
            .where("created_at > ?", 30.days.ago)
            .delete_all
        rescue => e
          Rails.logger.warn "[BenchmarkCleanup] app_build cleanup failed: #{e.message}"
        end

        DEPENDENT_TABLES = %w[
          module_canvases module_actions module_codes module_design_sessions
          custom_field_definitions module_webhooks tool_definitions
          scheduled_agent_tasks module_integrations website_pages
          web_app_modules automation_codes
        ].freeze

        def self.delete_module_dependencies!(mod_ids)
          return if mod_ids.empty?
          id_list = mod_ids.join(",")
          conn = ActiveRecord::Base.connection
          DEPENDENT_TABLES.each do |table|
            conn.execute("DELETE FROM #{table} WHERE app_module_id IN (#{id_list})") rescue nil
          end
          AgentPlugin.where(app_module_id: mod_ids).delete_all rescue nil
        end

        def self.build
          Scenario.new(
            id: :app_build_multi_module,
            level: :L3,
            category: :app_building,
            name: "Build a multi-module client management app",
            description: "The hardest real-world task: build a complete application with " \
                         "multiple related modules. This is exactly what users like Stephanie " \
                         "and Chris attempted. Tests app planning, module creation, table " \
                         "creation, canvas generation, and activation.",
            tags: [:core],
            setup: ->(entity:, user:) {
              AppBuildMultiModule.cleanup!(entity)
            },
            messages: [
              "Build me a client management app. I need a main Clients module with fields for " \
              "name, email, phone, company, and status. Then I need an Appointments module linked " \
              "to clients with date, time, duration, location, and notes. Finally an Invoices " \
              "module linked to clients with amount, due date, status (draft/sent/paid), and line items.",
            ],
            assertions: [
              { type: :tool_called, tool_name: "platform_create", min_times: 1 },
              { type: :record_exists, model: "AppModule", conditions: { status: "active" }, min_count: 1 },
              { type: :no_errors },
              { type: :conversation_completed },
              { type: :no_hallucinated_urls },
            ],
            quality_rubric: <<~RUBRIC,
              Evaluate the multi-module app build:
              1. TASK COMPLETION (0-20): Were the modules created and functional?
                 - Clients module created with requested fields
                 - Appointments module created and linked to Clients
                 - Invoices module created and linked to Clients
                 - All modules are in 'active' status (not stuck in 'generating')
              2. DATA MODEL QUALITY (0-20): Is the schema well-designed?
                 - Appropriate field types (dates, enums for status, etc.)
                 - Relationships between modules are correct
                 - Fields match what was requested
              3. USABILITY (0-15): Can the user actually use the app?
                 - Modules have canvases/views
                 - The user can access the app through the platform
                 - No broken references or missing tables
              4. COMMUNICATION (0-10): Was the build process transparent?
                 - Progress was communicated during the build
                 - Final result was presented clearly
                 - No false promises about external URLs or features that don't work
            RUBRIC
            timeout_seconds: 300
          )
        end
      end
    end
  end
end
