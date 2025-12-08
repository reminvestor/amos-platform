module Tools
  class SearchHistoryTool < BaseTool
    def self.read_only?
      true
    end

    def self.metadata
      {
        name: 'search_history',
        description: 'Search through unified memory for messages containing specific keywords. Searches all past conversations - not just the current session.',
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
      max_results = [get_arg(args, :max_results, 10), 50].min

      if error = validate_required_args(args, [:keywords])
        return error
      end

      begin
        unless @user && @entity
          return error_response("User context not available")
        end

        # Use unified memory system
        memory = Scout::UnifiedMemory.new(user: @user, entity: @entity)
        
        # Search L2 (recent messages with keyword matching)
        keyword_list = keywords.split(/\s+/)
        messages = memory.search_l2(keywords: keyword_list, limit: max_results)
        
        # Filter by role if specified
        messages = messages.select { |m| m[:role] == role } if role.present?

        # Get total count
        total_messages = ScoutMessage.where(user_id: @user.id, entity_id: @entity.id).count

        # Format results
        formatted_results = messages.map do |msg|
          {
            id: msg[:id],
            role: msg[:role],
            content: msg[:content].to_s.truncate(300),
            timestamp: msg[:timestamp]
          }
        end

        success_response(
          keywords: keywords,
          matches: formatted_results,
          match_count: formatted_results.length,
          total_messages: total_messages
        )

      rescue => e
        Rails.logger.error "History search failed: #{e.message}"
        Rails.logger.error e.backtrace.first(5).join("\n")
        error_response("Failed to search history: #{e.message}")
      end
    end
  end
end
