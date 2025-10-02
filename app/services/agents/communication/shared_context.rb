module Agents
  module Communication
    class SharedContext
      attr_reader :task_session_id
      
      def initialize(initial_context = {})
        @task_session_id = initial_context[:task_session_id]
        @redis = Redis.new(url: ENV['REDIS_URL'] || 'redis://localhost:6379/1')
        @local_cache = initial_context.dup
        @subscriptions = {}
        @mutex = Mutex.new
        
        # Subscribe to context updates
        start_subscription_thread if @task_session_id
      end
      
      # Write to shared context
      def write(key, value, agent_id)
        data = {
          value: value,
          agent_id: agent_id,
          timestamp: Time.current.to_f,
          version: next_version(key)
        }
        
        # Update local cache
        @mutex.synchronize do
          @local_cache[key] = data
        end
        
        # Persist to Redis if we have a task session
        if @task_session_id
          redis_key = context_key(key)
          @redis.set(redis_key, data.to_json, ex: 24.hours.to_i)
          
          # Publish update event
          publish_update(key, data)
        end
        
        # Notify local subscribers
        notify_subscribers(key, data)
        
        data
      end
      
      # Read from shared context
      def read(key)
        # Try local cache first
        @mutex.synchronize do
          if @local_cache.key?(key)
            return @local_cache[key][:value]
          end
        end
        
        # Try Redis if we have a task session
        if @task_session_id
          redis_key = context_key(key)
          if data = @redis.get(redis_key)
            parsed = JSON.parse(data, symbolize_names: true)
            
            # Update local cache
            @mutex.synchronize do
              @local_cache[key] = parsed
            end
            
            return parsed[:value]
          end
        end
        
        nil
      end
      
      # Alias for read to maintain consistency
      alias_method :get, :read
      
      # Read all context
      def read_all
        # Get all keys from Redis if we have a task session
        if @task_session_id
          pattern = "context:#{@task_session_id}:*"
          redis_keys = @redis.keys(pattern)
          
          redis_keys.each do |redis_key|
            key = redis_key.split(':').last
            next if @local_cache.key?(key.to_sym)
            
            if data = @redis.get(redis_key)
              parsed = JSON.parse(data, symbolize_names: true)
              @mutex.synchronize do
                @local_cache[key.to_sym] = parsed
              end
            end
          end
        end
        
        # Return values from cache
        @mutex.synchronize do
          @local_cache.transform_values { |data| data[:value] }
        end
      end
      
      # Subscribe to context changes
      def subscribe(pattern, agent_id, &callback)
        @mutex.synchronize do
          @subscriptions[pattern] ||= []
          @subscriptions[pattern] << {
            agent_id: agent_id,
            callback: callback,
            pattern: pattern
          }
        end
      end
      
      # Unsubscribe from context changes
      def unsubscribe(pattern, agent_id)
        @mutex.synchronize do
          if @subscriptions[pattern]
            @subscriptions[pattern].reject! { |sub| sub[:agent_id] == agent_id }
            @subscriptions.delete(pattern) if @subscriptions[pattern].empty?
          end
        end
      end
      
      # Get context metadata
      def metadata(key)
        @mutex.synchronize do
          if data = @local_cache[key]
            {
              agent_id: data[:agent_id],
              timestamp: data[:timestamp],
              version: data[:version]
            }
          end
        end
      end
      
      # Get context history
      def history(key, limit = 10)
        return [] unless @task_session_id
        
        history_key = "#{context_key(key)}:history"
        history_data = @redis.lrange(history_key, 0, limit - 1)
        
        history_data.map { |data| JSON.parse(data, symbolize_names: true) }
      rescue => e
        Rails.logger.error "Failed to get context history: #{e.message}"
        []
      end
      
      # Clear context
      def clear!
        @mutex.synchronize do
          @local_cache.clear
        end
        
        if @task_session_id
          pattern = "context:#{@task_session_id}:*"
          redis_keys = @redis.keys(pattern)
          @redis.del(*redis_keys) if redis_keys.any?
        end
      end
      
      # Atomic compare and swap
      def compare_and_swap(key, expected_value, new_value, agent_id)
        @mutex.synchronize do
          current = @local_cache[key]
          
          if current && current[:value] == expected_value
            write(key, new_value, agent_id)
            true
          else
            false
          end
        end
      end
      
      # Get keys matching pattern
      def keys_matching(pattern)
        regex = Regexp.new(pattern.gsub('*', '.*'))
        
        @mutex.synchronize do
          @local_cache.keys.select { |key| key.to_s =~ regex }
        end
      end
      
      # Cleanup old entries
      def cleanup(older_than: 1.hour)
        cutoff = Time.current - older_than
        
        @mutex.synchronize do
          @local_cache.delete_if do |key, data|
            Time.at(data[:timestamp]) < cutoff
          end
        end
      end
      
      private
      
      def context_key(key)
        "context:#{@task_session_id}:#{key}"
      end
      
      def next_version(key)
        if current = @local_cache[key]
          current[:version] + 1
        else
          1
        end
      end
      
      def publish_update(key, data)
        channel = "context:#{@task_session_id}:updates"
        message = {
          key: key,
          data: data,
          task_session_id: @task_session_id
        }
        
        @redis.publish(channel, message.to_json)
        
        # Also store in history
        history_key = "#{context_key(key)}:history"
        @redis.lpush(history_key, data.to_json)
        @redis.ltrim(history_key, 0, 99) # Keep last 100 versions
        @redis.expire(history_key, 24.hours.to_i)
      rescue => e
        Rails.logger.error "Failed to publish context update: #{e.message}"
      end
      
      def notify_subscribers(key, data)
        @mutex.synchronize do
          @subscriptions.each do |pattern, subscribers|
            if key.to_s =~ Regexp.new(pattern.gsub('*', '.*'))
              subscribers.each do |sub|
                begin
                  sub[:callback].call(key, data)
                rescue => e
                  Rails.logger.error "Subscriber callback failed: #{e.message}"
                end
              end
            end
          end
        end
      end
      
      def start_subscription_thread
        Thread.new do
          begin
            redis_sub = Redis.new(url: ENV['REDIS_URL'] || 'redis://localhost:6379/1')
            channel = "context:#{@task_session_id}:updates"
            
            redis_sub.subscribe(channel) do |on|
              on.message do |_, message|
                begin
                  update = JSON.parse(message, symbolize_names: true)
                  
                  # Update local cache if it's not our own update
                  if update[:data][:agent_id] != Thread.current[:agent_id]
                    @mutex.synchronize do
                      @local_cache[update[:key]] = update[:data]
                    end
                    
                    # Notify subscribers
                    notify_subscribers(update[:key], update[:data])
                  end
                rescue => e
                  Rails.logger.error "Failed to process context update: #{e.message}"
                end
              end
            end
          rescue => e
            Rails.logger.error "Context subscription thread failed: #{e.message}"
          end
        end
      end
    end
  end
end




