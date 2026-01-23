# frozen_string_literal: true

module Workflows
  module Executors
    # ═══════════════════════════════════════════════════════════════
    # LOGIC EXECUTORS
    # These handle control flow - conditions, switches, loops
    # ═══════════════════════════════════════════════════════════════

    # ConditionExecutor - Evaluates if/else conditions
    class ConditionExecutor < BaseExecutor
      def execute
        log_info "Evaluating condition"

        field = config[:field]
        operator = config[:operator]
        compare_to = config[:compare_to]

        return failure("Field is required for condition") if field.blank?
        return failure("Operator is required for condition") if operator.blank?

        # Get the value to check
        value = resolve_path(field)

        # Evaluate the condition
        result = evaluate(value, operator, compare_to)

        log_info "Condition: #{field} #{operator} #{compare_to} = #{result}"

        success(
          condition_result: result,
          evaluated_field: field,
          evaluated_value: value,
          operator: operator,
          compare_to: compare_to
        )
      end

      private

      def evaluate(value, operator, compare_to)
        case operator
        when 'equals', 'eq', '=='
          value.to_s == compare_to.to_s
        when 'not_equals', 'neq', '!='
          value.to_s != compare_to.to_s
        when 'contains', 'includes'
          value.to_s.include?(compare_to.to_s)
        when 'not_contains', 'not_includes'
          !value.to_s.include?(compare_to.to_s)
        when 'greater_than', 'gt', '>'
          value.to_f > compare_to.to_f
        when 'greater_than_or_equal', 'gte', '>='
          value.to_f >= compare_to.to_f
        when 'less_than', 'lt', '<'
          value.to_f < compare_to.to_f
        when 'less_than_or_equal', 'lte', '<='
          value.to_f <= compare_to.to_f
        when 'is_empty', 'empty', 'blank'
          value.blank?
        when 'is_not_empty', 'not_empty', 'present'
          value.present?
        when 'matches_regex', 'regex', 'matches'
          value.to_s.match?(Regexp.new(compare_to.to_s))
        when 'starts_with'
          value.to_s.start_with?(compare_to.to_s)
        when 'ends_with'
          value.to_s.end_with?(compare_to.to_s)
        when 'in', 'one_of'
          Array(compare_to).map(&:to_s).include?(value.to_s)
        when 'not_in', 'not_one_of'
          !Array(compare_to).map(&:to_s).include?(value.to_s)
        else
          log_warn "Unknown operator: #{operator}, defaulting to false"
          false
        end
      rescue => e
        log_error "Condition evaluation error: #{e.message}"
        false
      end
    end

    # SwitchExecutor - Routes to different paths based on value
    class SwitchExecutor < BaseExecutor
      def execute
        log_info "Evaluating switch"

        field = config[:field]
        cases = config[:cases] || []

        return failure("Field is required for switch") if field.blank?

        value = resolve_path(field)
        matched_case = cases.find { |c| c['value'].to_s == value.to_s }

        success(
          switch_value: value,
          matched_case: matched_case&.dig('value'),
          matched_output: matched_case&.dig('output_name') || 'default',
          all_cases: cases.map { |c| c['value'] }
        )
      end
    end

    # LoopExecutor - Iterates over arrays
    class LoopExecutor < BaseExecutor
      def execute
        log_info "Processing loop"

        items_field = config[:items_field]
        max_iterations = config[:max_iterations] || 100

        return failure("Items field is required for loop") if items_field.blank?

        items = resolve_path(items_field)
        
        unless items.is_a?(Array)
          return failure("Loop items must be an array, got: #{items.class}")
        end

        # Get current loop state from execution context
        loop_key = "loop_#{step['step_id']}"
        loop_state = execution.metadata&.dig(loop_key) || { index: 0 }
        current_index = loop_state['index']

        if current_index >= items.size || current_index >= max_iterations
          # Loop complete
          log_info "Loop complete after #{current_index} iterations"
          
          success(
            completed: true,
            total_iterations: current_index,
            items_count: items.size,
            loop_state: { has_more: false }
          )
        else
          # Return current item and update loop state
          current_item = items[current_index]
          
          # Update execution metadata with new loop state
          new_loop_state = { index: current_index + 1 }
          execution.update!(
            metadata: (execution.metadata || {}).merge(loop_key => new_loop_state)
          )

          success(
            item: current_item,
            index: current_index,
            total_items: items.size,
            is_first: current_index == 0,
            is_last: current_index == items.size - 1,
            loop_state: { has_more: current_index + 1 < items.size }
          )
        end
      end
    end

    # MergeExecutor - Combines multiple inputs
    class MergeExecutor < BaseExecutor
      def execute
        log_info "Merging inputs"

        merge_mode = config[:merge_mode] || 'combine'
        output_structure = config[:output_structure]

        merged = case merge_mode
        when 'wait_all'
          # All inputs must be present
          inputs.to_h
        when 'first_wins'
          # Take first non-nil input
          inputs.to_h.compact.first&.last || {}
        when 'combine'
          # Deep merge all inputs
          inputs.to_h.values.reduce({}) do |acc, input|
            deep_merge(acc, input.is_a?(Hash) ? input : { value: input })
          end
        else
          inputs.to_h
        end

        # Apply output structure mapping if configured
        if output_structure.present?
          merged = apply_structure(merged, output_structure)
        end

        success(merged: merged)
      end

      private

      def deep_merge(hash1, hash2)
        hash1.merge(hash2) do |key, v1, v2|
          if v1.is_a?(Hash) && v2.is_a?(Hash)
            deep_merge(v1, v2)
          elsif v1.is_a?(Array) && v2.is_a?(Array)
            v1 + v2
          else
            v2
          end
        end
      end

      def apply_structure(data, structure)
        result = {}
        structure.each do |output_key, source_path|
          result[output_key] = resolve_path(source_path) || data.dig(*source_path.split('.'))
        end
        result
      end
    end
  end
end
