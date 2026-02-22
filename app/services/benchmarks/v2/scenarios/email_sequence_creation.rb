# frozen_string_literal: true

module Benchmarks
  module V2
    module Scenarios
      class EmailSequenceCreation
        def self.build
          Scenario.new(
            id: :email_sequence_creation,
            level: :L2,
            category: :content_creation,
            name: "Create a 3-email welcome sequence",
            description: "Tests multi-step content creation: plan a sequence, " \
                         "create individual emails with distinct content, and set up timing.",
            tags: [:core],
            messages: [
              "Set up a welcome email sequence for new customers of my SaaS product 'CloudSync'. " \
              "I need 3 emails: first one immediately after signup welcoming them and explaining " \
              "key features, second one 3 days later with tips for getting started, and third one " \
              "7 days later asking for feedback and offering a discount on annual plans.",
            ],
            assertions: [
              { type: :tool_called, tool_name: "platform_create", min_times: 1 },
              { type: :no_errors },
              { type: :conversation_completed },
            ],
            quality_rubric: <<~RUBRIC,
              Evaluate the email sequence creation:
              1. TASK COMPLETION (0-15): Were all 3 emails created with correct timing?
                 - Email 1: Immediate welcome with feature overview
                 - Email 2: 3-day delay with getting started tips
                 - Email 3: 7-day delay with feedback request and annual discount offer
              2. CONTENT QUALITY (0-15): Is the email copy professional and effective?
                 - Subject lines are compelling and varied
                 - Body content is specific to 'CloudSync' (not generic)
                 - Each email has a distinct purpose and clear CTA
                 - Tone is consistent across the sequence
              3. STRATEGY (0-10): Does the sequence follow email marketing best practices?
                 - Progressive engagement (welcome -> educate -> convert)
                 - Timing makes sense
                 - Each email builds on the previous
              4. EFFICIENCY (0-10): Was this done smoothly?
                 - Didn't ask unnecessary clarifying questions
                 - Created all emails in a logical flow
            RUBRIC
            timeout_seconds: 180
          )
        end
      end
    end
  end
end
