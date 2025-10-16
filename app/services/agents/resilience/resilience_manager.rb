module Agents
  module Resilience
    class ResilienceManager
      include Singleton

      attr_reader :circuit_breakers, :retry_policies, :bulkheads

      def initialize
        @circuit_breakers = CircuitBreakerRegistry.instance
        @retry_policies = Concurrent::Hash.new
        @bulkheads = Concurrent::Hash.new
        @timeout_policies = Concurrent::Hash.new
        @fallback_handlers = Concurrent::Hash.new

        # Global configuration
        @default_timeout = 30.seconds
        @metrics_collector = MetricsCollector.new

        setup_default_policies
      end

      # Execute with full resilience stack
      def execute(name, options = {}, &block)
        # Get or create policies
        circuit_breaker = get_circuit_breaker(name, options[:circuit_breaker])
        retry_policy = get_retry_policy(name, options[:retry])
        bulkhead = get_bulkhead(name, options[:bulkhead])
        timeout = options[:timeout] || @default_timeout
        fallback = options[:fallback] || @fallback_handlers[name]

        # Start metrics
        start_time = Time.current

        begin
          # Apply bulkhead (connection pooling/rate limiting)
          bulkhead.acquire do
            # Apply timeout
            Timeout.timeout(timeout) do
              # Apply retry policy with circuit breaker
              retry_policy.execute do
                circuit_breaker.call(&block)
              end
            end
          end
        rescue => error
          # Record failure metrics
          @metrics_collector.record_failure(name, error, Time.current - start_time)

          # Try fallback if available
          if fallback
            Rails.logger.info "Executing fallback for #{name}"
            return fallback.call(error)
          end

          raise
        else
          # Record success metrics
          @metrics_collector.record_success(name, Time.current - start_time)
        end
      end

      # Async execution with resilience
      def execute_async(name, options = {}, &block)
        Concurrent::Promise.execute do
          execute(name, options, &block)
        end
      end

      # Configure a service with resilience policies
      def configure_service(name, config = {})
        # Circuit breaker config
        if cb_config = config[:circuit_breaker]
          @circuit_breakers.get(name, cb_config)
        end

        # Retry policy config
        if retry_config = config[:retry]
          @retry_policies[name] = build_retry_policy(retry_config)
        end

        # Bulkhead config
        if bulkhead_config = config[:bulkhead]
          @bulkheads[name] = build_bulkhead(name, bulkhead_config)
        end

        # Timeout config
        if timeout = config[:timeout]
          @timeout_policies[name] = timeout
        end

        # Fallback handler
        if fallback = config[:fallback]
          @fallback_handlers[name] = fallback
        end
      end

      # Get service health status
      def health_status
        {
          circuit_breakers: @circuit_breakers.status,
          bulkheads: bulkhead_status,
          metrics: @metrics_collector.summary
        }
      end

      # Reset all circuit breakers
      def reset_all
        @circuit_breakers.reset_all
        @bulkheads.each_value(&:reset)
      end

      private

      def setup_default_policies
        # Configure common services
        configure_service("bedrock_api", {
          circuit_breaker: {
            failure_threshold: 3,
            timeout: 30.seconds
          },
          retry: {
            max_attempts: 2,
            backoff: :exponential
          },
          bulkhead: {
            max_concurrent: 10,
            max_wait_time: 5.seconds
          },
          timeout: 120.seconds
        })

        configure_service("stripe_api", {
          circuit_breaker: {
            failure_threshold: 5,
            timeout: 60.seconds
          },
          retry: {
            max_attempts: 3,
            backoff: :exponential
          },
          bulkhead: {
            max_concurrent: 20
          },
          timeout: 30.seconds
        })

        configure_service("database", {
          retry: {
            max_attempts: 3,
            backoff: :linear,
            base_delay: 0.1
          },
          bulkhead: {
            max_concurrent: 50
          },
          timeout: 10.seconds
        })
      end

      def get_circuit_breaker(name, config = nil)
        if config
          @circuit_breakers.get(name, config)
        else
          @circuit_breakers.get(name)
        end
      end

      def get_retry_policy(name, config = nil)
        if config
          build_retry_policy(config)
        else
          @retry_policies[name] || RetryPolicy.new
        end
      end

      def get_bulkhead(name, config = nil)
        if config
          build_bulkhead(name, config)
        else
          @bulkheads[name] || Bulkhead.new(name)
        end
      end

      def build_retry_policy(config)
        case config
        when Symbol
          RetryPolicyBuilder.send("for_#{config}")
        when Hash
          RetryPolicy.new(config)
        else
          RetryPolicy.new
        end
      end

      def build_bulkhead(name, config)
        Bulkhead.new(name, config)
      end

      def bulkhead_status
        @bulkheads.transform_values(&:status)
      end
    end

    # Bulkhead pattern for resource isolation
    class Bulkhead
      attr_reader :name, :max_concurrent, :max_wait_time

      def initialize(name, options = {})
        @name = name
        @max_concurrent = options[:max_concurrent] || 10
        @max_wait_time = options[:max_wait_time] || 5.seconds
        @semaphore = Concurrent::Semaphore.new(@max_concurrent)
        @queue_size = Concurrent::AtomicFixnum.new(0)
        @active_count = Concurrent::AtomicFixnum.new(0)
        @rejected_count = Concurrent::AtomicFixnum.new(0)
      end

      def acquire
        start_time = Time.current
        acquired = false

        @queue_size.increment

        begin
          acquired = @semaphore.try_acquire(1, @max_wait_time)

          if acquired
            @active_count.increment
            yield
          else
            @rejected_count.increment
            raise BulkheadRejectedError, "Bulkhead '#{@name}' rejected - max concurrent requests reached"
          end
        ensure
          @queue_size.decrement

          if acquired
            @active_count.decrement
            @semaphore.release(1)
          end
        end
      end

      def status
        {
          active: @active_count.value,
          queued: @queue_size.value,
          rejected: @rejected_count.value,
          available: @max_concurrent - @active_count.value
        }
      end

      def reset
        @rejected_count.value = 0
      end
    end

    # Metrics collector for resilience patterns
    class MetricsCollector
      def initialize
        @metrics = Concurrent::Hash.new { |h, k| h[k] = ServiceMetrics.new(k) }
      end

      def record_success(service_name, duration)
        @metrics[service_name].record_success(duration)
      end

      def record_failure(service_name, error, duration)
        @metrics[service_name].record_failure(error, duration)
      end

      def summary
        @metrics.transform_values(&:summary)
      end
    end

    # Per-service metrics
    class ServiceMetrics
      def initialize(name)
        @name = name
        @success_count = Concurrent::AtomicFixnum.new(0)
        @failure_count = Concurrent::AtomicFixnum.new(0)
        @response_times = Concurrent::Array.new
        @errors = Concurrent::Hash.new { |h, k| h[k] = Concurrent::AtomicFixnum.new(0) }
      end

      def record_success(duration)
        @success_count.increment
        @response_times << { time: Time.current, duration: duration, success: true }
        trim_old_data
      end

      def record_failure(error, duration)
        @failure_count.increment
        @errors[error.class.name].increment
        @response_times << { time: Time.current, duration: duration, success: false }
        trim_old_data
      end

      def summary
        recent = @response_times.select { |r| r[:time] > 5.minutes.ago }
        successful = recent.select { |r| r[:success] }

        {
          total_requests: @success_count.value + @failure_count.value,
          success_count: @success_count.value,
          failure_count: @failure_count.value,
          success_rate: calculate_success_rate,
          average_response_time: calculate_average(successful),
          p95_response_time: calculate_percentile(successful, 0.95),
          p99_response_time: calculate_percentile(successful, 0.99),
          error_breakdown: @errors.transform_values(&:value)
        }
      end

      private

      def calculate_success_rate
        total = @success_count.value + @failure_count.value
        return 1.0 if total == 0

        @success_count.value.to_f / total
      end

      def calculate_average(responses)
        return 0 if responses.empty?

        total = responses.sum { |r| r[:duration] }
        total / responses.size
      end

      def calculate_percentile(responses, percentile)
        return 0 if responses.empty?

        sorted = responses.map { |r| r[:duration] }.sort
        index = (sorted.size * percentile).ceil - 1
        sorted[index] || sorted.last
      end

      def trim_old_data
        cutoff = 1.hour.ago
        @response_times.delete_if { |r| r[:time] < cutoff }
      end
    end

    # Convenience methods for resilient execution
    module Resilient
      def with_resilience(name, options = {}, &block)
        ResilienceManager.instance.execute(name, options, &block)
      end

      def with_resilience_async(name, options = {}, &block)
        ResilienceManager.instance.execute_async(name, options, &block)
      end
    end

    # Custom errors
    class BulkheadRejectedError < StandardError; end
  end
end
