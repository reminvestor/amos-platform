# frozen_string_literal: true

module Tools
  class ListScratchpadTool < BaseTool
    def self.read_only?
      true
    end

    def self.metadata
      {
        name: 'list_scratchpad',
        description: <<~DESC.strip,
          List all data entries currently in the session scratchpad.
          
          Use this to discover what data has been saved by you or other agents in this session.
          This is helpful when:
          - You were delegated a task and need to find the relevant data
          - You want to see what intermediate results are available
          - You're debugging or exploring the current session state
          
          Returns a summary of each entry including key, description, data type, row count, 
          and which agent saved it. Use read_from_scratchpad to get the actual data.
        DESC
        category: 'collaboration',
        input_schema: {
          type: 'object',
          properties: {
            data_type: {
              type: 'string',
              description: 'Optional: Filter by data type (research_data, intermediate_result, handoff_data, etc.)',
              enum: %w[research_data intermediate_result handoff_data working_state export_data raw_data]
            }
          },
          required: []
        }
      }
    end

    def execute(args)
      log_execution(args)

      data_type_filter = get_arg(args, :data_type)

      # Get session context
      session_id = @context[:session_id]
      unless session_id.present?
        return error_response('No session context - scratchpad requires an active session')
      end

      begin
        # Get entries
        entries = AgentScratchpad.list_for_session(session_id)
        entries = entries.by_type(data_type_filter) if data_type_filter.present?

        if entries.empty?
          return success_response(
            entries: [],
            count: 0,
            message: data_type_filter.present? ? 
              "📭 No scratchpad entries found with type '#{data_type_filter}'." :
              "📭 Scratchpad is empty for this session. Save data using save_to_scratchpad."
          )
        end

        # Build summaries
        summaries = entries.map(&:summary)

        success_response(
          entries: summaries,
          count: summaries.length,
          session_id: session_id,
          message: "📋 Found #{summaries.length} entries in scratchpad. Use read_from_scratchpad(key: \"...\") to retrieve data."
        )
      rescue => e
        Rails.logger.error "[ListScratchpadTool] Error: #{e.message}"
        error_response("Failed to list scratchpad: #{e.message}")
      end
    end
  end
end

