# frozen_string_literal: true

# Ensure executors are loaded
require_relative 'executors/base_executor'

module Workflows
  # ExecutorService runs compiled workflow steps deterministically.
  #
  # This is the "run with determinism" part of the architecture:
  # - No AI calls during execution (unless explicitly using an agent node)
  # - Predictable execution order
  # - Variable resolution from previous step outputs
  # - Condition evaluation for branching
  # - Error handling and retry logic
  #
  # Execution flow:
  # 1. Load compiled steps from automation_code
  # 2. Start from trigger step with initial context
  # 3. Execute each step in order, respecting conditions/branches
  # 4. Resolve variables from context and previous outputs
  # 5. Store step results and handle errors
  # 6. Complete when reaching an output node or running out of steps
  #
  class ExecutorService
    attr_reader :execution, :automation_code, :context, :step_results

    def initialize(execution)
      @execution = execution
      @automation_code = execution.automation_code
      @context = (execution.input_data || {}).with_indifferent_access
      @step_results = {}
      @current_step_index = 0
      @max_steps = 1000  # Safety limit
      @node_registry = NodeRegistry.instance
    end

    # Execute the workflow
    # Returns { success: true/false, output: {}, error: nil/string }
    def execute!
      start_execution!

      begin
        # Get compiled steps
        steps = automation_code.compiled_steps
        return failure("Workflow not compiled") if steps.blank?

        # Build step lookup
        @step_map = steps.index_by { |s| s['step_id'] }

        # Find trigger step (first step)
        trigger_step = steps.find { |s| s['category'] == 'trigger' }
        return failure("No trigger step found") unless trigger_step

        # Execute trigger (validates context, sets up initial outputs)
        result = execute_step(trigger_step)
        return failure(result[:error]) unless result[:success]

        # Follow the execution path
        next_step_ids = trigger_step['next_steps'] || []
        
        while next_step_ids.any? && @current_step_index < @max_steps
          @current_step_index += 1

          # For now, take the first next step (branching handled in conditions)
          current_step_id = next_step_ids.first
          current_step = @step_map[current_step_id]

          unless current_step
            Rails.logger.warn "[WorkflowExecutor] Step not found: #{current_step_id}"
            next_step_ids = []
            next
          end

          # Execute the step
          result = execute_step(current_step)
          
          unless result[:success]
            # Check if this is a handled error (via error output node)
            if current_step['category'] == 'output' && current_step['node_type'] == 'output-error'
              return complete_with_error(result[:error])
            end
            return failure(result[:error])
          end

          # Determine next steps based on step type
          next_step_ids = determine_next_steps(current_step, result)

          # Check for output nodes (workflow complete)
          if current_step['category'] == 'output'
            if current_step['node_type'] == 'output-success'
              return complete_with_success(result[:output])
            elsif current_step['node_type'] == 'output-error'
              return complete_with_error(result[:output])
            end
          end
        end

        if @current_step_index >= @max_steps
          return failure("Workflow exceeded maximum steps (#{@max_steps})")
        end

        # No more steps - implicit success
        complete_with_success(collect_final_output)

      rescue => e
        Rails.logger.error "[WorkflowExecutor] Execution failed: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
        failure(e.message)
      end
    end

    private

    def start_execution!
      execution.update!(
        status: 'running',
        started_at: Time.current
      )
    end

    def execute_step(step)
      step_id = step['step_id']
      node_type = step['node_type']
      config = step['config'] || {}

      Rails.logger.info "[WorkflowExecutor] Executing step: #{step_id} (#{node_type})"

      # Resolve variables in config
      resolved_config = resolve_variables(config)

      # Resolve inputs from previous steps
      resolved_inputs = resolve_inputs(step['inputs'] || {})

      # Get the executor for this node type
      executor_class = @node_registry.executor_for(node_type)
      
      unless executor_class
        # Use generic executor if no specific one
        executor_class = Executors::GenericExecutor
      end

      # Create executor instance
      executor = executor_class.new(
        step: step,
        config: resolved_config,
        inputs: resolved_inputs,
        context: @context,
        execution: execution
      )

      # Execute
      result = executor.execute

      # Store results
      @step_results[step_id] = result

      # Record step execution
      record_step_execution(step, result)

      result
    rescue => e
      Rails.logger.error "[WorkflowExecutor] Step #{step_id} failed: #{e.message}"
      { success: false, error: e.message }
    end

    def determine_next_steps(step, result)
      # Check for conditional branching
      conditions = step['conditions']
      
      return step['next_steps'] || [] unless conditions

      case conditions['type']
      when 'if'
        # Evaluate condition
        condition_result = evaluate_condition(conditions, result)
        if condition_result
          [conditions['true_step']].compact
        else
          [conditions['false_step']].compact
        end

      when 'switch'
        # Find matching case
        field_value = get_field_value(conditions['field'], result[:output])
        matching_case = conditions['cases'].find { |c| c['value'] == field_value.to_s }
        
        if matching_case
          [matching_case['step']].compact
        else
          [conditions['default_step']].compact
        end

      when 'loop'
        # Loop handling - check if we have more items
        loop_state = result[:loop_state] || {}
        
        if loop_state[:has_more]
          [conditions['loop_body_step']].compact
        else
          [conditions['completed_step']].compact
        end

      else
        step['next_steps'] || []
      end
    end

    def evaluate_condition(conditions, result)
      field = conditions['field']
      operator = conditions['operator']
      compare_to = conditions['compare_to']

      # Get the value from result output or context
      value = get_field_value(field, result[:output])

      case operator
      when 'equals'
        value.to_s == compare_to.to_s
      when 'not_equals'
        value.to_s != compare_to.to_s
      when 'contains'
        value.to_s.include?(compare_to.to_s)
      when 'not_contains'
        !value.to_s.include?(compare_to.to_s)
      when 'greater_than'
        value.to_f > compare_to.to_f
      when 'less_than'
        value.to_f < compare_to.to_f
      when 'is_empty'
        value.blank?
      when 'is_not_empty'
        value.present?
      when 'matches_regex'
        value.to_s.match?(Regexp.new(compare_to.to_s))
      else
        false
      end
    rescue => e
      Rails.logger.warn "[WorkflowExecutor] Condition evaluation failed: #{e.message}"
      false
    end

    def get_field_value(field_path, data)
      return nil if field_path.blank? || data.blank?

      parts = field_path.to_s.split('.')
      current = data.with_indifferent_access

      parts.each do |part|
        if current.is_a?(Hash)
          current = current[part]
        elsif current.is_a?(Array) && part =~ /^\d+$/
          current = current[part.to_i]
        else
          return nil
        end
      end

      current
    end

    def resolve_variables(config)
      deep_resolve(config)
    end

    def deep_resolve(obj)
      case obj
      when Hash
        obj.transform_values { |v| deep_resolve(v) }
      when Array
        obj.map { |v| deep_resolve(v) }
      when String
        resolve_string(obj)
      else
        obj
      end
    end

    def resolve_string(str)
      str.gsub(/\{\{([^}]+)\}\}/) do |match|
        var_path = $1.strip
        parts = var_path.split('.')

        if parts[0] == 'context'
          # Context variable
          get_field_value(parts[1..-1].join('.'), @context)
        elsif parts[0] == 'steps' && parts.size >= 3
          # Step output variable: steps.step_id.outputs.field
          step_id = parts[1]
          output_path = parts[3..-1]&.join('.') || parts[2]
          
          step_result = @step_results[step_id]
          if step_result
            get_field_value(output_path, step_result[:output])
          else
            match  # Keep original if step not executed yet
          end
        elsif parts[0] == 'trigger'
          # Trigger context shorthand
          get_field_value(parts[1..-1].join('.'), @context)
        else
          # Try direct context lookup
          get_field_value(var_path, @context) || match
        end
      end
    end

    def resolve_inputs(inputs_def)
      resolved = {}

      inputs_def.each do |input_name, input_spec|
        source = input_spec['source']
        
        if source
          step_id = source['step_id']
          output_name = source['output']
          
          step_result = @step_results[step_id]
          if step_result && step_result[:output]
            resolved[input_name] = get_field_value(output_name, step_result[:output])
          end
        end
      end

      resolved
    end

    def record_step_execution(step, result)
      # Create a step execution record for audit trail
      AutomationExecution.where(id: execution.id).update_all(
        "step_executions = step_executions || '#{[{
          step_id: step['step_id'],
          node_type: step['node_type'],
          executed_at: Time.current.iso8601,
          success: result[:success],
          duration_ms: result[:duration_ms],
          error: result[:error]
        }].to_json}'::jsonb"
      )
    rescue => e
      Rails.logger.warn "[WorkflowExecutor] Failed to record step execution: #{e.message}"
    end

    def collect_final_output
      # Gather outputs from all executed steps
      @step_results.transform_values { |r| r[:output] }
    end

    def complete_with_success(output)
      execution.update!(
        status: 'success',
        completed_at: Time.current,
        output_data: output,
        duration_ms: calculate_duration
      )

      automation_code.record_execution!({ success: true }, duration_ms: calculate_duration)

      { success: true, output: output }
    end

    def complete_with_error(error_message)
      execution.update!(
        status: 'failed',
        completed_at: Time.current,
        error_message: error_message,
        duration_ms: calculate_duration
      )

      automation_code.record_execution!({ success: false, error: error_message }, duration_ms: calculate_duration)

      { success: false, error: error_message }
    end

    def failure(error_message)
      execution.update!(
        status: 'failed',
        completed_at: Time.current,
        error_message: error_message,
        duration_ms: calculate_duration
      )

      automation_code.record_error!(StandardError.new(error_message))

      { success: false, error: error_message }
    end

    def calculate_duration
      return nil unless execution.started_at
      ((Time.current - execution.started_at) * 1000).round
    end
  end
end
