# frozen_string_literal: true

require 'test_helper'

# End-to-End tests for the Platform Factory redesign
#
# These tests verify the complete flow from planning through building
# an application using the new collaborative planning system.
#
class PlatformFactoryE2eTest < ActionDispatch::IntegrationTest
  fixtures :entities, :users

  setup do
    @entity = entities(:one)
    @user = users(:one)
    
    # Ensure ArchetypeIntelligence is available
    assert defined?(Modules::ArchetypeIntelligence), "ArchetypeIntelligence must be defined"
  end

  # ============================================
  # APPLICATION PLAN LIFECYCLE TESTS
  # ============================================

  test "full plan lifecycle: drafting -> pending_approval -> approved -> completed" do
    # Step 1: Create a plan
    plan = ApplicationPlan.create!(
      entity: @entity,
      created_by: @user,
      name: "E2E Test Knowledge Base",
      description: "Testing the full lifecycle",
      archetype: "knowledge_base",
      status: "drafting",
      plan_spec: {
        'modules' => [
          {
            'name' => 'Articles',
            'slug' => 'articles',
            'description' => 'Knowledge base articles',
            'fields' => [
              { 'name' => 'title', 'field_type' => 'string', 'required' => true },
              { 'name' => 'content', 'field_type' => 'text', 'required' => true },
              { 'name' => 'status', 'field_type' => 'select', 'options' => %w[draft published archived] }
            ],
            'views' => %w[list form detail]
          }
        ],
        'agent' => {
          'name' => 'KB Expert',
          'slug' => 'kb_expert',
          'description' => 'Knowledge base AI expert',
          'capabilities' => ['answer questions', 'suggest articles'],
          'personality' => 'helpful'
        },
        'integrations' => [
          { 'slug' => 'slack', 'purpose' => 'notifications' }
        ],
        'workflows' => [
          {
            'name' => 'Publish Flow',
            'trigger' => 'status_change',
            'from_status' => 'draft',
            'to_status' => 'published',
            'actions' => ['notify_team']
          }
        ],
        'scheduled_tasks' => [
          {
            'name' => 'Stale Content Check',
            'schedule' => 'weekly',
            'time' => '09:00',
            'action' => 'check_stale_articles'
          }
        ]
      }
    )
    
    assert plan.drafting?
    assert_equal 1, plan.modules_spec.count
    assert plan.has_agent?
    
    # Step 2: Submit for approval
    plan.submit_for_approval!
    assert plan.pending_approval?
    
    # Step 3: Request changes (simulate user feedback)
    plan.request_changes!("Add a category field")
    assert plan.drafting?
    assert_equal 1, plan.refinement_history.count
    assert_equal "Add a category field", plan.refinement_history.first['feedback']
    
    # Step 4: Refine and resubmit
    updated_fields = plan.modules_spec.first['fields'] + [
      { 'name' => 'category', 'field_type' => 'select', 'options' => %w[faq guide tutorial] }
    ]
    plan.plan_spec['modules'].first['fields'] = updated_fields
    plan.save!
    plan.submit_for_approval!
    assert plan.pending_approval?
    
    # Step 5: Approve
    plan.approve!
    assert plan.approved?
    assert_not_nil plan.approved_at
    
    # Step 6: Start build
    plan.start_build!
    assert plan.building?
    assert_not_nil plan.build_started_at
    
    # Step 7: Complete (simulate)
    results = {
      modules: [{ id: 1, name: 'Articles', slug: 'articles' }],
      agent: { id: 1, name: 'KB Expert' },
      tools: [{ id: 1, name: 'create_article' }]
    }
    plan.complete!(results)
    assert plan.completed?
    assert_not_nil plan.completed_at
    assert_equal results, plan.build_results.deep_symbolize_keys
  end

  test "plan can be cancelled from any non-final state" do
    plan = ApplicationPlan.create!(
      entity: @entity,
      created_by: @user,
      name: "Cancelled Plan",
      status: "drafting",
      plan_spec: { 'modules' => [{ 'name' => 'Test' }] }
    )
    
    plan.cancel!
    assert plan.cancelled?
    
    # Cannot cancel a completed plan
    completed_plan = ApplicationPlan.create!(
      entity: @entity,
      created_by: @user,
      name: "Completed Plan",
      status: "completed",
      plan_spec: { 'modules' => [{ 'name' => 'Test' }] }
    )
    
    assert_raises(ApplicationPlan::InvalidTransition) do
      completed_plan.cancel!
    end
  end

  # ============================================
  # APPLICATION PLANNER SERVICE TESTS
  # ============================================

  test "planner service creates plan with archetype detection" do
    service = ApplicationPlannerService.new(entity: @entity, user: @user)
    
    # Test social media archetype detection
    plan = service.create_plan(
      name: "Social Media Manager",
      description: "Track and schedule social posts"
    )
    
    assert_not_nil plan
    assert_equal "social_media", plan.archetype
    assert plan.pending_approval? # Auto-submitted
    
    # Should have archetype-suggested content
    assert plan.modules_spec.any?, "Should have suggested modules"
    
    # Check for suggested integrations from archetype
    archetype_data = Modules::ArchetypeIntelligence::ARCHETYPES[:social_media]
    if archetype_data[:suggested_integrations].present?
      assert plan.integrations_spec.any?, "Should have suggested integrations"
    end
  end

  test "planner service creates custom plan for unknown archetype" do
    service = ApplicationPlannerService.new(entity: @entity, user: @user)
    
    plan = service.create_plan(
      name: "Widget Inventory Tracker XYZ",
      description: "Completely custom thing"
    )
    
    assert_not_nil plan
    assert_equal "custom", plan.archetype
    assert plan.modules_spec.any?, "Should have basic module"
    assert plan.has_agent?, "Should have basic agent"
  end

  test "planner service refines plan with additions" do
    service = ApplicationPlannerService.new(entity: @entity, user: @user)
    
    # Create initial plan
    plan = service.create_plan(name: "CRM System")
    plan.update!(status: 'drafting') # Reset for refinement
    
    original_integration_count = plan.integrations_spec.count
    original_workflow_count = plan.workflows_spec.count
    
    # Refine with additions
    plan = service.refine_plan(plan, {
      add_integration: { slug: 'hubspot', purpose: 'sync contacts' },
      add_workflow: { name: 'Lead Scoring', trigger: 'record_created', actions: ['calculate_score'] },
      add_scheduled_task: { name: 'Daily Sync', schedule: 'daily', time: '08:00', action: 'sync_all' }
    })
    
    assert_equal original_integration_count + 1, plan.integrations_spec.count
    assert_equal original_workflow_count + 1, plan.workflows_spec.count
    assert plan.scheduled_tasks_spec.any?
  end

  # ============================================
  # WEBSITE BUILDER SERVICE TESTS
  # ============================================

  test "website builder creates website with pages" do
    service = WebsiteBuilderService.new(entity: @entity, user: @user)
    
    website = service.create_website({
      name: "Test Documentation Site",
      description: "A documentation website",
      theme: "modern",
      pages: [
        { name: "Home", template: "homepage", is_homepage: true },
        { name: "About Us", template: "content" },
        { name: "Contact", template: "form" }
      ],
      features: ["search", "newsletter"]
    })
    
    assert_not_nil website
    assert_equal "Test Documentation Site", website.name
    assert_equal "modern", website.theme
    assert_equal 3, website.website_pages.count
    assert website.homepage.is_homepage?
    assert_includes website.features, "search"
    
    # Check pages created correctly
    about_page = website.website_pages.find_by(slug: "about-us")
    assert_not_nil about_page
    assert_equal "content", about_page.template
    assert about_page.show_in_nav?
  end

  test "website builder creates web app with modules" do
    service = WebsiteBuilderService.new(entity: @entity, user: @user)
    
    # First, create a mock app module
    app_module = AppModule.create!(
      entity: @entity,
      name: "Articles",
      slug: "articles",
      description: "Knowledge base articles",
      status: "active",
      version: "1.0.0"
    )
    
    web_app = service.create_web_app(
      {
        name: "KB Portal App",
        requires_auth: true,
        auth_methods: ["email", "google"],
        allow_registration: true,
        features: ["user_dashboard", "notifications"]
      },
      modules: [app_module]
    )
    
    assert_not_nil web_app
    assert_equal "KB Portal App", web_app.name
    assert web_app.requires_auth
    assert_includes web_app.auth_methods, "email"
    assert web_app.allows_registration?
    assert_equal 1, web_app.web_app_modules.count
    
    # Check module configuration
    wam = web_app.web_app_modules.first
    assert_equal app_module.id, wam.app_module_id
    assert wam.allow_create
    assert wam.allow_edit
    
    # Clean up
    app_module.destroy
  end

  # ============================================
  # TOOLS E2E TESTS
  # ============================================

  test "plan_application tool creates and shows plan" do
    tool = Tools::PlanApplicationTool.new
    tool.instance_variable_set(:@entity, @entity)
    tool.instance_variable_set(:@user, @user)
    tool.instance_variable_set(:@context, { session_id: "test_session" })
    
    result = tool.execute({
      "name" => "Inventory System",
      "description" => "Track products and stock levels"
    })
    
    assert result[:success], "Tool should succeed: #{result[:error]}"
    assert_not_nil result[:plan_id]
    assert_equal "inventory", result[:archetype] # Should detect inventory archetype
    assert result[:summary].present?
    
    # Verify plan was created
    plan = ApplicationPlan.find(result[:plan_id])
    assert_equal "Inventory System", plan.name
    assert plan.pending_approval?
  end

  test "update_application_plan tool modifies plan" do
    # First create a plan
    plan = ApplicationPlan.create!(
      entity: @entity,
      created_by: @user,
      name: "Update Test Plan",
      status: "drafting",
      plan_spec: {
        'modules' => [
          { 'name' => 'Items', 'fields' => [{ 'name' => 'name', 'field_type' => 'string' }], 'views' => ['list'] }
        ],
        'integrations' => [],
        'workflows' => []
      }
    )
    
    tool = Tools::UpdateApplicationPlanTool.new
    tool.instance_variable_set(:@entity, @entity)
    tool.instance_variable_set(:@user, @user)
    tool.instance_variable_set(:@context, { session_id: "test_session" })
    
    result = tool.execute({
      "plan_id" => plan.id,
      "updates" => {
        "add_field" => { "name" => "sku", "field_type" => "string", "required" => true },
        "add_integration" => { "slug" => "shopify", "purpose" => "sync inventory" },
        "add_workflow" => { "name" => "Low Stock Alert", "trigger" => "field_changed", "actions" => ["notify_team"] }
      }
    })
    
    assert result[:success], "Tool should succeed: #{result[:error]}"
    assert_equal 3, result[:changes].count
    
    # Reload and verify
    plan.reload
    fields = plan.modules_spec.first['fields']
    assert fields.any? { |f| f['name'] == 'sku' }
    assert plan.integrations_spec.any? { |i| i['slug'] == 'shopify' }
    assert plan.workflows_spec.any? { |w| w['name'] == 'Low Stock Alert' }
  end

  test "get_platform_capabilities tool returns all categories" do
    tool = Tools::GetPlatformCapabilitiesTool.new
    tool.instance_variable_set(:@entity, @entity)
    tool.instance_variable_set(:@user, @user)
    tool.instance_variable_set(:@context, {})
    
    result = tool.execute({ "category" => "all" })
    
    assert result[:success]
    assert result[:capabilities].present?
    assert result[:capabilities][:archetypes].any?
    assert result[:capabilities][:field_types].any?
    assert result[:capabilities][:automations].present?
  end

  test "get_platform_capabilities tool returns archetype details" do
    tool = Tools::GetPlatformCapabilitiesTool.new
    tool.instance_variable_set(:@entity, @entity)
    tool.instance_variable_set(:@user, @user)
    tool.instance_variable_set(:@context, {})
    
    result = tool.execute({ "archetype" => "crm" })
    
    assert result[:success]
    assert_equal "crm", result[:archetype][:key]
    assert result[:archetype][:core_fields].any?
    assert result[:archetype][:suggested_integrations].any?
  end

  # ============================================
  # FULL E2E FLOW TEST
  # ============================================

  test "complete E2E flow: plan -> refine -> build (mocked)" do
    # Step 1: Create plan via service
    planner = ApplicationPlannerService.new(entity: @entity, user: @user)
    plan = planner.create_plan(
      name: "Project Tracker",
      description: "Track tasks and projects",
      requirements: {
        additional_fields: [
          { name: 'due_date', field_type: 'date' },
          { name: 'assignee', field_type: 'user_select' }
        ]
      }
    )
    
    assert plan.pending_approval?
    
    # Step 2: User requests changes
    plan.request_changes!("Add priority field")
    
    # Step 3: Refine
    plan.update!(status: 'drafting')
    planner.refine_plan(plan, {
      add_field: { module_index: 0, name: 'priority', field_type: 'select', options: %w[low medium high critical] }
    })
    plan.submit_for_approval!
    
    # Step 4: User approves
    plan.approve!
    assert plan.approved?
    
    # Step 5: Build would happen here (mocked due to DB complexity)
    # In a real test with full DB setup, we'd call:
    # builder = ApplicationBuildService.new(plan)
    # result = builder.execute!
    # assert result[:success]
    
    # For now, simulate completion
    plan.start_build!
    plan.complete!({
      modules: [{ id: 999, name: 'Project Tracker', slug: 'project_tracker' }],
      agent: { id: 999, name: 'Project Tracker Expert' },
      tools: [{ id: 999, name: 'create_project_tracker' }]
    })
    
    assert plan.completed?
    assert_not_nil plan.completed_at
    assert plan.build_results['modules'].any?
  end

  # ============================================
  # ERROR HANDLING TESTS
  # ============================================

  test "plan validation prevents invalid status transitions" do
    plan = ApplicationPlan.create!(
      entity: @entity,
      created_by: @user,
      name: "Invalid Transition Test",
      status: "drafting",
      plan_spec: { 'modules' => [{ 'name' => 'Test' }] }
    )
    
    # Cannot approve directly from drafting
    assert_raises(ApplicationPlan::InvalidTransition) do
      plan.approve!
    end
    
    # Cannot start build from drafting
    assert_raises(ApplicationPlan::InvalidTransition) do
      plan.start_build!
    end
    
    # Cannot complete from drafting
    assert_raises(ApplicationPlan::InvalidTransition) do
      plan.complete!({})
    end
  end

  test "plan spec validation catches invalid modules" do
    plan = ApplicationPlan.new(
      entity: @entity,
      created_by: @user,
      name: "Invalid Spec Test",
      status: "drafting",
      plan_spec: {
        'modules' => [
          { 'fields' => [] }  # Missing 'name'
        ]
      }
    )
    
    assert_not plan.valid?
    assert plan.errors[:plan_spec].any?
  end

  test "build service rejects unapproved plans" do
    plan = ApplicationPlan.create!(
      entity: @entity,
      created_by: @user,
      name: "Unapproved Plan",
      status: "drafting",
      plan_spec: { 'modules' => [{ 'name' => 'Test' }] }
    )
    
    service = ApplicationBuildService.new(plan)
    result = service.execute!
    
    assert_not result[:success]
    assert_includes result[:error], "must be approved"
    assert plan.reload.drafting?  # Should still be drafting
  end

  # ============================================
  # WEBSITE & WEB APP INTEGRATION TESTS
  # ============================================

  test "website page templates generate correct HTML structure" do
    service = WebsiteBuilderService.new(entity: @entity, user: @user)
    
    website = service.create_website({
      name: "Template Test Site",
      pages: [
        { name: "Home", template: "homepage", is_homepage: true },
        { name: "Articles", template: "list", is_dynamic: true }
      ]
    })
    
    homepage = website.homepage
    assert_not_nil homepage.html_content
    assert_includes homepage.html_content, "hero"
    
    list_page = website.website_pages.find_by(template: "list")
    assert list_page.is_dynamic?
  end

  test "web app module access control works correctly" do
    # Create web app with module
    app_module = AppModule.create!(
      entity: @entity,
      name: "Test Module",
      slug: "test_module",
      status: "active"
    )
    
    web_app = WebApp.create!(
      entity: @entity,
      created_by: @user,
      name: "Access Control Test",
      slug: "access-test",
      status: "active",
      requires_auth: true
    )
    
    # Add module with limited permissions
    wam = web_app.web_app_modules.create!(
      app_module: app_module,
      is_public: false,
      allow_create: true,
      allow_edit: false,
      allow_delete: false
    )
    
    assert wam.can_create?
    assert_not wam.can_edit?
    assert_not wam.can_delete?
    
    # Clean up
    app_module.destroy
    web_app.destroy
  end
end

