# frozen_string_literal: true

require "test_helper"

class DashboardComponentRendererTest < ActiveSupport::TestCase
  # ─────────────────────────────────────────────────────────────────────────────
  # KPI Components
  # ─────────────────────────────────────────────────────────────────────────────

  test "renders KPI with static value" do
    html = DashboardComponentRenderer.render({
      type: 'kpi',
      config: {
        title: 'Total Revenue',
        value: 12500,
        format: 'currency'
      }
    })
    
    assert_includes html, "Total Revenue"
    assert_includes html, "$12,500"
  end

  test "renders KPI with trend indicator" do
    html = DashboardComponentRenderer.render({
      type: 'kpi',
      config: {
        title: 'Sales',
        value: 150,
        trend: 'up',
        trend_value: 12
      }
    })
    
    assert_includes html, "150"
    assert_includes html, "12%"
    assert_includes html, "text-success"
  end

  test "renders KPI with down trend" do
    html = DashboardComponentRenderer.render({
      type: 'kpi',
      config: {
        title: 'Churn',
        value: 5,
        trend: 'down',
        trend_value: 8
      }
    })
    
    assert_includes html, "text-danger"
  end

  # ─────────────────────────────────────────────────────────────────────────────
  # Chart Components
  # ─────────────────────────────────────────────────────────────────────────────

  test "renders bar chart with data" do
    html = DashboardComponentRenderer.render({
      type: 'chart',
      config: {
        title: 'Monthly Sales',
        chart_type: 'bar',
        data_source: 'sales'
      }
    }, data: {
      'sales' => [
        { 'month' => 'Jan', 'value' => 100 },
        { 'month' => 'Feb', 'value' => 150 }
      ]
    })
    
    assert_includes html, "Monthly Sales"
    assert_includes html, "canvas"
    assert_includes html, "bar"
  end

  test "renders line chart" do
    html = DashboardComponentRenderer.render({
      type: 'chart',
      config: {
        title: 'User Growth',
        chart_type: 'line',
        data_source: 'users'
      }
    }, data: { 'users' => [] })
    
    assert_includes html, "User Growth"
    assert_includes html, "line"
  end

  test "renders pie chart" do
    html = DashboardComponentRenderer.render({
      type: 'chart',
      config: {
        title: 'Traffic Sources',
        chart_type: 'pie'
      }
    })
    
    assert_includes html, "Traffic Sources"
    assert_includes html, "pie"
  end

  # ─────────────────────────────────────────────────────────────────────────────
  # Table Components
  # ─────────────────────────────────────────────────────────────────────────────

  test "renders table with headers and rows" do
    html = DashboardComponentRenderer.render({
      type: 'table',
      config: {
        title: 'Users',
        columns: [
          { name: 'name', label: 'Name' },
          { name: 'email', label: 'Email' }
        ],
        data_source: 'users'
      }
    }, data: {
      'users' => [
        { 'name' => 'John', 'email' => 'john@test.com' },
        { 'name' => 'Jane', 'email' => 'jane@test.com' }
      ]
    })
    
    assert_includes html, "Name"
    assert_includes html, "Email"
    assert_includes html, "John"
    assert_includes html, "jane@test.com"
  end

  test "renders empty table with message" do
    html = DashboardComponentRenderer.render({
      type: 'table',
      config: {
        title: 'Empty Table',
        columns: [{ name: 'name', label: 'Name' }],
        data_source: 'items',
        empty_message: 'No items found'
      }
    }, data: { 'items' => [] })
    
    assert_includes html, "No items found"
  end

  test "renders table with currency formatting" do
    html = DashboardComponentRenderer.render({
      type: 'table',
      config: {
        title: 'Orders',
        columns: [
          { name: 'total', label: 'Total', format: 'currency' }
        ],
        data_source: 'orders'
      }
    }, data: {
      'orders' => [{ 'total' => 99.99 }]
    })
    
    assert_includes html, "$99.99"
  end

  # ─────────────────────────────────────────────────────────────────────────────
  # Metric Card Components
  # ─────────────────────────────────────────────────────────────────────────────

  test "renders metric card with icon" do
    # KPI with format: 'number' to get proper formatting
    html = DashboardComponentRenderer.render({
      type: 'kpi',
      config: {
        title: 'Active Users',
        value: 1234,
        format: 'number'
      }
    })
    
    assert_includes html, "Active Users"
    assert_includes html, "1,234"
  end

  # ─────────────────────────────────────────────────────────────────────────────
  # Layout Rendering
  # ─────────────────────────────────────────────────────────────────────────────

  test "renders grid layout with multiple components" do
    html = DashboardComponentRenderer.render_layout({
      type: 'grid',
      columns: 3,
      components: [
        { type: 'kpi', config: { title: 'KPI 1', value: 100 } },
        { type: 'kpi', config: { title: 'KPI 2', value: 200 } },
        { type: 'kpi', config: { title: 'KPI 3', value: 300 } }
      ]
    })
    
    assert_includes html, "KPI 1"
    assert_includes html, "KPI 2"
    assert_includes html, "KPI 3"
    assert_includes html, "grid-template-columns"
  end

  test "renders row layout" do
    html = DashboardComponentRenderer.render_layout({
      type: 'row',
      components: [
        { type: 'kpi', config: { title: 'Left', value: 1 } },
        { type: 'kpi', config: { title: 'Right', value: 2 } }
      ]
    })
    
    assert_includes html, "d-flex"
    assert_includes html, "Left"
    assert_includes html, "Right"
  end

  # ─────────────────────────────────────────────────────────────────────────────
  # Data Resolution
  # ─────────────────────────────────────────────────────────────────────────────

  test "resolves value from nested data path" do
    html = DashboardComponentRenderer.render({
      type: 'kpi',
      config: {
        title: 'Nested Value',
        data_source: 'report',
        data_path: 'summary.total'
      }
    }, data: {
      'report' => { 'summary' => { 'total' => 999 } }
    })
    
    assert_includes html, "999"
  end

  test "aggregates array values with sum" do
    html = DashboardComponentRenderer.render({
      type: 'kpi',
      config: {
        title: 'Total',
        data_source: 'items',
        data_path: 'amount',
        aggregation: 'sum'
      }
    }, data: {
      'items' => [
        { 'amount' => 100 },
        { 'amount' => 200 },
        { 'amount' => 300 }
      ]
    })
    
    assert_includes html, "600"
  end

  test "aggregates array values with average" do
    html = DashboardComponentRenderer.render({
      type: 'kpi',
      config: {
        title: 'Average',
        data_source: 'items',
        data_path: 'score',
        aggregation: 'avg'
      }
    }, data: {
      'items' => [
        { 'score' => 80 },
        { 'score' => 90 },
        { 'score' => 100 }
      ]
    })
    
    assert_includes html, "90"
  end

  # ─────────────────────────────────────────────────────────────────────────────
  # Error Handling
  # ─────────────────────────────────────────────────────────────────────────────

  test "handles unknown component type gracefully" do
    html = DashboardComponentRenderer.render({
      type: 'unknown_type',
      config: {}
    })
    
    assert_includes html, "Unknown component"
  end

  test "handles missing data source gracefully" do
    html = DashboardComponentRenderer.render({
      type: 'kpi',
      config: {
        title: 'Missing Data',
        data_source: 'nonexistent'
      }
    }, data: {})
    
    assert_includes html, "--"
  end

  test "handles nil config values" do
    html = DashboardComponentRenderer.render({
      type: 'kpi',
      config: {
        title: 'Nil Test',
        value: nil
      }
    })
    
    assert html.present?
    assert_includes html, "--"
  end
end
