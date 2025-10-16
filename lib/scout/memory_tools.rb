# Scout Memory Tools - Conversation History Management
# Provides tools for Scout to retrieve older messages from Redis storage
# when it needs additional context beyond the active 20-message window

module Scout
  class MemoryTools
    ACTIVE_WINDOW_SIZE = 20  # Last N messages kept in active conversation
    MAX_HISTORY_SIZE = 1000  # Maximum messages to store in Redis
    SESSION_TTL = 7200       # 2 hours in seconds

    def initialize(session_id, redis_client = nil)
      @session_id = session_id
      @redis = redis_client || $redis
    end

    # ==========================================
    # TOOL DEFINITIONS FOR BEDROCK
    # ==========================================

    def self.tool_definitions
      [
        {
          name: 'retrieve_history',
          description: 'Retrieve older conversation messages that are not in your current active context. Use this when the user references something from earlier in the conversation that you do not have in your recent message history. You can retrieve messages by range (start/end index) or get the last N messages.',
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
        },
        {
          name: 'get_message_count',
          description: 'Get the total number of messages in the conversation. Use this to understand how much conversation history exists beyond your active context window.',
          input_schema: {
            type: 'object',
            properties: {}
          }
        },
        {
          name: 'search_history',
          description: 'Search through conversation history for messages containing specific keywords. Use this when the user asks about a specific topic discussed earlier and you want to find relevant messages.',
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
      ]
    end

    # ==========================================
    # REDIS STORAGE OPERATIONS
    # ==========================================

    # Store a message incrementally as conversation progresses
    def store_message(role, content, metadata = {})
      return false unless @redis && content.present?

      begin
        # Get current message count
        count = get_message_count

        # Don't exceed max history size
        if count >= MAX_HISTORY_SIZE
          # Remove oldest message
          @redis.lrem(messages_key, 1, @redis.lindex(messages_key, 0))
        end

        # Create message object
        message = {
          index: count + 1,
          role: role,
          content: content,
          timestamp: Time.current.iso8601,
          metadata: metadata
        }.to_json

        # Push to Redis list (RPUSH adds to end)
        @redis.rpush(messages_key, message)

        # Update message count
        @redis.set(count_key, count + 1)

        # Set/refresh TTL on both keys
        @redis.expire(messages_key, SESSION_TTL)
        @redis.expire(count_key, SESSION_TTL)

        true
      rescue Redis::BaseError => e
        Rails.logger.error "Failed to store message in Redis: #{e.message}"
        false
      end
    end

    # Retrieve messages by range (1-based indexing)
    def retrieve_history(start_index: nil, end_index: nil, count: nil)
      return [] unless @redis

      begin
        total_count = get_message_count

        # Determine range to fetch
        if start_index && end_index
          # Validate range
          start_index = [start_index, 1].max
          end_index = [end_index, total_count].min

          # Convert to 0-based for Redis LRANGE
          redis_start = start_index - 1
          redis_end = end_index - 1
        elsif count
          # Get last N messages
          count = [count, total_count].min
          redis_start = -count
          redis_end = -1
        else
          # Default to last 20 messages
          count = [ACTIVE_WINDOW_SIZE, total_count].min
          redis_start = -count
          redis_end = -1
        end

        # Fetch messages from Redis
        messages_json = @redis.lrange(messages_key, redis_start, redis_end)

        # Parse and return
        messages_json.map { |msg| JSON.parse(msg).with_indifferent_access }
      rescue Redis::BaseError => e
        Rails.logger.error "Failed to retrieve history from Redis: #{e.message}"
        []
      rescue JSON::ParserError => e
        Rails.logger.error "Failed to parse message JSON: #{e.message}"
        []
      end
    end

    # Get total message count
    def get_message_count
      return 0 unless @redis

      begin
        count = @redis.get(count_key)
        count ? count.to_i : 0
      rescue Redis::BaseError => e
        Rails.logger.error "Failed to get message count: #{e.message}"
        0
      end
    end

    # Search for messages containing keywords
    def search_history(keywords:, role: nil, max_results: 10)
      return [] unless @redis && keywords.present?

      begin
        # Get all messages
        all_messages = retrieve_history(count: MAX_HISTORY_SIZE)

        # Filter by keywords (case-insensitive)
        keyword_pattern = Regexp.new(Regexp.escape(keywords), Regexp::IGNORECASE)

        matching_messages = all_messages.select do |msg|
          matches_keyword = msg[:content].match?(keyword_pattern)
          matches_role = role.nil? || msg[:role] == role
          matches_keyword && matches_role
        end

        # Limit results
        matching_messages.first(max_results)
      rescue Redis::BaseError => e
        Rails.logger.error "Failed to search history: #{e.message}"
        []
      end
    end

    # ==========================================
    # SESSION MANAGEMENT
    # ==========================================

    # Clear all messages for this session
    def clear_session
      return false unless @redis

      begin
        @redis.del(messages_key)
        @redis.del(count_key)
        true
      rescue Redis::BaseError => e
        Rails.logger.error "Failed to clear session: #{e.message}"
        false
      end
    end

    # Get full conversation history (admin/debugging)
    def get_full_history
      retrieve_history(count: MAX_HISTORY_SIZE)
    end

    # Check if Redis is available
    def redis_available?
      return false unless @redis

      begin
        @redis.ping == 'PONG'
      rescue Redis::BaseError
        false
      end
    end

    # Get session statistics
    def session_stats
      {
        session_id: @session_id,
        total_messages: get_message_count,
        redis_available: redis_available?,
        ttl_remaining: redis_ttl
      }
    end

    private

    def messages_key
      "scout:#{@session_id}:messages"
    end

    def count_key
      "scout:#{@session_id}:message_count"
    end

    def redis_ttl
      return nil unless @redis

      begin
        ttl = @redis.ttl(messages_key)
        ttl > 0 ? ttl : nil
      rescue Redis::BaseError
        nil
      end
    end
  end
end
