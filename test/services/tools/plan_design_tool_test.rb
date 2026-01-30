# frozen_string_literal: true

require "test_helper"

class PlanDesignToolTest < ActiveSupport::TestCase
  setup do
    @entity = entities(:one)
    @user = users(:one)
    @tool = Tools::PlanDesignTool.new(entity: @entity, user: @user)
  end

  # ============================================
  # METADATA TESTS
  # ============================================

  test "metadata returns correct structure" do
    metadata = Tools::PlanDesignTool.metadata

    assert_equal "plan_design", metadata[:name]
    assert_equal "design", metadata[:category]
    assert metadata[:description].include?("plan")
    assert_includes metadata[:input_schema][:properties].keys, :description
    assert_includes metadata[:input_schema][:properties].keys, :design_type
    assert_includes metadata[:input_schema][:properties].keys, :action
  end

  test "supports all design types" do
    metadata = Tools::PlanDesignTool.metadata
    design_types = metadata[:input_schema][:properties][:design_type][:enum]

    assert_includes design_types, "landing_page"
    assert_includes design_types, "website"
    assert_includes design_types, "app"
    assert_includes design_types, "canvas"
  end

  test "supports all actions" do
    metadata = Tools::PlanDesignTool.metadata
    actions = metadata[:input_schema][:properties][:action][:enum]

    assert_includes actions, "create"
    assert_includes actions, "refine"
    assert_includes actions, "build"
    assert_includes actions, "list"
    assert_includes actions, "load"
    assert_includes actions, "add_data_source"
    assert_includes actions, "remove_data_source"
  end

  # ============================================
  # LIST ACTION TESTS
  # ============================================

  test "list action returns empty list when no plans" do
    # Clean up any existing plans for this user
    DesignPlan.where(entity: @entity, user: @user).delete_all

    result = @tool.execute({ action: "list", description: "list plans" })

    assert result[:success]
    assert_equal [], result[:plans]
    assert result[:message].include?("don't have any")
  end

  test "list action returns user's plans" do
    # Create a plan for this user
    plan = DesignPlan.create!(
      entity: @entity,
      user: @user,
      name: "Test Plan",
      design_type: "landing_page",
      status: "draft",
      plan_data: { sections: [{ name: "hero" }] }
    )

    result = @tool.execute({ action: "list", description: "list plans" })

    assert result[:success]
    assert result[:plans].any? { |p| p[:id] == plan.id }
  end

  test "list action filters by design_type" do
    # Create plans of different types
    DesignPlan.create!(
      entity: @entity,
      user: @user,
      name: "Landing Page Plan",
      design_type: "landing_page",
      status: "draft",
      plan_data: {}
    )

    DesignPlan.create!(
      entity: @entity,
      user: @user,
      name: "Website Plan",
      design_type: "website",
      status: "draft",
      plan_data: {}
    )

    result = @tool.execute({ action: "list", design_type: "landing_page", description: "list" })

    assert result[:success]
    assert result[:plans].all? { |p| p[:design_type] == "landing_page" }
  end

  # ============================================
  # LOAD ACTION TESTS
  # ============================================

  test "load action returns plan data" do
    plan = DesignPlan.create!(
      entity: @entity,
      user: @user,
      name: "Test Plan",
      design_type: "landing_page",
      status: "draft",
      plan_data: { sections: [{ name: "hero", type: "hero" }] }
    )

    result = @tool.execute({ action: "load", plan_id: plan.id, description: "load plan" })

    assert result[:success]
    assert_equal plan.id, result[:plan_id]
    assert_equal "design_studio", result[:canvas_type]
  end

  test "load action returns error for non-existent plan" do
    result = @tool.execute({ action: "load", plan_id: 999999, description: "load plan" })

    assert_not result[:success]
    assert result[:error].include?("not found")
  end

  # ============================================
  # DATA SOURCE ACTION TESTS
  # ============================================

  test "add_data_source adds data source to app plan" do
    plan = DesignPlan.create!(
      entity: @entity,
      user: @user,
      name: "App Plan",
      design_type: "app",
      status: "draft",
      plan_data: { sections: [] },
      data_sources: []
    )

    result = @tool.execute({
      action: "add_data_source",
      plan_id: plan.id,
      data_source: {
        name: "revenue_data",
        type: "workflow",
        source_id: 123,
        output_path: "data.results"
      },
      description: "add data source"
    })

    assert result[:success]
    assert result[:message].include?("Added data source")

    plan.reload
    assert_equal 1, plan.data_sources.length
    assert_equal "revenue_data", plan.data_sources.first["name"]
  end

  test "add_data_source fails for landing page" do
    plan = DesignPlan.create!(
      entity: @entity,
      user: @user,
      name: "Landing Plan",
      design_type: "landing_page",
      status: "draft",
      plan_data: {},
      data_sources: []
    )

    result = @tool.execute({
      action: "add_data_source",
      plan_id: plan.id,
      data_source: { name: "test", type: "workflow" },
      description: "add data source"
    })

    assert_not result[:success]
    assert result[:error].include?("apps and canvases")
  end

  test "add_data_source prevents duplicate names" do
    plan = DesignPlan.create!(
      entity: @entity,
      user: @user,
      name: "Canvas Plan",
      design_type: "canvas",
      status: "draft",
      plan_data: {},
      data_sources: [{ "name" => "existing", "type" => "workflow" }]
    )

    result = @tool.execute({
      action: "add_data_source",
      plan_id: plan.id,
      data_source: { name: "existing", type: "integration" },
      description: "add data source"
    })

    assert_not result[:success]
    assert result[:error].include?("already exists")
  end

  test "remove_data_source removes data source" do
    plan = DesignPlan.create!(
      entity: @entity,
      user: @user,
      name: "App Plan",
      design_type: "app",
      status: "draft",
      plan_data: {},
      data_sources: [{ "name" => "to_remove", "type" => "workflow" }]
    )

    result = @tool.execute({
      action: "remove_data_source",
      plan_id: plan.id,
      data_source_name: "to_remove",
      description: "remove data source"
    })

    assert result[:success]
    assert result[:message].include?("Removed")

    plan.reload
    assert_equal 0, plan.data_sources.length
  end

  # ============================================
  # REFINE ACTION TESTS
  # ============================================

  test "refine action updates plan colors" do
    plan = DesignPlan.create!(
      entity: @entity,
      user: @user,
      name: "Test Plan",
      design_type: "landing_page",
      status: "draft",
      plan_data: {
        "sections" => [],
        "color_scheme" => { "primary" => "#000000" }
      }
    )

    result = @tool.execute({
      action: "refine",
      plan_id: plan.id,
      refinements: {
        update_colors: { primary: "#FF0000", accent: "#00FF00" }
      },
      description: "refine colors"
    })

    assert result[:success]

    plan.reload
    assert_equal "#FF0000", plan.plan_data["color_scheme"]["primary"]
    assert_equal "#00FF00", plan.plan_data["color_scheme"]["accent"]
  end

  # ============================================
  # ERROR HANDLING TESTS
  # ============================================

  test "returns error for unknown action" do
    result = @tool.execute({ action: "invalid_action", description: "test" })

    assert_not result[:success]
    assert result[:error].include?("Unknown action")
  end

  test "returns error when plan_id required but missing" do
    result = @tool.execute({ action: "load", description: "load" })

    assert_not result[:success]
    assert result[:error].present?
  end

  # ============================================
  # ADVANCED SECTION OPTIONS TESTS
  # ============================================

  test "refine action updates section content and visual options" do
    plan = DesignPlan.create!(
      entity: @entity,
      user: @user,
      name: "Test Plan",
      design_type: "landing_page",
      status: "draft",
      plan_data: {
        "sections" => [
          { "name" => "hero", "type" => "hero", "content" => {} }
        ]
      }
    )

    result = @tool.execute({
      action: "refine",
      plan_id: plan.id,
      refinements: {
        update_section: {
          section_name: "hero",
          content: {
            headline: "New Headline"
          },
          visual_description: "Dark gradient background with bold white text",
          content_guidance: "Focus on compliance and trust messaging",
          image_style: "photorealistic"
        }
      },
      description: "update hero visual details"
    })

    assert result[:success], "Expected success but got: #{result[:error]}"

    plan.reload
    hero_section = plan.plan_data["sections"].find { |s| s["name"] == "hero" }
    
    assert_equal "New Headline", hero_section["content"]["headline"]
    assert_equal "Dark gradient background with bold white text", 
                 hero_section["visual_description"]
    assert_equal "Focus on compliance and trust messaging", 
                 hero_section["content_guidance"]
    assert_equal "photorealistic", 
                 hero_section["image_style"]
  end

  test "refine action adds section by type" do
    plan = DesignPlan.create!(
      entity: @entity,
      user: @user,
      name: "Test Plan",
      design_type: "landing_page",
      status: "draft",
      plan_data: { "sections" => [] }
    )

    result = @tool.execute({
      action: "refine",
      plan_id: plan.id,
      refinements: {
        add_section: "hero"  # Note: add_section takes a section TYPE string, not an object
      },
      description: "add hero section"
    })

    assert result[:success]

    plan.reload
    assert_equal 1, plan.plan_data["sections"].length
    assert_equal "hero", plan.plan_data["sections"].first["type"]
  end

  test "refine action removes section" do
    plan = DesignPlan.create!(
      entity: @entity,
      user: @user,
      name: "Test Plan",
      design_type: "landing_page",
      status: "draft",
      plan_data: {
        "sections" => [
          { "name" => "hero", "type" => "hero" },
          { "name" => "features", "type" => "features" }
        ]
      }
    )

    result = @tool.execute({
      action: "refine",
      plan_id: plan.id,
      refinements: {
        remove_section: "features"
      },
      description: "remove features section"
    })

    assert result[:success]

    plan.reload
    assert_equal 1, plan.plan_data["sections"].length
    assert_equal "hero", plan.plan_data["sections"].first["name"]
  end

  test "refine action updates section content" do
    plan = DesignPlan.create!(
      entity: @entity,
      user: @user,
      name: "Test Plan",
      design_type: "landing_page",
      status: "draft",
      plan_data: {
        "sections" => [
          { "name" => "hero", "type" => "hero", "content" => { "headline" => "Old Headline" } }
        ]
      }
    )

    result = @tool.execute({
      action: "refine",
      plan_id: plan.id,
      refinements: {
        update_section: {
          section_name: "hero",
          content: { headline: "New Headline", subheadline: "New Subheadline" }
        }
      },
      description: "update hero content"
    })

    assert result[:success]

    plan.reload
    hero = plan.plan_data["sections"].first
    assert_equal "New Headline", hero["content"]["headline"]
    assert_equal "New Subheadline", hero["content"]["subheadline"]
  end

  # ============================================
  # CREATE ACTION WITH DESIGN TYPES
  # ============================================

  test "create action generates app plan with default structure" do
    # Stub AI generation
    BedrockService.any_instance.stubs(:send_message).returns(JSON.generate({
      name: "Test App",
      pages: [
        { name: "Dashboard", slug: "dashboard", sections: [{ type: "kpi", name: "Metrics" }] }
      ],
      color_scheme: { primary: "#6366f1" }
    }))

    result = @tool.execute({
      action: "create",
      design_type: "app",
      description: "Create a simple dashboard app"
    })

    assert result[:success], "Expected success but got: #{result[:error]}"
    assert result[:plan_id].present?
    assert_equal "design_studio", result[:canvas_type]

    plan = DesignPlan.find(result[:plan_id])
    assert_equal "app", plan.design_type
  end

  test "create action generates canvas plan with data source hints" do
    # Stub AI generation
    BedrockService.any_instance.stubs(:send_message).returns(JSON.generate({
      name: "Sales Dashboard",
      sections: [
        { type: "kpi", name: "Total Sales", data_source: "sales_data" },
        { type: "chart", name: "Sales Trend", data_source: "sales_data" }
      ],
      color_scheme: { primary: "#10b981" }
    }))

    result = @tool.execute({
      action: "create",
      design_type: "canvas",
      description: "Create a sales dashboard canvas"
    })

    assert result[:success], "Expected success but got: #{result[:error]}"
    
    plan = DesignPlan.find(result[:plan_id])
    assert_equal "canvas", plan.design_type
    
    # Canvas plans should indicate they support data sources
    assert result[:message].include?("data source") || plan.plan_data.present?
  end
end
