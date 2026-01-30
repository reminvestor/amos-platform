# frozen_string_literal: true

require "test_helper"

class ModuleCanvasTest < ActiveSupport::TestCase
  def setup
    @entity = entities(:one)
    @user = users(:one)
    @app_module = AppModule.create!(
      entity: @entity,
      created_by: @user,
      name: "Test Module",
      slug: "test_module_#{SecureRandom.hex(4)}",
      status: "active"
    )
  end

  # ─────────────────────────────────────────────────────────────────────────────
  # Basic Creation
  # ─────────────────────────────────────────────────────────────────────────────

  test "creates module canvas with required attributes" do
    canvas = ModuleCanvas.new(
      app_module: @app_module,
      entity: @entity,
      name: "Inventory List",
      slug: "inventory_list"
    )
    
    assert canvas.valid?
    assert canvas.save
  end

  test "requires app_module" do
    canvas = ModuleCanvas.new(
      entity: @entity,
      name: "Orphan Canvas",
      slug: "orphan_canvas"
    )
    
    assert_not canvas.valid?
    assert_includes canvas.errors[:app_module], "must exist"
  end

  test "requires unique slug per app_module" do
    ModuleCanvas.create!(
      app_module: @app_module,
      entity: @entity,
      name: "First Canvas",
      slug: "unique_canvas_slug"
    )
    
    duplicate = ModuleCanvas.new(
      app_module: @app_module,
      entity: @entity,
      name: "Second Canvas",
      slug: "unique_canvas_slug"
    )
    
    assert_not duplicate.valid?
  end

  # ─────────────────────────────────────────────────────────────────────────────
  # Canvas Types
  # ─────────────────────────────────────────────────────────────────────────────

  test "supports data_grid canvas type" do
    canvas = ModuleCanvas.create!(
      app_module: @app_module,
      entity: @entity,
      name: "Data Grid",
      slug: "data_grid_canvas",
      canvas_type: "data_grid"
    )
    
    assert_equal "data_grid", canvas.canvas_type
  end

  test "supports form canvas type" do
    canvas = ModuleCanvas.create!(
      app_module: @app_module,
      entity: @entity,
      name: "Edit Form",
      slug: "edit_form_canvas",
      canvas_type: "form"
    )
    
    assert_equal "form", canvas.canvas_type
  end

  test "supports report canvas type" do
    canvas = ModuleCanvas.create!(
      app_module: @app_module,
      entity: @entity,
      name: "Report View",
      slug: "report_canvas",
      canvas_type: "report"
    )
    
    assert_equal "report", canvas.canvas_type
  end

  test "supports dashboard canvas type" do
    canvas = ModuleCanvas.create!(
      app_module: @app_module,
      entity: @entity,
      name: "Dashboard",
      slug: "dashboard_canvas",
      canvas_type: "dashboard"
    )
    
    assert_equal "dashboard", canvas.canvas_type
  end

  # ─────────────────────────────────────────────────────────────────────────────
  # Data Sources
  # ─────────────────────────────────────────────────────────────────────────────

  test "stores data_sources as JSONB array" do
    canvas = ModuleCanvas.create!(
      app_module: @app_module,
      entity: @entity,
      name: "With Data Sources",
      slug: "with_data_sources",
      data_sources: [
        { "type" => "module_data", "model" => "inventory_items" },
        { "type" => "integration", "name" => "stripe_customers" }
      ]
    )
    
    assert_equal 2, canvas.data_sources.length
    assert_equal "module_data", canvas.data_sources.first["type"]
  end

  test "data_sources defaults to empty array" do
    canvas = ModuleCanvas.create!(
      app_module: @app_module,
      entity: @entity,
      name: "No Data Sources",
      slug: "no_data_sources"
    )
    
    assert_equal [], canvas.data_sources
  end

  # ─────────────────────────────────────────────────────────────────────────────
  # Content
  # ─────────────────────────────────────────────────────────────────────────────

  test "stores html_content" do
    canvas = ModuleCanvas.create!(
      app_module: @app_module,
      entity: @entity,
      name: "HTML Canvas",
      slug: "html_canvas",
      html_content: "<div class='data-grid'>{{ items }}</div>"
    )
    
    assert_includes canvas.html_content, "data-grid"
  end

  test "stores js_content" do
    canvas = ModuleCanvas.create!(
      app_module: @app_module,
      entity: @entity,
      name: "JS Canvas",
      slug: "js_canvas",
      js_content: "function init() { console.log('loaded'); }"
    )
    
    assert_includes canvas.js_content, "init"
  end

  test "stores css_content" do
    canvas = ModuleCanvas.create!(
      app_module: @app_module,
      entity: @entity,
      name: "CSS Canvas",
      slug: "css_canvas",
      css_content: ".data-grid { display: grid; }"
    )
    
    assert_includes canvas.css_content, "display: grid"
  end

  # ─────────────────────────────────────────────────────────────────────────────
  # Default Canvas
  # ─────────────────────────────────────────────────────────────────────────────

  test "is_default flag marks primary canvas for module" do
    default_canvas = ModuleCanvas.create!(
      app_module: @app_module,
      entity: @entity,
      name: "Default Canvas",
      slug: "default_canvas",
      is_default: true
    )
    
    other_canvas = ModuleCanvas.create!(
      app_module: @app_module,
      entity: @entity,
      name: "Other Canvas",
      slug: "other_canvas",
      is_default: false
    )
    
    assert default_canvas.is_default
    assert_not other_canvas.is_default
  end

  # ─────────────────────────────────────────────────────────────────────────────
  # Layout Configuration
  # ─────────────────────────────────────────────────────────────────────────────

  test "stores layout_config as JSONB" do
    canvas = ModuleCanvas.create!(
      app_module: @app_module,
      entity: @entity,
      name: "Configured Canvas",
      slug: "configured_canvas",
      layout_config: {
        "columns" => 3,
        "show_filters" => true,
        "pagination" => { "per_page" => 25 }
      }
    )
    
    assert_equal 3, canvas.layout_config["columns"]
    assert canvas.layout_config["show_filters"]
    assert_equal 25, canvas.layout_config["pagination"]["per_page"]
  end

  # ─────────────────────────────────────────────────────────────────────────────
  # Versioning
  # ─────────────────────────────────────────────────────────────────────────────

  test "tracks version number" do
    canvas = ModuleCanvas.create!(
      app_module: @app_module,
      entity: @entity,
      name: "Versioned Canvas",
      slug: "versioned_canvas",
      version: 1
    )
    
    assert_equal 1, canvas.version
    
    canvas.update!(version: 2)
    assert_equal 2, canvas.version
  end
end
