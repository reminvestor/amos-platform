module Tools
  class SearchHistoryTool < BaseTool
    def self.read_only?
      true
    end

    def self.metadata
      {
        name: 'search_history',
        description: 'Search through conversation history for messages containing specific keywords. Use this when the user asks about a specific topic discussed earlier and you want to find relevant messages.',
        category: 'memory',
        input_schema: {
          type: 'object',
          properties: {
            keywords: {
              type: 'string',
              description: 'Keywords or phrase to search for in message content'
            },
            role: {
              type: 'string',
              description: 'Filter by message role: "user", "assistant", or omit for all messages',
              enum: ['user', 'assistant']
            },
            max_results: {
              type: 'integer',
              description: 'Maximum number of matching messages to return (default: 10)'
            }
          },
          required: ['keywords']
        }
      }
    end

    def execute(args)
      log_execution(args)

      keywords = get_arg(args, :keywords)
      role = get_arg(args, :role)
      max_results = get_arg(args, :max_results, 10)

      # Validate required args
      if error = validate_required_args(args, [:keywords])
        return error
      end

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

        # Search history
        matching_messages = memory.search_history(
          keywords: keywords,
          role: role,
          max_results: max_results
        )

        # Format results
        formatted_results = matching_messages.map do |msg|
          {
            index: msg[:index],
            role: msg[:role],
            content: msg[:content],
            timestamp: msg[:timestamp]
          }
        end

        success_response(
          keywords: keywords,
          matches: formatted_results,
          match_count: formatted_results.length,
          total_messages: memory.get_message_count
        )

      rescue => e
        Rails.logger.error "History search failed: #{e.message}"
        error_response("Failed to search history: #{e.message}")
      end
    end
  end
end
