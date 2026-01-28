# frozen_string_literal: true

require "test_helper"

class DashboardComponentRendererTest < ActiveSupport::TestCase
  setup do
    @entity = entities(:one)
    @user = users(:one)
  end

  # ============================================
  # KPI COMPONENT TESTS
  # ============================================

  test "renders KPI component with static value" do
    component = {
      type: 'kpi',
      config: {
        title: 'Total Revenue',
        value: 125000,
        format: 'currency',
        prefix: '$',
        trend: 'up',
        trend_value: 12.5
      }
    }

    result = DashboardComponentRenderer.render(component, data: {})
    
    assert result.include?('Total Revenue')
    assert result.include?('125,000') # Formatted number
    assert result.include?('$')
  end

  test "renders KPI component with data binding" do
    component = {
      type: 'kpi',
      config: {
        title: 'Active Users',
        data_source: 'user_stats',
        data_path: 'active_count',
        format: 'number'
      }
    }

    data = { 'user_stats' => { 'active_count' => 1523 } }
    result = DashboardComponentRenderer.render(component, data: data)
    
    assert result.include?('Active Users')
    assert result.include?('1,523')
  end

  test "renders KPI component with missing data gracefully" do
    component = {
      type: 'kpi',
      config: {
        title: 'Missing Data',
        data_source: 'nonexistent',
        data_path: 'value'
      }
    }

    result = DashboardComponentRenderer.render(component, data: {})
    
    assert result.include?('Missing Data')
    assert result.include?('--') # Placeholder for missing data
  end

  # ============================================
  # CHART COMPONENT TESTS
  # ============================================

  test "renders bar chart component" do
    component = {
      type: 'chart',
      config: {
        chart_type: 'bar',
        title: 'Monthly Sales',
        data_source: 'sales_data',
        x_axis: 'month',
        y_axis: 'revenue'
      }
    }

    data = {
      'sales_data' => [
        { 'month' => 'Jan', 'revenue' => 10000 },
        { 'month' => 'Feb', 'revenue' => 15000 },
        { 'month' => 'Mar', 'revenue' => 12000 }
      ]
    }

    result = DashboardComponentRenderer.render(component, data: data)
    
    assert result.include?('Monthly Sales')
    assert result.include?('chart') # Should contain chart element
    assert result.include?('bar') # Chart type indicator
  end

  test "renders line chart component" do
    component = {
      type: 'chart',
      config: {
        chart_type: 'line',
        title: 'User Growth',
        data_source: 'growth_data',
        x_axis: 'date',
        y_axis: 'users'
      }
    }

    data = {
      'growth_data' => [
        { 'date' => '2026-01-01', 'users' => 100 },
        { 'date' => '2026-01-15', 'users' => 150 },
        { 'date' => '2026-02-01', 'users' => 225 }
      ]
    }

    result = DashboardComponentRenderer.render(component, data: data)
    
    assert result.include?('User Growth')
    assert result.include?('line')
  end

  test "renders pie chart component" do
    component = {
      type: 'chart',
      config: {
        chart_type: 'pie',
        title: 'Traffic Sources',
        data_source: 'traffic_data',
        label_field: 'source',
        value_field: 'visits'
      }
    }

    data = {
      'traffic_data' => [
        { 'source' => 'Organic', 'visits' => 5000 },
        { 'source' => 'Social', 'visits' => 3000 },
        { 'source' => 'Direct', 'visits' => 2000 }
      ]
    }

    result = DashboardComponentRenderer.render(component, data: data)
    
    assert result.include?('Traffic Sources')
    assert result.include?('pie')
  end

  # ============================================
  # TABLE COMPONENT TESTS
  # ============================================

  test "renders table component with columns" do
    component = {
      type: 'table',
      config: {
        title: 'Recent Orders',
        data_source: 'orders',
        columns: [
          { name: 'order_id', label: 'Order #', width: '100px' },
          { name: 'customer', label: 'Customer' },
          { name: 'amount', label: 'Amount', format: 'currency' },
          { name: 'status', label: 'Status' }
        ],
        pagination: true,
        page_size: 10
      }
    }

    data = {
      'orders' => [
        { 'order_id' => 'ORD-001', 'customer' => 'John Doe', 'amount' => 150.00, 'status' => 'Completed' },
        { 'order_id' => 'ORD-002', 'customer' => 'Jane Smith', 'amount' => 250.00, 'status' => 'Pending' }
      ]
    }

    result = DashboardComponentRenderer.render(component, data: data)
    
    assert result.include?('Recent Orders')
    assert result.include?('Order #')
    assert result.include?('Customer')
    assert result.include?('John Doe')
    assert result.include?('ORD-001')
  end

  test "renders table component with empty data" do
    component = {
      type: 'table',
      config: {
        title: 'Empty Table',
        data_source: 'items',
        columns: [
          { name: 'name', label: 'Name' }
        ],
        empty_message: 'No items found'
      }
    }

    result = DashboardComponentRenderer.render(component, data: { 'items' => [] })
    
    assert result.include?('Empty Table')
    assert result.include?('No items found')
  end

  # ============================================
  # METRIC CARD COMPONENT TESTS
  # ============================================

  test "renders metric card with comparison" do
    component = {
      type: 'metric_card',
      config: {
        title: 'Conversion Rate',
        data_source: 'analytics',
        value_path: 'conversion_rate',
        comparison_path: 'previous_conversion_rate',
        format: 'percentage',
        icon: 'trending-up'
      }
    }

    data = {
      'analytics' => {
        'conversion_rate' => 3.5,
        'previous_conversion_rate' => 2.8
      }
    }

    result = DashboardComponentRenderer.render(component, data: data)
    
    assert result.include?('Conversion Rate')
    assert result.include?('3.5%')
    # Should show positive change
    assert result.include?('up') || result.include?('increase') || result.include?('+')
  end

  # ============================================
  # DATA SOURCE BINDING TESTS
  # ============================================

  test "resolves nested data path" do
    component = {
      type: 'kpi',
      config: {
        title: 'Nested Value',
        data_source: 'report',
        data_path: 'metrics.sales.total',
        format: 'number'
      }
    }

    data = {
      'report' => {
        'metrics' => {
          'sales' => {
            'total' => 99999
          }
        }
      }
    }

    result = DashboardComponentRenderer.render(component, data: data)
    
    # Either formatted number or the raw value should be present
    assert result.include?('99,999') || result.include?('99999'), "Expected formatted number in: #{result}"
  end

  test "handles array data with aggregation" do
    component = {
      type: 'kpi',
      config: {
        title: 'Total Sales',
        data_source: 'transactions',
        data_path: 'amount',
        aggregation: 'sum'
      }
    }

    data = {
      'transactions' => [
        { 'amount' => 100 },
        { 'amount' => 200 },
        { 'amount' => 300 }
      ]
    }

    result = DashboardComponentRenderer.render(component, data: data)
    
    assert result.include?('600') # Sum of 100 + 200 + 300
  end

  # ============================================
  # LAYOUT TESTS
  # ============================================

  test "renders grid layout with multiple components" do
    layout = {
      type: 'grid',
      columns: 3,
      gap: '16px',
      components: [
        { type: 'kpi', config: { title: 'KPI 1', value: 100 } },
        { type: 'kpi', config: { title: 'KPI 2', value: 200 } },
        { type: 'kpi', config: { title: 'KPI 3', value: 300 } }
      ]
    }

    result = DashboardComponentRenderer.render_layout(layout, data: {})
    
    assert result.include?('grid')
    assert result.include?('KPI 1')
    assert result.include?('KPI 2')
    assert result.include?('KPI 3')
  end
end
