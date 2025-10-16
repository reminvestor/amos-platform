module Agents
  module Resilience
    class CircuitBreaker
      STATES = [ :closed, :open, :half_open ].freeze

      attr_reader :name, :state, :failure_count, :last_failure_time

      def initialize(name, options = {})
        @name = name
        @state = :closed
        @failure_count = 0
        @success_count = 0
        @last_failure_time = nil
        @last_state_change = Time.current

        # Configuration
        @failure_threshold = options[:failure_threshold] || 5
        @success_threshold = options[:success_threshold] || 2
        @timeout = options[:timeout] || 60.seconds
        @half_open_timeout = options[:half_open_timeout] || 30.seconds
        @on_state_change = options[:on_state_change]

        # Metrics
        @metrics = CircuitBreakerMetrics.new(name)
        @lock = Mutex.new
      end

      # Execute a block with circuit breaker protection
      def call
        @lock.synchronize do
          case @state
          when :open
            if timeout_expired?
              transition_to(:half_open)
            else
              @metrics.record_rejection
              raise CircuitOpenError, "Circuit breaker '#{@name}' is open"
            end
          when :half_open
            # Allow limited requests through
            if @success_count >= @success_threshold
              transition_to(:closed)
            end
          end
        end

        begin
          start_time = Time.current
          result = yield

          @lock.synchronize do
            record_success
            @metrics.record_success(Time.current - start_time)
          end

          result
        rescue => error
          @lock.synchronize do
            record_failure(error)
            @metrics.record_failure(error)
          end

          raise
        end
      end

      # Force the circuit to open
      def trip!
        @lock.synchronize do
          transition_to(:open)
        end
      end

      # Force the circuit to close
      def reset!
        @lock.synchronize do
          @failure_count = 0
          @success_count = 0
          @last_failure_time = nil
          transition_to(:closed)
        end
      end

      # Get current circuit status
      def status
        {
          name: @name,
          state: @state,
          failure_count: @failure_count,
          success_count: @success_count,
          last_failure: @last_failure_time,
          last_state_change: @last_state_change,
          metrics: @metrics.summary
        }
      end

      private

      def record_success
        @success_count += 1

        if @state == :half_open && @success_count >= @success_threshold
          transition_to(:closed)
        end
      end

      def record_failure(error)
        @failure_count += 1
        @last_failure_time = Time.current

        if @state == :closed && @failure_count >= @failure_threshold
          transition_to(:open)
        elsif @state == :half_open
          transition_to(:open)
        end
      end

      def timeout_expired?
        return false unless @last_failure_time

        Time.current - @last_failure_time >= @timeout
      end

      def transition_to(new_state)
        return if @state == new_state

        old_state = @state
        @state = new_state
        @last_state_change = Time.current

        # Reset counters on state change
        if new_state == :closed
          @failure_count = 0
          @success_count = 0
        elsif new_state == :half_open
          @success_count = 0
        end

        # Notify listeners
        @on_state_change&.call(old_state, new_state, self)

        # Log state change
        Rails.logger.info "CircuitBreaker[#{@name}]: #{old_state} -> #{new_state}"

        # Emit metrics
        @metrics.record_state_change(old_state, new_state)
      end
    end

    # Circuit breaker metrics collector
    class CircuitBreakerMetrics
      def initialize(name)
        @name = name
        @success_count = Concurrent::AtomicFixnum.new(0)
        @failure_count = Concurrent::AtomicFixnum.new(0)
        @rejection_count = Concurrent::AtomicFixnum.new(0)
        @response_times = Concurrent::Array.new
        @state_changes = Concurrent::Array.new
      end

      def record_success(duration)
        @success_count.increment
        @response_times << { time: Time.current, duration: duration, success: true }

        # Keep only recent data
        trim_old_data
      end

      def record_failure(error)
        @failure_count.increment
        @response_times << { time: Time.current, error: error.class.name, success: false }

        trim_old_data
      end

      def record_rejection
        @rejection_count.increment
      end

      def record_state_change(from_state, to_state)
        @state_changes << {
          time: Time.current,
          from: from_state,
          to: to_state
        }

        # Emit event
        ActiveSupport::Notifications.instrument("circuit_breaker.state_change", {
          name: @name,
          from_state: from_state,
          to_state: to_state
        })
      end

      def summary
        recent_responses = @response_times.select { |r| r[:time] > 5.minutes.ago }
        successful = recent_responses.select { |r| r[:success] }

        {
          total_requests: @success_count.value + @failure_count.value,
          success_count: @success_count.value,
          failure_count: @failure_count.value,
          rejection_count: @rejection_count.value,
          success_rate: calculate_success_rate,
          average_response_time: calculate_average_response_time(successful),
          recent_errors: recent_errors,
          state_changes: @state_changes.last(10)
        }
      end

      private

      def calculate_success_rate
        total = @success_count.value + @failure_count.value
        return 1.0 if total == 0

        @success_count.value.to_f / total
      end

      def calculate_average_response_time(successful_responses)
        return 0 if successful_responses.empty?

        total_duration = successful_responses.sum { |r| r[:duration] || 0 }
        total_duration / successful_responses.size
      end

      def recent_errors
        @response_times
          .select { |r| !r[:success] && r[:time] > 1.hour.ago }
          .group_by { |r| r[:error] }
          .transform_values(&:count)
      end

      def trim_old_data
        cutoff_time = 1.hour.ago
        @response_times.delete_if { |r| r[:time] < cutoff_time }
        @state_changes.delete_if { |s| s[:time] < cutoff_time }
      end
    end

    # Circuit breaker registry
    class CircuitBreakerRegistry
      include Singleton

      def initialize
        @breakers = Concurrent::Hash.new
        @default_config = {
          failure_threshold: 5,
          success_threshold: 2,
          timeout: 60.seconds
        }
      end

      # Get or create a circuit breaker
      def get(name, options = {})
        @breakers.compute_if_absent(name) do
          config = @default_config.merge(options)
          config[:on_state_change] = method(:handle_state_change)

          CircuitBreaker.new(name, config)
        end
      end

      # Get all circuit breakers
      def all
        @breakers.values
      end

      # Get circuit breaker status
      def status
        @breakers.transform_values(&:status)
      end

      # Reset a specific circuit breaker
      def reset(name)
        @breakers[name]&.reset!
      end

      # Reset all circuit breakers
      def reset_all
        @breakers.each_value(&:reset!)
      end

      private

      def handle_state_change(from_state, to_state, breaker)
        # Broadcast state change via ActionCable
        ActionCable.server.broadcast(
          "circuit_breaker_status",
          {
            breaker: breaker.name,
            from_state: from_state,
            to_state: to_state,
            status: breaker.status
          }
        )

        # Alert if circuit opens
        if to_state == :open
          notify_circuit_open(breaker)
        end
      end

      def notify_circuit_open(breaker)
        # Send alerts (email, Slack, etc.)
        Rails.logger.error "ALERT: Circuit breaker '#{breaker.name}' opened due to failures"

        # Could integrate with alerting service
        # AlertService.send_alert(
        #   type: :circuit_breaker_open,
        #   breaker: breaker.name,
        #   details: breaker.status
        # )
      end
    end

    # Convenient module for including circuit breaker functionality
    module CircuitBreakerSupport
      def self.included(base)
        base.extend(ClassMethods)
      end

      module ClassMethods
        def circuit_breaker(name, options = {})
          define_method "#{name}_with_circuit_breaker" do |*args, &block|
            breaker = CircuitBreakerRegistry.instance.get(
              "#{self.class.name}##{name}",
              options
            )

            breaker.call do
              send("#{name}_without_circuit_breaker", *args, &block)
            end
          end

          alias_method "#{name}_without_circuit_breaker", name
          alias_method name, "#{name}_with_circuit_breaker"
        end
      end
    end

    # Custom error classes
    class CircuitOpenError < StandardError; end
  end
end
