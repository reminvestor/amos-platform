# frozen_string_literal: true

require "test_helper"

class UnifiedEditorTest < ActiveSupport::TestCase
  fixtures :entities, :users

  setup do
    @entity = entities(:one)
    @user = users(:one)
  end

  # ═══════════════════════════════════════════════════════════════
  # SCOUT DATA REGISTRY - WEBSITES & WEBSITE PAGES
  # ═══════════════════════════════════════════════════════════════

  test "ScoutDataRegistry includes websites in available objects" do
    assert ScoutDataRegistry::AVAILABLE_OBJECTS.key?("websites"),
      "ScoutDataRegistry should include 'websites' in AVAILABLE_OBJECTS"
  end

  test "ScoutDataRegistry includes website_pages in available objects" do
    assert ScoutDataRegistry::AVAILABLE_OBJECTS.key?("website_pages"),
      "ScoutDataRegistry should include 'website_pages' in AVAILABLE_OBJECTS"
  end

  test "websites config has correct model" do
    config = ScoutDataRegistry::AVAILABLE_OBJECTS["websites"]
    assert_equal "Website", config[:model]
  end

  test "website_pages config has correct model" do
    config = ScoutDataRegistry::AVAILABLE_OBJECTS["website_pages"]
    assert_equal "WebsitePage", config[:model]
  end

  test "websites has queryable fields including id and name" do
    config = ScoutDataRegistry::AVAILABLE_OBJECTS["websites"]
    assert_includes config[:queryable_fields], "id"
    assert_includes config[:queryable_fields], "name"
    assert_includes config[:queryable_fields], "slug"
    assert_includes config[:queryable_fields], "status"
  end

  test "website_pages has queryable fields including website_id" do
    config = ScoutDataRegistry::AVAILABLE_OBJECTS["website_pages"]
    assert_includes config[:queryable_fields], "website_id"
    assert_includes config[:queryable_fields], "name"
    assert_includes config[:queryable_fields], "slug"
    assert_includes config[:queryable_fields], "is_homepage"
  end

  test "websites is entity-scoped" do
    config = ScoutDataRegistry::AVAILABLE_OBJECTS["websites"]
    assert_equal "entity_id", config[:scoped_by]
  end

  test "website_pages is entity-scoped" do
    config = ScoutDataRegistry::AVAILABLE_OBJECTS["website_pages"]
    assert_equal "entity_id", config[:scoped_by]
  end

  test "websites relationships include website_pages" do
    config = ScoutDataRegistry::AVAILABLE_OBJECTS["websites"]
    assert_includes config[:relationships], "website_pages"
  end

  # ═══════════════════════════════════════════════════════════════
  # GUIDANCE LIBRARY - WEBSITE EDIT → LANDING PAGE EDIT ROUTING
  # ═══════════════════════════════════════════════════════════════

  test "edit my website routes to landing_page_edit" do
    task_type = GuidanceLibrary.detect_task_type(
      message: "edit my website"
    )
    assert_equal :landing_page_edit, task_type
  end

  test "update my website routes to landing_page_edit" do
    task_type = GuidanceLibrary.detect_task_type(
      message: "update my website"
    )
    assert_equal :landing_page_edit, task_type
  end

  test "open my website routes to landing_page_edit" do
    task_type = GuidanceLibrary.detect_task_type(
      message: "open my website the-cord"
    )
    assert_equal :landing_page_edit, task_type
  end

  test "change my website routes to landing_page_edit" do
    task_type = GuidanceLibrary.detect_task_type(
      message: "change my website homepage"
    )
    assert_equal :landing_page_edit, task_type
  end

  test "create a website still routes to website_create" do
    task_type = GuidanceLibrary.detect_task_type(
      message: "create a website for my business"
    )
    assert_equal :website_create, task_type
  end

  test "build a website still routes to website_create" do
    task_type = GuidanceLibrary.detect_task_type(
      message: "build a website for my company"
    )
    assert_equal :website_create, task_type
  end

  # ═══════════════════════════════════════════════════════════════
  # GUIDANCE LIBRARY - UNIFIED EDITOR GUIDANCE CONTENT
  # ═══════════════════════════════════════════════════════════════

  test "landing_page_edit guidance covers both landing pages and website pages" do
    guidance = GuidanceLibrary.for_task(:landing_page_edit)
    assert guidance.is_a?(String)

    # Should mention unified editor
    assert_match(/unified.*editor|page.*editor/i, guidance,
      "Guidance should mention unified editor concept")

    # Should include landing page instructions
    assert_match(/landing.*page/i, guidance,
      "Guidance should include landing page instructions")

    # Should include website page instructions
    assert_match(/website.*page/i, guidance,
      "Guidance should include website page instructions")
  end

  test "landing_page_edit guidance includes canvas loading instructions" do
    guidance = GuidanceLibrary.for_task(:landing_page_edit)

    # Should mention landing_page_editor canvas
    assert_match /landing_page_editor/, guidance,
      "Guidance should reference landing_page_editor canvas name"

    # Should mention website_page_editor canvas
    assert_match /website_page_editor/, guidance,
      "Guidance should reference website_page_editor canvas name"
  end

  test "landing_page_edit tools include platform_query and load_canvas" do
    tools = GuidanceLibrary.tools_for_task(:landing_page_edit)
    assert_includes tools, "platform_query",
      "landing_page_edit should have platform_query tool"
    assert_includes tools, "load_canvas",
      "landing_page_edit should have load_canvas tool"
  end

  test "no separate website_edit task type exists" do
    # website_edit should NOT be a separate task type — it routes to landing_page_edit
    refute GuidanceLibrary::TASK_GUIDANCE.key?(:website_edit),
      "There should be no separate :website_edit guidance entry — editing uses unified :landing_page_edit"
  end

  # ═══════════════════════════════════════════════════════════════
  # GUIDANCE LIBRARY - CANVAS CONTEXT DETECTION
  # ═══════════════════════════════════════════════════════════════

  test "landing_page_editor canvas context routes to landing_page_edit" do
    task_type = GuidanceLibrary.detect_task_type(
      canvas_context: { type: "landing_page_editor" }
    )
    assert_equal :landing_page_edit, task_type
  end

  test "landing_page_viewer canvas context routes to landing_page_edit" do
    task_type = GuidanceLibrary.detect_task_type(
      canvas_context: { type: "landing_page_viewer" }
    )
    assert_equal :landing_page_edit, task_type
  end

  # ═══════════════════════════════════════════════════════════════
  # SCOUT CONTROLLER - WEBSITE PAGE EDITOR USES UNIFIED PARTIAL
  # ═══════════════════════════════════════════════════════════════

  test "render_website_page_editor exists as a method on ScoutController" do
    assert ScoutController.instance_methods(false).include?(:render_website_page_editor) ||
           ScoutController.private_instance_methods(false).include?(:render_website_page_editor),
      "ScoutController should have render_website_page_editor method"
  end

  # ═══════════════════════════════════════════════════════════════
  # WEBSITE & WEBSITE PAGE MODELS
  # ═══════════════════════════════════════════════════════════════

  test "Website model has website_pages association" do
    assert Website.reflect_on_association(:website_pages),
      "Website should have website_pages association"
  end

  test "WebsitePage model belongs to website" do
    assert WebsitePage.reflect_on_association(:website),
      "WebsitePage should belong to website"
  end

  test "Website has homepage method" do
    assert Website.instance_methods.include?(:homepage) ||
           Website.method_defined?(:homepage),
      "Website should have a homepage method"
  end
end
