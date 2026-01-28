# frozen_string_literal: true

require "test_helper"

class DesignPlanDataSourceTest < ActiveSupport::TestCase
  setup do
    @entity = entities(:one)
    @user = users(:one)
    @plan = DesignPlan.create!(
      entity: @entity,
      user: @user,
      name: "Dashboard App",
      description: "Sales dashboard with live data",
      design_type: "app",
      status: "draft",
      plan_data: { "name" => "Dashboard", "sections" => [] }
    )
  end

  # ============================================
  # DATA SOURCE STORAGE TESTS
  # ============================================

  test "stores data sources as JSONB array" do
    @plan.data_sources = [
      { name: 'revenue', type: 'workflow', source_id: 1 }
    ]
    @plan.save!
    @plan.reload

    assert_equal 1, @plan.data_sources.length
    assert_equal 'revenue', @plan.data_sources.first['name']
  end

  test "can add multiple data sources" do
    @plan.data_sources = [
      { name: 'revenue', type: 'workflow', source_id: 1 },
      { name: 'users', type: 'model', source_id: 2 },
      { name: 'orders', type: 'integration', source_id: 3, action_id: 10 }
    ]
    @plan.save!
    @plan.reload

    assert_equal 3, @plan.data_sources.length
    assert_equal %w[revenue users orders], @plan.data_sources.map { |ds| ds['name'] }
  end

  # ============================================
  # DATA SOURCE TYPES
  # ============================================

  test "supports workflow output data source" do
    data_source = {
      name: 'sales_report',
      type: 'workflow',
      source_id: 123,
      output_path: 'data.results',
      refresh_interval: 300  # 5 minutes
    }

    @plan.data_sources = [data_source]
    @plan.save!
    @plan.reload

    ds = @plan.data_sources.first
    assert_equal 'workflow', ds['type']
    assert_equal 123, ds['source_id']
    assert_equal 'data.results', ds['output_path']
    assert_equal 300, ds['refresh_interval']
  end

  test "supports model data source" do
    data_source = {
      name: 'contacts',
      type: 'model',
      source_id: 456,  # AppModule ID
      filters: { status: 'active' },
      sort_by: 'created_at',
      sort_direction: 'desc',
      limit: 50
    }

    @plan.data_sources = [data_source]
    @plan.save!

    ds = @plan.data_sources.first
    assert_equal 'model', ds['type']
    assert_equal({ 'status' => 'active' }, ds['filters'])
  end

  test "supports integration action data source" do
    data_source = {
      name: 'stripe_customers',
      type: 'integration',
      source_id: 789,  # Connection ID
      action_id: 101,  # IntegrationAction ID
      parameters: { limit: 100 },
      cache_ttl: 600  # 10 minutes
    }

    @plan.data_sources = [data_source]
    @plan.save!

    ds = @plan.data_sources.first
    assert_equal 'integration', ds['type']
    assert_equal 101, ds['action_id']
  end

  # ============================================
  # HELPER METHODS
  # ============================================

  test "has_data_sources? returns true when data sources present" do
    @plan.data_sources = [{ name: 'test', type: 'workflow', source_id: 1 }]
    assert @plan.has_data_sources?
  end

  test "has_data_sources? returns false when empty" do
    @plan.data_sources = []
    assert_not @plan.has_data_sources?
  end

  test "find_data_source returns matching source by name" do
    @plan.data_sources = [
      { name: 'revenue', type: 'workflow', source_id: 1 },
      { name: 'users', type: 'model', source_id: 2 }
    ]

    result = @plan.find_data_source('users')
    assert_equal 'model', result['type']
    assert_equal 2, result['source_id']
  end

  test "find_data_source returns nil for unknown name" do
    @plan.data_sources = [{ name: 'revenue', type: 'workflow', source_id: 1 }]
    assert_nil @plan.find_data_source('nonexistent')
  end

  # ============================================
  # DATA SOURCE VALIDATION
  # ============================================

  test "validates data source has required fields" do
    # This should work - has all required fields
    valid_source = { name: 'test', type: 'workflow', source_id: 1 }
    @plan.data_sources = [valid_source]
    assert @plan.valid?
  end

  # ============================================
  # DESIGN TYPES WITH DATA SOURCES
  # ============================================

  test "app design type supports data sources" do
    @plan.design_type = 'app'
    @plan.data_sources = [{ name: 'data', type: 'workflow', source_id: 1 }]
    assert @plan.valid?
    assert @plan.app?
  end

  test "canvas design type supports data sources" do
    @plan.design_type = 'canvas'
    @plan.data_sources = [{ name: 'data', type: 'model', source_id: 1 }]
    assert @plan.valid?
    assert @plan.canvas?
  end

  test "website design type can have data sources for dynamic content" do
    @plan.design_type = 'website'
    @plan.data_sources = [{ name: 'blog_posts', type: 'model', source_id: 1 }]
    assert @plan.valid?
  end
end
