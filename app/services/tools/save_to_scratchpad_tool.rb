# frozen_string_literal: true

module Tools
  class SaveToScratchpadTool < BaseTool
    def self.metadata
      {
        name: 'save_to_scratchpad',
        description: <<~DESC.strip,
          Save structured data to the session scratchpad for later use or handoff to other agents.
          
          Use this when you have data that:
          - Another agent will need (e.g., research results → export agent)
          - You'll need in a later step of a multi-step task
          - Should be preserved if the task is interrupted
          
          The scratchpad is shared across all agents in this session. Other agents can read
          your saved data using the key you provide. Data expires after 24 hours.
          
          Examples:
          - After researching VCs: save_to_scratchpad(key: "vc_research", data: [...], description: "100 VCs for AMOS Labs")
          - Before exporting: The export agent can read_from_scratchpad(key: "vc_research") to get the data
        DESC
        category: 'collaboration',
        input_schema: {
          type: 'object',
          properties: {
            key: {
              type: 'string',
              description: 'Unique identifier for this data (e.g., "vc_research", "competitor_analysis", "campaign_metrics")'
            },
            data: {
              type: 'object',
              description: 'The structured data to save. Can be an array of objects, a hash, or any JSON-serializable data.'
            },
            description: {
              type: 'string',
              description: 'Human-readable description of what this data is (helps other agents understand it)'
            },
            data_type: {
              type: 'string',
              description: 'Category of data: research_data, intermediate_result, handoff_data, working_state, export_data',
              enum: %w[research_data intermediate_result handoff_data working_state export_data raw_data]
            }
          },
          required: %w[key data]
        }
      }
    end

    def execute(args)
      log_execution(args)

      key = get_arg(args, :key)
      data = get_arg(args, :data)
      description = get_arg(args, :description)
      data_type = get_arg(args, :data_type, 'handoff_data')

      # Validate required args
      if key.blank?
        return error_response('Key is required')
      end

      if data.nil?
        return error_response('Data is required')
      end

      # Get session context
      session_id = @context[:session_id]
      unless session_id.present?
        return error_response('No session context - scratchpad requires an active session')
      end

      # Get agent context
      agent = @context[:agent_plugin]
      execution = @context[:execution]

      begin
        # Save to scratchpad
        entry = AgentScratchpad.save_data(
          session_id: session_id,
          key: key,
          data: data,
          description: description,
          data_type: data_type,
          user: @user,
          entity: @entity,
          agent: agent,
          execution: execution
        )

        # Calculate data info
        row_count = data.is_a?(Array) ? data.length : nil
        size_bytes = data.to_json.bytesize

        success_response(
          saved: true,
          key: key,
          description: description,
          data_type: data_type,
          row_count: row_count,
          size_bytes: size_bytes,
          expires_at: entry.expires_at.iso8601,
          message: "✅ Saved data to scratchpad as '#{key}'. #{row_count ? "#{row_count} rows, " : ''}#{size_bytes} bytes. Available to all agents in this session."
        )
      rescue => e
        Rails.logger.error "[SaveToScratchpadTool] Error: #{e.message}"
        error_response("Failed to save to scratchpad: #{e.message}")
      end
    end
  end
end

