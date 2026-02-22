# frozen_string_literal: true

module Benchmarks
  module V2
    module Scenarios
      class AmbiguousRequestHandling
        def self.build
          Scenario.new(
            id: :ambiguous_request_handling,
            level: :L4,
            category: :conversation_quality,
            name: "Handle an ambiguous business request",
            description: "Tests how the AI handles vague, open-ended requests that require " \
                         "clarification and strategic thinking. The AI should NOT just guess -- " \
                         "it should ask smart follow-up questions to understand the user's needs " \
                         "before taking action.",
            tags: [:core],
            messages: [
              "Help me grow my business",
              "I run a small interior design firm with about 20 clients. Most of my work " \
              "comes from referrals but I want to expand. I have a website but it's not " \
              "generating any leads.",
            ],
            assertions: [
              { type: :conversation_completed },
              { type: :no_errors },
              { type: :response_contains_question, on_message: 0 },
            ],
            quality_rubric: <<~RUBRIC,
              Evaluate how the AI handles an ambiguous request:
              1. CLARIFICATION QUALITY (0-15): Did the AI ask good follow-up questions?
                 - First response should NOT jump to action -- should ask questions
                 - Questions should be specific and relevant (not generic)
                 - Questions should help narrow down: industry, goals, current state, budget
              2. STRATEGIC THINKING (0-15): After getting context, did the AI provide a strategic response?
                 - Identified key opportunities (website optimization, lead generation)
                 - Recommendations are specific to interior design industry
                 - Suggested concrete, actionable next steps
                 - Prioritized recommendations logically
              3. PLATFORM AWARENESS (0-10): Did the AI suggest platform capabilities?
                 - Landing page creation for lead capture
                 - Email campaigns for nurturing
                 - Contact management for client tracking
                 - Offered to implement suggestions, not just advise
              4. CONVERSATION QUALITY (0-10): Was the interaction natural?
                 - Didn't overwhelm with too many questions at once
                 - Acknowledged the user's context
                 - Felt like talking to a strategic advisor, not a form
            RUBRIC
            timeout_seconds: 120
          )
        end
      end
    end
  end
end
