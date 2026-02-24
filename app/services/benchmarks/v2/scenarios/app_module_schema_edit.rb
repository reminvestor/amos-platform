# frozen_string_literal: true

module Benchmarks
  module V2
    module Scenarios
      class AppModuleSchemaEdit
        APP_NAME = "Benchmark Project Tracker"
        MODULE_SLUG = "bench_projects"

        INITIAL_FIELDS = [
          { name: "project_name", field_type: "string", required: true },
          { name: "client_name", field_type: "string", required: false },
          { name: "status", field_type: "select", required: true, options: ["planning", "active", "completed"] },
          { name: "start_date", field_type: "date", required: false },
          { name: "budget", field_type: "number", required: false },
          { name: "notes", field_type: "text", required: false },
        ].freeze

        def self.cleanup!(entity)
          conn = ActiveRecord::Base.connection
          mod_ids = AppModule.where(entity: entity)
            .where("slug LIKE ? OR name ILIKE ?", "bench_project%", "%benchmark project%")
            .pluck(:id)

          return unless mod_ids.any?

          AppBuildMultiModule.delete_module_dependencies!(mod_ids)
          AppModule.where(id: mod_ids).delete_all

          app_ids = App.where(entity: entity).where("name ILIKE ?", "%benchmark project%").pluck(:id)
          if app_ids.any?
            AppBuildMultiModule.delete_plugin_dependencies_by_app!(app_ids)
            App.where(id: app_ids).delete_all
          end
        rescue => e
          Rails.logger.warn "[BenchmarkCleanup] app_module_schema_edit cleanup failed: #{e.message}"
        end

        def self.setup!(entity, user)
          cleanup!(entity)

          app = App.create!(
            entity: entity,
            created_by: user,
            name: APP_NAME,
            slug: "benchmark-project-tracker",
            status: "active"
          )

          app_module = AppModule.create!(
            entity: entity,
            app: app,
            name: "Projects",
            slug: MODULE_SLUG,
            status: "active",
            metadata: {
              "schema" => {
                "fields" => INITIAL_FIELDS.map(&:stringify_keys)
              }
            }
          )

          app_module
        end

        def self.build
          Scenario.new(
            id: :app_module_schema_edit,
            level: :L3,
            category: :iterative_editing,
            name: "Edit app module schema and fields",
            description: "Tests iterative editing of an existing app module's schema. " \
                         "A project tracker module exists with basic fields. The user " \
                         "reviews it, then asks to add a priority field, rename a field, " \
                         "and add new status options. Exercises platform_query for module " \
                         "discovery and platform_update with schema merging.",
            tags: [:core],
            setup: ->(entity:, user:) {
              AppModuleSchemaEdit.setup!(entity, user)
            },
            teardown: ->(entity:, user:) {
              AppModuleSchemaEdit.cleanup!(entity)
            },
            messages: [
              "I have an app module called 'Projects' (slug: bench_projects). " \
              "Can you show me what fields it has and their types?",

              "I need a few changes to the Projects module schema: " \
              "1. Add a 'priority' field as a dropdown with options: low, medium, high, urgent. " \
              "2. The status field needs two more options: 'on_hold' and 'cancelled'. " \
              "3. Rename the 'client_name' field to 'client_company'. " \
              "4. Make the 'start_date' field required.",
            ],
            assertions: [
              { type: :tool_called, tool_name: "platform_query", min_times: 1 },
              { type: :tool_called, tool_name: "platform_update", min_times: 1 },
              { type: :no_errors },
              { type: :conversation_completed },
            ],
            quality_rubric: <<~RUBRIC,
              Evaluate the AI's ability to review and edit an app module's schema:

              1. DISCOVERY (0-15): Did Turn 1 accurately present the module's fields?
                 - Found the project tracker module
                 - Listed all 6 fields with their types
                 - Showed which fields are required vs optional
                 - Showed the status field's current options (planning, active, completed)

              2. FIELD_ADDITION (0-15): Was the priority field added correctly?
                 - Used platform_update with type "app_module"
                 - Added a field named 'priority' with type 'select'
                 - Options include: low, medium, high, urgent
                 - Field was added without disrupting existing fields

              3. STATUS_OPTIONS (0-15): Were the status options expanded?
                 - Updated the existing 'status' field
                 - Added 'on_hold' and 'cancelled' to the existing options
                 - Original options (planning, active, completed) were preserved
                 - Did NOT create a new status field or replace the existing one

              4. FIELD_RENAME (0-10): Was client_name renamed to client_company?
                 - The field name was changed from 'client_name' to 'client_company'
                 - Field type and other properties were preserved

              5. REQUIRED_CHANGE (0-5): Was start_date made required?
                 - The start_date field's required property was set to true

              6. PRECISION (0-5): Were the edits surgical?
                 - Only the requested changes were made
                 - Other fields (project_name, budget, notes) were not modified
                 - The module was not recreated from scratch
                 - All changes were made via platform_update, not platform_create
            RUBRIC
            timeout_seconds: 120
          )
        end
      end
    end
  end
end
