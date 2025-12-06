# frozen_string_literal: true

module Tools
  class AnalyzeDatasetTool < BaseTool
    def self.metadata
      {
        name: "analyze_dataset",
        description: "Analyze a JSON dataset with flexible aggregation, filtering, and grouping. Works with any data structure. Can load data from an artifact_id (preferred for large datasets) or accept data directly.",
        category: "analytics",
        input_schema: {
          type: "object",
          properties: {
            artifact_id: {
              type: "integer",
              description: "ID of an artifact containing the data to analyze (preferred for large datasets from execute_integration)"
            },
            data: {
              type: "array",
              description: "Array of JSON objects to analyze. Use artifact_id instead for large datasets to avoid token limits."
            },
            operations: {
              type: "array",
              description: "Array of operations to perform. Each operation is an object with: {type: 'count'|'sum'|'avg'|'min'|'max'|'group_by'|'filter'|'top'|'distinct', field: 'field_name', ...options}. Examples: {type: 'filter', field: 'status', operator: 'eq', value: 'succeeded'}, {type: 'sum', field: 'amount'}, {type: 'group_by', field: 'currency', aggregate: 'sum', aggregate_field: 'amount'}, {type: 'top', count: 10, sort_by: 'amount', order: 'desc'}"
            },
            description: {
              type: "string",
              description: "Human-readable description of what this analysis is computing"
            }
          },
          required: ["operations"]
        }
      }
    end

    def execute(args)
      artifact_id = args["artifact_id"]
      data = args["data"]
      operations = args["operations"]
      description = args["description"] || "Dataset analysis"

      return error_response("No operations specified") if operations.nil? || operations.empty?

      # Load data from artifact if artifact_id provided
      if artifact_id.present?
        data = load_data_from_artifact(artifact_id)
        return data if data.is_a?(Hash) && data[:error] # Error response
      end

      return error_response("No data provided. Either pass 'data' array or 'artifact_id' from execute_integration.") if data.nil? || data.empty?

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
        
        # Load results into canvas
        load_analysis_canvas(results, description)
        
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

    def load_data_from_artifact(artifact_id)
      artifact = Artifact.find_by(id: artifact_id)
      
      unless artifact
        return error_response("Artifact #{artifact_id} not found")
      end

      # Check access permissions
      unless artifact.user_id == @user&.id || artifact.entity_id == @entity&.id
        return error_response("Access denied to artifact #{artifact_id}")
      end

      # Load data from artifact - stored in 'sample' column (up to 100 records)
      data = artifact.sample
      
      if data.nil? || data.empty?
        return error_response("Artifact #{artifact_id} contains no data")
      end

      Rails.logger.info "[AnalyzeDataset] Loaded #{data.length} records from artifact #{artifact_id}"
      data
    end

    def load_analysis_canvas(results, description)
      html = generate_analysis_html(results, description)
      
      @context[:canvas_suggestion] = "dynamic_canvas"
      @context[:canvas_data] = {
        title: description,
        content: html,
        artifact_type: "analysis"
      }
    end

    def generate_analysis_html(results, description)
      html = <<~HTML
        <div class="analysis-results p-3">
          <div class="analysis-header mb-4">
            <h4 class="mb-2">#{description}</h4>
            <div class="text-muted small">
              <span class="badge bg-secondary me-2">#{results[:input_count]} records analyzed</span>
              <span class="badge bg-info">#{results[:final_count]} after filters</span>
            </div>
          </div>
      HTML

      # Render summary metrics (count, sum, avg, min, max)
      metrics_html = generate_metrics_html(results[:results])
      html += metrics_html if metrics_html.present?

      # Render grouped results
      if results[:results][:grouped].present?
        html += generate_grouped_html(results[:results][:grouped])
      end

      # Render top results
      if results[:results][:top].present?
        html += generate_top_html(results[:results][:top])
      end

      # Render distinct results
      if results[:results][:distinct].present?
        html += generate_distinct_html(results[:results][:distinct])
      end

      # Render date range
      if results[:results][:date_range].present?
        html += generate_date_range_html(results[:results][:date_range])
      end

      html += "</div>"
      html
    end

    def generate_metrics_html(results)
      metrics = []
      
      if results[:count].present?
        metrics << { label: "Count", value: format_number(results[:count]), icon: "📊" }
      end
      
      results[:sum]&.each do |field, value|
        metrics << { label: "Sum (#{field.to_s.humanize})", value: format_currency_or_number(value), icon: "➕" }
      end
      
      results[:avg]&.each do |field, value|
        metrics << { label: "Average (#{field.to_s.humanize})", value: format_currency_or_number(value), icon: "📈" }
      end
      
      results[:min]&.each do |field, value|
        metrics << { label: "Min (#{field.to_s.humanize})", value: format_currency_or_number(value), icon: "⬇️" }
      end
      
      results[:max]&.each do |field, value|
        metrics << { label: "Max (#{field.to_s.humanize})", value: format_currency_or_number(value), icon: "⬆️" }
      end

      return nil if metrics.empty?

      cards = metrics.map do |m|
        <<~HTML
          <div class="col-md-3 col-sm-6 mb-3">
            <div class="card h-100 border-0 shadow-sm">
              <div class="card-body text-center">
                <div class="display-6 mb-2">#{m[:icon]}</div>
                <h5 class="card-title text-primary mb-1">#{m[:value]}</h5>
                <p class="card-text text-muted small mb-0">#{m[:label]}</p>
              </div>
            </div>
          </div>
        HTML
      end.join

      <<~HTML
        <div class="metrics-section mb-4">
          <h5 class="mb-3">📊 Summary Metrics</h5>
          <div class="row">#{cards}</div>
        </div>
      HTML
    end

    def generate_grouped_html(grouped_data)
      sections = grouped_data.map do |field, groups|
        rows = groups.map do |key, value|
          <<~HTML
            <tr>
              <td><strong>#{key || "(empty)"}</strong></td>
              <td class="text-end">#{format_currency_or_number(value)}</td>
            </tr>
          HTML
        end.join

        <<~HTML
          <div class="grouped-section mb-4">
            <h5 class="mb-3">📁 Grouped by #{field.to_s.humanize}</h5>
            <div class="table-responsive">
              <table class="table table-hover">
                <thead class="table-light">
                  <tr>
                    <th>#{field.to_s.humanize}</th>
                    <th class="text-end">Value</th>
                  </tr>
                </thead>
                <tbody>#{rows}</tbody>
              </table>
            </div>
          </div>
        HTML
      end.join

      sections
    end

    def generate_top_html(top_items)
      return "" if top_items.empty?

      columns = top_items.first.keys.first(8) # Limit columns for display
      
      header = columns.map { |col| "<th>#{col.to_s.humanize}</th>" }.join
      
      rows = top_items.map do |item|
        cells = columns.map { |col| "<td>#{format_cell_value(item[col] || item[col.to_s])}</td>" }.join
        "<tr>#{cells}</tr>"
      end.join

      <<~HTML
        <div class="top-section mb-4">
          <h5 class="mb-3">🏆 Top Results</h5>
          <div class="table-responsive">
            <table class="table table-striped table-hover">
              <thead class="table-light">
                <tr>#{header}</tr>
              </thead>
              <tbody>#{rows}</tbody>
            </table>
          </div>
        </div>
      HTML
    end

    def generate_distinct_html(distinct_data)
      sections = distinct_data.map do |field, data|
        values = data[:values].first(20) # Limit display
        badges = values.map { |v| "<span class='badge bg-secondary me-1 mb-1'>#{v}</span>" }.join
        more = data[:count] > 20 ? "<span class='text-muted'>...and #{data[:count] - 20} more</span>" : ""

        <<~HTML
          <div class="distinct-section mb-4">
            <h5 class="mb-3">🔍 Distinct #{field.to_s.humanize} (#{data[:count]} unique)</h5>
            <div class="d-flex flex-wrap">#{badges}#{more}</div>
          </div>
        HTML
      end.join

      sections
    end

    def generate_date_range_html(date_range)
      <<~HTML
        <div class="date-range-section mb-4">
          <h5 class="mb-3">📅 Date Range (#{date_range[:field]})</h5>
          <div class="d-flex gap-4">
            <div><strong>From:</strong> #{date_range[:min]}</div>
            <div><strong>To:</strong> #{date_range[:max]}</div>
          </div>
        </div>
      HTML
    end

    def format_number(value)
      return "0" if value.nil?
      value.to_i.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse
    end

    def format_currency_or_number(value)
      return "0" if value.nil?
      
      # Check if this looks like cents (common for Stripe)
      if value.is_a?(Numeric) && value.abs >= 100
        # Format as currency (assuming cents)
        dollars = value / 100.0
        "$#{format('%.2f', dollars)}"
      elsif value.is_a?(Float)
        format('%.2f', value)
      else
        format_number(value)
      end
    end

    def format_cell_value(value)
      case value
      when nil
        "-"
      when true
        "✅"
      when false
        "❌"
      when Numeric
        format_currency_or_number(value)
      when Hash, Array
        "<code>#{value.to_json.truncate(50)}</code>"
      else
        value.to_s.truncate(100)
      end
    end
  end
end
