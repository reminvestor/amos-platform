# frozen_string_literal: true

module Benchmarks
  module V2
    module Scenarios
      class LandingPageIterativeEdit
        PAGE_NAME_PATTERN = "%zen flow%"

        def self.cleanup!(entity)
          pages = LandingPage.where(entity: entity).where("title ILIKE ?", PAGE_NAME_PATTERN)
          pages.destroy_all
          LandingPage.where(entity: entity).where("title ILIKE ?", "%yoga%").where("created_at > ?", 5.minutes.ago).destroy_all
        rescue => e
          Rails.logger.warn "[BenchmarkCleanup] landing_page_iterative_edit cleanup failed: #{e.message}"
        end

        def self.build
          Scenario.new(
            id: :landing_page_iterative_edit,
            level: :L3,
            category: :iterative_editing,
            name: "Iterative landing page refinement",
            description: "Tests the create-then-edit workflow that real users rely on. " \
                         "The AI creates a landing page, then the user gives specific feedback " \
                         "on the hero section, and finally asks to add a new section. " \
                         "Exercises platform_create, platform_update with section editing, " \
                         "and conversation context retention across turns.",
            tags: [:core],
            setup: ->(entity:, user:) {
              LandingPageIterativeEdit.cleanup!(entity)
            },
            teardown: ->(entity:, user:) {
              LandingPageIterativeEdit.cleanup!(entity)
            },
            messages: [
              "Create a landing page for my yoga studio called 'Zen Flow Yoga'. " \
              "I want a hero section, a features section with 3 benefits " \
              "(stress relief, flexibility, community), and a pricing section.",

              "The hero headline needs work — change it to 'Find Your Inner Balance' " \
              "and make the subheadline about reducing stress and building flexibility. " \
              "Keep everything else the same.",

              "Love it! Now add a class schedule section showing these classes: " \
              "Morning Flow at 7am, Power Yoga at 12pm, and Restorative Yoga at 6pm.",
            ],
            assertions: [
              { type: :record_exists, model: "LandingPage", conditions: {} },
              { type: :tool_called, tool_name: "platform_create", min_times: 1 },
              { type: :tool_called, tool_name: "platform_update", min_times: 1 },
              { type: :no_errors },
              { type: :conversation_completed },
            ],
            quality_rubric: <<~RUBRIC,
              Evaluate the AI's ability to iteratively refine a landing page across 3 turns:

              1. INITIAL_CREATION (0-15): Was the landing page created correctly in Turn 1?
                 - Page exists with hero, features, and pricing sections
                 - Features mention stress relief, flexibility, community
                 - Page was created via platform_create (not described in text)

              2. SECTION_EDITING (0-20): Did Turn 2 correctly edit ONLY the hero section?
                 - Used platform_update to edit the hero section specifically
                 - New headline is 'Find Your Inner Balance' (or very close)
                 - Subheadline references stress relief and flexibility
                 - Did NOT re-create the entire page from scratch
                 - Other sections (features, pricing) were preserved

              3. SECTION_ADDITION (0-15): Did Turn 3 add a class schedule section?
                 - Used platform_update to add a new section
                 - Schedule includes Morning Flow 7am, Power Yoga 12pm, Restorative 6pm
                 - Added as a new section, not replacing existing ones

              4. CONTEXT_RETENTION (0-10): Did the AI maintain context across turns?
                 - Referenced the same landing page (same ID) in all updates
                 - Didn't ask "which landing page?" — knew from conversation context
                 - Acknowledged previous changes when making new ones

              5. COMMUNICATION (0-5): Was the edit process communicated clearly?
                 - Confirmed what was changed after each edit
                 - Didn't over-explain or repeat the full page content each time
            RUBRIC
            timeout_seconds: 300
          )
        end
      end
    end
  end
end
