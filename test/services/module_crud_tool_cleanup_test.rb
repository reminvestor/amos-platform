# frozen_string_literal: true

require "test_helper"

class ModuleCrudToolCleanupTest < ActiveSupport::TestCase
  fixtures :entities, :users

  setup do
    @entity = entities(:one)
    @user = users(:one)
    @other_entity = entities(:two)
  end

  # ═══════════════════════════════════════════════════════════════
  # APPLICATION BUILD SERVICE — NO CRUD TOOL GENERATION
  # ═══════════════════════════════════════════════════════════════

  test "build_tools! does not create ToolDefinition records" do
    plan = build_approved_plan("No Tools App")
    service = ApplicationBuildService.new(plan)

    app_module = AppModule.create!(
      entity: @entity,
      name: "Test Module",
      slug: "test_no_crud_#{SecureRandom.hex(4)}",
      status: "active",
      metadata: { "schema" => { "fields" => [{ "name" => "title", "field_type" => "string" }] } }
    )

    service.instance_variable_set(:@results, {
      app: nil, modules: [{ id: app_module.id, name: app_module.name }],
      agent: nil, tools: [], integrations: [], workflows: [],
      scheduled_tasks: [], webhooks: [], website: nil, web_app: nil
    })

    initial_count = ToolDefinition.where(entity: @entity).count

    service.send(:build_tools!)

    assert_equal initial_count, ToolDefinition.where(entity: @entity).count,
      "build_tools! should NOT create any ToolDefinition records"
    assert_empty service.instance_variable_get(:@results)[:tools],
      "No tools should be reported in results"
  end

  # ═══════════════════════════════════════════════════════════════
  # DYNAMIC TOOL REGISTRAR — CRUD GENERATION DISABLED
  # ═══════════════════════════════════════════════════════════════

  test "create_crud_tools_for_model returns empty array" do
    app_module = create_test_module("registrar_test")
    model_code = create_test_model_code(app_module, "RegistrarWidget")

    registrar = Modules::DynamicToolRegistrar.instance
    result = registrar.create_crud_tools_for_model(app_module, model_code)

    assert_equal [], result, "Should return empty array (CRUD handled by platform tools)"
  end

  test "create_tool_for_module still works for non-CRUD custom tools" do
    app_module = create_test_module("custom_tool_test")

    registrar = Modules::DynamicToolRegistrar.instance
    tool = registrar.create_tool_for_module(app_module, {
      name: "custom_webhook_handler_#{SecureRandom.hex(4)}",
      description: "Handle incoming webhooks for this module",
      parameters: { type: "object", properties: { payload: { type: "object" } } },
      execution_type: "ruby_code",
      code: "{ success: true, received: _args }"
    })

    assert tool.persisted?, "Custom (non-CRUD) tools should still be creatable"
    assert_equal app_module.id, tool.app_module_id
  end

  # ═══════════════════════════════════════════════════════════════
  # TOOL CATALOG — FILTERS OUT MODULE CRUD TOOLS
  # ═══════════════════════════════════════════════════════════════

  test "load_dynamic_tools_for_entity excludes module-linked tools" do
    # Create a module-linked CRUD tool (simulating old behavior)
    app_module = create_test_module("catalog_filter_test")
    module_tool = ToolDefinition.create!(
      entity: @entity,
      app_module: app_module,
      name: "create_catalog_filter_test_#{SecureRandom.hex(4)}",
      description: "Create a record (should be filtered out)",
      execution_type: "ruby_code",
      code: "{ success: true }",
      parameters: { "type" => "object", "properties" => {} }
    )

    # Create a standalone custom tool (no module link)
    custom_tool = ToolDefinition.create!(
      entity: @entity,
      app_module: nil,
      name: "custom_standalone_#{SecureRandom.hex(4)}",
      description: "A genuinely custom tool",
      execution_type: "ruby_code",
      code: "{ success: true }",
      parameters: { "type" => "object", "properties" => {} }
    )

    catalog = Tools::ToolCatalog.instance
    # Clear cache to force reload
    catalog.instance_variable_set(:@entity_tools, {})

    loaded = catalog.send(:load_dynamic_tools_for_entity, @entity)

    refute loaded.key?(module_tool.name),
      "Module-linked CRUD tools should NOT be loaded into LLM context"
    assert loaded.key?(custom_tool.name),
      "Standalone custom tools should be loaded"
  end

  test "load_dynamic_tools_for_entity returns empty for entity with only module tools" do
    entity = @other_entity

    app_module = AppModule.create!(
      entity: entity, name: "Only CRUD", slug: "only_crud_#{SecureRandom.hex(4)}",
      status: "active", version: "1.0.0", author_type: "amos", visibility: "user_private"
    )

    ToolDefinition.create!(
      entity: entity, app_module: app_module,
      name: "list_only_crud_#{SecureRandom.hex(4)}",
      description: "List records", execution_type: "ruby_code",
      code: "{ success: true }", parameters: { "type" => "object", "properties" => {} }
    )

    catalog = Tools::ToolCatalog.instance
    catalog.instance_variable_set(:@entity_tools, {})

    loaded = catalog.send(:load_dynamic_tools_for_entity, entity)
    assert_empty loaded, "Should return empty when only module CRUD tools exist"
  end

  # ═══════════════════════════════════════════════════════════════
  # PLATFORM EXECUTE — DELETE SUPPORTS CUSTOM MODULES
  # ═══════════════════════════════════════════════════════════════

  test "delete still works for standard types" do
    contact = Contact.create!(
      entity: @entity, user: @user,
      first_name: "Del", last_name: "Test",
      email: "del-crud-test-#{SecureRandom.hex(4)}@test.com"
    )

    tool = V3::Tools::PlatformExecuteTool.new(user: @user, entity: @entity)
    result = tool.execute({ "action" => "delete", "type" => "contact", "id" => contact.id })

    assert result[:success] != false, "Standard delete should still work: #{result[:error]}"
    refute Contact.exists?(id: contact.id)
  end

  test "delete error message includes custom module hint" do
    tool = V3::Tools::PlatformExecuteTool.new(user: @user, entity: @entity)
    result = tool.execute({ "action" => "delete", "type" => "nonexistent_xyz", "id" => 1 })

    assert_equal false, result[:success]
    assert_match /custom module type/, result[:error],
      "Error message should mention custom module support"
  end

  test "resolve_dynamic_model_for_delete returns nil for nonexistent modules" do
    tool = V3::Tools::PlatformExecuteTool.new(user: @user, entity: @entity)
    result = tool.send(:resolve_dynamic_model_for_delete, "completely_fake_module")
    assert_nil result
  end

  test "resolve_dynamic_model_for_delete resolves by slug/ModelName format" do
    app_module = create_test_module("del_test_mod")
    create_test_model_code(app_module, "DelWidget")

    mock_model = mock_dynamic_model_class("DelWidget")
    tool = V3::Tools::PlatformExecuteTool.new(user: @user, entity: @entity)

    Modules::DynamicModelLoader.instance.stub(:get_model_by_path, mock_model) do
      result = tool.send(:resolve_dynamic_model_for_delete, "del_test_mod/DelWidget")
      assert_equal mock_model, result
    end
  end

  test "resolve_dynamic_model_for_delete resolves by module slug" do
    app_module = create_test_module("slug_del_test")
    create_test_model_code(app_module, "SlugDelTest")

    mock_model = mock_dynamic_model_class("SlugDelTest")
    tool = V3::Tools::PlatformExecuteTool.new(user: @user, entity: @entity)

    Modules::DynamicModelLoader.instance.stub(:get_model_by_path, mock_model) do
      result = tool.send(:resolve_dynamic_model_for_delete, "slug_del_test")
      assert_equal mock_model, result
    end
  end

  # ═══════════════════════════════════════════════════════════════
  # PLATFORM FACTORY JOB — NO TOOL GENERATION
  # ═══════════════════════════════════════════════════════════════

  test "generate_tools returns empty tools array" do
    app_module = create_test_module("factory_test")

    job = PlatformFactoryJob.new
    job.instance_variable_set(:@app_module, app_module)

    schema = { models: [{ name: "FactoryWidget" }] }
    result = job.send(:generate_tools, schema)

    assert result[:success]
    assert_empty result[:tools], "Should not generate any tools"
    assert_empty result[:errors]
  end

  test "generate_tools_from_plan returns empty tools array" do
    app_module = create_test_module("factory_plan_test")

    job = PlatformFactoryJob.new
    job.instance_variable_set(:@app_module, app_module)

    planned_spec = {
      tools: [
        { name: "manage_widget", description: "Manage widgets", tool_type: "crud", model: "Widget" }
      ]
    }
    result = job.send(:generate_tools_from_plan, planned_spec)

    assert result[:success]
    assert_empty result[:tools], "Should not generate any tools from plan"
  end

  private

  def build_approved_plan(name)
    ApplicationPlan.create!(
      entity: @entity,
      created_by: @user,
      name: name,
      status: "approved",
      approved_at: Time.current,
      plan_spec: {
        "modules" => [
          {
            "name" => "Test Module",
            "slug" => "test_module_#{SecureRandom.hex(4)}",
            "fields" => [{ "name" => "title", "field_type" => "string" }]
          }
        ]
      }
    )
  end

  def create_test_module(slug, status: "active")
    AppModule.create!(
      entity: @entity,
      name: slug.titleize,
      slug: slug,
      status: status,
      version: "1.0.0",
      author_type: "amos",
      visibility: "user_private"
    )
  end

  def create_test_model_code(app_module, model_name, table_name: nil, fields: nil)
    table = table_name || app_module.slug.pluralize
    schema_fields = fields || [
      { "name" => "name", "type" => "string" },
      { "name" => "status", "type" => "string" }
    ]

    ModuleCode.create!(
      app_module: app_module,
      entity_id: app_module.entity_id,
      name: model_name,
      code_type: "model",
      content: <<~RUBY,
        class #{model_name} < ApplicationRecord
          self.table_name = '#{table}'
          belongs_to :entity
        end
      RUBY
      schema_definition: {
        "table_name" => table,
        "fields" => schema_fields,
        "associations" => [],
        "indexes" => [{ "fields" => ["entity_id"] }]
      },
      status: "deployed"
    )
  end

  def mock_dynamic_model_class(name)
    Class.new do
      define_singleton_method(:name) { name }
      define_singleton_method(:table_name) { name.underscore.pluralize }
      define_singleton_method(:column_names) { %w[id name status entity_id created_at updated_at] }
    end
  end
end
