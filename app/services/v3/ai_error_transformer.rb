# frozen_string_literal: true

module V3
  # Transforms Ruby exceptions into structured, actionable responses for the LLM.
  # The AI is the primary consumer of all error messages on this platform.
  # Every error must tell the AI exactly what went wrong and how to fix it.
  class AiErrorTransformer
    class << self
      # Transform any exception into an AI-actionable error hash.
      # @param exception [Exception] the raw Ruby exception
      # @param context [Hash] optional context: { type:, tool:, action:, data: }
      # @return [Hash] structured error with :error, :error_type, :suggestion, and schema info
      def transform(exception, context = {})
        result = case exception
                 when ActiveRecord::RecordInvalid
                   handle_record_invalid(exception, context)
                 when ActiveRecord::RecordNotFound
                   handle_record_not_found(exception, context)
                 when ActiveRecord::RecordNotUnique
                   handle_record_not_unique(exception, context)
                 when PG::ForeignKeyViolation
                   handle_foreign_key_violation(exception, context)
                 when PG::UniqueViolation
                   handle_unique_violation(exception, context)
                 when PG::UndefinedColumn
                   handle_undefined_column(exception, context)
                 when PG::UndefinedTable
                   handle_undefined_table(exception, context)
                 when ArgumentError
                   handle_argument_error(exception, context)
                 when JSON::ParserError
                   handle_json_error(exception, context)
                 when Timeout::Error, Net::ReadTimeout, Net::OpenTimeout
                   handle_timeout(exception, context)
                 else
                   handle_generic(exception, context)
                 end

        result[:success] = false
        result
      end

      # Enrich any error response with schema info for the given type.
      # Call this from tools to add required/optional fields to any error message.
      def enrich_with_schema(error_message, type)
        schema = lookup_schema(type)
        return error_message unless schema

        parts = [error_message]
        parts << "Required fields for '#{type}': #{schema[:required].join(', ')}." if schema[:required]&.any?
        parts << "Optional fields: #{schema[:optional]&.first(10)&.join(', ')}." if schema[:optional]&.any?

        if schema[:defaults]&.any?
          defaults_str = schema[:defaults].select { |_, v| !v.is_a?(Proc) }.map { |k, v| "#{k}=#{v}" }.join(", ")
          parts << "Defaults: #{defaults_str}." if defaults_str.present?
        end

        parts << schema[:notes] if schema[:notes].present?
        parts.join(" ")
      end

      # Build a structured schema hint hash for inclusion in error responses.
      def schema_hint(type)
        schema = lookup_schema(type)
        return nil unless schema

        hint = {
          required_fields: schema[:required],
          optional_fields: schema[:optional]&.first(12)
        }

        if schema[:defaults]&.any?
          hint[:defaults] = schema[:defaults].select { |_, v| !v.is_a?(Proc) }
        end

        hint[:notes] = schema[:notes] if schema[:notes].present?
        hint
      end

      private

      def handle_record_invalid(exception, context)
        record = exception.record
        type = context[:type] || record&.class&.name&.underscore
        errors = record&.errors

        enriched = errors&.map do |error|
          msg = error.full_message
          msg = append_valid_values(msg, error, record)
          msg
        end || [exception.message]

        provided = context[:data]&.keys&.map(&:to_s) || []
        schema = lookup_schema(type)
        missing = schema ? (schema[:required].map(&:to_s) - provided) : []

        response = {
          error: "Validation failed: #{enriched.join('. ')}",
          error_type: "validation",
          object_type: type,
          validation_errors: enriched
        }

        if schema
          response[:required_fields] = schema[:required]
          response[:optional_fields] = schema[:optional]&.first(12)
          response[:missing_fields] = missing if missing.any?
          response[:defaults] = schema[:defaults]&.select { |_, v| !v.is_a?(Proc) }
          response[:notes] = schema[:notes] if schema[:notes].present?
        end

        if missing.any?
          response[:suggestion] = "Add missing required fields: #{missing.join(', ')}. " \
                                  "Then retry with all required fields in one call."
        else
          response[:suggestion] = "Fix the validation errors above and retry. " \
                                  "Check valid values for enum fields."
        end

        response
      end

      def handle_record_not_found(exception, context)
        type = context[:type] || extract_model_from_message(exception.message)

        {
          error: exception.message,
          error_type: "not_found",
          object_type: type,
          suggestion: "The #{type || 'record'} was not found. " \
                      "Use platform_query to search for existing records, or create a new one with platform_create."
        }
      end

      def handle_record_not_unique(exception, context)
        type = context[:type]
        field = extract_field_from_unique_error(exception.message)

        {
          error: "A #{type || 'record'} with this #{field || 'value'} already exists.",
          error_type: "duplicate",
          object_type: type,
          duplicate_field: field,
          suggestion: "Use platform_query to find the existing record, " \
                      "or use platform_update to modify it instead of creating a new one."
        }
      end

      def handle_foreign_key_violation(exception, context)
        referenced_table = exception.message[/table "(\w+)"/, 1]
        constraint = exception.message[/constraint "(\w+)"/, 1]

        {
          error: "Cannot complete this operation because related records exist in '#{referenced_table}'.",
          error_type: "foreign_key_violation",
          referenced_table: referenced_table,
          constraint: constraint,
          suggestion: "The record is referenced by other data. Delete or update the dependent records first, " \
                      "or use a different approach."
        }
      end

      def handle_unique_violation(exception, context)
        field = extract_field_from_unique_error(exception.message)
        type = context[:type]

        {
          error: "Duplicate value for '#{field || 'field'}' on #{type || 'record'}.",
          error_type: "duplicate",
          object_type: type,
          duplicate_field: field,
          suggestion: "A record with this #{field} already exists. " \
                      "Query for the existing record first, or choose a different value."
        }
      end

      def handle_undefined_column(exception, context)
        column = exception.message[/column (\S+)\.(\w+)/, 2] || exception.message[/column "?(\w+)"?/, 1]
        table = exception.message[/column (\S+)\./, 1] || context[:type]
        type = context[:type]

        response = {
          error: "Field '#{column}' does not exist on '#{table || type}'.",
          error_type: "invalid_field",
          invalid_field: column,
          object_type: type
        }

        schema = lookup_schema(type)
        if schema
          all_fields = (schema[:required] || []) + (schema[:optional] || [])
          response[:valid_fields] = all_fields
          response[:suggestion] = "Field '#{column}' is not valid. Available fields: #{all_fields.join(', ')}."
        else
          response[:suggestion] = "Field '#{column}' is not valid. Use platform_query(type: 'schema', object: '#{type}') to see available fields."
        end

        response
      end

      def handle_undefined_table(exception, context)
        table = exception.message[/relation "(\w+)"/, 1]

        {
          error: "Table '#{table}' does not exist.",
          error_type: "missing_table",
          table: table,
          suggestion: "This object type may not be set up yet. If this is a custom app module, " \
                      "ensure the app build completed successfully."
        }
      end

      def handle_argument_error(exception, context)
        {
          error: "Invalid argument: #{exception.message}",
          error_type: "invalid_argument",
          suggestion: "Check the tool's parameter format. Ensure all values are the correct type (string, number, array, etc.)."
        }
      end

      def handle_json_error(exception, context)
        {
          error: "Invalid JSON in request data.",
          error_type: "json_parse_error",
          suggestion: "Ensure the 'data' parameter is a valid JSON object with properly quoted keys and values."
        }
      end

      def handle_timeout(exception, context)
        tool = context[:tool] || "operation"

        {
          error: "The #{tool} timed out.",
          error_type: "timeout",
          suggestion: "The operation took too long. Try again, or break it into smaller operations. " \
                      "For large batch operations, reduce the batch size."
        }
      end

      def handle_generic(exception, context)
        type = context[:type]
        message = exception.message.to_s

        # Strip internal Ruby noise
        clean_message = message
          .gsub(/\n.*$/m, "")          # Remove multi-line backtraces
          .gsub(/\(pry\).*$/, "")      # Remove pry artifacts
          .truncate(300)

        response = {
          error: clean_message,
          error_type: "internal_error"
        }

        schema = lookup_schema(type)
        if schema
          response[:required_fields] = schema[:required]
          response[:suggestion] = "If this is a data issue, ensure you're providing: #{schema[:required].join(', ')}."
        else
          response[:suggestion] = "An unexpected error occurred. Try the operation again, " \
                                  "or simplify the request."
        end

        response
      end

      # Append valid enum values to a validation error message
      def append_valid_values(msg, error, record)
        return msg unless record

        attr = error.attribute.to_s
        klass = record.class

        # Check for defined_enums (Rails enums)
        if klass.respond_to?(:defined_enums) && klass.defined_enums.key?(attr)
          valid = klass.defined_enums[attr].keys
          return "#{msg}. Valid values: #{valid.join(', ')}"
        end

        # Check for common constant patterns
        const_names = ["#{attr.upcase}S", "#{attr.pluralize.upcase}", "#{attr.upcase}_VALUES", "VALID_#{attr.upcase}S"]
        const_names.each do |const_name|
          if klass.const_defined?(const_name)
            const = klass.const_get(const_name)
            values = const.is_a?(Hash) ? const.keys : const
            return "#{msg}. Valid values: #{Array(values).join(', ')}"
          end
        end

        msg
      end

      # Registry uses plural keys ("contacts", "campaigns") but tools pass singular ("contact").
      # Try both forms to find the schema.
      def lookup_schema(type)
        return nil if type.blank?
        ScoutDataRegistry.creation_schema(type.to_s) ||
          ScoutDataRegistry.creation_schema(type.to_s.pluralize) ||
          ScoutDataRegistry.creation_schema(type.to_s.singularize)
      end

      def extract_model_from_message(message)
        message[/Couldn't find (\w+)/, 1]&.underscore
      end

      def extract_field_from_unique_error(message)
        message[/Key \((\w+)\)/, 1] || message[/unique.*"(\w+)"/, 1]
      end
    end
  end
end
