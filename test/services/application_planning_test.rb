# frozen_string_literal: true

require 'test_helper'

class ApplicationPlanningTest < ActiveSupport::TestCase
  fixtures :entities, :users

  setup do
    @entity = entities(:one)
    @user = users(:one)
  end

  # ============================================
  # APPLICATION PLAN MODEL TESTS
  # ============================================

  test 'ApplicationPlan can be created with valid attributes' do
    plan = ApplicationPlan.new(
      entity: @entity,
      created_by: @user,
      name: 'Test Knowledge Base',
      description: 'A test knowledge base',
      archetype: 'knowledge_base',
      status: 'drafting',
      plan_spec: {
        'modules' => [
          { 'name' => 'Articles', 'fields' => [{ 'name' => 'title', 'field_type' => 'string' }] }
        ]
      }
    )
    
    assert plan.valid?, plan.errors.full_messages.join(', ')
  end

  test 'ApplicationPlan validates status inclusion' do
    plan = ApplicationPlan.new(
      entity: @entity,
      created_by: @user,
      name: 'Test Plan',
      status: 'invalid_status'
    )
    
    assert_not plan.valid?
    assert_includes plan.errors[:status], 'is not included in the list'
  end

  test 'ApplicationPlan status transitions work correctly' do
    plan = ApplicationPlan.create!(
      entity: @entity,
      created_by: @user,
      name: 'Test Plan',
      status: 'drafting',
      plan_spec: { 'modules' => [{ 'name' => 'Test' }] }
    )
    
    # drafting -> pending_approval
    plan.submit_for_approval!
    assert_equal 'pending_approval', plan.status
    
    # pending_approval -> approved
    plan.approve!
    assert_equal 'approved', plan.status
    assert_not_nil plan.approved_at
    
    # approved -> building
    plan.start_build!
    assert_equal 'building', plan.status
    assert_not_nil plan.build_started_at
    
    # building -> completed
    plan.complete!({ modules: [] })
    assert_equal 'completed', plan.status
    assert_not_nil plan.completed_at
  end

  test 'ApplicationPlan can request changes' do
    plan = ApplicationPlan.create!(
      entity: @entity,
      created_by: @user,
      name: 'Test Plan',
      status: 'drafting',
      plan_spec: { 'modules' => [{ 'name' => 'Test' }] }
    )
    
    plan.submit_for_approval!
    plan.request_changes!('Add more fields')
    
    assert_equal 'drafting', plan.status
    assert_equal 1, plan.refinement_history.length
    assert_equal 'Add more fields', plan.refinement_history.first['feedback']
  end

  # ============================================
  # APPLICATION PLANNER SERVICE TESTS
  # ============================================

  test 'ApplicationPlannerService creates plan with archetype detection' do
    service = ApplicationPlannerService.new(entity: @entity, user: @user)
    
    plan = service.create_plan(
      name: 'Social Media Manager',
      description: 'Track and schedule social posts'
    )
    
    assert_not_nil plan
    assert_equal 'Social Media Manager', plan.name
    assert_equal 'social_media', plan.archetype
    assert plan.drafting?, "Plan should start in drafting status"
    
    # Should have detected archetype and added suggestions
    assert plan.modules_spec.any?, "Should have modules in spec"
  end

  test 'ApplicationPlannerService creates plan for unknown archetype' do
    service = ApplicationPlannerService.new(entity: @entity, user: @user)
    
    plan = service.create_plan(
      name: 'Custom Widget Tracker',
      description: 'Track widgets'
    )
    
    assert_not_nil plan
    assert_equal 'custom', plan.archetype
  end

  test 'ApplicationPlannerService refines plan' do
    service = ApplicationPlannerService.new(entity: @entity, user: @user)
    
    plan = service.create_plan(name: 'CRM')
    plan.update!(status: 'drafting')
    
    original_integration_count = plan.integrations_spec.count
    
    plan = service.refine_plan(plan, {
      add_integration: { slug: 'slack', purpose: 'notifications' }
    })
    
    assert_equal original_integration_count + 1, plan.integrations_spec.count
  end

  # ============================================
  # APPLICATION BUILD SERVICE TESTS
  # ============================================

  test 'ApplicationBuildService validates plan before building' do
    plan = ApplicationPlan.create!(
      entity: @entity,
      created_by: @user,
      name: 'Test Plan',
      status: 'drafting',  # Not approved!
      plan_spec: { 'modules' => [{ 'name' => 'Test' }] }
    )
    
    service = ApplicationBuildService.new(plan)
    
    # Should raise an error since plan is not approved
    error = assert_raises(ApplicationBuildService::BuildError) do
      service.execute!
    end
    
    assert_includes error.message, 'must be approved'
  end

  # ============================================
  # WEBSITE BUILDER SERVICE TESTS
  # ============================================

  test 'WebsiteBuilderService creates website with pages' do
    service = WebsiteBuilderService.new(entity: @entity, user: @user)
    
    website = service.create_website({
      name: 'Test Site',
      theme: 'modern',
      pages: [
        { name: 'Home', template: 'homepage', is_homepage: true },
        { name: 'About', template: 'content' }
      ]
    })
    
    assert_not_nil website
    assert_equal 'Test Site', website.name
    assert_equal 2, website.website_pages.count
    assert website.homepage.is_homepage?
  end

  test 'WebsiteBuilderService creates web app with modules' do
    service = WebsiteBuilderService.new(entity: @entity, user: @user)
    
    # First create a mock module (if AppModule exists)
    skip 'Requires AppModule fixture' unless defined?(AppModule)
    
    app_module = AppModule.create!(
      entity: @entity,
      name: 'Articles',
      slug: 'articles',
      status: 'active'
    )
    
    web_app = service.create_web_app(
      { name: 'KB App', requires_auth: true },
      modules: [app_module]
    )
    
    assert_not_nil web_app
    assert_equal 1, web_app.web_app_modules.count
    assert web_app.requires_auth
  end

  # ============================================
  # TOOLS TESTS
  # ============================================

  test 'PlanApplicationTool creates plan from name' do
    skip 'Requires full Rails environment'
    
    tool = Tools::PlanApplicationTool.new
    tool.instance_variable_set(:@entity, @entity)
    tool.instance_variable_set(:@user, @user)
    tool.instance_variable_set(:@context, {})
    
    result = tool.execute({ name: 'Knowledge Base' })
    
    assert result[:success]
    assert_not_nil result[:plan_id]
  end

  test 'GetPlatformCapabilitiesTool returns archetypes' do
    skip 'Requires full Rails environment'
    
    tool = Tools::GetPlatformCapabilitiesTool.new
    result = tool.execute({ category: 'archetypes' })
    
    assert result[:success]
    assert result[:archetypes].any?
  end

end

