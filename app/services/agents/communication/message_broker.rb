module Agents
  module Communication
    class MessageBroker
      include Singleton
      
      def initialize
        @queues = {}
        @mutex = Mutex.new
        @redis = $redis || Redis.new(url: ENV['REDIS_URL'] || 'redis://localhost:6379/1')
        @delivery_threads = {}
      end
      
      # Deliver a message to an agent
      def deliver(from:, to:, content:, priority: :normal)
        message = {
          id: SecureRandom.uuid,
          from: from,
          to: to,
          content: content,
          priority: priority,
          timestamp: Time.current.to_f,
          delivery_attempts: 0
        }
        
        # Add to queue
        enqueue_message(to, message)
        
        # Start delivery thread if needed
        ensure_delivery_thread(to)
        
        # Log delivery
        Rails.logger.debug "Message queued: #{from} -> #{to} (#{content[:type] rescue 'unknown'})"
        
        message[:id]
      end
      
      # Check messages for an agent (non-blocking)
      def check_messages(agent_id, limit = 10)
        messages = []
        
        @mutex.synchronize do
          queue = @queues[agent_id] || []
          
          # Get high priority messages first
          high_priority = queue.select { |m| m[:priority] == :high }.take(limit)
          messages.concat(high_priority)
          
          # Then normal priority
          remaining = limit - messages.size
          if remaining > 0
            normal_priority = queue.select { |m| m[:priority] == :normal }.take(remaining)
            messages.concat(normal_priority)
          end
          
          # Remove retrieved messages from queue
          @queues[agent_id] = queue - messages
        end
        
        # Also check Redis for persistent messages
        if messages.size < limit
          redis_messages = check_redis_messages(agent_id, limit - messages.size)
          messages.concat(redis_messages)
        end
        
        messages
      end
      
      # Wait for messages (blocking)
      def wait_for_message(agent_id, timeout = 5)
        deadline = Time.current + timeout
        
        while Time.current < deadline
          messages = check_messages(agent_id, 1)
          return messages.first if messages.any?
          
          sleep(0.1)
        end
        
        nil
      end
      
      # Subscribe to message patterns
      def subscribe(agent_id, pattern, &callback)
        subscription_key = "subscriptions:#{agent_id}"
        
        @redis.hset(subscription_key, pattern, {
          callback_id: SecureRandom.uuid,
          created_at: Time.current
        }.to_json)
        
        # Start subscription thread
        start_subscription_thread(agent_id, pattern, callback)
      end
      
      # Unsubscribe from pattern
      def unsubscribe(agent_id, pattern)
        subscription_key = "subscriptions:#{agent_id}"
        @redis.hdel(subscription_key, pattern)
      end
      
      # Send broadcast message
      def broadcast(from:, content:, target_roles: nil, target_capabilities: nil)
        recipients = if target_roles || target_capabilities
          find_targeted_recipients(target_roles, target_capabilities)
        else
          AgentRegistry.active_agents.map(&:id)
        end
        
        recipients.each do |recipient_id|
          deliver(from: from, to: recipient_id, content: content)
        end
        
        Rails.logger.info "Broadcast sent from #{from} to #{recipients.size} agents"
      end
      
      # Get message statistics
      def statistics
        @mutex.synchronize do
          stats = {
            total_queues: @queues.size,
            total_messages: @queues.values.flatten.size,
            messages_by_priority: count_by_priority,
            oldest_message_age: oldest_message_age
          }
          
          # Add per-agent stats
          @queues.each do |agent_id, queue|
            stats["agent_#{agent_id}_queue_size"] = queue.size
          end
          
          stats
        end
      end
      
      # Clear messages for an agent
      def clear_messages(agent_id)
        @mutex.synchronize do
          @queues.delete(agent_id)
        end
        
        # Also clear from Redis
        @redis.del("messages:#{agent_id}")
      end
      
      # Retry failed deliveries
      def retry_failed_deliveries
        pattern = "failed_messages:*"
        failed_keys = @redis.keys(pattern)
        
        retried_count = 0
        
        failed_keys.each do |key|
          message_data = @redis.get(key)
          next unless message_data
          
          message = JSON.parse(message_data, symbolize_names: true)
          
          # Check if we should retry
          if message[:delivery_attempts] < 3
            message[:delivery_attempts] += 1
            deliver(
              from: message[:from],
              to: message[:to],
              content: message[:content],
              priority: :high # Boost priority for retries
            )
            
            @redis.del(key)
            retried_count += 1
          end
        end
        
        Rails.logger.info "Retried #{retried_count} failed message deliveries"
      end
      
      private
      
      def enqueue_message(agent_id, message)
        @mutex.synchronize do
          @queues[agent_id] ||= []
          
          # Insert based on priority
          if message[:priority] == :high
            # Find first non-high priority message
            insert_index = @queues[agent_id].find_index { |m| m[:priority] != :high } || @queues[agent_id].size
            @queues[agent_id].insert(insert_index, message)
          else
            @queues[agent_id] << message
          end
          
          # Limit queue size
          if @queues[agent_id].size > 1000
            overflow = @queues[agent_id].pop(100) # Remove oldest 100
            persist_overflow(agent_id, overflow)
          end
        end
      end
      
      def ensure_delivery_thread(agent_id)
        return if @delivery_threads[agent_id]&.alive?
        
        @delivery_threads[agent_id] = Thread.new do
          begin
            process_deliveries(agent_id)
          rescue => e
            Rails.logger.error "Delivery thread error for agent #{agent_id}: #{e.message}"
          ensure
            @delivery_threads.delete(agent_id)
          end
        end
      end
      
      def process_deliveries(agent_id)
        agent = AgentRegistry.get_agent(agent_id)
        return unless agent
        
        loop do
          messages = check_messages(agent_id, 5)
          break if messages.empty?
          
          messages.each do |message|
            begin
              # Convert message format for agent
              agent_message = AgentMessage.new(
                id: message[:id],
                sender_id: message[:from],
                recipient_id: message[:to],
                message_type: message[:content][:type] || 'general',
                content: message[:content],
                task_session_id: agent.task_session&.id
              )
              
              # Deliver to agent
              agent.handle_message(agent_message)
              
              # Log successful delivery
              log_delivery(message, :success)
              
            rescue => e
              Rails.logger.error "Failed to deliver message to agent #{agent_id}: #{e.message}"
              handle_delivery_failure(message, e)
            end
          end
          
          # Small delay to prevent tight loops
          sleep(0.1)
        end
      end
      
      def check_redis_messages(agent_id, limit)
        key = "messages:#{agent_id}"
        messages_data = @redis.lrange(key, 0, limit - 1)
        
        return [] if messages_data.empty?
        
        # Remove retrieved messages
        @redis.ltrim(key, limit, -1)
        
        # Parse messages
        messages_data.map do |data|
          JSON.parse(data, symbolize_names: true)
        rescue
          nil
        end.compact
      end
      
      def persist_overflow(agent_id, messages)
        key = "messages:#{agent_id}"
        
        messages.each do |message|
          @redis.rpush(key, message.to_json)
        end
        
        # Set expiry
        @redis.expire(key, 24.hours.to_i)
      end
      
      def find_targeted_recipients(target_roles, target_capabilities)
        recipients = []
        
        if target_roles
          target_roles.each do |role|
            agents = AgentRegistry.find_by_role(role)
            recipients.concat(agents.map(&:id))
          end
        end
        
        if target_capabilities
          agents = AgentRegistry.find_by_capabilities(target_capabilities)
          recipients.concat(agents.map(&:id))
        end
        
        recipients.uniq
      end
      
      def count_by_priority
        counts = { high: 0, normal: 0, low: 0 }
        
        @queues.values.flatten.each do |message|
          priority = message[:priority] || :normal
          counts[priority] += 1
        end
        
        counts
      end
      
      def oldest_message_age
        oldest_timestamp = @queues.values.flatten
                                  .map { |m| m[:timestamp] }
                                  .min
        
        return nil unless oldest_timestamp
        
        Time.current.to_f - oldest_timestamp
      end
      
      def log_delivery(message, status)
        ObservabilityService.instance.track_event(
          'message.delivered',
          {
            message_id: message[:id],
            from: message[:from],
            to: message[:to],
            status: status,
            delivery_time: Time.current.to_f - message[:timestamp],
            attempts: message[:delivery_attempts]
          }
        )
      end
      
      def handle_delivery_failure(message, error)
        message[:delivery_attempts] += 1
        
        if message[:delivery_attempts] >= 3
          # Move to failed messages
          key = "failed_messages:#{message[:id]}"
          @redis.setex(key, 24.hours.to_i, message.to_json)
          
          log_delivery(message, :failed)
        else
          # Re-queue with delay
          Thread.new do
            sleep(message[:delivery_attempts] * 2) # Exponential backoff
            enqueue_message(message[:to], message)
          end
        end
      end
      
      def start_subscription_thread(agent_id, pattern, callback)
        Thread.new do
          redis_sub = Redis.new(url: ENV['REDIS_URL'] || 'redis://localhost:6379/1')
          channel = "messages:pattern:#{pattern}"
          
          redis_sub.subscribe(channel) do |on|
            on.message do |_, message_data|
              begin
                message = JSON.parse(message_data, symbolize_names: true)
                
                # Check if message matches agent's subscription
                if message[:to] == agent_id || message[:to] == 'broadcast'
                  callback.call(message)
                end
              rescue => e
                Rails.logger.error "Subscription callback error: #{e.message}"
              end
            end
          end
        end
      end
      
      class << self
        # Convenience methods
        def deliver(from:, to:, content:, priority: :normal)
          instance.deliver(from: from, to: to, content: content, priority: priority)
        end
        
        def check_messages(agent_id, limit = 10)
          instance.check_messages(agent_id, limit)
        end
        
        def broadcast(from:, content:, target_roles: nil, target_capabilities: nil)
          instance.broadcast(
            from: from,
            content: content,
            target_roles: target_roles,
            target_capabilities: target_capabilities
          )
        end
      end
    end
  end
end
