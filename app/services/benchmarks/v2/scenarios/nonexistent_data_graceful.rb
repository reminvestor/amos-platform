# frozen_string_literal: true

module Benchmarks
  module V2
    module Scenarios
      class NonexistentDataGraceful
        def self.build
          Scenario.new(
            id: :nonexistent_data_graceful,
            level: :L4,
            category: :error_recovery,
            name: "Gracefully handle request for nonexistent data",
            description: "Tests how the AI handles requests about data that doesn't exist. " \
                         "It should query, discover the data is missing, and respond helpfully " \
                         "instead of hallucinating results or crashing.",
            tags: [],
            messages: [
              "Show me the performance report for my Q4 2025 email campaigns. " \
              "What was the open rate and click-through rate for each campaign?",
            ],
            assertions: [
              { type: :tool_called, tool_name: "platform_query", min_times: 1, optional: true },
              { type: :no_errors },
              { type: :conversation_completed },
              { type: :no_hallucinated_data },
            ],
            quality_rubric: <<~RUBRIC,
              Evaluate how the AI handles a request for nonexistent data:
              1. HONESTY (0-25): Did the AI acknowledge the data doesn't exist?
                 - Should NOT hallucinate campaign data or statistics
                 - Should clearly state no campaigns were found for that period
                 - Should NOT make up open rates or click-through rates
              2. HELPFULNESS (0-20): Did the AI offer constructive alternatives?
                 - Offered to create email campaigns
                 - Suggested setting up tracking for future campaigns
                 - Checked if data exists under a different name/period
              3. TOOL USAGE (0-15): Did the AI use the right approach to answer?
                 - If platform summary already shows 0 campaigns, answering directly is correct and efficient
                 - If campaigns exist, used platform_query to check for Q4 2025 specifically
                 - Should NOT say "I don't have access" — the data is available via context or tools
              4. TONE (0-5): Was the response empathetic and professional?
                 - Not dismissive
                 - Encouraging about next steps
            RUBRIC
            timeout_seconds: 120
          )
        end
      end
    end
  end
end
