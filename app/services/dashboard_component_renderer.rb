# frozen_string_literal: true

# DashboardComponentRenderer - Renders dashboard components (KPIs, charts, tables) as HTML
#
# Supports:
# - KPI cards with trends and comparisons
# - Charts (bar, line, pie, area)
# - Tables with pagination and formatting
# - Metric cards with icons
# - Grid layouts for component arrangement
#
# Data binding:
# - Static values via `value` property
# - Dynamic values via `data_source` + `data_path`
# - Array aggregations (sum, avg, count, min, max)
#
class DashboardComponentRenderer
  class << self
    # Render a single component
    def render(component, data: {})
      component = component.with_indifferent_access
      type = component[:type]&.to_s
      config = (component[:config] || {}).with_indifferent_access

      case type
      when 'kpi'
        render_kpi(config, data)
      when 'chart'
        render_chart(config, data)
      when 'table'
        render_table(config, data)
      when 'metric_card'
        render_metric_card(config, data)
      else
        render_unknown(type, config)
      end
    end

    # Render a layout with multiple components
    def render_layout(layout, data: {})
      layout = layout.with_indifferent_access
      type = layout[:type]&.to_s
      components = layout[:components] || []

      case type
      when 'grid'
        render_grid_layout(layout, components, data)
      when 'row'
        render_row_layout(components, data)
      when 'column'
        render_column_layout(components, data)
      else
        render_default_layout(components, data)
      end
    end

    private

    # =========================================
    # KPI COMPONENT
    # =========================================

    def render_kpi(config, data)
      title = config[:title] || 'KPI'
      value = resolve_value(config, data)
      formatted_value = format_value(value, config[:format], config)
      trend = config[:trend]
      trend_value = config[:trend_value]

      trend_html = if trend.present?
        trend_class = trend == 'up' ? 'text-success' : 'text-danger'
        trend_icon = trend == 'up' ? '↑' : '↓'
        trend_display = trend_value.present? ? "#{trend_icon} #{trend_value}%" : trend_icon
        %(<span class="kpi-trend #{trend_class}">#{trend_display}</span>)
      else
        ''
      end

      <<~HTML
        <div class="dashboard-kpi card h-100">
          <div class="card-body text-center">
            <h6 class="card-subtitle text-muted mb-2">#{h(title)}</h6>
            <h2 class="card-title mb-0">#{config[:prefix]}#{formatted_value}#{config[:suffix]}</h2>
            #{trend_html}
          </div>
        </div>
      HTML
    end

    # =========================================
    # CHART COMPONENT
    # =========================================

    def render_chart(config, data)
      title = config[:title] || 'Chart'
      chart_type = config[:chart_type] || 'bar'
      chart_data = resolve_data_source(config[:data_source], data)
      chart_id = "chart-#{SecureRandom.hex(4)}"

      # Prepare data for Chart.js
      labels = []
      values = []

      if chart_data.is_a?(Array)
        labels = chart_data.map { |d| d[config[:x_axis] || config[:label_field]] }
        values = chart_data.map { |d| d[config[:y_axis] || config[:value_field]] }
      end

      <<~HTML
        <div class="dashboard-chart card h-100">
          <div class="card-body">
            <h6 class="card-subtitle text-muted mb-3">#{h(title)}</h6>
            <div class="chart-container" style="position: relative; height: 200px;">
              <canvas id="#{chart_id}" data-chart-type="#{chart_type}" 
                      data-labels='#{labels.to_json}' 
                      data-values='#{values.to_json}'></canvas>
            </div>
          </div>
        </div>
        <script>
          (function() {
            var ctx = document.getElementById('#{chart_id}');
            if (ctx && typeof Chart !== 'undefined') {
              new Chart(ctx, {
                type: '#{chart_type}',
                data: {
                  labels: #{labels.to_json},
                  datasets: [{
                    label: '#{h(title)}',
                    data: #{values.to_json},
                    backgroundColor: ['#6366f1', '#8b5cf6', '#a855f7', '#d946ef', '#ec4899'],
                    borderColor: '#6366f1',
                    borderWidth: 1
                  }]
                },
                options: {
                  responsive: true,
                  maintainAspectRatio: false,
                  plugins: { legend: { display: false } }
                }
              });
            }
          })();
        </script>
      HTML
    end

    # =========================================
    # TABLE COMPONENT
    # =========================================

    def render_table(config, data)
      title = config[:title] || 'Table'
      columns = config[:columns] || []
      table_data = resolve_data_source(config[:data_source], data) || []
      empty_message = config[:empty_message] || 'No data available'

      if table_data.empty?
        return <<~HTML
          <div class="dashboard-table card h-100">
            <div class="card-body">
              <h6 class="card-subtitle text-muted mb-3">#{h(title)}</h6>
              <div class="text-center text-muted py-4">#{h(empty_message)}</div>
            </div>
          </div>
        HTML
      end

      headers = columns.map do |col|
        width = col[:width] ? " style=\"width: #{col[:width]}\"" : ''
        "<th#{width}>#{h(col[:label] || col[:name])}</th>"
      end.join

      rows = table_data.map do |row|
        cells = columns.map do |col|
          value = row[col[:name]]
          formatted = format_value(value, col[:format], col)
          "<td>#{formatted}</td>"
        end.join
        "<tr>#{cells}</tr>"
      end.join

      <<~HTML
        <div class="dashboard-table card h-100">
          <div class="card-body">
            <h6 class="card-subtitle text-muted mb-3">#{h(title)}</h6>
            <div class="table-responsive">
              <table class="table table-sm table-hover">
                <thead><tr>#{headers}</tr></thead>
                <tbody>#{rows}</tbody>
              </table>
            </div>
          </div>
        </div>
      HTML
    end

    # =========================================
    # METRIC CARD COMPONENT
    # =========================================

    def render_metric_card(config, data)
      title = config[:title] || 'Metric'
      source_data = resolve_data_source(config[:data_source], data) || {}
      value = resolve_path(source_data, config[:value_path])
      comparison = resolve_path(source_data, config[:comparison_path])
      formatted = format_value(value, config[:format], config)
      icon = config[:icon] || 'bar-chart-2'

      change_html = ''
      if comparison.present? && value.present? && comparison > 0
        change = ((value - comparison) / comparison.to_f * 100).round(1)
        change_class = change >= 0 ? 'text-success' : 'text-danger'
        change_icon = change >= 0 ? '↑' : '↓'
        change_html = %(<span class="#{change_class}">#{change_icon} #{change.abs}%</span>)
      end

      <<~HTML
        <div class="dashboard-metric-card card h-100">
          <div class="card-body">
            <div class="d-flex align-items-center">
              <div class="metric-icon me-3">
                <i data-lucide="#{icon}" style="width: 24px; height: 24px;"></i>
              </div>
              <div>
                <h6 class="text-muted mb-1">#{h(title)}</h6>
                <h4 class="mb-0">#{formatted}</h4>
                #{change_html}
              </div>
            </div>
          </div>
        </div>
      HTML
    end

    # =========================================
    # LAYOUT RENDERERS
    # =========================================

    def render_grid_layout(layout, components, data)
      columns = layout[:columns] || 3
      gap = layout[:gap] || '16px'

      rendered = components.map { |c| render(c, data: data) }.join

      <<~HTML
        <div class="dashboard-grid" style="display: grid; grid-template-columns: repeat(#{columns}, 1fr); gap: #{gap};">
          #{rendered}
        </div>
      HTML
    end

    def render_row_layout(components, data)
      rendered = components.map { |c| "<div class=\"flex-fill\">#{render(c, data: data)}</div>" }.join

      <<~HTML
        <div class="d-flex gap-3">#{rendered}</div>
      HTML
    end

    def render_column_layout(components, data)
      rendered = components.map { |c| "<div class=\"mb-3\">#{render(c, data: data)}</div>" }.join

      <<~HTML
        <div class="d-flex flex-column">#{rendered}</div>
      HTML
    end

    def render_default_layout(components, data)
      components.map { |c| render(c, data: data) }.join
    end

    def render_unknown(type, config)
      <<~HTML
        <div class="dashboard-unknown card h-100">
          <div class="card-body text-muted">
            Unknown component type: #{h(type)}
          </div>
        </div>
      HTML
    end

    # =========================================
    # DATA RESOLUTION
    # =========================================

    def resolve_value(config, data)
      # Static value takes precedence
      return config[:value] if config[:value].present?

      # Otherwise resolve from data source
      return '--' unless config[:data_source].present?

      source_data = resolve_data_source(config[:data_source], data)
      return '--' unless source_data.present?

      if source_data.is_a?(Array) && config[:aggregation].present?
        aggregate(source_data, config[:data_path], config[:aggregation])
      elsif source_data.is_a?(Array) && config[:data_path].present?
        # Sum values from array by default
        aggregate(source_data, config[:data_path], 'sum')
      elsif config[:data_path].present?
        resolve_path(source_data, config[:data_path])
      else
        source_data
      end
    end

    def resolve_data_source(name, data)
      return nil unless name.present? && data.present?
      data[name.to_s] || data[name.to_sym]
    end

    def resolve_path(data, path)
      return data unless path.present?
      return nil unless data.present?

      path.to_s.split('.').reduce(data) do |acc, key|
        break nil unless acc.is_a?(Hash) || acc.respond_to?(:[])
        acc[key] || acc[key.to_sym]
      end
    end

    def aggregate(array, path, method)
      return 0 unless array.is_a?(Array)

      values = array.map { |item| resolve_path(item, path) }.compact.map(&:to_f)
      return 0 if values.empty?

      case method.to_s
      when 'sum' then values.sum
      when 'avg', 'average' then (values.sum / values.length).round(2)
      when 'count' then values.length
      when 'min' then values.min
      when 'max' then values.max
      else values.sum
      end
    end

    # =========================================
    # FORMATTING
    # =========================================

    def format_value(value, format, config = {})
      return '--' if value.nil? || value == '--'

      case format&.to_s
      when 'currency'
        prefix = config[:currency_symbol] || '$'
        "#{prefix}#{number_with_delimiter(value.to_f.round(2))}"
      when 'percentage'
        "#{value}%"
      when 'number'
        number_with_delimiter(value)
      when 'date'
        format_date(value)
      when 'datetime'
        format_datetime(value)
      else
        h(value.to_s)
      end
    end

    def number_with_delimiter(number)
      parts = number.to_s.split('.')
      parts[0] = parts[0].reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse
      parts.join('.')
    end

    def format_date(value)
      return value unless value.respond_to?(:strftime)
      value.strftime('%b %d, %Y')
    rescue
      value.to_s
    end

    def format_datetime(value)
      return value unless value.respond_to?(:strftime)
      value.strftime('%b %d, %Y %H:%M')
    rescue
      value.to_s
    end

    def h(str)
      ERB::Util.html_escape(str.to_s)
    end
  end
end
