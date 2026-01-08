# frozen_string_literal: true

module Tools
  class ReadFromScratchpadTool < BaseTool
    def self.read_only?
      true
    end

    def self.metadata
      {
        name: 'read_from_scratchpad',
        description: <<~DESC.strip,
          Read data that was previously saved to the session scratchpad by you or another agent.
          
          Use this when:
          - You were delegated a task and need data from the delegating agent
          - You need to continue a multi-step task with previously saved intermediate results
          - You want to see what data is available from other agents in this session
          
          Common patterns:
          - Export agent reads research results: read_from_scratchpad(key: "vc_research")
          - Continue interrupted task: read_from_scratchpad(key: "step1_results")
          
          Use list_scratchpad first if you're not sure what data is available.
        DESC
        category: 'collaboration',
        input_schema: {
          type: 'object',
          properties: {
            key: {
              type: 'string',
              description: 'The key of the data to read (e.g., "vc_research", "competitor_analysis")'
            }
          },
          required: %w[key]
        }
      }
    end

    def execute(args)
      log_execution(args)

      key = get_arg(args, :key)

      if key.blank?
        return error_response('Key is required')
      end

      # Get session context
      session_id = @context[:session_id]
      unless session_id.present?
        return error_response('No session context - scratchpad requires an active session')
      end

      begin
        # Read from scratchpad
        entry = AgentScratchpad.read_data(session_id: session_id, key: key)

        unless entry
          # List available keys to help the agent
          available = AgentScratchpad.list_for_session(session_id).pluck(:key)
          
          if available.empty?
            return error_response(
              "No data found for key '#{key}'. The scratchpad is empty for this session.",
              available_keys: []
            )
          else
            return error_response(
              "No data found for key '#{key}'. Available keys: #{available.join(', ')}",
              available_keys: available
            )
          end
        end

        # Return the data
        success_response(
          found: true,
          key: key,
          data: entry.data,
          description: entry.description,
          data_type: entry.data_type,
          source_agent: entry.source_agent_plugin&.name,
          row_count: entry.data_row_count,
          size_bytes: entry.data_size,
          created_at: entry.created_at.iso8601,
          expires_at: entry.expires_at.iso8601,
          message: "📦 Retrieved '#{key}' from scratchpad. #{entry.description || ''}"
        )
      rescue => e
        Rails.logger.error "[ReadFromScratchpadTool] Error: #{e.message}"
        error_response("Failed to read from scratchpad: #{e.message}")
      end
    end
  end
end

