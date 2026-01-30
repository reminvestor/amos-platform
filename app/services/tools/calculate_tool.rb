# frozen_string_literal: true

module Tools
  class CalculateTool < BaseTool
    # Safe math operations allowed
    ALLOWED_OPERATIONS = %w[+ - * / % ** sqrt abs round ceil floor sum avg min max count].freeze
    
    def self.metadata
      {
        name: "calculate",
        description: "Perform accurate mathematical calculations. Use this for any math operations instead of calculating in your head. Supports basic arithmetic, aggregations (sum, avg, min, max), and operations on arrays of numbers.",
        category: "utility",
        input_schema: {
          type: "object",
          properties: {
            expression: {
              type: "string",
              description: "Math expression to evaluate. Examples: '175 + 138 + 103', 'sum([100, 200, 300])', 'avg([10, 20, 30])', '(500 * 1.2) - 100'"
            },
            values: {
              type: "array",
              items: { type: "number" },
              description: "Array of numbers for aggregate operations (sum, avg, min, max, count)"
            },
            operation: {
              type: "string",
              description: "Operation for array values: sum, avg, min, max, count"
            },
            precision: {
              type: "integer",
              description: "Decimal places for rounding result (default: 2)"
            }
          },
          required: []
        }
      }
    end

    def self.read_only?
      true
    end

    def execute(args)
      log_execution(args)

      expression = get_arg(args, :expression)
      values = get_arg(args, :values)
      operation = get_arg(args, :operation)
      precision = get_arg(args, :precision, 2)

      # Handle array operations
      if values.present?
        return calculate_array_operation(values, operation || 'sum', precision)
      end

      # Handle expression
      if expression.present?
        return evaluate_expression(expression, precision)
      end

      error_response("Please provide either an 'expression' to evaluate or 'values' array with 'operation'.")
    end

    private

    def calculate_array_operation(values, operation, precision)
      # Ensure all values are numeric
      numeric_values = values.map do |v|
        case v
        when Numeric then v
        when String then parse_number(v)
        else
          return error_response("Invalid value in array: #{v}")
        end
      end.compact

      if numeric_values.empty?
        return error_response("No valid numeric values provided")
      end

      result = case operation.to_s.downcase
      when 'sum'
        numeric_values.sum
      when 'avg', 'average', 'mean'
        numeric_values.sum / numeric_values.count.to_f
      when 'min', 'minimum'
        numeric_values.min
      when 'max', 'maximum'
        numeric_values.max
      when 'count'
        numeric_values.count
      when 'median'
        sorted = numeric_values.sort
        mid = sorted.length / 2
        sorted.length.odd? ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2.0
      when 'range'
        numeric_values.max - numeric_values.min
      else
        return error_response("Unknown operation: #{operation}. Use: sum, avg, min, max, count, median, range")
      end

      formatted_result = result.is_a?(Float) ? result.round(precision) : result

      success_response(
        operation: operation,
        values: numeric_values,
        result: formatted_result,
        formatted: format_number(formatted_result),
        value_count: numeric_values.count,
        message: "#{operation.capitalize} of #{numeric_values.count} values = #{format_number(formatted_result)}"
      )
    end

    def evaluate_expression(expression, precision)
      # Clean and validate expression
      cleaned = expression.to_s.strip

      # Check for dangerous patterns
      if contains_dangerous_code?(cleaned)
        return error_response("Expression contains disallowed operations")
      end

      # Handle special function syntax
      cleaned = convert_functions(cleaned)

      # Evaluate safely
      begin
        result = safe_eval(cleaned)
        
        return error_response("Calculation resulted in undefined value") if result.nil?
        return error_response("Result is not a number") unless result.is_a?(Numeric)
        return error_response("Result is infinite") if result.respond_to?(:infinite?) && result.infinite?
        return error_response("Result is not a number (NaN)") if result.respond_to?(:nan?) && result.nan?

        formatted_result = result.is_a?(Float) ? result.round(precision) : result

        success_response(
          expression: expression,
          result: formatted_result,
          formatted: format_number(formatted_result),
          message: "#{expression} = #{format_number(formatted_result)}"
        )
      rescue ZeroDivisionError
        error_response("Division by zero")
      rescue SyntaxError => e
        error_response("Invalid expression syntax: #{e.message}")
      rescue => e
        Rails.logger.error "Calculate error: #{e.message}"
        error_response("Failed to evaluate expression: #{e.message}")
      end
    end

    def contains_dangerous_code?(expr)
      # Block any potential code execution
      dangerous_patterns = [
        /`/,           # Backticks
        /system/i,     # System calls
        /exec/i,       # Exec
        /eval/i,       # Eval (we use our own safe_eval)
        /require/i,    # Require
        /load/i,       # Load
        /File/i,       # File operations
        /IO/i,         # IO operations
        /Dir/i,        # Directory operations
        /ENV/i,        # Environment
        /\$/,          # Global vars
        /@/,           # Instance vars
        /class/i,      # Class definition
        /def\s/i,      # Method definition
        /module/i,     # Module
        /lambda/i,     # Lambda
        /proc/i,       # Proc
        /->/,          # Lambda arrow
        /send/i,       # Method send
        /__/,          # Dunder methods
        /binding/i,    # Binding
        /open/i,       # Open
      ]

      dangerous_patterns.any? { |p| expr.match?(p) }
    end

    def convert_functions(expr)
      # Convert common math function syntax to Ruby
      expr = expr.gsub(/sum\s*\(\s*\[([^\]]+)\]\s*\)/i) { "[#{$1}].sum" }
      expr = expr.gsub(/avg\s*\(\s*\[([^\]]+)\]\s*\)/i) { "([#{$1}].sum.to_f / [#{$1}].count)" }
      expr = expr.gsub(/min\s*\(\s*\[([^\]]+)\]\s*\)/i) { "[#{$1}].min" }
      expr = expr.gsub(/max\s*\(\s*\[([^\]]+)\]\s*\)/i) { "[#{$1}].max" }
      expr = expr.gsub(/sqrt\s*\(([^)]+)\)/i) { "Math.sqrt(#{$1})" }
      expr = expr.gsub(/abs\s*\(([^)]+)\)/i) { "(#{$1}).abs" }
      expr = expr.gsub(/round\s*\(([^)]+)\)/i) { "(#{$1}).round" }
      expr = expr.gsub(/ceil\s*\(([^)]+)\)/i) { "(#{$1}).ceil" }
      expr = expr.gsub(/floor\s*\(([^)]+)\)/i) { "(#{$1}).floor" }
      expr = expr.gsub(/pow\s*\(([^,]+),\s*([^)]+)\)/i) { "(#{$1}) ** (#{$2})" }
      expr
    end

    def safe_eval(expr)
      # Only allow numbers, operators, parentheses, and safe methods
      allowed_pattern = /\A[\d\s+\-*\/%()\[\],.\^]+\z/
      
      # Also allow Math. methods and array methods
      safe_expr = expr.gsub(/Math\.(sqrt|log|exp|sin|cos|tan|abs)/, 'MATH_FUNC')
      safe_expr = safe_expr.gsub(/\.(sum|min|max|count|to_f|round|ceil|floor|abs)/, '.ARRAY_METHOD')
      
      unless safe_expr.gsub(/MATH_FUNC|\.ARRAY_METHOD/, '').match?(allowed_pattern)
        raise "Expression contains disallowed characters"
      end

      # Convert integer division to float division to preserve decimals
      # e.g., "10 / 3" becomes "10.0 / 3" to return 3.333... instead of 3
      float_expr = expr.gsub(/(\d+)\s*\/\s*(\d+)/) do |match|
        "#{$1}.0 / #{$2}"
      end

      # Evaluate in a restricted context
      binding.eval(float_expr)
    end

    def parse_number(str)
      return nil if str.nil?
      # Handle currency formatting
      cleaned = str.to_s.gsub(/[$,\s]/, '')
      return nil if cleaned.empty?
      
      if cleaned.include?('.')
        cleaned.to_f
      else
        cleaned.to_i
      end
    rescue
      nil
    end

    def format_number(num)
      return num.to_s unless num.is_a?(Numeric)
      
      if num.is_a?(Integer) || (num.is_a?(Float) && num == num.to_i)
        num.to_i.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse
      else
        parts = num.round(2).to_s.split('.')
        parts[0] = parts[0].reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse
        parts.join('.')
      end
    end
  end
end
