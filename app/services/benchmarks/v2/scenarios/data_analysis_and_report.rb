# frozen_string_literal: true

module Benchmarks
  module V2
    module Scenarios
      class DataAnalysisAndReport
        def self.build
          Scenario.new(
            id: :data_analysis_and_report,
            level: :L3,
            category: :data_analysis,
            name: "Analyze existing data and create a visual report",
            description: "Tests the platform's ability to query existing data, perform " \
                         "analysis, and present results visually. Requires platform_query, " \
                         "data reasoning, and freeform canvas or visualization.",
            tags: [:core],
            messages: [
              "Can you analyze my contacts and give me a breakdown? I want to know: " \
              "how many total contacts I have, how many are in each group, which contacts " \
              "were added in the last 30 days, and a visual dashboard showing this data.",
            ],
            assertions: [
              { type: :tool_called, tool_name: "platform_query", min_times: 1 },
              { type: :conversation_completed },
              { type: :no_errors },
            ],
            quality_rubric: <<~RUBRIC,
              Evaluate the data analysis and reporting:
              1. TASK COMPLETION (0-20): Were all requested analyses performed?
                 - Total contact count reported
                 - Contacts broken down by group
                 - Recent contacts (last 30 days) identified
                 - Visual dashboard created (freeform canvas or similar)
              2. ACCURACY (0-20): Is the data analysis correct?
                 - Numbers match actual database state
                 - No hallucinated statistics
                 - Groups are correctly identified
                 - Date filtering is accurate
              3. PRESENTATION (0-15): Is the report well-presented?
                 - Data is clearly organized
                 - Visual dashboard is readable and informative
                 - Key insights are highlighted
              4. INITIATIVE (0-10): Did the AI add value beyond the literal request?
                 - Identified trends or patterns
                 - Suggested actionable next steps
                 - Presentation is professional quality
            RUBRIC
            timeout_seconds: 240
          )
        end
      end
    end
  end
end
