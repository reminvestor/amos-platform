# frozen_string_literal: true

require "test_helper"

class ApplicationBuildServiceTest < ActiveSupport::TestCase
  fixtures :entities, :users, :application_plans

  setup do
    @entity = entities(:one)
    @user = users(:one)
  end

  # ═══════════════════════════════════════════════════════════════
  # UNIQUE SLUG GENERATION
  # ═══════════════════════════════════════════════════════════════

  test "unique_slug returns base slug when no collision" do
    plan = build_approved_plan("Unique App Name")
    service = ApplicationBuildService.new(plan)

    slug = service.send(:unique_slug, App, "unique_app_name", @entity.id)
    assert_equal "unique_app_name", slug
  end

  test "unique_slug appends counter on collision" do
    plan = build_approved_plan("Collision Test")
    service = ApplicationBuildService.new(plan)

    # Create an existing app to cause collision
    App.create!(
      entity_id: @entity.id,
      created_by: @user,
      name: "Existing",
      slug: "collision_test",
      status: "active"
    )

    slug = service.send(:unique_slug, App, "collision_test", @entity.id)
    assert_equal "collision_test_2", slug
  end

  test "unique_slug increments past multiple collisions" do
    plan = build_approved_plan("Multi Collision")
    service = ApplicationBuildService.new(plan)

    # Create multiple collisions
    %w[multi_collision multi_collision_2 multi_collision_3].each do |s|
      App.create!(
        entity_id: @entity.id,
        created_by: @user,
        name: "Ghost App",
        slug: s,
        status: "building"
      )
    end

    slug = service.send(:unique_slug, App, "multi_collision", @entity.id)
    assert_equal "multi_collision_4", slug
  end

  test "unique_slug is entity-scoped" do
    plan = build_approved_plan("Scoped Test")
    service = ApplicationBuildService.new(plan)

    # Create app in a DIFFERENT entity
    other_entity = entities(:two)
    App.create!(
      entity_id: other_entity.id,
      created_by: @user,
      name: "Other Entity App",
      slug: "scoped_test",
      status: "active"
    )

    # Same slug should be available for our entity
    slug = service.send(:unique_slug, App, "scoped_test", @entity.id)
    assert_equal "scoped_test", slug
  end

  test "unique_slug works for AppModule model" do
    plan = build_approved_plan("Module Slug Test")
    service = ApplicationBuildService.new(plan)

    AppModule.create!(
      entity_id: @entity.id,
      name: "Existing Module",
      slug: "contacts",
      status: "active"
    )

    slug = service.send(:unique_slug, AppModule, "contacts", @entity.id)
    assert_equal "contacts_2", slug
  end

  # ═══════════════════════════════════════════════════════════════
  # LINK TOOLS TO AGENT
  # ═══════════════════════════════════════════════════════════════

  test "link_tools_to_agent only links tools that exist in ToolCatalog" do
    plan = build_approved_plan("Tool Link Test")
    service = ApplicationBuildService.new(plan)

    # Create an agent
    agent = AgentPlugin.create!(
      entity: @entity,
      name: "Test Agent",
      slug: "test_agent_link_#{SecureRandom.hex(4)}",
      role: "executor",
      status: "active"
    )

    # Simulate having some CRUD tools created
    tool = ToolDefinition.create!(
      entity: @entity,
      name: "create_test_record_#{SecureRandom.hex(4)}",
      description: "Create test record",
      execution_type: "ruby_code",
      code: "{ success: true }",
      parameters: { type: "object", properties: {} }
    )

    service.instance_variable_set(:@results, {
      tools: [{ id: tool.id, name: tool.name }]
    })

    # Link tools
    service.send(:link_tools_to_agent, agent)

    linked_tool_names = AgentTool.where(agent_plugin: agent).pluck(:tool_name)

    # Should have the CRUD tool
    assert_includes linked_tool_names, tool.name

    # Should have standard tools that exist in catalog
    assert_includes linked_tool_names, "ask_user" if Tools::ToolCatalog.instance.tool_exists?("ask_user")
    assert_includes linked_tool_names, "web_search" if Tools::ToolCatalog.instance.tool_exists?("web_search")

    # Should NOT have deprecated tools
    refute_includes linked_tool_names, "get_data"
    refute_includes linked_tool_names, "get_schema"
  end

  test "link_tools_to_agent does not fail on missing standard tools" do
    plan = build_approved_plan("Safe Link Test")
    service = ApplicationBuildService.new(plan)

    agent = AgentPlugin.create!(
      entity: @entity,
      name: "Safe Agent",
      slug: "safe_agent_#{SecureRandom.hex(4)}",
      role: "executor",
      status: "active"
    )

    service.instance_variable_set(:@results, { tools: [] })

    # Should not raise any errors
    assert_nothing_raised do
      service.send(:link_tools_to_agent, agent)
    end
  end

  # ═══════════════════════════════════════════════════════════════
  # CREATE PARENT APP WITH SLUG DEDUP
  # ═══════════════════════════════════════════════════════════════

  test "create_parent_app deduplicates slug on collision" do
    # Create an existing app
    App.create!(
      entity_id: @entity.id,
      created_by: @user,
      name: "My CRM",
      slug: "my_crm",
      status: "building"
    )

    plan = build_approved_plan("My CRM")
    service = ApplicationBuildService.new(plan)
    service.instance_variable_set(:@results, {
      app: nil, modules: [], agent: nil, tools: [],
      integrations: [], workflows: [], scheduled_tasks: [],
      webhooks: [], website: nil, web_app: nil
    })

    service.send(:create_parent_app!)

    app = service.instance_variable_get(:@app)
    assert_not_nil app
    assert_equal "my_crm_2", app.slug
    assert_equal "My CRM", app.name
  end

  # ═══════════════════════════════════════════════════════════════
  # CREATE MODULE WITH SLUG DEDUP
  # ═══════════════════════════════════════════════════════════════

  test "create_module deduplicates slug on collision" do
    # Create an existing module with the target slug
    AppModule.create!(
      entity_id: @entity.id,
      name: "Contacts",
      slug: "contacts_dedup_test",
      status: "active"
    )

    plan = build_approved_plan("Module Dedup Test")
    service = ApplicationBuildService.new(plan)
    service.instance_variable_set(:@plan, plan)

    module_spec = {
      "name" => "Contacts",
      "slug" => "contacts_dedup_test",
      "description" => "Contact management",
      "fields" => [{ "name" => "name", "field_type" => "string" }]
    }

    app_module = service.send(:create_module, module_spec)
    assert_equal "contacts_dedup_test_2", app_module.slug
    assert_equal "Contacts", app_module.name
  end

  # ═══════════════════════════════════════════════════════════════
  # FULL BUILD VALIDATION
  # ═══════════════════════════════════════════════════════════════

  test "build rejects non-approved plans" do
    plan = ApplicationPlan.create!(
      entity: @entity,
      created_by: @user,
      name: "Drafting Plan",
      status: "drafting",
      plan_spec: { "modules" => [{ "name" => "Test" }] }
    )

    service = ApplicationBuildService.new(plan)
    error = assert_raises(ApplicationBuildService::BuildError) do
      service.execute!
    end
    assert_includes error.message, "must be approved"
  end

  test "build rejects plans without modules" do
    plan = ApplicationPlan.create!(
      entity: @entity,
      created_by: @user,
      name: "Empty Plan",
      status: "approved",
      approved_at: Time.current,
      plan_spec: { "modules" => [] }
    )

    service = ApplicationBuildService.new(plan)
    error = assert_raises(ApplicationBuildService::BuildError) do
      service.execute!
    end
    assert_includes error.message, "at least one module"
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
end
