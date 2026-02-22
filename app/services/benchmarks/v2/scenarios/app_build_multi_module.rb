# frozen_string_literal: true

module Benchmarks
  module V2
    module Scenarios
      class AppBuildMultiModule
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
              1. TASK COMPLETION (0-15): Were the modules created and functional?
                 - Clients module created with requested fields
                 - Appointments module created and linked to Clients
                 - Invoices module created and linked to Clients
                 - All modules are in 'active' status (not stuck in 'generating')
              2. DATA MODEL QUALITY (0-15): Is the schema well-designed?
                 - Appropriate field types (dates, enums for status, etc.)
                 - Relationships between modules are correct
                 - Fields match what was requested
              3. USABILITY (0-10): Can the user actually use the app?
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
