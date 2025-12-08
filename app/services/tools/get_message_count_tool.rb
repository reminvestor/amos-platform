module Tools
  class GetMessageCountTool < BaseTool
    def self.read_only?
      true
    end

    def self.metadata
      {
        name: 'get_message_count',
        description: 'Get the total number of messages in your conversation history. Shows how much history exists beyond your active context window.',
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
        unless @user && @entity
          return error_response("User context not available")
        end

        # Query from unified memory (PostgreSQL)
        total_count = ScoutMessage.where(user_id: @user.id, entity_id: @entity.id).count
        
        # Get memory segment count (L3)
        segment_count = 0
        if defined?(MemorySegment)
          segment_count = MemorySegment.where(user_id: @user.id, entity_id: @entity.id, active: true).count
        end

        success_response(
          total_messages: total_count,
          active_window_size: Scout::UnifiedMemory::L1_SIZE,
          messages_beyond_window: [total_count - Scout::UnifiedMemory::L1_SIZE, 0].max,
          memory_segments: segment_count
        )

      rescue => e
        Rails.logger.error "Message count retrieval failed: #{e.message}"
        error_response("Failed to get message count: #{e.message}")
      end
    end
  end
end
