module Tools
  class CreateDynamicVisualizationTool < BaseTool
    def self.metadata
      {
        name: "create_dynamic_visualization",
        description: "Create custom HTML visualizations for data analysis and reporting",
        category: "analytics",
        input_schema: {
          type: "object",
          properties: {
            title: {
              type: "string",
              description: "Title for the visualization"
            },
            data: {
              type: "object",
              description: "Data to visualize"
            },
            visualization_type: {
              type: "string",
              enum: [ "comparison", "dashboard", "report", "custom" ],
              description: "Type of visualization to create"
            },
            options: {
              type: "object",
              description: "Additional options for the visualization"
            }
          },
          required: [ "title", "data" ]
        }
      }
    end

    def execute(args)
      log_execution(args)

      title = get_arg(args, :title)
      data = get_arg(args, :data)
      viz_type = get_arg(args, :visualization_type, "custom")
      options = get_arg(args, :options, {})

      # Validate required args
      if error = validate_required_args(args, [ :title, :data ])
        return error
      end

      begin
        # Generate visualization HTML based on type
        html_content = case viz_type
        when "comparison"
          generate_comparison_visualization(title, data, options)
        when "dashboard"
          generate_dashboard_visualization(title, data, options)
        when "report"
          generate_report_visualization(title, data, options)
        else
          generate_custom_visualization(title, data, options)
        end

        # Load the visualization in canvas
        load_visualization_canvas(title, html_content)

        success_response(
          title: title,
          visualization_type: viz_type,
          canvas_loaded: true,
          message: "Created #{viz_type} visualization: #{title}"
        )
      rescue => e
        Rails.logger.error "Visualization creation failed: #{e.message}"
        error_response("Failed to create visualization: #{e.message}")
      end
    end

    private

    def generate_comparison_visualization(title, data, options)
      # Extract comparison data
      items = data["items"] || data[:items] || []
      metrics = data["metrics"] || data[:metrics] || []

      <<~HTML
        <div class="comparison-visualization">
          <h3>#{title}</h3>
        #{'  '}
          <div class="comparison-grid">
            #{generate_comparison_cards(items, metrics)}
          </div>
        #{'  '}
          #{generate_comparison_chart(items, metrics) if items.length <= 10}
        </div>

        <style>
          .comparison-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(250px, 1fr));
            gap: 20px;
            margin: 20px 0;
          }
        #{'  '}
          .comparison-card {
            background: white;
            border: 1px solid #e0e0e0;
            border-radius: 8px;
            padding: 20px;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1);
          }
        #{'  '}
          .comparison-card h4 {
            margin: 0 0 15px 0;
            color: #333;
          }
        #{'  '}
          .metric {
            margin: 10px 0;
            display: flex;
            justify-content: space-between;
          }
        #{'  '}
          .metric-label {
            color: #666;
          }
        #{'  '}
          .metric-value {
            font-weight: bold;
            color: #333;
          }
        #{'  '}
          .metric-positive {
            color: #4caf50;
          }
        #{'  '}
          .metric-negative {
            color: #f44336;
          }
        </style>
      HTML
    end

    def generate_dashboard_visualization(title, data, options)
      # Dynamically generate dashboard based on data structure
      <<~HTML
        <div class="dashboard-visualization">
          <div class="dashboard-header">
            <h2>#{title}</h2>
            <p class="text-muted">#{options['subtitle'] || "Generated on #{Time.current.strftime('%B %d, %Y')}"}</p>
          </div>
        #{'  '}
          #{generate_dynamic_content(data, options)}
        </div>

        <style>
          .dashboard-header {
            margin-bottom: 30px;
            padding-bottom: 20px;
            border-bottom: 2px solid #e0e0e0;
          }
        #{'  '}
          .dashboard-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(300px, 1fr));
            gap: 25px;
          }
        #{'  '}
          .dashboard-widget {
            background: white;
            border: 1px solid #e0e0e0;
            border-radius: 8px;
            padding: 20px;
            min-height: 200px;
          }
        #{'  '}
          .widget-header {
            display: flex;
            justify-content: space-between;
            align-items: center;
            margin-bottom: 15px;
          }
        #{'  '}
          .widget-title {
            font-size: 18px;
            font-weight: 600;
            color: #333;
          }
        #{'  '}
          .widget-value {
            font-size: 32px;
            font-weight: bold;
            color: #1976d2;
            margin: 20px 0;
          }
        #{'  '}
          .widget-chart {
            margin-top: 20px;
          }
        </style>
      HTML
    end

    def generate_report_visualization(title, data, options)
      # Generate a structured report
      sections = data["sections"] || data[:sections] || []

      # If no sections provided, generate content from the raw data
      report_content = if sections.empty?
        generate_dynamic_content(data, options)
      else
        generate_report_sections(sections)
      end

      <<~HTML
        <div class="report-visualization">
          <div class="report-header">
            <h1>#{title}</h1>
            <div class="report-meta">
              <p><strong>Generated:</strong> #{Time.current.strftime('%B %d, %Y at %I:%M %p')}</p>
              <p><strong>Entity:</strong> #{entity.name}</p>
            </div>
          </div>
        #{'  '}
          <div class="report-content">
            #{report_content}
          </div>
        #{'  '}
          <div class="report-footer">
            <p class="text-muted">This report was automatically generated by Amos AI</p>
          </div>
        </div>

        <style>
          /* Force all report text to be dark and readable */
          .report-visualization,
          .report-visualization * {
            color: #212529 !important;
          }
        #{'  '}
          .report-header {
            background: #f8f9fa;
            padding: 30px;
            border-radius: 8px;
            margin-bottom: 30px;
          }
        #{'  '}
          .report-header h1 {
            color: #212529 !important;
            font-weight: 600;
          }
        #{'  '}
          .report-meta {
            margin-top: 20px;
            color: #6c757d !important;
          }
        #{'  '}
          .report-meta p,
          .report-meta strong {
            color: #6c757d !important;
          }
        #{'  '}
          .report-section {
            margin: 30px 0;
            padding: 20px;
            background: white;
            border: 1px solid #e0e0e0;
            border-radius: 8px;
          }
        #{'  '}
          .section-title {
            font-size: 24px;
            color: #212529 !important;
            margin-bottom: 20px;
            padding-bottom: 10px;
            border-bottom: 2px solid #e0e0e0;
            font-weight: 600;
          }
        #{'  '}
          .report-content {
            color: #212529 !important;
          }
        #{'  '}
          .report-content * {
            color: #212529 !important;
          }
        #{'  '}
          .report-footer {
            margin-top: 40px;
            padding-top: 20px;
            border-top: 1px solid #e0e0e0;
            text-align: center;
          }
        #{'  '}
          .report-footer .text-muted {
            color: #6c757d !important;
          }
        </style>
      HTML
    end

    def generate_custom_visualization(title, data, options)
      # Flexible custom visualization
      <<~HTML
        <div class="custom-visualization">
          <h2>#{title}</h2>
        #{'  '}
          <div class="visualization-content">
            #{format_data_as_html(data)}
          </div>
        </div>

        <style>
          .custom-visualization {
            padding: 20px;
          }
        #{'  '}
          .visualization-content {
            margin-top: 20px;
          }
        #{'  '}
          .data-table {
            width: 100%;
            border-collapse: collapse;
            margin: 20px 0;
          }
        #{'  '}
          .data-table th,
          .data-table td {
            padding: 12px;
            text-align: left;
            border-bottom: 1px solid #e0e0e0;
          }
        #{'  '}
          .data-table th {
            background-color: #f8f9fa;
            font-weight: 600;
            color: #333;
          }
        #{'  '}
          .data-table tr:hover {
            background-color: #f8f9fa;
          }
        </style>
      HTML
    end

    def generate_comparison_cards(items, metrics)
      items.map do |item|
        name = item["name"] || item[:name] || "Unknown"
        values = item["values"] || item[:values] || {}

        <<~HTML
          <div class="comparison-card">
            <h4>#{name}</h4>
            #{metrics.map { |metric|
              value = values[metric] || values[metric.to_sym] || 0
              css_class = value > 0 ? 'metric-positive' : value < 0 ? 'metric-negative' : ''
              # {'    '}
              <<~METRIC
                <div class="dynamic-metric">
                  <span class="dynamic-metric-label">#{metric.to_s.humanize}:</span>
                  <span class="dynamic-metric-value #{css_class}">#{format_metric_value(value)}</span>
                </div>
              METRIC
            }.join}
          </div>
        HTML
      end.join
    end

    def generate_comparison_chart(items, metrics)
      # Simple bar chart visualization
      chart_id = "chart-#{SecureRandom.hex(8)}"

      <<~HTML
        <div class="comparison-chart" style="margin-top: 40px;">
          <canvas id="#{chart_id}" width="400" height="200"></canvas>
        </div>

        <script src="https://cdn.jsdelivr.net/npm/chart.js"></script>
        <script>
          (function() {
            const ctx = document.getElementById('#{chart_id}').getContext('2d');
            new Chart(ctx, {
              type: 'bar',
              data: {
                labels: #{items.map { |i| i['name'] || i[:name] }.to_json},
                datasets: #{metrics.map { |metric|
                  {
                    label: metric.to_s.humanize,
                    data: items.map { |i| (i['values'] || i[:values] || {})[metric] || 0 },
                    backgroundColor: "rgba(#{rand(255)}, #{rand(255)}, #{rand(255)}, 0.6)"
                  }
                }.to_json}
              },
              options: {
                responsive: true,
                maintainAspectRatio: false,
                scales: {
                  y: {
                    beginAtZero: true
                  }
                }
              }
            });
          })();
        </script>
      HTML
    end

    def generate_dashboard_widgets(widgets)
      widgets.map do |widget|
        type = widget["type"] || widget[:type] || "metric"

        case type
        when "metric"
          generate_metric_widget(widget)
        when "chart"
          generate_chart_widget(widget)
        when "list"
          generate_list_widget(widget)
        else
          generate_text_widget(widget)
        end
      end.join
    end

    def generate_metric_widget(widget)
      <<~HTML
        <div class="dashboard-widget">
          <div class="widget-header">
            <div class="widget-title">#{widget['title'] || widget[:title]}</div>
            #{widget['icon'] ? "<i class='#{widget['icon']}'></i>" : ''}
          </div>
          <div class="widget-value">#{format_metric_value(widget['value'] || widget[:value])}</div>
          #{widget['subtitle'] ? "<p class='text-muted'>#{widget['subtitle']}</p>" : ''}
        </div>
      HTML
    end

    def generate_report_sections(sections)
      sections.map do |section|
        <<~HTML
          <div class="report-section">
            <h3 class="section-title">#{section['title'] || section[:title]}</h3>
            <div class="section-content">
              #{format_section_content(section['content'] || section[:content])}
            </div>
          </div>
        HTML
      end.join
    end

    def format_data_as_html(data)
      case data
      when Array
        if data.first.is_a?(Hash)
          # Array of objects - create table
          generate_data_table(data)
        else
          # Simple array - create list
          "<ul>#{data.map { |item| "<li>#{item}</li>" }.join}</ul>"
        end
      when Hash
        # Key-value pairs
        "<dl>#{data.map { |k, v| "<dt>#{k.to_s.humanize}</dt><dd>#{format_value(v)}</dd>" }.join}</dl>"
      else
        # Simple value
        "<p>#{data}</p>"
      end
    end

    def generate_data_table(data)
      return "<p>No data to display</p>" if data.empty?

      columns = data.first.keys

      <<~HTML
        <table class="data-table">
          <thead>
            <tr>
              #{columns.map { |col| "<th>#{col.to_s.humanize}</th>" }.join}
            </tr>
          </thead>
          <tbody>
            #{data.map { |row|
              "<tr>#{columns.map { |col| "<td>#{format_value(row[col])}</td>" }.join}</tr>"
            }.join}
          </tbody>
        </table>
      HTML
    end

    def format_section_content(content)
      case content
      when String
        "<p>#{content}</p>"
      when Array
        format_data_as_html(content)
      when Hash
        format_data_as_html(content)
      else
        "<p>#{content}</p>"
      end
    end

    def format_metric_value(value)
      case value
      when Numeric
        if value >= 1_000_000
          "#{(value / 1_000_000.0).round(1)}M"
        elsif value >= 1_000
          "#{(value / 1_000.0).round(1)}K"
        elsif value.is_a?(Float)
          "%.2f" % value
        else
          value.to_s
        end
      else
        value.to_s
      end
    end

    def format_value(value)
      case value
      when Time, DateTime
        value.strftime("%Y-%m-%d %H:%M")
      when Date
        value.strftime("%Y-%m-%d")
      when true
        "✓"
      when false
        "✗"
      when nil
        "-"
      else
        value.to_s
      end
    end

    def generate_dynamic_content(data, options = {})
      # Intelligently render any data structure
      content_parts = []

      # If data has a summary or metrics, show them as cards
      if data["summary"] || data[:summary]
        summary = data["summary"] || data[:summary]
        content_parts << generate_metric_cards(summary)
      end

      # Look for any array data to display
      data.each do |key, value|
        next if key.to_s == "summary" # Already handled

        if value.is_a?(Array) && !value.empty?
          content_parts << "<div class='data-section'>"
          content_parts << "<h3>#{key.to_s.humanize}</h3>"

          if value.first.is_a?(Hash)
            # Array of objects - create cards or table based on size
            if value.length <= 10
              content_parts << generate_object_cards(value)
            else
              content_parts << generate_responsive_table(value)
            end
          else
            # Simple array
            content_parts << generate_list(value)
          end

          content_parts << "</div>"
        elsif value.is_a?(Hash) && !value.empty?
          # Nested object - show as details
          content_parts << "<div class='data-section'>"
          content_parts << "<h3>#{key.to_s.humanize}</h3>"
          content_parts << generate_key_value_display(value)
          content_parts << "</div>"
        end
      end

      # If no structured content was generated, fall back to generic display
      if content_parts.empty?
        content_parts << format_data_as_html(data)
      end

      <<~HTML
        <div class="dynamic-content">
          #{content_parts.join("\n")}
        </div>

        <style>
          /* Force dark text for all elements */
          .dynamic-content {
            padding: 20px;
            color: #212529 !important;
          }
        #{'  '}
          .dynamic-content * {
            color: #212529 !important;
          }
        #{'  '}
          .dynamic-content h1,
          .dynamic-content h2,
          .dynamic-content h3,
          .dynamic-content h4,
          .dynamic-content h5,
          .dynamic-content h6,
          .dynamic-content p,
          .dynamic-content div,
          .dynamic-content span,
          .dynamic-content td,
          .dynamic-content th,
          .dynamic-content li,
          .dynamic-content dt,
          .dynamic-content dd {
            color: #212529 !important;
          }
        #{'  '}
          .metric-cards {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
            gap: 20px;
            margin-bottom: 30px;
          }
        #{'  '}
          .dynamic-metric-card {
            background: #ffffff !important;
            background-color: #ffffff !important;
            border: 1px solid #e0e0e0 !important;
            border-radius: 8px !important;
            padding: 20px !important;
            text-align: center !important;
            box-shadow: 0 2px 4px rgba(0,0,0,0.05) !important;
            transition: transform 0.2s, box-shadow 0.2s;
            color: #212529 !important;
          }
        #{'  '}
          .dynamic-metric-card * {
            color: inherit !important;
          }
        #{'  '}
          .dynamic-metric-card:hover {
            transform: translateY(-2px);
            box-shadow: 0 4px 8px rgba(0,0,0,0.1) !important;
          }
        #{'  '}
          .dynamic-metric-value {
            font-size: 36px !important;
            font-weight: 700 !important;
            color: #212529 !important;
            margin: 10px 0 !important;
            line-height: 1.2 !important;
            display: block !important;
          }
        #{'  '}
          .dynamic-metric-label {
            font-size: 14px !important;
            color: #6c757d !important;
            text-transform: capitalize !important;
            font-weight: 600 !important;
            letter-spacing: 0.5px !important;
            display: block !important;
          }
        #{'  '}
          /* Override any bootstrap text color classes */
          .dynamic-content .text-white {
            color: #212529 !important;
          }
        #{'  '}
          .dynamic-content .text-light {
            color: #212529 !important;
          }
        #{'  '}
          /* Override AI template default styles */
          .dynamic-content .ai-metric-value {
            color: #212529 !important;
          }
        #{'  '}
          .dynamic-content .ai-metric-label {
            color: #495057 !important;
          }
        #{'  '}
          .dynamic-content .ai-metric-card {
            background: #ffffff !important;
            color: #212529 !important;
          }
        #{'  '}
          .dynamic-content .ai-metric-card * {
            color: inherit !important;
          }
        #{'  '}
          /* Handle AI-generated metric-card classes (without dynamic- prefix) */
          .dynamic-content .metric-card {
            background: #ffffff !important;
            color: #212529 !important;
          }
        #{'  '}
          .dynamic-content .metric-card * {
            color: #212529 !important;
          }
        #{'  '}
          .dynamic-content .metric-label {
            color: #495057 !important;
            font-weight: 600 !important;
          }
        #{'  '}
          .dynamic-content .metric-value {
            color: #212529 !important;
            font-weight: 700 !important;
          }
        #{'  '}
          .data-section {
            margin: 30px 0;
          }
        #{'  '}
          .data-section h3 {
            margin-bottom: 20px;
            color: #333;
            border-bottom: 2px solid #e0e0e0;
            padding-bottom: 10px;
          }
        #{'  '}
          .object-cards {
            display: grid;
            grid-template-columns: repeat(auto-fill, minmax(300px, 1fr));
            gap: 20px;
          }
        #{'  '}
          .object-card {
            background: white;
            border: 1px solid #e0e0e0;
            border-radius: 8px;
            padding: 20px;
            box-shadow: 0 2px 4px rgba(0,0,0,0.05);
          }
        #{'  '}
          .object-card .card-title {
            font-weight: 600;
            font-size: 18px;
            margin-bottom: 10px;
            color: #212529;
          }
        #{'  '}
          .object-card .card-field {
            margin: 8px 0;
            display: flex;
            justify-content: space-between;
            align-items: center;
          }
        #{'  '}
          .object-card .field-label {
            font-size: 14px;
            color: #6c757d;
            text-transform: capitalize;
          }
        #{'  '}
          .object-card .field-value {
            font-size: 14px;
            color: #212529;
            font-weight: 500;
            text-align: right;
          }
        #{'  '}
          .responsive-table {
            overflow-x: auto;
            margin: 20px 0;
          }
        #{'  '}
          .data-table {
            width: 100%;
            border-collapse: collapse;
            background: white;
          }
        #{'  '}
          .data-table th,
          .data-table td {
            padding: 12px;
            text-align: left;
            border-bottom: 1px solid #e0e0e0;
          }
        #{'  '}
          .data-table th {
            background-color: #f8f9fa;
            font-weight: 600;
            color: #333;
            text-transform: capitalize;
            position: sticky;
            top: 0;
          }
        #{'  '}
          .data-table tr:hover {
            background-color: #f8f9fa;
          }
        #{'  '}
          .data-list {
            list-style: none;
            padding: 0;
          }
        #{'  '}
          .data-list li {
            padding: 10px;
            border-bottom: 1px solid #e0e0e0;
          }
        #{'  '}
          .data-list li:last-child {
            border-bottom: none;
          }
        #{'  '}
          .key-value-display {
            background: #f8f9fa;
            border-radius: 8px;
            padding: 20px;
          }
        #{'  '}
          .key-value-item {
            margin: 10px 0;
            display: flex;
            justify-content: space-between;
            align-items: center;
          }
        #{'  '}
          .key-value-key {
            font-weight: 500;
            color: #6c757d;
            text-transform: capitalize;
          }
        #{'  '}
          .key-value-value {
            color: #333;
          }
        #{'  '}
          @media (max-width: 768px) {
            .object-cards {
              grid-template-columns: 1fr;
            }
        #{'    '}
            .metric-cards {
              grid-template-columns: 1fr;
            }
          }
        </style>
      HTML
    end

    def generate_metric_cards(metrics)
      return "" if metrics.empty?

      cards = metrics.map do |key, value|
        <<~HTML
          <div class="dynamic-metric-card">
            <div class="dynamic-metric-label">#{key.to_s.humanize}</div>
            <div class="dynamic-metric-value">#{format_metric_value(value)}</div>
          </div>
        HTML
      end

      "<div class='metric-cards'>#{cards.join}</div>"
    end

    def generate_object_cards(objects)
      return "" if objects.empty?

      cards = objects.map do |obj|
        # Try to find a title field
        title = obj["name"] || obj[:name] ||
                obj["title"] || obj[:title] ||
                obj["email"] || obj[:email] ||
                obj["id"] || obj[:id] ||
                "Item"

        # Generate fields, excluding the title field
        fields = obj.map do |key, value|
          next if key.to_s == "name" || key.to_s == "title" || value.nil?

          <<~HTML
            <div class="card-field">
              <span class="field-label">#{key.to_s.humanize}</span>
              <span class="field-value">#{format_value(value)}</span>
            </div>
          HTML
        end.compact

        <<~HTML
          <div class="object-card">
            <div class="card-title">#{title}</div>
            #{fields.join}
          </div>
        HTML
      end

      "<div class='object-cards'>#{cards.join}</div>"
    end

    def generate_responsive_table(objects)
      return "" if objects.empty?

      # Get all unique keys across all objects
      all_keys = objects.flat_map(&:keys).uniq

      # Prioritize certain columns to appear first
      priority_keys = [ "name", "title", "email", "id", "created_at" ]
      ordered_keys = priority_keys.select { |k| all_keys.include?(k) } +
                     (all_keys - priority_keys)

      <<~HTML
        <div class="responsive-table">
          <table class="data-table">
            <thead>
              <tr>
                #{ordered_keys.map { |key| "<th>#{key.to_s.humanize}</th>" }.join}
              </tr>
            </thead>
            <tbody>
              #{objects.map { |obj|
                "<tr>#{ordered_keys.map { |key|# {' '}
                  "<td>#{format_value(obj[key])}</td>"# {' '}
                }.join}</tr>"
              }.join}
            </tbody>
          </table>
        </div>
      HTML
    end

    def generate_list(items)
      <<~HTML
        <ul class="data-list">
          #{items.map { |item| "<li>#{format_value(item)}</li>" }.join}
        </ul>
      HTML
    end

    def generate_key_value_display(hash)
      items = hash.map do |key, value|
        <<~HTML
          <div class="key-value-item">
            <span class="key-value-key">#{key.to_s.humanize}</span>
            <span class="key-value-value">#{format_value(value)}</span>
          </div>
        HTML
      end

      "<div class='key-value-display'>#{items.join}</div>"
    end


    def load_visualization_canvas(title, html_content)
      @context[:canvas_suggestion] = "dynamic_canvas"
      @context[:canvas_data] = {
        title: title,
        html_content: html_content,
        artifact_type: "visualization"
      }
    end
  end
end
