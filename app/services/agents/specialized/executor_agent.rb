module Agents
  module Specialized
    class ExecutorAgent < Agents::Base::BaseAgent
      # Support both initialization patterns:
      # 1. Legacy: task_session, initial_context (for WorkflowEngine)
      # 2. Plugin: role, capabilities, system_prompt, config, context (for AgentPlugin)
      def initialize(task_session: nil, initial_context: {}, role: nil, capabilities: nil, system_prompt: nil, config: {}, context: {})
        # Determine which initialization pattern is being used
        if role || capabilities || system_prompt
          # Plugin-style initialization
          super(
            role: role || :executor,
            capabilities: capabilities || [
              "tool_execution",
              "data_manipulation",
              "api_integration",
              "task_completion",
              "error_handling",
              "retry_logic",
              "result_validation"
            ],
            context: context,
            task_session: context[:task_session] || task_session
          )
          @custom_system_prompt = system_prompt
          @config = config
        else
          # Legacy initialization for WorkflowEngine
          super(
            role: :executor,
            capabilities: [
              "tool_execution",
              "data_manipulation",
              "api_integration",
              "task_completion",
              "error_handling",
              "retry_logic",
              "result_validation"
            ],
            context: initial_context,
            task_session: initial_context[:task_session] || task_session
          )
          @config = {}
        end

        @tool_catalog = ::Tools::ToolCatalog.instance rescue nil
        @plugin_manager = Agents::Platform::PluginManager.instance rescue nil
        @retry_strategies = initialize_retry_strategies
        @execution_history = []
      end

      # Override system prompt for execution expertise
      def system_prompt
        # Use custom prompt if provided (from AgentPlugin)
        return @custom_system_prompt if @custom_system_prompt.present?

        # Otherwise use default prompt
        <<~PROMPT
          You are an expert AI Execution Agent responsible for carrying out tasks efficiently and reliably.

          Your responsibilities:
          1. Execute tools and operations to achieve step goals
          2. Use multiple tools creatively when needed to accomplish objectives
          3. Self-heal and retry with different approaches when things fail
          4. Chain tools together intelligently to solve complex problems
          5. Validate inputs and outputs for each operation
          6. Know when to give up if a goal is impossible

          Available tools:
          #{available_tools_summary}

          Execution principles:
          - Focus on achieving the goal, not just executing prescribed steps
          - Be creative in combining tools to solve problems
          - Learn from failures and try alternative approaches
          - Always validate inputs before execution
          - Use appropriate retry strategies for transient failures
          - Provide detailed feedback about what you're trying
          - Clean up resources after execution
          - Know your limits and fail gracefully when needed
        PROMPT
      end

      # Execute a workflow step
      def execute_step(step, inputs = {})
        Rails.logger.info "ExecutorAgent #{@id}: Executing step #{step[:id]} (#{step[:type]})"

        # Check if we should use adaptive execution
        use_adaptive = step[:adaptive] || step[:config]&.dig(:adaptive) || false

        if use_adaptive && step[:type] == "tool_call"
          Rails.logger.info "🤖 Using AdaptiveStepExecutor for step #{step[:id]}"
          # Pass the actual context from our initialization
          adaptive_context = {
            user: @task_session&.user,
            entity: @task_session&.user&.entity,
            task_session: @task_session,
            workflow_execution: @context.get(:workflow_execution),
            progress_callback: @context.get(:progress_callback)
          }
          adaptive_executor = Agents::AdaptiveStepExecutor.new(step, adaptive_context)
          return adaptive_executor.execute(inputs)
        end

        # Record execution start
        execution_record = {
          step_id: step[:id],
          started_at: Time.current,
          inputs: sanitize_inputs(inputs)
        }

        begin
          # Pre-execution validation
          validate_step_requirements(step, inputs)

          # Execute based on step type
          result = case step[:type]
          when "tool_call"
            execute_tool_step(step, inputs)
          when "api_call"
            execute_api_step(step, inputs)
          when "data_transform"
            execute_transform_step(step, inputs)
          when "conditional"
            execute_conditional_step(step, inputs)
          when "parallel"
            execute_parallel_steps(step, inputs)
          when "wait"
            execute_wait_step(step)
          else
            execute_custom_step(step, inputs)
          end

          # Post-execution validation
          validated_result = validate_result(step, result)

          # Record success
          execution_record.merge!(
            completed_at: Time.current,
            status: "success",
            result: sanitize_result(validated_result),
            duration_ms: (Time.current - execution_record[:started_at]) * 1000
          )

          @execution_history << execution_record
          @memory.store_short_term(:last_execution, execution_record)

          {
            success: true,
            result: validated_result,
            execution_time: execution_record[:duration_ms]
          }

        rescue => e
          # Handle execution failure
          handle_step_failure(step, inputs, e, execution_record)
        end
      end

      # Execute multiple steps in parallel
      def execute_parallel_steps(parent_step, inputs)
        parallel_steps = parent_step[:config][:parallel_steps] || []

        Rails.logger.info "ExecutorAgent #{@id}: Executing #{parallel_steps.size} steps in parallel"

        # Check if we can afford parallel execution
        unless request_resources(:compute_threads, parallel_steps.size)
          # Fall back to sequential execution
          return execute_sequential_fallback(parallel_steps, inputs)
        end

        # Execute in parallel using concurrent-ruby
        require "concurrent"

        promises = parallel_steps.map do |step|
          Concurrent::Promise.execute do
            execute_step(step, inputs)
          end
        end

        # Wait for all to complete
        results = Concurrent::Promise.zip(*promises).value

        # Check for failures
        failed = results.select { |r| !r[:success] }
        if failed.any?
          {
            success: false,
            results: results,
            failed_count: failed.size,
            errors: failed.map { |f| f[:error] }
          }
        else
          {
            success: true,
            results: results.map { |r| r[:result] }
          }
        end
      end

      private

      def available_tools_summary
        tools = @tool_catalog.all_tools
        custom_tools = @plugin_manager.available_plugins(
          user: @task_session&.user,
          plugin_type: "tool"
        )[:custom]

        summary = "System tools (#{tools.size}):\n"
        summary += tools.map { |name, info| "- #{name}: #{info[:metadata][:description]}" }.join("\n")

        if custom_tools.any?
          summary += "\n\nCustom tools (#{custom_tools.size}):\n"
          summary += custom_tools.map { |tool| "- #{tool.plugin_id}: #{tool.spec['description']}" }.join("\n")
        end

        summary
      end

      def validate_step_requirements(step, inputs)
        # Check required inputs
        if step[:config][:required_inputs]
          missing = step[:config][:required_inputs] - inputs.keys.map(&:to_s)
          raise "Missing required inputs: #{missing.join(', ')}" if missing.any?
        end

        # Check tool availability
        if step[:type] == "tool_call" && step[:config][:tool]
          tool_name = step[:config][:tool]
          unless tool_available?(tool_name)
            raise "Tool not available: #{tool_name}"
          end
        end

        # Check resource availability
        if step[:config][:resource_requirements]
          step[:config][:resource_requirements].each do |resource, amount|
            unless request_resources(resource.to_sym, amount)
              raise "Insufficient resources: #{resource} (need #{amount})"
            end
          end
        end
      end

      def execute_tool_step(step, inputs)
        tool_name = step[:config][:tool]
        tool_args = resolve_tool_args(step[:config][:tool_args] || {}, inputs)

        Rails.logger.info "ExecutorAgent #{@id}: Executing tool #{tool_name} with args: #{tool_args.keys}"

        # Check if it's a custom tool
        if custom_tool?(tool_name)
          execute_custom_tool(tool_name, tool_args)
        else
          # Execute system tool
          user = @task_session&.user
          entity = @task_session&.user&.entity

          Rails.logger.info "ExecutorAgent #{@id}: Context - user: #{user&.id}, entity: #{entity&.id}, task_session: #{@task_session&.id}"

          context = {
            user: user,
            entity: entity,
            context: { task_session_id: @task_session&.id }
          }

          with_retry(tool_name) do
            @tool_catalog.execute_tool(tool_name, tool_args, context)
          end
        end
      end

      def execute_api_step(step, inputs)
        api_config = step[:config][:api] || {}

        # Build request
        request = {
          method: api_config[:method] || "GET",
          url: resolve_value(api_config[:url], inputs),
          headers: resolve_value(api_config[:headers] || {}, inputs),
          body: resolve_value(api_config[:body], inputs)
        }

        # Execute with retry
        with_retry("api_call") do
          response = make_api_request(request)

          # Parse response based on expected format
          parse_api_response(response, api_config[:response_format])
        end
      end

      def execute_transform_step(step, inputs)
        transform_config = step[:config][:transform] || {}

        # Get input data
        data = resolve_value(transform_config[:input], inputs)

        # Apply transformations
        result = data

        (transform_config[:operations] || []).each do |operation|
          result = apply_transformation(result, operation)
        end

        result
      end

      def execute_conditional_step(step, inputs)
        condition = step[:config][:condition]

        # Evaluate condition
        condition_result = evaluate_condition(condition, inputs)

        # Execute appropriate branch
        if condition_result
          then_steps = step[:config][:then_steps] || []
          execute_steps_sequence(then_steps, inputs)
        else
          else_steps = step[:config][:else_steps] || []
          execute_steps_sequence(else_steps, inputs)
        end
      end

      def execute_wait_step(step)
        duration = step[:config][:duration] || step[:duration] || 1

        Rails.logger.info "ExecutorAgent #{@id}: Waiting for #{duration} seconds"
        sleep(duration)

        { waited: duration }
      end

      def execute_custom_step(step, inputs)
        # For custom step types, try to find a handler
        handler_method = "handle_#{step[:type]}_step"

        if respond_to?(handler_method, true)
          send(handler_method, step, inputs)
        else
          # Try custom plugins
          if plugin = find_step_handler_plugin(step[:type])
            plugin.execute(:handle_step, { step: step, inputs: inputs })
          else
            raise "Unknown step type: #{step[:type]}"
          end
        end
      end

      def with_retry(operation_name, &block)
        strategy = @retry_strategies[operation_name] || @retry_strategies[:default]

        attempts = 0
        last_error = nil

        strategy[:max_attempts].times do |attempt|
          attempts += 1

          begin
            return yield
          rescue => e
            last_error = e

            # Check if error is retryable
            if retryable_error?(e, strategy)
              wait_time = calculate_backoff(attempt, strategy)
              Rails.logger.warn "ExecutorAgent #{@id}: Attempt #{attempts} failed, retrying in #{wait_time}s: #{e.message}"

              sleep(wait_time)
            else
              # Non-retryable error, fail immediately
              raise
            end
          end
        end

        # All attempts failed
        raise last_error
      end

      def retryable_error?(error, strategy)
        # Check error patterns
        retryable_patterns = strategy[:retryable_errors] || [
          /timeout/i,
          /temporary/i,
          /rate.?limit/i,
          /throttl/i
        ]

        error_message = error.message.to_s
        retryable_patterns.any? { |pattern| error_message =~ pattern }
      end

      def calculate_backoff(attempt, strategy)
        case strategy[:backoff_type]
        when :exponential
          base = strategy[:backoff_base] || 2
          base ** attempt
        when :linear
          multiplier = strategy[:backoff_multiplier] || 1
          (attempt + 1) * multiplier
        else
          strategy[:backoff_seconds] || 1
        end
      end

      def handle_step_failure(step, inputs, error, execution_record)
        Rails.logger.error "ExecutorAgent #{@id}: Step #{step[:id]} failed: #{error.message}"
        Rails.logger.error error.backtrace.join("\n")

        # Record failure
        execution_record.merge!(
          completed_at: Time.current,
          status: "failed",
          error: {
            message: error.message,
            class: error.class.name,
            backtrace: error.backtrace.first(5)
          },
          duration_ms: (Time.current - execution_record[:started_at]) * 1000
        )

        @execution_history << execution_record
        @memory.store_short_term(:last_failure, execution_record)

        # Try recovery strategies
        if recovery_result = attempt_recovery(step, inputs, error)
          return recovery_result
        end

        # Request help from other agents
        if should_request_help?(error)
          request_assistance({
            task_type: "execution_failure",
            step: step,
            error: error.message,
            required_capabilities: [ "error_recovery", "debugging" ]
          })
        end

        {
          success: false,
          error: error.message,
          error_type: error.class.name,
          execution_time: execution_record[:duration_ms],
          recovery_attempted: true
        }
      end

      def attempt_recovery(step, inputs, error)
        # Check if step has recovery configuration
        recovery_config = step[:config][:on_failure]
        return nil unless recovery_config

        case recovery_config[:strategy]
        when "use_default"
          # Try with default values
          default_result = recovery_config[:default_result]
          Rails.logger.info "ExecutorAgent #{@id}: Using default result for failed step"
          {
            success: true,
            result: default_result,
            recovered: true
          }

        when "skip"
          # Skip this step
          Rails.logger.info "ExecutorAgent #{@id}: Skipping failed step"
          {
            success: true,
            result: nil,
            skipped: true
          }

        when "alternative_tool"
          # Try alternative tool
          alt_tool = recovery_config[:alternative_tool]
          Rails.logger.info "ExecutorAgent #{@id}: Trying alternative tool: #{alt_tool}"

          alt_step = step.dup
          alt_step[:config][:tool] = alt_tool
          execute_tool_step(alt_step, inputs)

        else
          nil
        end
      rescue => recovery_error
        Rails.logger.error "Recovery failed: #{recovery_error.message}"
        nil
      end

      def validate_result(step, result)
        validations = step[:config][:validations] || []

        validations.each do |validation|
          case validation[:type]
          when "required_fields"
            check_required_fields(result, validation[:fields])
          when "schema"
            validate_against_schema(result, validation[:schema])
          when "range"
            validate_range(result, validation)
          when "custom"
            validate_custom(result, validation)
          end
        end

        result
      end

      def check_required_fields(result, fields)
        return unless result.is_a?(Hash)

        missing = fields - result.keys.map(&:to_s)
        raise "Missing required fields in result: #{missing.join(', ')}" if missing.any?
      end

      def validate_against_schema(result, schema)
        # Simple schema validation - can be enhanced with JSON Schema
        schema.each do |field, constraints|
          value = result[field] || result[field.to_s]

          if constraints[:required] && value.nil?
            raise "Required field missing: #{field}"
          end

          if constraints[:type] && value
            expected_class = case constraints[:type]
            when "string" then String
            when "number" then Numeric
            when "boolean" then [ TrueClass, FalseClass ]
            when "array" then Array
            when "object" then Hash
            end

            unless value.is_a?(expected_class) || (expected_class.is_a?(Array) && expected_class.any? { |c| value.is_a?(c) })
              raise "Field #{field} has wrong type. Expected #{constraints[:type]}, got #{value.class}"
            end
          end
        end
      end

      def validate_range(result, validation)
        value = result[validation[:field]]
        return unless value.is_a?(Numeric)

        if validation[:min] && value < validation[:min]
          raise "Value #{value} is below minimum #{validation[:min]}"
        end

        if validation[:max] && value > validation[:max]
          raise "Value #{value} is above maximum #{validation[:max]}"
        end
      end

      def validate_custom(result, validation)
        # Execute custom validation code
        validator_name = validation[:validator]

        if validator = find_validator(validator_name)
          unless validator.call(result)
            raise "Custom validation failed: #{validator_name}"
          end
        end
      end

      def resolve_tool_args(args_spec, inputs)
        return {} unless args_spec

        resolved = {}

        args_spec.each do |key, value|
          resolved[key] = resolve_value(value, inputs)
        end

        resolved
      end

      def resolve_value(value, context)
        case value
        when String
          # Check for variable references
          if value.start_with?("{{") && value.end_with?("}}")
            var_name = value[2..-3].strip
            resolve_variable(var_name, context)
          else
            value
          end
        when Hash
          # Recursively resolve hash values
          value.transform_values { |v| resolve_value(v, context) }
        when Array
          # Resolve array elements
          value.map { |v| resolve_value(v, context) }
        else
          value
        end
      end

      def resolve_variable(var_name, context)
        # Handle dot notation
        parts = var_name.split(".")
        current = context

        parts.each do |part|
          if current.is_a?(Hash)
            current = current[part] || current[part.to_sym]
          else
            return nil
          end
        end

        current
      end

      def tool_available?(tool_name)
        # Check system tools
        return true if @tool_catalog.get_metadata(tool_name)

        # Check custom tools
        custom_tool?(tool_name)
      end

      def custom_tool?(tool_name)
        return false unless @task_session

        custom_tools = @plugin_manager.available_plugins(
          user: @task_session.user,
          plugin_type: "tool"
        )[:custom]

        custom_tools.any? { |tool| tool.plugin_id == tool_name }
      end

      def execute_custom_tool(tool_name, args)
        plugin = CustomPlugin.find_by(
          plugin_id: tool_name,
          plugin_type: "tool",
          status: "active"
        )

        raise "Custom tool not found: #{tool_name}" unless plugin

        plugin.execute(:execute, args, {
          user: @task_session.user,
          entity: @task_session.user.entity,
          executor_agent: @id
        })
      end

      def make_api_request(request)
        require "net/http"
        require "uri"

        uri = URI.parse(request[:url])

        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == "https"
        http.read_timeout = 30

        # Build request
        req_class = case request[:method].upcase
        when "GET" then Net::HTTP::Get
        when "POST" then Net::HTTP::Post
        when "PUT" then Net::HTTP::Put
        when "DELETE" then Net::HTTP::Delete
        else raise "Unsupported HTTP method: #{request[:method]}"
        end

        req = req_class.new(uri.request_uri)

        # Set headers
        request[:headers]&.each do |key, value|
          req[key] = value
        end

        # Set body
        if request[:body]
          req.body = request[:body].is_a?(Hash) ? request[:body].to_json : request[:body]
          req["Content-Type"] = "application/json" unless req["Content-Type"]
        end

        # Execute request
        response = http.request(req)

        {
          status: response.code.to_i,
          headers: response.to_hash,
          body: response.body
        }
      end

      def parse_api_response(response, format)
        case format
        when "json"
          JSON.parse(response[:body])
        when "xml"
          # Would use Nokogiri or similar
          response[:body]
        else
          response[:body]
        end
      rescue JSON::ParserError => e
        raise "Failed to parse API response as #{format}: #{e.message}"
      end

      def apply_transformation(data, operation)
        case operation[:type]
        when "map"
          data.map { |item| transform_item(item, operation[:transform]) }
        when "filter"
          data.select { |item| evaluate_condition(operation[:condition], item) }
        when "reduce"
          data.reduce(operation[:initial]) do |acc, item|
            transform_item({ acc: acc, item: item }, operation[:transform])
          end
        when "sort"
          data.sort_by { |item| resolve_value(operation[:by], item) }
        when "limit"
          data.take(operation[:count])
        else
          data
        end
      end

      def transform_item(item, transform_spec)
        # Simple transformation - can be enhanced
        if transform_spec.is_a?(Hash)
          result = {}
          transform_spec.each do |key, value|
            result[key] = resolve_value(value, item)
          end
          result
        else
          resolve_value(transform_spec, item)
        end
      end

      def evaluate_condition(condition, context)
        case condition[:operator]
        when "equals"
          resolve_value(condition[:left], context) == resolve_value(condition[:right], context)
        when "not_equals"
          resolve_value(condition[:left], context) != resolve_value(condition[:right], context)
        when "greater_than"
          resolve_value(condition[:left], context) > resolve_value(condition[:right], context)
        when "less_than"
          resolve_value(condition[:left], context) < resolve_value(condition[:right], context)
        when "contains"
          left = resolve_value(condition[:left], context)
          right = resolve_value(condition[:right], context)
          left.respond_to?(:include?) && left.include?(right)
        when "and"
          condition[:conditions].all? { |c| evaluate_condition(c, context) }
        when "or"
          condition[:conditions].any? { |c| evaluate_condition(c, context) }
        else
          true
        end
      end

      def execute_steps_sequence(steps, inputs)
        results = []
        current_context = inputs.dup

        steps.each do |step|
          result = execute_step(step, current_context)

          unless result[:success]
            return {
              success: false,
              completed_steps: results.size,
              failed_step: step[:id],
              error: result[:error]
            }
          end

          results << result

          # Update context with step result
          if result[:result].is_a?(Hash)
            current_context.merge!(result[:result])
          end
          current_context["#{step[:id]}_result"] = result[:result]
        end

        {
          success: true,
          results: results
        }
      end

      def execute_sequential_fallback(steps, inputs)
        Rails.logger.warn "ExecutorAgent #{@id}: Falling back to sequential execution"
        execute_steps_sequence(steps, inputs)
      end

      def find_step_handler_plugin(step_type)
        return nil unless @task_session

        plugins = @plugin_manager.available_plugins(
          user: @task_session.user,
          plugin_type: "agent"
        )

        # Find plugins that can handle this step type
        plugins[:custom].find do |plugin|
          plugin.spec["capabilities"]&.include?("handle_#{step_type}")
        end
      end

      def find_validator(validator_name)
        # Look up custom validators
        # This could be expanded to support custom validation plugins
        case validator_name
        when "email_format"
          ->(value) { value =~ /\A[^@\s]+@[^@\s]+\z/ }
        when "url_format"
          ->(value) { value =~ /\Ahttps?:\/\// }
        else
          nil
        end
      end

      def should_request_help?(error)
        # Decide if we should ask for help based on error type
        case error
        when SecurityError, Agents::Platform::Sandbox::SecurityError
          true # Always ask for help with security issues
        when NoMethodError, NameError
          true # Likely a configuration issue
        else
          # Check if we've seen this error multiple times
          recent_failures = @execution_history.select do |record|
            record[:status] == "failed" &&
            record[:error][:class] == error.class.name &&
            record[:completed_at] > 5.minutes.ago
          end

          recent_failures.size >= 3
        end
      end

      def sanitize_inputs(inputs)
        # Remove sensitive data from inputs for logging
        inputs.deep_dup.tap do |safe_inputs|
          %w[password api_key token secret credential].each do |sensitive_key|
            safe_inputs.each do |key, value|
              if key.to_s.downcase.include?(sensitive_key)
                safe_inputs[key] = "[REDACTED]"
              elsif value.is_a?(Hash)
                value.each do |k, v|
                  if k.to_s.downcase.include?(sensitive_key)
                    value[k] = "[REDACTED]"
                  end
                end
              end
            end
          end
        end
      end

      def sanitize_result(result)
        # Remove large data from results for storage
        return result unless result.is_a?(Hash)

        result.deep_dup.tap do |safe_result|
          safe_result.each do |key, value|
            if value.is_a?(String) && value.length > 10_000
              safe_result[key] = "#{value[0..100]}...[truncated]"
            elsif value.is_a?(Array) && value.size > 100
              safe_result[key] = value.take(10) + [ "...[#{value.size - 10} more items]" ]
            end
          end
        end
      end

      def initialize_retry_strategies
        {
          default: {
            max_attempts: 3,
            backoff_type: :exponential,
            backoff_base: 2,
            retryable_errors: [ /timeout/i, /temporary/i ]
          },
          api_call: {
            max_attempts: 5,
            backoff_type: :exponential,
            backoff_base: 2,
            retryable_errors: [ /timeout/i, /rate.?limit/i, /throttl/i, /503/, /502/ ]
          },
          database: {
            max_attempts: 3,
            backoff_type: :linear,
            backoff_multiplier: 0.5,
            retryable_errors: [ /deadlock/i, /lock/i, /connection/i ]
          },
          ai_service: {
            max_attempts: 3,
            backoff_type: :exponential,
            backoff_base: 3,
            retryable_errors: [ /rate.?limit/i, /capacity/i, /throttl/i ]
          }
        }
      end
    end
  end
end
