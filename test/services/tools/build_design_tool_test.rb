# frozen_string_literal: true

require "test_helper"

class BuildDesignToolTest < ActiveSupport::TestCase
  setup do
    @entity = entities(:one)
    @user = users(:one)
    @tool = Tools::BuildDesignTool.new(entity: @entity, user: @user)
  end

  # ============================================
  # METADATA TESTS
  # ============================================

  test "metadata returns correct structure" do
    metadata = Tools::BuildDesignTool.metadata

    assert_equal "build_design", metadata[:name]
    assert_equal "design", metadata[:category]
    assert metadata[:description].include?("Build")
    assert_includes metadata[:input_schema][:properties].keys, :plan_id
    assert_includes metadata[:input_schema][:properties].keys, :confirm
    assert_includes metadata[:input_schema][:required], "plan_id"
  end

  # ============================================
  # VALIDATION TESTS
  # ============================================

  test "returns error when plan_id is missing" do
    result = @tool.execute({})

    assert_not result[:success]
    assert result[:error].include?("plan_id is required")
  end

  test "returns error when plan not found" do
    result = @tool.execute({ plan_id: 999999 })

    assert_not result[:success]
    assert result[:error].include?("not found")
  end

  test "returns error when plan belongs to different user" do
    other_user = User.create!(
      email: "other_#{SecureRandom.hex(4)}@test.com",
      password: "password123",
      entity: @entity
    )

    plan = DesignPlan.create!(
      entity: @entity,
      user: other_user,
      name: "Other User Plan",
      design_type: "landing_page",
      status: "draft",
      plan_data: {}
    )

    result = @tool.execute({ plan_id: plan.id })

    assert_not result[:success]
    assert result[:error].include?("not found")
  end

  test "returns error when plan is not in draft status" do
    plan = DesignPlan.create!(
      entity: @entity,
      user: @user,
      name: "Completed Plan",
      design_type: "landing_page",
      status: "completed",
      plan_data: {}
    )

    result = @tool.execute({ plan_id: plan.id })

    assert_not result[:success]
    assert result[:error].include?("must be in 'draft' status")
  end

  # ============================================
  # LANDING PAGE BUILD TESTS
  # ============================================

  test "builds landing page from plan" do
    plan = DesignPlan.create!(
      entity: @entity,
      user: @user,
      name: "Test Landing Page",
      description: "A test landing page",
      design_type: "landing_page",
      status: "draft",
      plan_data: {
        "name" => "Test Landing Page",
        "sections" => [
          { "name" => "hero", "type" => "hero", "content" => { "headline" => "Welcome" } }
        ],
        "color_scheme" => { "primary" => "#6366f1" },
        "style" => "modern"
      }
    )

    # Stub the GenerateLandingPageTool to avoid AI calls
    mock_result = {
      success: true,
      id: 123,
      message: "Landing page created"
    }

    Tools::GenerateLandingPageTool.any_instance.stubs(:execute).returns(mock_result)

    result = @tool.execute({ plan_id: plan.id })

    assert result[:success]
    assert_equal 123, result[:landing_page_id]
    assert_equal "landing_page_editor", result[:canvas_type]

    plan.reload
    assert_equal "completed", plan.status
    assert_equal 123, plan.landing_page_id
  end

  test "handles landing page build failure" do
    plan = DesignPlan.create!(
      entity: @entity,
      user: @user,
      name: "Failing Plan",
      design_type: "landing_page",
      status: "draft",
      plan_data: { "sections" => [] }
    )

    # Stub the GenerateLandingPageTool to return failure
    mock_result = {
      success: false,
      error: "Generation failed"
    }

    Tools::GenerateLandingPageTool.any_instance.stubs(:execute).returns(mock_result)

    result = @tool.execute({ plan_id: plan.id })

    assert_not result[:success]
    assert result[:error].include?("Generation failed")

    plan.reload
    assert_equal "failed", plan.status
    assert_equal "Generation failed", plan.error_message
  end

  # ============================================
  # WEBSITE BUILD TESTS
  # ============================================

  test "builds website from plan" do
    plan = DesignPlan.create!(
      entity: @entity,
      user: @user,
      name: "Test Website",
      description: "A test website",
      design_type: "website",
      status: "draft",
      plan_data: {
        "name" => "Test Website",
        "pages" => [
          { "name" => "Home", "slug" => "home", "sections" => [{ "name" => "hero", "type" => "hero" }] },
          { "name" => "About", "slug" => "about", "sections" => [{ "name" => "content", "type" => "content" }] }
        ],
        "color_scheme" => { "primary" => "#10b981" },
        "style" => "minimal",
        "navigation" => { "items" => ["Home", "About"] }
      }
    )

    # Stub BedrockService to avoid AI calls
    BedrockService.any_instance.stubs(:send_message).returns("<div>Test HTML</div>")

    result = @tool.execute({ plan_id: plan.id })

    assert result[:success]
    assert result[:website_id].present?
    assert_equal 2, result[:page_count]
    assert_equal "website_editor", result[:canvas_type]

    plan.reload
    assert_equal "completed", plan.status
    assert plan.website_id.present?

    # Verify website was created
    website = Website.find(result[:website_id])
    assert_equal "Test Website", website.name
    assert_equal 2, website.website_pages.count
  end

  # ============================================
  # APP BUILD TESTS
  # ============================================

  test "builds app with data sources" do
    plan = DesignPlan.create!(
      entity: @entity,
      user: @user,
      name: "Test App",
      description: "A test app with data",
      design_type: "app",
      status: "draft",
      plan_data: {
        "name" => "Test App",
        "pages" => [
          { "name" => "Dashboard", "slug" => "dashboard", "sections" => [] }
        ],
        "color_scheme" => { "primary" => "#f59e0b" },
        "style" => "modern"
      },
      data_sources: [
        { "name" => "revenue", "type" => "workflow", "source_id" => 1 }
      ]
    )

    # Stub BedrockService to avoid AI calls
    BedrockService.any_instance.stubs(:send_message).returns("<div>App HTML</div>")

    result = @tool.execute({ plan_id: plan.id })

    assert result[:success]
    assert result[:website_id].present?
    assert result[:has_data_sources]
    assert result[:message].include?("app")

    # Verify data sources were stored on website
    website = Website.find(result[:website_id])
    assert website.data_sources.present? if website.respond_to?(:data_sources)
  end

  # ============================================
  # CANVAS BUILD TESTS
  # ============================================

  test "builds canvas dashboard" do
    # Ensure we have an app_module for canvases
    app_module = AppModule.find_or_create_by!(
      entity: @entity,
      slug: 'user-dashboards'
    ) do |m|
      m.name = 'User Dashboards'
      m.description = 'Test module'
      m.status = 'active'
    end

    plan = DesignPlan.create!(
      entity: @entity,
      user: @user,
      name: "Sales Dashboard",
      description: "A sales dashboard",
      design_type: "canvas",
      status: "draft",
      plan_data: {
        "name" => "Sales Dashboard",
        "sections" => [
          { "name" => "Revenue", "type" => "kpi", "data_source" => "revenue" },
          { "name" => "Sales Chart", "type" => "chart", "data_source" => "sales_data" }
        ],
        "color_scheme" => { "primary" => "#8b5cf6" },
        "style" => "modern"
      },
      data_sources: [
        { "name" => "revenue", "type" => "workflow", "source_id" => 1 },
        { "name" => "sales_data", "type" => "workflow", "source_id" => 2 }
      ]
    )

    result = @tool.execute({ plan_id: plan.id })

    assert result[:success]
    assert result[:canvas_id].present?
    assert_equal 2, result[:data_source_count]
    assert_equal "module_canvas", result[:canvas_type]

    plan.reload
    assert_equal "completed", plan.status
    assert plan.module_canvas_id.present?

    # Verify canvas was created
    canvas = ModuleCanvas.find(result[:canvas_id])
    assert_equal "Sales Dashboard", canvas.name
    assert_equal "dashboard", canvas.canvas_type
    assert_equal 2, canvas.data_sources.length
  end

  # ============================================
  # HELPER METHOD TESTS
  # ============================================

  test "determine_template returns correct template" do
    tool = Tools::BuildDesignTool.new(entity: @entity, user: @user)

    # Test landing template
    page_plan = { "sections" => [{ "type" => "hero" }, { "type" => "cta" }] }
    assert_equal "landing", tool.send(:determine_template, page_plan)

    # Test form template
    page_plan = { "sections" => [{ "type" => "contact" }] }
    assert_equal "form", tool.send(:determine_template, page_plan)

    # Test list template
    page_plan = { "sections" => [{ "type" => "gallery" }] }
    assert_equal "list", tool.send(:determine_template, page_plan)

    # Test homepage template
    page_plan = { "slug" => "index", "sections" => [] }
    assert_equal "homepage", tool.send(:determine_template, page_plan)

    # Test default content template
    page_plan = { "sections" => [{ "type" => "text" }] }
    assert_equal "content", tool.send(:determine_template, page_plan)
  end

  test "format_color_scheme returns formatted string" do
    tool = Tools::BuildDesignTool.new(entity: @entity, user: @user)

    scheme = { primary: "#ff0000", accent: "#00ff00" }
    result = tool.send(:format_color_scheme, scheme)

    assert result.include?("primary")
    assert result.include?("#ff0000")
  end

  test "format_color_scheme returns nil for non-hash" do
    tool = Tools::BuildDesignTool.new(entity: @entity, user: @user)

    assert_nil tool.send(:format_color_scheme, nil)
    assert_nil tool.send(:format_color_scheme, "string")
  end

  # ============================================
  # HTML GENERATION TESTS
  # ============================================

  test "generates canvas HTML with KPI sections" do
    tool = Tools::BuildDesignTool.new(entity: @entity, user: @user)

    plan_data = {
      "sections" => [
        { "name" => "Total Revenue", "type" => "kpi", "data_source" => "revenue" }
      ]
    }

    html = tool.send(:generate_canvas_html, plan_data)

    assert html.include?("Total Revenue")
    assert html.include?("data-binding")
    assert html.include?("display-4")
  end

  test "generates canvas HTML with chart sections" do
    tool = Tools::BuildDesignTool.new(entity: @entity, user: @user)

    plan_data = {
      "sections" => [
        { "name" => "Sales Trend", "type" => "chart", "data_source" => "sales", "chart_type" => "bar" }
      ]
    }

    html = tool.send(:generate_canvas_html, plan_data)

    assert html.include?("Sales Trend")
    assert html.include?("chart-container")
    assert html.include?('data-chart-type="bar"')
  end

  test "generates canvas HTML with table sections" do
    tool = Tools::BuildDesignTool.new(entity: @entity, user: @user)

    plan_data = {
      "sections" => [
        { "name" => "Recent Orders", "type" => "table", "data_source" => "orders" }
      ]
    }

    html = tool.send(:generate_canvas_html, plan_data)

    assert html.include?("Recent Orders")
    assert html.include?("table-responsive")
    assert html.include?("table-striped")
  end
end
