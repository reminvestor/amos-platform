# frozen_string_literal: true

module Tools
  class AnalyzeDatasetTool < BaseTool
    tool_name "analyze_dataset"
    description "Analyze a JSON dataset with flexible aggregation, filtering, and grouping. Works with any data structure - the AI should first fetch sample records to understand the schema, then use this tool to analyze the full dataset."

    parameter :data, type: :array, required: true, description: "Array of JSON objects to analyze (e.g., from execute_integration results)"
    parameter :operations, type: :array, required: true, description: "Array of operations to perform. Each operation is an object with: {type: 'count'|'sum'|'avg'|'min'|'max'|'group_by'|'filter'|'top', field: 'field_name', ...options}"
    parameter :description, type: :string, required: false, description: "Human-readable description of what this analysis is computing"

    # Example operations:
    # {type: "filter", field: "status", operator: "eq", value: "succeeded"}
    # {type: "filter", field: "amount", operator: "gt", value: 1000}
    # {type: "sum", field: "amount"}
    # {type: "avg", field: "amount"}
    # {type: "count"}
    # {type: "group_by", field: "status", aggregate: "count"}
    # {type: "group_by", field: "currency", aggregate: "sum", aggregate_field: "amount"}
    # {type: "top", count: 10, sort_by: "amount", order: "desc"}

    def execute(args)
      data = args["data"]
      operations = args["operations"]
      description = args["description"] || "Dataset analysis"

      return error_response("No data provided") if data.nil? || data.empty?
      return error_response("No operations specified") if operations.nil? || operations.empty?

      # Work with a copy of the data
      working_data = data.deep_dup
      results = {
        description: description,
        input_count: data.count,
        operations_applied: [],
        results: {}
      }

      begin
        operations.each do |op|
          op = op.with_indifferent_access
          op_type = op[:type]&.to_s&.downcase

          case op_type
          when "filter"
            working_data = apply_filter(working_data, op)
            results[:operations_applied] << { type: "filter", field: op[:field], operator: op[:operator], value: op[:value], remaining_count: working_data.count }

          when "count"
            results[:results][:count] = working_data.count
            results[:operations_applied] << { type: "count", result: working_data.count }

          when "sum"
            field = op[:field]
            total = working_data.sum { |item| extract_numeric(item, field) }
            results[:results][:sum] ||= {}
            results[:results][:sum][field] = total
            results[:operations_applied] << { type: "sum", field: field, result: total }

          when "avg"
            field = op[:field]
            values = working_data.map { |item| extract_numeric(item, field) }
            avg = values.any? ? values.sum.to_f / values.count : 0
            results[:results][:avg] ||= {}
            results[:results][:avg][field] = avg.round(2)
            results[:operations_applied] << { type: "avg", field: field, result: avg.round(2) }

          when "min"
            field = op[:field]
            min_val = working_data.map { |item| extract_numeric(item, field) }.min
            results[:results][:min] ||= {}
            results[:results][:min][field] = min_val
            results[:operations_applied] << { type: "min", field: field, result: min_val }

          when "max"
            field = op[:field]
            max_val = working_data.map { |item| extract_numeric(item, field) }.max
            results[:results][:max] ||= {}
            results[:results][:max][field] = max_val
            results[:operations_applied] << { type: "max", field: field, result: max_val }

          when "group_by"
            field = op[:field]
            aggregate = op[:aggregate]&.to_s || "count"
            aggregate_field = op[:aggregate_field]
            
            grouped = working_data.group_by { |item| extract_value(item, field) }
            
            grouped_results = grouped.transform_values do |items|
              case aggregate
              when "count"
                items.count
              when "sum"
                items.sum { |item| extract_numeric(item, aggregate_field) }
              when "avg"
                values = items.map { |item| extract_numeric(item, aggregate_field) }
                values.any? ? (values.sum.to_f / values.count).round(2) : 0
              else
                items.count
              end
            end
            
            results[:results][:grouped] ||= {}
            results[:results][:grouped][field] = grouped_results
            results[:operations_applied] << { type: "group_by", field: field, aggregate: aggregate, groups: grouped_results.keys.count }

          when "top"
            count = op[:count] || 10
            sort_by = op[:sort_by]
            order = op[:order]&.to_s || "desc"
            
            sorted = if sort_by
              working_data.sort_by { |item| extract_numeric(item, sort_by) }
            else
              working_data
            end
            sorted = sorted.reverse if order == "desc"
            
            results[:results][:top] = sorted.first(count)
            results[:operations_applied] << { type: "top", count: count, sort_by: sort_by, order: order }

          when "distinct"
            field = op[:field]
            distinct_values = working_data.map { |item| extract_value(item, field) }.uniq.compact
            results[:results][:distinct] ||= {}
            results[:results][:distinct][field] = { values: distinct_values, count: distinct_values.count }
            results[:operations_applied] << { type: "distinct", field: field, count: distinct_values.count }

          when "date_range"
            field = op[:field]
            dates = working_data.map { |item| extract_value(item, field) }.compact
            
            # Try to parse as timestamps or date strings
            parsed_dates = dates.map do |d|
              if d.is_a?(Numeric)
                Time.at(d)
              elsif d.is_a?(String)
                Time.parse(d) rescue nil
              else
                nil
              end
            end.compact
            
            if parsed_dates.any?
              results[:results][:date_range] = {
                field: field,
                min: parsed_dates.min&.iso8601,
                max: parsed_dates.max&.iso8601
              }
            end
            results[:operations_applied] << { type: "date_range", field: field }

          else
            results[:operations_applied] << { type: op_type, error: "Unknown operation type" }
          end
        end

        results[:final_count] = working_data.count
        results[:success] = true
        
        results

      rescue => e
        Rails.logger.error "[AnalyzeDataset] Error: #{e.message}"
        Rails.logger.error e.backtrace.first(5).join("\n")
        error_response("Analysis failed: #{e.message}")
      end
    end

    private

    def apply_filter(data, op)
      field = op[:field]
      operator = op[:operator]&.to_s || "eq"
      value = op[:value]

      data.select do |item|
        item_value = extract_value(item, field)
        
        case operator
        when "eq", "=="
          item_value == value || item_value.to_s == value.to_s
        when "neq", "!=", "ne"
          item_value != value && item_value.to_s != value.to_s
        when "gt", ">"
          extract_numeric(item, field) > value.to_f
        when "gte", ">="
          extract_numeric(item, field) >= value.to_f
        when "lt", "<"
          extract_numeric(item, field) < value.to_f
        when "lte", "<="
          extract_numeric(item, field) <= value.to_f
        when "contains", "like"
          item_value.to_s.downcase.include?(value.to_s.downcase)
        when "in"
          Array(value).include?(item_value) || Array(value).map(&:to_s).include?(item_value.to_s)
        when "not_in"
          !Array(value).include?(item_value) && !Array(value).map(&:to_s).include?(item_value.to_s)
        when "null", "nil"
          item_value.nil?
        when "not_null", "present"
          !item_value.nil?
        when "true"
          item_value == true || item_value == "true"
        when "false"
          item_value == false || item_value == "false"
        else
          true
        end
      end
    end

    def extract_value(item, field)
      return nil if field.nil?
      
      # Support nested fields like "customer.email" or "items.0.price"
      parts = field.to_s.split(".")
      value = item
      
      parts.each do |part|
        if value.is_a?(Hash)
          value = value[part] || value[part.to_sym]
        elsif value.is_a?(Array) && part.match?(/^\d+$/)
          value = value[part.to_i]
        else
          return nil
        end
      end
      
      value
    end

    def extract_numeric(item, field)
      value = extract_value(item, field)
      return 0 if value.nil?
      
      if value.is_a?(Numeric)
        value
      else
        value.to_s.gsub(/[^0-9.-]/, "").to_f
      end
    end

    def error_response(message)
      { success: false, error: message }
    end
  end
end

