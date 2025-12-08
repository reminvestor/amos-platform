module Tools
  class RetrieveHistoryTool < BaseTool
    def self.read_only?
      true
    end

    def self.metadata
      {
        name: 'retrieve_history',
        description: 'Retrieve conversation messages from unified memory. Queries your full conversation history - including past sessions. Use when user references something from earlier or asks about past conversations.',
        category: 'memory',
        input_schema: {
          type: 'object',
          properties: {
            count: {
              type: 'integer',
              description: 'Number of recent messages to retrieve (default: 20, max: 100).'
            },
            offset: {
              type: 'integer',
              description: 'Skip this many recent messages (for pagination). Default: 0.'
            }
          }
        }
      }
    end

    def execute(args)
      log_execution(args)

      count = [get_arg(args, :count, 20), 100].min
      offset = get_arg(args, :offset, 0)

      begin
        unless @user && @entity
          return error_response("User context not available")
        end

        # Use unified memory system
        memory = Scout::UnifiedMemory.new(user: @user, entity: @entity)
        messages = memory.fetch_l2_messages(count: count, offset: offset)
        
        # Get total count
        total_messages = ScoutMessage.where(user_id: @user.id, entity_id: @entity.id).count

        # Format messages
        formatted_messages = messages.map.with_index(1) do |msg, idx|
          {
            index: total_messages - offset - count + idx,
            role: msg[:role],
            content: msg[:content].to_s.truncate(500),
            timestamp: msg[:timestamp]
          }
        end

        success_response(
          messages: formatted_messages,
          count: formatted_messages.length,
          total_messages: total_messages
        )

      rescue => e
        Rails.logger.error "History retrieval failed: #{e.message}"
        Rails.logger.error e.backtrace.first(5).join("\n")
        error_response("Failed to retrieve history: #{e.message}")
      end
    end
  end
end
