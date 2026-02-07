# frozen_string_literal: true

require "test_helper"

class DesignStudioComponentVisibilityTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @entity = entities(:one)
    sign_in @user
  end

  # ─────────────────────────────────────────────────────────────────────────────
  # OUTCOME: Landing page design type shows landing page components
  # ─────────────────────────────────────────────────────────────────────────────

  test "landing page design type shows landing page components in sidebar" do
    post scout_load_canvas_path, params: {
      canvas_type: "design_studio",
      canvas_data: { create_type: "landing_page" }
    }, as: :json

    assert_response :success
    json = JSON.parse(response.body)
    assert json["success"]
    
    html = json["canvas"]["content"]
    
    # Should show landing page components
    assert_match(/id="landing-page-components"/, html)
    assert_no_match(/id="landing-page-components"[^>]*style="display:\s*none/, html)
    
    # Should hide app/canvas components
    assert_match(/id="dashboard-components"[^>]*style="display:\s*none/, html)
    assert_match(/id="app-layout-category"[^>]*style="display:\s*none/, html)
    assert_match(/id="data-model-category"[^>]*style="display:\s*none/, html)
  end

  test "landing page shows appropriate canvas placeholders" do
    post scout_load_canvas_path, params: {
      canvas_type: "design_studio",
      canvas_data: { create_type: "landing_page" }
    }, as: :json

    assert_response :success
    html = JSON.parse(response.body)["canvas"]["content"]
    
    # Data attribute should indicate landing_page
    assert_match(/data-design-type="landing_page"/, html)
    assert_match(/data-is-app-or-canvas="false"/, html)
  end

  # ─────────────────────────────────────────────────────────────────────────────
  # OUTCOME: Canvas design type shows dashboard components
  # ─────────────────────────────────────────────────────────────────────────────

  test "canvas design type shows dashboard components in sidebar" do
    post scout_load_canvas_path, params: {
      canvas_type: "design_studio",
      canvas_data: { create_type: "canvas" }
    }, as: :json

    assert_response :success
    html = JSON.parse(response.body)["canvas"]["content"]
    
    # Should show app/canvas components
    assert_match(/id="dashboard-components"/, html)
    assert_no_match(/id="dashboard-components"[^>]*style="display:\s*none/, html)
    
    # Should hide landing page components
    assert_match(/id="landing-page-components"[^>]*style="display:\s*none/, html)
    assert_match(/id="typography-category"[^>]*style="display:\s*none/, html)
  end

  test "canvas shows data-is-app-or-canvas as true" do
    post scout_load_canvas_path, params: {
      canvas_type: "design_studio",
      canvas_data: { create_type: "canvas" }
    }, as: :json

    assert_response :success
    html = JSON.parse(response.body)["canvas"]["content"]
    
    assert_match(/data-design-type="canvas"/, html)
    assert_match(/data-is-app-or-canvas="true"/, html)
  end

  # ─────────────────────────────────────────────────────────────────────────────
  # OUTCOME: App design type shows app mode switcher and dashboard components
  # ─────────────────────────────────────────────────────────────────────────────

  test "app design type shows app mode switcher" do
    post scout_load_canvas_path, params: {
      canvas_type: "design_studio",
      canvas_data: { create_type: "app" }
    }, as: :json

    assert_response :success
    html = JSON.parse(response.body)["canvas"]["content"]
    
    # App mode switcher should be visible
    assert_match(/id="app-mode-switcher"/, html)
    assert_no_match(/id="app-mode-switcher"[^>]*style="display:\s*none/, html)
    
    # Should have mode tabs
    assert_match(/data-mode="pages"/, html)
    assert_match(/data-mode="canvases"/, html)
    assert_match(/data-mode="data"/, html)
    assert_match(/data-mode="workflows"/, html)
  end

  test "app design type shows dashboard components by default" do
    post scout_load_canvas_path, params: {
      canvas_type: "design_studio",
      canvas_data: { create_type: "app" }
    }, as: :json

    assert_response :success
    html = JSON.parse(response.body)["canvas"]["content"]
    
    # Data attribute should indicate app
    assert_match(/data-design-type="app"/, html)
    assert_match(/data-is-app-or-canvas="true"/, html)
    
    # Should show dashboard components
    assert_match(/id="dashboard-components"/, html)
    assert_no_match(/id="dashboard-components"[^>]*style="display:\s*none/, html)
  end

  # ─────────────────────────────────────────────────────────────────────────────
  # OUTCOME: Website design type shows landing page components
  # ─────────────────────────────────────────────────────────────────────────────

  test "website design type shows landing page components" do
    post scout_load_canvas_path, params: {
      canvas_type: "design_studio",
      canvas_data: { create_type: "website" }
    }, as: :json

    assert_response :success
    html = JSON.parse(response.body)["canvas"]["content"]
    
    # Should show landing page components for websites
    assert_match(/id="landing-page-components"/, html)
    assert_no_match(/id="landing-page-components"[^>]*style="display:\s*none/, html)
    
    # Data attribute should indicate website
    assert_match(/data-design-type="website"/, html)
    assert_match(/data-is-app-or-canvas="false"/, html)
  end

  test "website does not show app mode switcher" do
    post scout_load_canvas_path, params: {
      canvas_type: "design_studio",
      canvas_data: { create_type: "website" }
    }, as: :json

    assert_response :success
    html = JSON.parse(response.body)["canvas"]["content"]
    
    # App mode switcher should be hidden for websites
    assert_match(/id="app-mode-switcher"[^>]*style="display:\s*none/, html)
  end

  # ─────────────────────────────────────────────────────────────────────────────
  # OUTCOME: Loading existing plan uses plan's design_type
  # ─────────────────────────────────────────────────────────────────────────────

  test "loading existing canvas plan shows dashboard components" do
    plan = DesignPlan.create!(
      entity: @entity,
      user: @user,
      name: "Dashboard Plan",
      design_type: "canvas",
      status: "draft",
      plan_data: { sections: [{ type: "kpi", name: "Revenue" }] }
    )

    post scout_load_canvas_path, params: {
      canvas_type: "design_studio",
      canvas_data: { plan_id: plan.id }
    }, as: :json

    assert_response :success
    html = JSON.parse(response.body)["canvas"]["content"]
    
    # Should detect canvas design type from plan
    assert_match(/data-design-type="canvas"/, html)
    assert_match(/data-is-app-or-canvas="true"/, html)
    
    # Should show dashboard components
    assert_no_match(/id="dashboard-components"[^>]*style="display:\s*none/, html)
  end

  test "loading existing landing page plan shows landing page components" do
    plan = DesignPlan.create!(
      entity: @entity,
      user: @user,
      name: "Landing Page Plan",
      design_type: "landing_page",
      status: "draft",
      plan_data: { sections: [{ type: "hero", name: "Welcome" }] }
    )

    post scout_load_canvas_path, params: {
      canvas_type: "design_studio",
      canvas_data: { plan_id: plan.id }
    }, as: :json

    assert_response :success
    html = JSON.parse(response.body)["canvas"]["content"]
    
    # Should detect landing_page design type from plan
    assert_match(/data-design-type="landing_page"/, html)
    assert_match(/data-is-app-or-canvas="false"/, html)
    
    # Should show landing page components
    assert_no_match(/id="landing-page-components"[^>]*style="display:\s*none/, html)
  end

  # ─────────────────────────────────────────────────────────────────────────────
  # OUTCOME: Default design type is landing_page
  # ─────────────────────────────────────────────────────────────────────────────

  test "default design type is landing_page when not specified" do
    post scout_load_canvas_path, params: {
      canvas_type: "design_studio",
      canvas_data: {}
    }, as: :json

    assert_response :success
    html = JSON.parse(response.body)["canvas"]["content"]
    
    # Default should be landing_page
    assert_match(/data-design-type="landing_page"/, html)
    assert_match(/data-is-app-or-canvas="false"/, html)
  end
end
