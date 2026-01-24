# frozen_string_literal: true

module Workflows
  module Executors
    # ═══════════════════════════════════════════════════════════════
    # TRANSFORM EXECUTORS
    # These transform and manipulate data
    # ═══════════════════════════════════════════════════════════════
    module TransformExecutors
      # Module wrapper for Zeitwerk compatibility
    end

    # MapTransformExecutor - Maps/transforms fields
    class MapTransformExecutor < BaseExecutor
      def execute
        log_info "Mapping fields"

        mapping = config[:mapping] || []
        data = inputs[:data] || inputs.to_h

        result = {}

        mapping.each do |map_item|
          source = map_item['source']
          target = map_item['target']
          transform = map_item['transform']

          # Get source value
          value = if source.start_with?('{{')
            interpolate(source)
          else
            resolve_path(source) || data.dig(*source.split('.'))
          end

          # Apply transform if specified
          if transform.present?
            value = apply_transform(value, transform)
          end

          # Set target value (supports nested paths)
          set_nested(result, target, value)
        end

        success(result: result)
      end

      private

      def apply_transform(value, transform)
        case transform
        when 'uppercase', 'upcase'
          value.to_s.upcase
        when 'lowercase', 'downcase'
          value.to_s.downcase
        when 'trim', 'strip'
          value.to_s.strip
        when 'to_integer', 'to_i'
          value.to_i
        when 'to_float', 'to_f'
          value.to_f
        when 'to_string', 'to_s'
          value.to_s
        when 'to_boolean', 'to_bool'
          ActiveModel::Type::Boolean.new.cast(value)
        when 'to_json'
          value.to_json
        when 'from_json', 'parse_json'
          JSON.parse(value.to_s) rescue value
        when 'first'
          value.is_a?(Array) ? value.first : value
        when 'last'
          value.is_a?(Array) ? value.last : value
        when 'count', 'length', 'size'
          value.respond_to?(:size) ? value.size : 0
        when /^split\((.+)\)$/
          value.to_s.split($1)
        when /^join\((.+)\)$/
          value.is_a?(Array) ? value.join($1) : value
        when /^slice\((\d+),(\d+)\)$/
          value.to_s[$1.to_i, $2.to_i]
        when /^replace\((.+),(.+)\)$/
          value.to_s.gsub($1, $2)
        when /^default\((.+)\)$/
          value.blank? ? $1 : value
        else
          # Try to evaluate as Ruby expression (sandboxed)
          if transform.include?('value')
            safe_eval(transform, value)
          else
            value
          end
        end
      rescue => e
        log_warn "Transform '#{transform}' failed: #{e.message}"
        value
      end

      def safe_eval(expression, value)
        # Only allow safe operations
        allowed_methods = %w[to_s to_i to_f upcase downcase strip split join first last size length]
        
        # Check if expression uses only allowed methods
        method_calls = expression.scan(/\.(\w+)/).flatten
        
        if method_calls.all? { |m| allowed_methods.include?(m) }
          eval(expression.gsub('value', 'value_var'), binding_with_value(value))
        else
          log_warn "Unsafe transform expression: #{expression}"
          value
        end
      rescue => e
        log_warn "Transform eval failed: #{e.message}"
        value
      end

      def binding_with_value(value)
        value_var = value
        binding
      end

      def set_nested(hash, path, value)
        parts = path.split('.')
        current = hash

        parts[0..-2].each do |part|
          current[part] ||= {}
          current = current[part]
        end

        current[parts.last] = value
      end
    end

    # FilterTransformExecutor - Filters arrays
    class FilterTransformExecutor < BaseExecutor
      def execute
        log_info "Filtering array"

        items = inputs[:items] || []
        field = config[:field]
        operator = config[:operator] || 'equals'
        compare_value = config[:value]

        unless items.is_a?(Array)
          return failure("Items must be an array")
        end

        matched = []
        rejected = []

        items.each do |item|
          value = if field.present?
            item.is_a?(Hash) ? (item[field] || item[field.to_sym]) : item
          else
            item
          end

          if matches?(value, operator, compare_value)
            matched << item
          else
            rejected << item
          end
        end

        success(
          matched: matched,
          rejected: rejected,
          matched_count: matched.size,
          rejected_count: rejected.size,
          total: items.size
        )
      end

      private

      def matches?(value, operator, compare_to)
        case operator
        when 'equals', 'eq'
          value.to_s == compare_to.to_s
        when 'not_equals', 'neq'
          value.to_s != compare_to.to_s
        when 'contains'
          value.to_s.include?(compare_to.to_s)
        when 'greater_than', 'gt'
          value.to_f > compare_to.to_f
        when 'less_than', 'lt'
          value.to_f < compare_to.to_f
        when 'is_empty'
          value.blank?
        when 'is_not_empty'
          value.present?
        when 'matches'
          value.to_s.match?(Regexp.new(compare_to.to_s))
        else
          true
        end
      rescue
        false
      end
    end

    # AggregateTransformExecutor - Aggregates values
    class AggregateTransformExecutor < BaseExecutor
      def execute
        log_info "Aggregating values"

        items = inputs[:items] || []
        operation = config[:operation] || 'count'
        field = config[:field]
        group_by = config[:group_by]

        unless items.is_a?(Array)
          return failure("Items must be an array")
        end

        if group_by.present?
          # Grouped aggregation
          groups = items.group_by { |item| item.is_a?(Hash) ? (item[group_by] || item[group_by.to_sym]) : nil }
          
          result = groups.transform_values do |group_items|
            aggregate(group_items, operation, field)
          end

          success(
            result: result,
            groups: groups.keys,
            operation: operation
          )
        else
          # Simple aggregation
          result = aggregate(items, operation, field)

          success(
            result: result,
            count: items.size,
            operation: operation
          )
        end
      end

      private

      def aggregate(items, operation, field)
        values = if field.present?
          items.map { |i| i.is_a?(Hash) ? (i[field] || i[field.to_sym]) : i }
        else
          items
        end

        case operation
        when 'count'
          values.size
        when 'sum'
          values.map(&:to_f).sum
        when 'average', 'avg', 'mean'
          values.empty? ? 0 : values.map(&:to_f).sum / values.size
        when 'min'
          values.map(&:to_f).min
        when 'max'
          values.map(&:to_f).max
        when 'first'
          values.first
        when 'last'
          values.last
        when 'unique', 'distinct'
          values.uniq
        when 'flatten'
          values.flatten
        else
          values.size
        end
      end
    end

    # CodeTransformExecutor - Executes AI-generated transformation code
    class CodeTransformExecutor < BaseExecutor
      def execute
        log_info "Executing custom code transform"

        code = config[:code]
        return failure("Code is required") if code.blank?

        # Verify code is tested
        unless config[:tested]
          log_warn "Executing untested code transform"
        end

        begin
          # Execute in a sandboxed context
          result = execute_sandboxed(code, inputs[:data] || inputs.to_h)

          success(result: result)
        rescue => e
          log_error "Code execution failed: #{e.message}"
          failure("Code execution failed: #{e.message}")
        end
      end

      private

      def execute_sandboxed(code, data)
        # Create a clean execution context
        sandbox = Sandbox.new(data: data, context: context.to_h)
        sandbox.execute(code)
      end

      # Simple sandbox for code execution
      class Sandbox
        attr_reader :data, :context

        ALLOWED_CLASSES = [String, Integer, Float, Array, Hash, TrueClass, FalseClass, NilClass, Symbol, Time, Date, DateTime].freeze

        def initialize(data:, context:)
          @data = data.with_indifferent_access
          @context = context.with_indifferent_access
          @result = nil
        end

        def execute(code)
          # Wrap code to capture result
          wrapped = <<~RUBY
            @result = begin
              #{code}
            end
          RUBY

          instance_eval(wrapped)
          sanitize_result(@result)
        end

        private

        def sanitize_result(value)
          case value
          when *ALLOWED_CLASSES
            value
          when Struct
            value.to_h
          else
            if value.respond_to?(:to_h)
              value.to_h
            elsif value.respond_to?(:to_a)
              value.to_a
            else
              value.to_s
            end
          end
        end
      end
    end
  end
end
