module Tools
  class RetrieveHistoryTool < BaseTool
    def self.read_only?
      true
    end

    def self.metadata
      {
        name: 'retrieve_history',
        description: 'Retrieve older conversation messages that are not in your current active context. Use this when the user references something from earlier in the conversation that you do not have in your recent message history. You can retrieve messages by range (start/end index) or get the last N messages.',
        category: 'memory',
        input_schema: {
          type: 'object',
          properties: {
            start_index: {
              type: 'integer',
              description: 'Starting message index (1-based). If not provided with end_index, will retrieve last N messages using count parameter instead.'
            },
            end_index: {
              type: 'integer',
              description: 'Ending message index (1-based, inclusive). Use with start_index to get a specific range.'
            },
            count: {
              type: 'integer',
              description: 'Number of recent messages to retrieve (default: 20). Used when start_index/end_index not provided.'
            }
          }
        }
      }
    end

    def execute(args)
      log_execution(args)

      start_index = get_arg(args, :start_index)
      end_index = get_arg(args, :end_index)
      count = get_arg(args, :count, 20)

      begin
        # Get session_id from context
        session_id = context[:session_id]

        unless session_id
          return error_response("Session ID not available in context")
        end

        # Initialize memory tools
        memory = Scout::MemoryTools.new(session_id)

        # Check Redis availability
        unless memory.redis_available?
          return error_response("Conversation history storage is currently unavailable")
        end

        # Retrieve messages
        messages = if start_index && end_index
          memory.retrieve_history(start_index: start_index, end_index: end_index)
        else
          memory.retrieve_history(count: count)
        end

        # Format messages for response
        formatted_messages = messages.map do |msg|
          {
            index: msg[:index],
            role: msg[:role],
            content: msg[:content],
            timestamp: msg[:timestamp]
          }
        end

        success_response(
          messages: formatted_messages,
          count: formatted_messages.length,
          total_messages: memory.get_message_count
        )

      rescue => e
        Rails.logger.error "History retrieval failed: #{e.message}"
        Rails.logger.error e.backtrace.join("\n")
        error_response("Failed to retrieve history: #{e.message}")
      end
    end
  end
end
