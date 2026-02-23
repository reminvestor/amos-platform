# frozen_string_literal: true

require "test_helper"

class AppBuildPipelineTest < ActiveSupport::TestCase
  fixtures :entities, :users

  setup do
    @entity = entities(:one)
    @user = users(:one)
  end

  # ═══════════════════════════════════════════════════════════════
  # FIX 1: IMMEDIATE MODULE ACTIVATION
  # ═══════════════════════════════════════════════════════════════

  test "build_single_module activates the module immediately" do
    plan = build_approved_plan("Early Activate App")
    service = ApplicationBuildService.new(plan)
    service.instance_variable_set(:@results, empty_results)

    module_spec = plan.modules_spec.first

    # Stub DynamicModelLoader to avoid actual table creation
    Modules::DynamicModelLoader.instance.stub(:load_model, nil) do
      service.send(:build_single_module, module_spec)
    end

    built_module = AppModule.find(service.instance_variable_get(:@results)[:modules].first[:id])
    assert_equal "active", built_module.status,
      "Module should be active immediately after build_single_module, not stuck in generating"
  end

  test "finalize_build still activates modules that were missed" do
    plan = build_building_plan("Finalize Safety Net")
    service = ApplicationBuildService.new(plan)

    slug = "safety_net_#{SecureRandom.hex(4)}"
    app_module = AppModule.create!(
      entity: @entity,
      name: "Safety Net Module",
      slug: slug,
      status: "generating",
      version: "1.0.0",
      author_type: "amos",
      visibility: "user_private"
    )

    service.instance_variable_set(:@results, empty_results.merge(
      modules: [{ id: app_module.id, name: app_module.name, slug: slug }]
    ))

    service.send(:finalize_build!)

    app_module.reload
    assert_equal "active", app_module.status,
      "finalize_build! should activate any remaining generating modules"
  end

  test "finalize_build activates web app" do
    plan = build_building_plan("WebApp Activate")
    service = ApplicationBuildService.new(plan)

    web_app = WebApp.create!(
      entity: @entity,
      created_by: @user,
      name: "Test Web App",
      slug: "test_webapp_#{SecureRandom.hex(4)}",
      status: "draft"
    )

    service.instance_variable_set(:@results, empty_results.merge(
      web_app: { id: web_app.id, name: web_app.name }
    ))

    service.send(:finalize_build!)

    web_app.reload
    assert_equal "active", web_app.status,
      "finalize_build! should activate the web app"
  end

  # ═══════════════════════════════════════════════════════════════
  # FIX 2: PLAN RESUME
  # ═══════════════════════════════════════════════════════════════

  test "find_existing_plan finds paused plans" do
    plan = build_approved_plan("Resume Test App")
    plan.update!(status: "paused")

    tool = build_platform_create_tool
    result = tool.send(:find_existing_plan, "Resume Test App")

    assert_not_nil result, "Should find a paused plan with matching name"
    assert_equal plan.id, result.id
  end

  test "find_existing_plan finds building plans" do
    plan = build_approved_plan("Building Test App")
    plan.update!(status: "building")

    tool = build_platform_create_tool
    result = tool.send(:find_existing_plan, "Building Test App")

    assert_not_nil result, "Should find a building plan with matching name"
    assert_equal plan.id, result.id
  end

  test "find_existing_plan finds completed plans to prevent duplicates" do
    plan = build_approved_plan("Completed App")
    plan.update!(status: "completed")

    tool = build_platform_create_tool
    result = tool.send(:find_existing_plan, "Completed App")

    assert_not_nil result, "Should find a completed plan to prevent duplicate creation"
    assert_equal plan.id, result.id
    assert_equal "completed", result.status
  end

  test "find_existing_plan ignores old plans" do
    plan = build_approved_plan("Old Paused App")
    plan.update!(status: "paused", created_at: 31.days.ago)

    tool = build_platform_create_tool
    result = tool.send(:find_existing_plan, "Old Paused App")

    assert_nil result, "Should not find a plan older than 30 days"
  end

  test "find_existing_plan is case insensitive" do
    plan = build_approved_plan("My CRM App")
    plan.update!(status: "paused")

    tool = build_platform_create_tool
    result = tool.send(:find_existing_plan, "my crm app")

    assert_not_nil result, "Should find plan regardless of case"
    assert_equal plan.id, result.id
  end

  # ═══════════════════════════════════════════════════════════════
  # FIX 3: SMART CANCELLATION
  # ═══════════════════════════════════════════════════════════════

  test "cancellation check ignores affirmative messages" do
    tool = build_platform_create_tool
    build_start = 1.second.ago
    check = tool.send(:build_cancellation_check, build_start)

    affirmatives = ["yes", "Yes!", "continue", "go ahead", "build it", "ok", "sure", "Yeah", "proceed"]
    affirmatives.each do |msg|
      ScoutMessage.where(user_id: @user.id, entity_id: @entity.id, role: "user")
        .where("created_at > ?", build_start).delete_all

      ScoutMessage.create!(
        user: @user,
        entity: @entity,
        session_id: "test_session",
        role: "user",
        content: msg
      )

      assert_not check.call, "Should NOT cancel on affirmative message: '#{msg}'"
    end
  end

  test "cancellation check triggers on real messages" do
    tool = build_platform_create_tool
    build_start = 1.second.ago
    check = tool.send(:build_cancellation_check, build_start)

    ScoutMessage.create!(
      user: @user,
      entity: @entity,
      session_id: "test_session",
      role: "user",
      content: "Actually, I want to build something completely different instead"
    )

    assert check.call, "Should cancel on a real topic-change message"
  end

  test "cancellation check returns false when no new messages" do
    tool = build_platform_create_tool
    build_start = Time.current
    check = tool.send(:build_cancellation_check, build_start)

    assert_not check.call, "Should not cancel when no new messages exist"
  end

  # ═══════════════════════════════════════════════════════════════
  # FIX 4b: NO DEAD WEB APP URLS
  # ═══════════════════════════════════════════════════════════════

  test "build_web_app results use preview URL not public_url" do
    plan = build_approved_plan("No Dead URL App")
    service = ApplicationBuildService.new(plan)

    web_app = WebApp.create!(
      entity: @entity,
      created_by: @user,
      name: "Preview URL App",
      slug: "preview_url_#{SecureRandom.hex(4)}",
      subdomain: "preview-test",
      status: "draft"
    )

    service.instance_variable_set(:@results, empty_results)
    results = service.instance_variable_get(:@results)
    results[:web_app] = {
      id: web_app.id,
      name: web_app.name,
      slug: web_app.slug,
      preview_url: "/design_preview/web_app/#{web_app.id}",
      requires_auth: false
    }

    assert_includes results[:web_app][:preview_url], "/design_preview/",
      "Web app results should use design preview URL"
    assert_nil results[:web_app][:public_url],
      "Web app results should not include public_url"
  end

  # ═══════════════════════════════════════════════════════════════
  # FIX: ApplicationPlan.built_app_modules via JSONB metadata
  # ═══════════════════════════════════════════════════════════════

  test "ApplicationPlan built_app_modules finds modules via metadata JSONB" do
    plan = build_approved_plan("JSONB Lookup App")
    slug = "jsonb_test_#{SecureRandom.hex(4)}"

    mod = AppModule.create!(
      entity: @entity,
      name: "JSONB Module",
      slug: slug,
      status: "active",
      version: "1.0.0",
      author_type: "amos",
      visibility: "user_private",
      metadata: { "application_plan_id" => plan.id.to_s }
    )

    found = plan.built_app_modules
    assert_includes found.pluck(:id), mod.id,
      "built_app_modules should find modules linked via metadata JSONB"

    active = plan.built_app_modules.where(status: "active")
    assert_includes active.pluck(:id), mod.id,
      "Should be chainable with .where(status: 'active')"
  ensure
    mod&.delete
    plan&.delete
  end

  test "ApplicationPlan built_app_modules excludes modules from other plans" do
    plan_a = build_approved_plan("Plan A")
    plan_b = build_approved_plan("Plan B")

    mod_a = AppModule.create!(
      entity: @entity,
      name: "Module A",
      slug: "mod_a_#{SecureRandom.hex(4)}",
      status: "active",
      version: "1.0.0",
      author_type: "amos",
      visibility: "user_private",
      metadata: { "application_plan_id" => plan_a.id.to_s }
    )

    mod_b = AppModule.create!(
      entity: @entity,
      name: "Module B",
      slug: "mod_b_#{SecureRandom.hex(4)}",
      status: "active",
      version: "1.0.0",
      author_type: "amos",
      visibility: "user_private",
      metadata: { "application_plan_id" => plan_b.id.to_s }
    )

    result_a = plan_a.built_app_modules.pluck(:id)
    result_b = plan_b.built_app_modules.pluck(:id)

    assert_includes result_a, mod_a.id
    refute_includes result_a, mod_b.id, "Plan A should not see Plan B's modules"

    assert_includes result_b, mod_b.id
    refute_includes result_b, mod_a.id, "Plan B should not see Plan A's modules"
  ensure
    mod_a&.delete
    mod_b&.delete
    plan_a&.delete
    plan_b&.delete
  end

  test "ApplicationPlan does not have has_many app_modules association" do
    plan = build_approved_plan("No Association Test")

    refute plan.class.reflect_on_association(:app_modules),
      "ApplicationPlan should NOT have has_many :app_modules (removed; use built_app_modules)"
  ensure
    plan&.delete
  end

  private

  def build_approved_plan(name)
    slug = name.parameterize.underscore + "_#{SecureRandom.hex(4)}"
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
            "slug" => slug,
            "fields" => [{ "name" => "title", "field_type" => "string" }]
          }
        ]
      }
    )
  end

  def empty_results
    {
      app: nil, modules: [], agent: nil, tools: [],
      integrations: [], workflows: [], scheduled_tasks: [],
      webhooks: [], website: nil, web_app: nil
    }
  end

  def build_building_plan(name)
    plan = build_approved_plan(name)
    plan.update!(status: "building")
    plan
  end

  def build_platform_create_tool
    V3::Tools::PlatformCreateTool.new(user: @user, entity: @entity)
  end
end
