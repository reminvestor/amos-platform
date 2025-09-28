module Tools
  class CreateDynamicVisualizationTool < BaseTool
    def self.metadata
      {
        name: 'create_dynamic_visualization',
        description: 'Create custom HTML visualizations for data analysis and reporting',
        category: 'analytics',
        input_schema: {
          type: 'object',
          properties: {
            title: {
              type: 'string',
              description: 'Title for the visualization'
            },
            data: {
              type: 'object',
              description: 'Data to visualize'
            },
            visualization_type: {
              type: 'string',
              enum: ['comparison', 'dashboard', 'report', 'custom'],
              description: 'Type of visualization to create'
            },
            options: {
              type: 'object',
              description: 'Additional options for the visualization'
            }
          },
          required: ['title', 'data']
        }
      }
    end
    
    def execute(args)
      log_execution(args)
      
      title = get_arg(args, :title)
      data = get_arg(args, :data)
      viz_type = get_arg(args, :visualization_type, 'custom')
      options = get_arg(args, :options, {})
      
      # Validate required args
      if error = validate_required_args(args, [:title, :data])
        return error
      end
      
      begin
        # Generate visualization HTML based on type
        html_content = case viz_type
        when 'comparison'
          generate_comparison_visualization(title, data, options)
        when 'dashboard'
          generate_dashboard_visualization(title, data, options)
        when 'report'
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
      items = data['items'] || data[:items] || []
      metrics = data['metrics'] || data[:metrics] || []
      
      <<~HTML
        <div class="comparison-visualization">
          <h3>#{title}</h3>
          
          <div class="comparison-grid">
            #{generate_comparison_cards(items, metrics)}
          </div>
          
          #{generate_comparison_chart(items, metrics) if items.length <= 10}
        </div>
        
        <style>
          .comparison-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(250px, 1fr));
            gap: 20px;
            margin: 20px 0;
          }
          
          .comparison-card {
            background: white;
            border: 1px solid #e0e0e0;
            border-radius: 8px;
            padding: 20px;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1);
          }
          
          .comparison-card h4 {
            margin: 0 0 15px 0;
            color: #333;
          }
          
          .metric {
            margin: 10px 0;
            display: flex;
            justify-content: space-between;
          }
          
          .metric-label {
            color: #666;
          }
          
          .metric-value {
            font-weight: bold;
            color: #333;
          }
          
          .metric-positive {
            color: #4caf50;
          }
          
          .metric-negative {
            color: #f44336;
          }
        </style>
      HTML
    end
    
    def generate_dashboard_visualization(title, data, options)
      # Generate a dashboard with multiple widgets
      widgets = data['widgets'] || data[:widgets] || []
      
      <<~HTML
        <div class="dashboard-visualization">
          <div class="dashboard-header">
            <h2>#{title}</h2>
            <p class="text-muted">#{options['subtitle'] || "Generated on #{Time.current.strftime('%B %d, %Y')}"}</p>
          </div>
          
          <div class="dashboard-grid">
            #{generate_dashboard_widgets(widgets)}
          </div>
        </div>
        
        <style>
          .dashboard-header {
            margin-bottom: 30px;
            padding-bottom: 20px;
            border-bottom: 2px solid #e0e0e0;
          }
          
          .dashboard-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(300px, 1fr));
            gap: 25px;
          }
          
          .dashboard-widget {
            background: white;
            border: 1px solid #e0e0e0;
            border-radius: 8px;
            padding: 20px;
            min-height: 200px;
          }
          
          .widget-header {
            display: flex;
            justify-content: space-between;
            align-items: center;
            margin-bottom: 15px;
          }
          
          .widget-title {
            font-size: 18px;
            font-weight: 600;
            color: #333;
          }
          
          .widget-value {
            font-size: 32px;
            font-weight: bold;
            color: #1976d2;
            margin: 20px 0;
          }
          
          .widget-chart {
            margin-top: 20px;
          }
        </style>
      HTML
    end
    
    def generate_report_visualization(title, data, options)
      # Generate a structured report
      sections = data['sections'] || data[:sections] || []
      
      <<~HTML
        <div class="report-visualization">
          <div class="report-header">
            <h1>#{title}</h1>
            <div class="report-meta">
              <p><strong>Generated:</strong> #{Time.current.strftime('%B %d, %Y at %I:%M %p')}</p>
              <p><strong>Entity:</strong> #{entity.name}</p>
            </div>
          </div>
          
          <div class="report-content">
            #{generate_report_sections(sections)}
          </div>
          
          <div class="report-footer">
            <p class="text-muted">This report was automatically generated by Amos AI</p>
          </div>
        </div>
        
        <style>
          .report-header {
            background: #f8f9fa;
            padding: 30px;
            border-radius: 8px;
            margin-bottom: 30px;
          }
          
          .report-meta {
            margin-top: 20px;
            color: #666;
          }
          
          .report-section {
            margin: 30px 0;
            padding: 20px;
            background: white;
            border: 1px solid #e0e0e0;
            border-radius: 8px;
          }
          
          .section-title {
            font-size: 24px;
            color: #333;
            margin-bottom: 20px;
            padding-bottom: 10px;
            border-bottom: 2px solid #e0e0e0;
          }
          
          .report-footer {
            margin-top: 40px;
            padding-top: 20px;
            border-top: 1px solid #e0e0e0;
            text-align: center;
          }
        </style>
      HTML
    end
    
    def generate_custom_visualization(title, data, options)
      # Flexible custom visualization
      <<~HTML
        <div class="custom-visualization">
          <h2>#{title}</h2>
          
          <div class="visualization-content">
            #{format_data_as_html(data)}
          </div>
        </div>
        
        <style>
          .custom-visualization {
            padding: 20px;
          }
          
          .visualization-content {
            margin-top: 20px;
          }
          
          .data-table {
            width: 100%;
            border-collapse: collapse;
            margin: 20px 0;
          }
          
          .data-table th,
          .data-table td {
            padding: 12px;
            text-align: left;
            border-bottom: 1px solid #e0e0e0;
          }
          
          .data-table th {
            background-color: #f8f9fa;
            font-weight: 600;
            color: #333;
          }
          
          .data-table tr:hover {
            background-color: #f8f9fa;
          }
        </style>
      HTML
    end
    
    def generate_comparison_cards(items, metrics)
      items.map do |item|
        name = item['name'] || item[:name] || 'Unknown'
        values = item['values'] || item[:values] || {}
        
        <<~HTML
          <div class="comparison-card">
            <h4>#{name}</h4>
            #{metrics.map { |metric|
              value = values[metric] || values[metric.to_sym] || 0
              css_class = value > 0 ? 'metric-positive' : value < 0 ? 'metric-negative' : ''
              
              <<~METRIC
                <div class="metric">
                  <span class="metric-label">#{metric.to_s.humanize}:</span>
                  <span class="metric-value #{css_class}">#{format_metric_value(value)}</span>
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
        type = widget['type'] || widget[:type] || 'metric'
        
        case type
        when 'metric'
          generate_metric_widget(widget)
        when 'chart'
          generate_chart_widget(widget)
        when 'list'
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
    
    def load_visualization_canvas(title, html_content)
      @context[:canvas_suggestion] = 'dynamic_canvas'
      @context[:canvas_data] = {
        title: title,
        content: html_content,
        artifact_type: 'visualization'
      }
    end
  end
end
