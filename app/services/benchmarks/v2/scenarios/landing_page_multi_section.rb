# frozen_string_literal: true

module Benchmarks
  module V2
    module Scenarios
      class LandingPageMultiSection
        def self.build
          Scenario.new(
            id: :landing_page_multi_section,
            level: :L2,
            category: :content_creation,
            name: "Build a multi-section landing page",
            description: "Tests the platform's ability to create a complete landing page " \
                         "with multiple sections, custom copy, and a call-to-action. " \
                         "Requires platform_create tool, content generation, and canvas loading.",
            tags: [:core],
            messages: [
              "I need a landing page for my new product called 'TaskFlow Pro' - it's a project management " \
              "tool for small teams. I want a hero section with a strong headline, a features section " \
              "highlighting 3 key features (real-time collaboration, smart scheduling, and automated " \
              "reports), a testimonials section, and a pricing section with a free trial CTA.",
            ],
            assertions: [
              { type: :record_exists, model: "LandingPage", conditions: {} },
              { type: :tool_called, tool_name: "platform_create", min_times: 1 },
              { type: :no_errors },
              { type: :conversation_completed },
              { type: :no_hallucinated_urls },
            ],
            quality_rubric: <<~RUBRIC,
              Evaluate the AI's response for creating a landing page:
              1. TASK COMPLETION (0-20): Did it actually create a landing page with multiple sections?
                 - Hero section with headline and subheadline
                 - Features section with the 3 requested features
                 - Testimonials section
                 - Pricing section with CTA
              2. CONTENT QUALITY (0-20): Is the generated copy professional and relevant?
                 - Headlines are compelling, not generic
                 - Feature descriptions are specific to a project management tool
                 - CTA is clear and action-oriented
              3. USER EXPERIENCE (0-15): Was the interaction smooth?
                 - Did the AI create it without asking unnecessary questions?
                 - Was progress communicated clearly?
                 - Was the result presented or made viewable?
              4. EFFICIENCY (0-10): Did the AI accomplish this in a reasonable number of steps?
                 - Minimal unnecessary tool calls
                 - No repeated failures or retries
            RUBRIC
            timeout_seconds: 180
          )
        end
      end
    end
  end
end
