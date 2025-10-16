module Agents
  module Resilience
    class RetryPolicy
      attr_reader :max_attempts, :backoff_strategy, :retriable_errors

      def initialize(options = {})
        @max_attempts = options[:max_attempts] || 3
        @backoff_strategy = options[:backoff] || :exponential
        @base_delay = options[:base_delay] || 1.0
        @max_delay = options[:max_delay] || 60.0
        @jitter = options[:jitter] != false
        @retriable_errors = options[:retriable_errors] || default_retriable_errors
        @on_retry = options[:on_retry]
        @on_failure = options[:on_failure]

        # For circuit breaker integration
        @circuit_breaker = options[:circuit_breaker]
      end

      # Execute a block with retry logic
      def execute
        attempts = 0
        last_error = nil

        begin
          attempts += 1

          # Execute with circuit breaker if available
          if @circuit_breaker
            @circuit_breaker.call { yield }
          else
            yield
          end

        rescue => error
          last_error = error

          if should_retry?(error, attempts)
            delay = calculate_delay(attempts)

            # Notify retry callback
            @on_retry&.call(error, attempts, delay)

            # Log retry attempt
            Rails.logger.warn "Retry attempt #{attempts}/#{@max_attempts} after #{delay}s delay. Error: #{error.message}"

            # Sleep with jitter
            sleep(delay)

            # Retry
            retry
          else
            # Max attempts reached or non-retriable error
            @on_failure&.call(error, attempts)
            raise
          end
        end
      end

      # Async version using concurrent-ruby
      def execute_async(&block)
        Concurrent::Promise.execute do
          execute(&block)
        end
      end

      private

      def should_retry?(error, attempts)
        return false if attempts >= @max_attempts

        # Check if error is retriable
        @retriable_errors.any? { |klass| error.is_a?(klass) }
      end

      def calculate_delay(attempt)
        delay = case @backoff_strategy
        when :exponential
                  @base_delay * (2 ** (attempt - 1))
        when :linear
                  @base_delay * attempt
        when :constant
                  @base_delay
        when Proc
                  @backoff_strategy.call(attempt)
        else
                  @base_delay
        end

        # Apply max delay cap
        delay = [ delay, @max_delay ].min

        # Add jitter if enabled
        if @jitter
          delay = add_jitter(delay)
        end

        delay
      end

      def add_jitter(delay)
        # Add random jitter up to 25% of the delay
        jitter_range = delay * 0.25
        delay + (rand * jitter_range * 2) - jitter_range
      end

      def default_retriable_errors
        [
          # Network errors
          Net::ReadTimeout,
          Net::OpenTimeout,
          Errno::ECONNREFUSED,
          Errno::ETIMEDOUT,
          Errno::ECONNRESET,

          # AWS errors
          Aws::Errors::ServiceError,

          # Custom errors
          defined?(BedrockService::BedrockError) ? BedrockService::BedrockError : nil,
          defined?(CircuitOpenError) ? CircuitOpenError : nil
        ].compact
      end
    end

    # Retry policy builder for common scenarios
    class RetryPolicyBuilder
      def self.for_api_calls
        RetryPolicy.new(
          max_attempts: 3,
          backoff: :exponential,
          base_delay: 1.0,
          max_delay: 30.0,
          jitter: true
        )
      end

      def self.for_ai_calls
        RetryPolicy.new(
          max_attempts: 2,
          backoff: :exponential,
          base_delay: 2.0,
          max_delay: 60.0,
          jitter: true,
          retriable_errors: [
            Aws::BedrockRuntime::Errors::ThrottlingException,
            Aws::BedrockRuntime::Errors::ServiceUnavailable,
            Net::ReadTimeout
          ]
        )
      end

      def self.for_database
        RetryPolicy.new(
          max_attempts: 3,
          backoff: :linear,
          base_delay: 0.1,
          max_delay: 1.0,
          retriable_errors: [
            ActiveRecord::Deadlocked,
            ActiveRecord::ConnectionTimeoutError,
            PG::ConnectionBad,
            PG::UnableToSend
          ]
        )
      end

      def self.for_webhook
        RetryPolicy.new(
          max_attempts: 5,
          backoff: ->(attempt) { [ 2 ** attempt, 300 ].min },
          jitter: true,
          retriable_errors: [
            Net::HTTPServerError,
            Net::HTTPServiceUnavailable,
            Net::HTTPGatewayTimeout
          ]
        )
      end
    end

    # Convenient module for adding retry support
    module RetrySupport
      def self.included(base)
        base.extend(ClassMethods)
      end

      module ClassMethods
        def retryable(method_name, options = {})
          original_method = instance_method(method_name)

          define_method(method_name) do |*args, &block|
            policy = RetryPolicy.new(options)

            policy.execute do
              original_method.bind(self).call(*args, &block)
            end
          end
        end
      end

      # Instance method for ad-hoc retries
      def with_retry(options = {}, &block)
        policy = RetryPolicy.new(options)
        policy.execute(&block)
      end
    end

    # Retry queue for async retries
    class RetryQueue
      include Singleton

      def initialize
        @queue = Concurrent::Array.new
        @processor = start_processor
      end

      def add(job, retry_policy, metadata = {})
        @queue << {
          job: job,
          policy: retry_policy,
          metadata: metadata,
          attempts: 0,
          added_at: Time.current
        }
      end

      def size
        @queue.size
      end

      def clear
        @queue.clear
      end

      private

      def start_processor
        Thread.new do
          loop do
            process_queue
            sleep 1
          rescue => e
            Rails.logger.error "RetryQueue error: #{e.message}"
          end
        end
      end

      def process_queue
        @queue.each do |item|
          next unless should_process?(item)

          begin
            item[:job].call
            @queue.delete(item)
          rescue => e
            handle_failure(item, e)
          end
        end
      end

      def should_process?(item)
        return true if item[:next_retry_at].nil?

        Time.current >= item[:next_retry_at]
      end

      def handle_failure(item, error)
        item[:attempts] += 1

        if item[:attempts] >= item[:policy].max_attempts
          # Max retries reached
          Rails.logger.error "RetryQueue: Max attempts reached for job: #{item[:metadata]}"
          @queue.delete(item)
        else
          # Schedule next retry
          delay = item[:policy].send(:calculate_delay, item[:attempts])
          item[:next_retry_at] = Time.current + delay

          Rails.logger.info "RetryQueue: Scheduling retry #{item[:attempts]} in #{delay}s"
        end
      end
    end
  end
end
