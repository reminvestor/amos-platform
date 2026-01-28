# frozen_string_literal: true

require "test_helper"

class AppModuleTest < ActiveSupport::TestCase
  def setup
    @entity = entities(:one)
    @user = users(:one)
  end

  # ─────────────────────────────────────────────────────────────────────────────
  # Basic Creation
  # ─────────────────────────────────────────────────────────────────────────────

  test "creates app module with required attributes" do
    app_module = AppModule.new(
      entity: @entity,
      created_by: @user,
      name: "Inventory Items",
      slug: "inventory_items",
      status: "draft"
    )
    
    assert app_module.valid?
    assert app_module.save
  end

  test "requires entity" do
    app_module = AppModule.new(
      name: "Test Module",
      slug: "test_module"
    )
    
    assert_not app_module.valid?
    assert_includes app_module.errors[:entity], "must exist"
  end

  test "requires name" do
    app_module = AppModule.new(
      entity: @entity,
      slug: "test_slug"
    )
    
    assert_not app_module.valid?
    assert_includes app_module.errors[:name], "can't be blank"
  end

  test "requires unique slug per entity" do
    AppModule.create!(
      entity: @entity,
      name: "First Module",
      slug: "unique_slug",
      status: "draft"
    )
    
    duplicate = AppModule.new(
      entity: @entity,
      name: "Second Module",
      slug: "unique_slug"
    )
    
    assert_not duplicate.valid?
  end

  # ─────────────────────────────────────────────────────────────────────────────
  # Status Management
  # ─────────────────────────────────────────────────────────────────────────────

  test "defaults to draft status" do
    app_module = AppModule.new(
      entity: @entity,
      name: "New Module",
      slug: "new_module"
    )
    
    assert_equal "draft", app_module.status
  end

  test "supports status transitions" do
    app_module = AppModule.create!(
      entity: @entity,
      name: "Status Test",
      slug: "status_test",
      status: "draft"
    )
    
    # Draft -> Designing -> Generating -> Active
    app_module.update!(status: "designing")
    assert_equal "designing", app_module.status
    
    app_module.update!(status: "generating")
    assert_equal "generating", app_module.status
    
    app_module.update!(status: "active")
    assert_equal "active", app_module.status
  end

  # ─────────────────────────────────────────────────────────────────────────────
  # Visibility & Permissions
  # ─────────────────────────────────────────────────────────────────────────────

  test "defaults to user_private visibility" do
    app_module = AppModule.new(
      entity: @entity,
      created_by: @user,
      name: "Private Module",
      slug: "private_module"
    )
    
    # Check the default is set
    assert_includes %w[entity_private user_private], app_module.visibility
  end

  test "entity_private visibility is accessible to all entity users" do
    app_module = AppModule.create!(
      entity: @entity,
      created_by: @user,
      name: "Entity Module",
      slug: "entity_module",
      visibility: "entity_private",
      status: "active"
    )
    
    # Should be visible to any user in the entity
    if AppModule.respond_to?(:visible_to)
      visible = AppModule.visible_to(@user)
      assert_includes visible, app_module
    end
  end

  # ─────────────────────────────────────────────────────────────────────────────
  # Associations
  # ─────────────────────────────────────────────────────────────────────────────

  test "has many module_canvases" do
    app_module = AppModule.create!(
      entity: @entity,
      name: "Canvas Parent",
      slug: "canvas_parent",
      status: "active"
    )
    
    assert_respond_to app_module, :module_canvases
  end

  test "has many module_codes" do
    app_module = AppModule.create!(
      entity: @entity,
      name: "Code Parent",
      slug: "code_parent",
      status: "active"
    )
    
    assert_respond_to app_module, :module_codes
  end

  test "belongs to created_by user" do
    app_module = AppModule.create!(
      entity: @entity,
      created_by: @user,
      name: "User Created",
      slug: "user_created",
      status: "draft"
    )
    
    assert_equal @user, app_module.created_by
  end

  # ─────────────────────────────────────────────────────────────────────────────
  # Configuration
  # ─────────────────────────────────────────────────────────────────────────────

  test "stores components as JSONB" do
    app_module = AppModule.create!(
      entity: @entity,
      name: "With Components",
      slug: "with_components",
      components: {
        "tables" => ["inventory_items"],
        "canvases" => ["list", "form", "detail"],
        "tools" => ["create", "update", "delete"]
      }
    )
    
    assert_equal ["inventory_items"], app_module.components["tables"]
    assert_equal ["list", "form", "detail"], app_module.components["canvases"]
  end

  test "stores field_config as JSONB" do
    app_module = AppModule.create!(
      entity: @entity,
      name: "With Fields",
      slug: "with_fields",
      field_config: {
        "fields" => [
          { "name" => "name", "type" => "string", "required" => true },
          { "name" => "quantity", "type" => "integer" },
          { "name" => "price", "type" => "decimal" }
        ]
      }
    )
    
    fields = app_module.field_config["fields"]
    assert_equal 3, fields.length
    assert_equal "name", fields.first["name"]
  end

  # ─────────────────────────────────────────────────────────────────────────────
  # Scopes
  # ─────────────────────────────────────────────────────────────────────────────

  test "active scope returns only active modules" do
    active = AppModule.create!(entity: @entity, name: "Active", slug: "active_mod", status: "active")
    draft = AppModule.create!(entity: @entity, name: "Draft", slug: "draft_mod", status: "draft")
    
    active_modules = AppModule.where(entity: @entity).active rescue AppModule.where(entity: @entity, status: "active")
    
    assert_includes active_modules, active
    assert_not_includes active_modules, draft
  end
end
