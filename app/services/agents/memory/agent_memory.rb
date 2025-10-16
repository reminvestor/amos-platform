module Agents
  module Memory
    class AgentMemory
      attr_reader :agent_id, :role

      def initialize(agent_id:, role:)
        @agent_id = agent_id
        @role = role
        @short_term = {}
        @long_term = {}
        @memory_limit = 100 # Keep last 100 items per category
        @redis = Redis.new(url: ENV["REDIS_URL"] || "redis://localhost:6379/1")

        # Load existing long-term memory from Redis
        load_from_persistence
      end

      # Store in short-term memory (volatile)
      def store_short_term(key, value)
        @short_term[key] ||= []
        @short_term[key].unshift({
          value: value,
          timestamp: Time.current,
          context: current_context
        })

        # Limit memory size
        @short_term[key] = @short_term[key].take(@memory_limit)
      end

      # Store in long-term memory (persistent)
      def store_long_term(key, value)
        @long_term[key] ||= []
        @long_term[key].unshift({
          value: value,
          timestamp: Time.current,
          importance: calculate_importance(value),
          access_count: 0
        })

        # Keep only important memories when limit reached
        if @long_term[key].size > @memory_limit
          @long_term[key] = @long_term[key]
            .sort_by { |m| -m[:importance] - (m[:access_count] * 0.1) }
            .take(@memory_limit)
        end

        # Persist to Redis
        persist_key(key)
      end

      # Retrieve recent memories
      def get_recent_memories(limit = 10)
        recent = {}

        # Get from short-term
        @short_term.each do |key, memories|
          recent[key] = memories.take(limit / @short_term.keys.size)
        end

        # Add from long-term if needed
        remaining = limit - recent.values.flatten.size
        if remaining > 0
          @long_term.each do |key, memories|
            next if recent[key]
            recent[key] = memories.take(remaining / @long_term.keys.size)
          end
        end

        recent
      end

      # Get specific long-term memories
      def get_long_term(key)
        memories = @long_term[key] || []

        # Increment access count
        memories.each { |m| m[:access_count] += 1 }

        memories
      end

      # Find memories relevant to a pattern
      def find_relevant_patterns(task)
        patterns = []

        # Search through successful patterns
        if @long_term[:successful_patterns]
          patterns += @long_term[:successful_patterns].select do |pattern|
            pattern_matches?(pattern[:value], task)
          end
        end

        # Search through general patterns
        if @long_term[:patterns]
          patterns += @long_term[:patterns].select do |pattern|
            pattern_matches?(pattern[:value], task)
          end
        end

        # Sort by relevance and recency
        patterns.sort_by do |p|
          relevance = calculate_relevance(p[:value], task)
          recency = (Time.current - p[:timestamp]) / 1.hour
          -(relevance * 10 - recency)
        end
      end

      # Count experiences related to a task
      def count_relevant_experiences(task)
        count = 0

        @long_term.each do |key, memories|
          count += memories.count do |memory|
            task_related?(memory[:value], task)
          end
        end

        count
      end

      # Add a new pattern
      def add_pattern(pattern)
        existing = @long_term[:patterns] || []

        # Check if pattern already exists
        unless existing.any? { |p| p[:value] == pattern }
          store_long_term(:patterns, pattern)
        end
      end

      # Update decision weights based on outcomes
      def update_decision_weights(failure_analysis)
        weights = @long_term[:decision_weights] || {}

        failure_analysis.each do |decision_type, failures|
          weights[decision_type] ||= 1.0

          # Reduce weight for failed decision types
          weights[decision_type] *= (1.0 - 0.1 * failures.size)
          weights[decision_type] = [ weights[decision_type], 0.1 ].max # Min weight of 0.1
        end

        store_long_term(:decision_weights, weights)
      end

      # Get decision weights
      def get_decision_weights
        @long_term[:decision_weights] || {}
      end

      # Consolidate short-term memories into long-term
      def consolidate
        @short_term.each do |key, memories|
          important_memories = memories.select do |memory|
            calculate_importance(memory[:value]) > 0.5
          end

          important_memories.each do |memory|
            store_long_term(key, memory[:value])
          end
        end

        # Clear consolidated short-term memories
        @short_term.clear
      end

      # Persist all long-term memory
      def persist!
        @long_term.each_key do |key|
          persist_key(key)
        end

        # Also save metadata
        @redis.hset(
          "agent_memory:#{@agent_id}",
          "metadata",
          {
            role: @role,
            last_persist: Time.current,
            total_memories: @long_term.values.flatten.size
          }.to_json
        )
      end

      # Forget memories below importance threshold
      def forget_unimportant(threshold = 0.3)
        @long_term.each do |key, memories|
          @long_term[key] = memories.reject do |memory|
            memory[:importance] < threshold && memory[:access_count] < 5
          end
        end

        persist!
      end

      private

      def current_context
        {
          agent_id: @agent_id,
          role: @role,
          timestamp: Time.current
        }
      end

      def calculate_importance(value)
        score = 0.5 # Base importance

        # Increase importance based on content
        case value
        when Hash
          score += 0.1 if value[:success]
          score += 0.2 if value[:error] || value[:failure]
          score += 0.1 if value[:learned]
          score += 0.1 if value[:pattern]
        when String
          score += 0.1 if value.include?("error") || value.include?("fail")
          score += 0.1 if value.include?("success")
          score += 0.2 if value.include?("important") || value.include?("critical")
        end

        [ score, 1.0 ].min
      end

      def pattern_matches?(pattern, task)
        return false unless pattern.is_a?(Hash) && task.is_a?(Hash)

        # Check type match
        return true if pattern[:type] == task[:type]

        # Check capability overlap
        if pattern[:required_capabilities] && task[:required_capabilities]
          overlap = pattern[:required_capabilities] & task[:required_capabilities]
          return true if overlap.any?
        end

        # Check description similarity
        if pattern[:description] && task[:description]
          return true if similar_descriptions?(pattern[:description], task[:description])
        end

        false
      end

      def task_related?(memory_value, task)
        return false unless memory_value.is_a?(Hash) && task.is_a?(Hash)

        # Check if memory is about similar task
        if memory_value[:task]
          return pattern_matches?(memory_value[:task], task)
        end

        # Check if memory contains relevant action
        if memory_value[:action] && task[:required_capabilities]
          action_type = memory_value[:action][:type]
          return task[:required_capabilities].any? { |cap| cap.to_s.include?(action_type.to_s) }
        end

        false
      end

      def calculate_relevance(pattern, task)
        relevance = 0.0

        # Type match is highly relevant
        relevance += 0.5 if pattern[:type] == task[:type]

        # Capability overlap
        if pattern[:required_capabilities] && task[:required_capabilities]
          overlap = pattern[:required_capabilities] & task[:required_capabilities]
          relevance += 0.3 * (overlap.size.to_f / task[:required_capabilities].size)
        end

        # Context similarity
        if pattern[:context] && task[:context]
          context_match = (pattern[:context].keys & task[:context].keys).size
          relevance += 0.2 * (context_match.to_f / task[:context].keys.size)
        end

        relevance
      end

      def similar_descriptions?(desc1, desc2)
        return false unless desc1 && desc2

        # Simple word overlap similarity
        words1 = desc1.downcase.split(/\W+/)
        words2 = desc2.downcase.split(/\W+/)

        common_words = words1 & words2
        total_words = (words1 + words2).uniq.size

        similarity = common_words.size.to_f / total_words
        similarity > 0.3
      end

      def persist_key(key)
        return if @long_term[key].nil? || @long_term[key].empty?

        @redis.hset(
          "agent_memory:#{@agent_id}",
          key.to_s,
          @long_term[key].to_json
        )
      rescue => e
        Rails.logger.error "Failed to persist memory key #{key}: #{e.message}"
      end

      def load_from_persistence
        memories = @redis.hgetall("agent_memory:#{@agent_id}")

        memories.each do |key, value|
          next if key == "metadata"

          begin
            @long_term[key.to_sym] = JSON.parse(value, symbolize_names: true)

            # Convert timestamp strings back to Time objects
            @long_term[key.to_sym].each do |memory|
              memory[:timestamp] = Time.parse(memory[:timestamp]) if memory[:timestamp].is_a?(String)
            end
          rescue => e
            Rails.logger.error "Failed to load memory key #{key}: #{e.message}"
          end
        end
      rescue => e
        Rails.logger.error "Failed to load agent memory: #{e.message}"
      end
    end
  end
end
