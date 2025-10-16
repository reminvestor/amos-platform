module Tools
  class GetMessageCountTool < BaseTool
    def self.read_only?
      true
    end

    def self.metadata
      {
        name: 'get_message_count',
        description: 'Get the total number of messages in the conversation. Use this to understand how much conversation history exists beyond your active context window.',
        category: 'memory',
        input_schema: {
          type: 'object',
          properties: {}
        }
      }
    end

    def execute(args)
      log_execution(args)

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

        # Get message count and stats
        total_count = memory.get_message_count
        stats = memory.session_stats

        success_response(
          total_messages: total_count,
          active_window_size: Scout::MemoryTools::ACTIVE_WINDOW_SIZE,
          messages_beyond_window: [total_count - Scout::MemoryTools::ACTIVE_WINDOW_SIZE, 0].max,
          session_stats: stats
        )

      rescue => e
        Rails.logger.error "Message count retrieval failed: #{e.message}"
        error_response("Failed to get message count: #{e.message}")
      end
    end
  end
end
