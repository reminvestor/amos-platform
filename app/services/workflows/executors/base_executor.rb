# frozen_string_literal: true

module Workflows
  module Executors
    # BaseExecutor is the parent class for all node executors.
    # Each node type has its own executor that handles the specific logic.
    #
    # Executors must:
    # - Accept step, config, inputs, context, execution in initialize
    # - Implement #execute that returns { success: true/false, output: {}, error: nil }
    #
    class BaseExecutor
      attr_reader :step, :config, :inputs, :context, :execution

      def initialize(step:, config:, inputs:, context:, execution:)
        @step = step
        @config = config.with_indifferent_access
        @inputs = inputs.with_indifferent_access
        @context = context.with_indifferent_access
        @execution = execution
        @start_time = Time.current
      end

      # Override this in subclasses
      def execute
        raise NotImplementedError, "#{self.class} must implement #execute"
      end

      protected

      def success(output = {})
        {
          success: true,
          output: output,
          duration_ms: duration_ms
        }
      end

      def failure(error_message)
        {
          success: false,
          error: error_message,
          duration_ms: duration_ms
        }
      end

      def duration_ms
        ((Time.current - @start_time) * 1000).round
      end

      def entity
        execution.entity
      end

      def user
        execution.triggered_by
      end

      # Get a value from inputs, config, or context (in that order of priority)
      def get_value(key, default = nil)
        inputs[key] || config[key] || context[key] || default
      end

      # Interpolate {{variable}} references in a string
      def interpolate(template)
        return template unless template.is_a?(String)

        template.gsub(/\{\{([^}]+)\}\}/) do |match|
          var_path = $1.strip
          resolve_path(var_path) || match
        end
      end

      # Resolve a dotted path to a value
      def resolve_path(path)
        parts = path.split('.')
        current = nil

        case parts[0]
        when 'inputs'
          current = inputs
          parts = parts[1..-1]
        when 'config'
          current = config
          parts = parts[1..-1]
        when 'context', 'trigger'
          current = context
          parts = parts[1..-1]
        else
          # Try inputs first, then context
          current = inputs[parts[0]] || context
        end

        parts.each do |part|
          if current.is_a?(Hash)
            current = current[part] || current[part.to_sym]
          elsif current.is_a?(Array) && part =~ /^\d+$/
            current = current[part.to_i]
          else
            return nil
          end
        end

        current
      end

      # Log execution info
      def log_info(message)
        Rails.logger.info "[#{self.class.name.demodulize}] #{message}"
      end

      def log_warn(message)
        Rails.logger.warn "[#{self.class.name.demodulize}] #{message}"
      end

      def log_error(message)
        Rails.logger.error "[#{self.class.name.demodulize}] #{message}"
      end
    end

    # GenericExecutor is a fallback for nodes without specific executors
    class GenericExecutor < BaseExecutor
      def execute
        log_warn "No specific executor for node type: #{step['node_type']}, passing through"
        
        # Pass inputs through as outputs
        success(inputs.merge(config))
      end
    end
  end
end
