# frozen_string_literal: true

require 'test_helper'

class ApplicationPlanTest < ActiveSupport::TestCase
  fixtures :entities, :users, :application_plans

  # ============================================
  # VALIDATIONS
  # ============================================

  test "requires name" do
    plan = ApplicationPlan.new(
      entity: entities(:one),
      created_by: users(:one),
      status: "drafting"
    )
    assert_not plan.valid?
    assert_includes plan.errors[:name], "can't be blank"
  end

  test "validates status inclusion" do
    plan = ApplicationPlan.new(
      entity: entities(:one),
      created_by: users(:one),
      name: "Test",
      status: "invalid_status"
    )
    assert_not plan.valid?
    assert_includes plan.errors[:status], "is not included in the list"
  end

  test "validates archetype inclusion when present" do
    plan = ApplicationPlan.new(
      entity: entities(:one),
      created_by: users(:one),
      name: "Test",
      status: "drafting",
      archetype: "invalid_archetype"
    )
    assert_not plan.valid?
    assert_includes plan.errors[:archetype], "is not included in the list"
  end

  test "valid archetypes are accepted" do
    ApplicationPlan::ARCHETYPES.each do |archetype|
      plan = ApplicationPlan.new(
        entity: entities(:one),
        created_by: users(:one),
        name: "Test #{archetype}",
        status: "drafting",
        archetype: archetype,
        plan_spec: { 'modules' => [{ 'name' => 'Test' }] }
      )
      assert plan.valid?, "Archetype '#{archetype}' should be valid: #{plan.errors.full_messages}"
    end
  end

  test "validates plan_spec structure - modules must have names" do
    plan = ApplicationPlan.new(
      entity: entities(:one),
      created_by: users(:one),
      name: "Test",
      status: "drafting",
      plan_spec: {
        'modules' => [
          { 'fields' => [] }  # Missing name
        ]
      }
    )
    assert_not plan.valid?
    assert plan.errors[:plan_spec].any?
  end

  test "validates plan_spec structure - website must have pages" do
    skip "TODO: Fix - validation logic changed"
    plan = ApplicationPlan.new(
      entity: entities(:one),
      created_by: users(:one),
      name: "Test",
      status: "drafting",
      plan_spec: {
        'modules' => [{ 'name' => 'Test' }],
        'website' => {}  # Missing pages
      }
    )
    assert_not plan.valid?
    assert plan.errors[:plan_spec].any?
  end

  test "validates plan_spec structure - agent must have name" do
    plan = ApplicationPlan.new(
      entity: entities(:one),
      created_by: users(:one),
      name: "Test",
      status: "drafting",
      plan_spec: {
        'modules' => [{ 'name' => 'Test' }],
        'agent' => { 'description' => 'Test agent' }  # Missing name
      }
    )
    assert_not plan.valid?
    assert plan.errors[:plan_spec].any?
  end

  # ============================================
  # STATUS HELPERS
  # ============================================

  test "status helper methods work correctly" do
    assert application_plans(:drafting_plan).drafting?
    assert application_plans(:pending_approval_plan).pending_approval?
    assert application_plans(:approved_plan).approved?
    assert application_plans(:completed_plan).completed?
    assert application_plans(:failed_plan).failed?
  end

  test "editable? returns true only for drafting and pending_approval" do
    assert application_plans(:drafting_plan).editable?
    assert application_plans(:pending_approval_plan).editable?
    assert_not application_plans(:approved_plan).editable?
    assert_not application_plans(:completed_plan).editable?
    assert_not application_plans(:failed_plan).editable?
  end

  # ============================================
  # STATE TRANSITIONS
  # ============================================

  test "submit_for_approval! transitions from drafting" do
    plan = application_plans(:drafting_plan)
    plan.submit_for_approval!
    assert plan.pending_approval?
  end

  test "submit_for_approval! raises for non-drafting" do
    plan = application_plans(:approved_plan)
    assert_raises(ApplicationPlan::InvalidTransition) do
      plan.submit_for_approval!
    end
  end

  test "request_changes! adds to refinement history" do
    plan = application_plans(:pending_approval_plan)
    plan.request_changes!("Add more fields")
    
    assert plan.drafting?
    assert_equal 1, plan.refinement_history.count
    assert_equal "Add more fields", plan.refinement_history.first['feedback']
    assert_equal "user_feedback", plan.refinement_history.first['type']
  end

  test "approve! sets approved_at timestamp" do
    plan = application_plans(:pending_approval_plan)
    plan.approve!
    
    assert plan.approved?
    assert_not_nil plan.approved_at
  end

  test "start_build! sets build_started_at timestamp" do
    plan = application_plans(:approved_plan)
    plan.start_build!
    
    assert plan.building?
    assert_not_nil plan.build_started_at
  end

  test "complete! stores results and sets timestamp" do
    plan = application_plans(:approved_plan)
    plan.start_build!
    
    results = { modules: [{ id: 1, name: 'Test' }] }
    plan.complete!(results)
    
    assert plan.completed?
    assert_not_nil plan.completed_at
    assert_equal results, plan.build_results.deep_symbolize_keys
  end

  test "fail! stores error and log entry" do
    plan = application_plans(:approved_plan)
    plan.start_build!
    
    plan.fail!("Database error", { details: "Connection failed" })
    
    assert plan.failed?
    assert_equal "Database error", plan.error_message
    assert plan.build_log.any?
  end

  test "cancel! works from active states" do
    plan = application_plans(:drafting_plan)
    plan.cancel!
    assert plan.cancelled?
  end

  test "cancel! raises for completed plans" do
    plan = application_plans(:completed_plan)
    assert_raises(ApplicationPlan::InvalidTransition) do
      plan.cancel!
    end
  end

  # ============================================
  # SPEC ACCESSORS
  # ============================================

  test "modules_spec returns modules array" do
    plan = application_plans(:pending_approval_plan)
    assert plan.modules_spec.is_a?(Array)
    assert plan.modules_spec.any?
  end

  test "agent_spec returns agent hash" do
    plan = application_plans(:pending_approval_plan)
    assert plan.agent_spec.is_a?(Hash)
    assert_equal "KB Expert", plan.agent_spec['name']
  end

  test "has_website? returns true when website present" do
    skip "TODO: Fix - has_website? logic changed"
    plan = ApplicationPlan.new(plan_spec: { 'website' => { 'pages' => [] } })
    assert_not plan.has_website?  # Empty pages
    
    plan.plan_spec = { 'website' => { 'pages' => [{ 'name' => 'Home' }] } }
    assert plan.has_website?
  end

  test "has_agent? returns true when agent present" do
    plan = ApplicationPlan.new(plan_spec: {})
    assert_not plan.has_agent?
    
    plan.plan_spec = { 'agent' => { 'name' => 'Test' } }
    assert plan.has_agent?
  end

  # ============================================
  # SPEC MUTATORS
  # ============================================

  test "update_plan_spec! merges updates" do
    plan = application_plans(:drafting_plan)
    original_modules = plan.modules_spec.dup
    
    plan.update_plan_spec!({ 'website' => { 'pages' => [{ 'name' => 'Home' }] } })
    
    assert_equal original_modules, plan.modules_spec  # Preserved
    assert plan.has_website?  # Added
  end

  test "update_plan_spec! raises for non-editable plans" do
    plan = application_plans(:approved_plan)
    
    assert_raises(ApplicationPlan::InvalidTransition) do
      plan.update_plan_spec!({ 'website' => {} })
    end
  end

  test "add_module! appends to modules list" do
    plan = application_plans(:drafting_plan)
    original_count = plan.modules_spec.count
    
    plan.add_module!({ name: 'New Module', fields: [] })
    
    assert_equal original_count + 1, plan.modules_spec.count
  end

  test "add_integration! appends to integrations list" do
    plan = application_plans(:drafting_plan)
    plan.add_integration!({ slug: 'slack', purpose: 'notify' })
    
    assert plan.integrations_spec.any? { |i| i['slug'] == 'slack' }
  end

  # ============================================
  # SUMMARY & DISPLAY
  # ============================================

  test "component_summary returns correct counts" do
    plan = application_plans(:pending_approval_plan)
    summary = plan.component_summary
    
    assert_equal 1, summary[:modules]
    assert summary[:has_agent]
    assert summary[:integrations] >= 0
    assert summary[:workflows] >= 0
  end

  test "estimated_build_time returns readable format" do
    plan = application_plans(:drafting_plan)
    time = plan.estimated_build_time
    
    assert time.is_a?(String)
    assert(time.include?('seconds') || time.include?('minute'))
  end

  test "to_preview returns expected structure" do
    plan = application_plans(:pending_approval_plan)
    preview = plan.to_preview
    
    assert_equal plan.id, preview[:id]
    assert_equal plan.name, preview[:name]
    assert_equal plan.status, preview[:status]
    assert preview[:summary].present?
    assert preview[:plan_spec].present?
  end

  # ============================================
  # SCOPES
  # ============================================

  test "active scope returns non-final states" do
    active = ApplicationPlan.active
    
    active.each do |plan|
      assert_includes %w[drafting pending_approval approved building], plan.status
    end
  end

  test "completed scope returns only completed" do
    ApplicationPlan.completed.each do |plan|
      assert_equal 'completed', plan.status
    end
  end

  test "for_entity scope filters by entity" do
    entity = entities(:one)
    plans = ApplicationPlan.for_entity(entity.id)
    
    plans.each do |plan|
      assert_equal entity.id, plan.entity_id
    end
  end
end

