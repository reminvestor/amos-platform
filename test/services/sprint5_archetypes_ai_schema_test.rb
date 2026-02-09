# frozen_string_literal: true

require 'test_helper'

class Sprint5ArchetypesAiSchemaTest < ActiveSupport::TestCase
  fixtures :entities, :users

  setup do
    @entity = entities(:one)
    @user = users(:one)
  end

  # ══════════════════════════════════════════════════════════════
  # NEW ARCHETYPES EXIST IN ARCHETYPE_INTELLIGENCE
  # ══════════════════════════════════════════════════════════════

  test 'education archetype exists with full definition' do
    archetype = Modules::ArchetypeIntelligence::ARCHETYPES[:education]
    assert_not_nil archetype
    assert_equal 'Education / LMS', archetype[:name]
    assert archetype[:triggers].include?('course')
    assert archetype[:triggers].include?('student')
    assert archetype[:core_fields].present?
    assert archetype[:sub_models].present?
    assert archetype[:suggested_workflows].present?
    assert archetype[:suggested_scheduled_tasks].present?
    assert archetype[:canvas_views].present?
  end

  test 'fleet_management archetype exists with full definition' do
    archetype = Modules::ArchetypeIntelligence::ARCHETYPES[:fleet_management]
    assert_not_nil archetype
    assert_equal 'Fleet Management', archetype[:name]
    assert archetype[:triggers].include?('vehicle')
    assert archetype[:triggers].include?('fleet')
    assert archetype[:core_fields].present?
    assert archetype[:sub_models].present?
    assert archetype[:suggested_workflows].present?
  end

  test 'restaurant archetype exists with full definition' do
    archetype = Modules::ArchetypeIntelligence::ARCHETYPES[:restaurant]
    assert_not_nil archetype
    assert_equal 'Restaurant Management', archetype[:name]
    assert archetype[:triggers].include?('restaurant')
    assert archetype[:triggers].include?('menu')
    assert archetype[:triggers].include?('order')
    assert archetype[:core_fields].present?
    assert archetype[:sub_models].present?
  end

  # ══════════════════════════════════════════════════════════════
  # NEW ARCHETYPES — SUB MODELS
  # ══════════════════════════════════════════════════════════════

  test 'education archetype has correct sub_models' do
    subs = Modules::ArchetypeIntelligence::ARCHETYPES[:education][:sub_models]
    sub_names = subs.map { |s| s[:name] }
    assert_includes sub_names, 'Student'
    assert_includes sub_names, 'Enrollment'
    assert_includes sub_names, 'Assignment'
  end

  test 'fleet_management archetype has correct sub_models' do
    subs = Modules::ArchetypeIntelligence::ARCHETYPES[:fleet_management][:sub_models]
    sub_names = subs.map { |s| s[:name] }
    assert_includes sub_names, 'Driver'
    assert_includes sub_names, 'Trip'
    assert_includes sub_names, 'Maintenance'
    assert_includes sub_names, 'FuelLog'
  end

  test 'restaurant archetype has correct sub_models' do
    subs = Modules::ArchetypeIntelligence::ARCHETYPES[:restaurant][:sub_models]
    sub_names = subs.map { |s| s[:name] }
    assert_includes sub_names, 'Order'
    assert_includes sub_names, 'Table'
    assert_includes sub_names, 'Reservation'
    assert_includes sub_names, 'Ingredient'
  end

  test 'all new archetype sub_models have required fields' do
    %i[education fleet_management restaurant].each do |key|
      archetype = Modules::ArchetypeIntelligence::ARCHETYPES[key]
      archetype[:sub_models].each_with_index do |sub, idx|
        assert sub[:name].present?, "#{key} sub_model[#{idx}] must have name"
        assert sub[:slug].present?, "#{key} sub_model[#{idx}] must have slug"
        assert sub[:fields].is_a?(Array), "#{key} sub_model[#{idx}] fields must be Array"
        assert sub[:fields].any?, "#{key} sub_model[#{idx}] must have fields"
        assert sub[:relationship].present?, "#{key} sub_model[#{idx}] must have relationship"
      end
    end
  end

  # ══════════════════════════════════════════════════════════════
  # NEW ARCHETYPES — CORE FIELDS
  # ══════════════════════════════════════════════════════════════

  test 'education archetype has appropriate core fields' do
    fields = Modules::ArchetypeIntelligence::ARCHETYPES[:education][:core_fields]
    field_names = fields.map { |f| f[:name] }
    assert_includes field_names, 'name'
    assert_includes field_names, 'status'
    assert_includes field_names, 'instructor'
    assert_includes field_names, 'start_date'
  end

  test 'fleet_management archetype has appropriate core fields' do
    fields = Modules::ArchetypeIntelligence::ARCHETYPES[:fleet_management][:core_fields]
    field_names = fields.map { |f| f[:name] }
    assert_includes field_names, 'name'
    assert_includes field_names, 'license_plate'
    assert_includes field_names, 'status'
    assert_includes field_names, 'current_mileage'
  end

  test 'restaurant archetype has appropriate core fields' do
    fields = Modules::ArchetypeIntelligence::ARCHETYPES[:restaurant][:core_fields]
    field_names = fields.map { |f| f[:name] }
    assert_includes field_names, 'name'
    assert_includes field_names, 'price'
    assert_includes field_names, 'category'
    assert_includes field_names, 'status'
  end

  # ══════════════════════════════════════════════════════════════
  # ARCHETYPE DETECTION
  # ══════════════════════════════════════════════════════════════

  test 'education archetype is detectable' do
    result = Modules::ArchetypeIntelligence.detect(name: 'Online Course Platform', description: 'Student enrollment and grade tracking')
    assert_equal :education, result[:archetype]
  end

  test 'fleet_management archetype is detectable' do
    result = Modules::ArchetypeIntelligence.detect(name: 'Vehicle Fleet Tracker', description: 'Track company vehicles and drivers')
    assert_equal :fleet_management, result[:archetype]
  end

  test 'restaurant archetype is detectable' do
    result = Modules::ArchetypeIntelligence.detect(name: 'Restaurant Order System', description: 'Menu and table management')
    assert_equal :restaurant, result[:archetype]
  end

  # ══════════════════════════════════════════════════════════════
  # APPLICATION PLAN — NEW ARCHETYPES IN CONSTANT
  # ══════════════════════════════════════════════════════════════

  test 'ApplicationPlan ARCHETYPES includes new types' do
    assert_includes ApplicationPlan::ARCHETYPES, 'education'
    assert_includes ApplicationPlan::ARCHETYPES, 'fleet_management'
    assert_includes ApplicationPlan::ARCHETYPES, 'restaurant'
  end

  test 'ApplicationPlan validates new archetypes' do
    plan = ApplicationPlan.new(
      entity: @entity,
      created_by: @user,
      name: 'Test',
      archetype: 'education',
      status: 'drafting',
      plan_spec: { 'modules' => [] }
    )
    assert plan.valid?, "Education archetype should be valid: #{plan.errors.full_messages}"
  end

  # ══════════════════════════════════════════════════════════════
  # APPLICATION PLANNER SERVICE — DESCRIPTIONS
  # ══════════════════════════════════════════════════════════════

  test 'generate_description returns text for education' do
    service = ApplicationPlannerService.new(entity: @entity, user: @user)
    desc = service.send(:generate_description, 'My LMS', :education)
    assert_includes desc, 'Learning management'
  end

  test 'generate_description returns text for fleet_management' do
    service = ApplicationPlannerService.new(entity: @entity, user: @user)
    desc = service.send(:generate_description, 'Fleet', :fleet_management)
    assert_includes desc, 'Fleet management'
  end

  test 'generate_description returns text for restaurant' do
    service = ApplicationPlannerService.new(entity: @entity, user: @user)
    desc = service.send(:generate_description, 'My Restaurant', :restaurant)
    assert_includes desc, 'Restaurant management'
  end

  # ══════════════════════════════════════════════════════════════
  # APPLICATION PLANNER SERVICE — AI SCHEMA DESIGN PARSING
  # ══════════════════════════════════════════════════════════════

  test 'parse_schema_design_response parses JSON code block' do
    service = ApplicationPlannerService.new(entity: @entity, user: @user)
    raw = <<~TEXT
      Here is the schema:
      ```json
      {
        "modules": [
          { "name": "Widget", "slug": "widget", "is_primary": true, "fields": [{ "name": "title", "field_type": "string" }] }
        ],
        "workflows": []
      }
      ```
    TEXT

    result = service.send(:parse_schema_design_response, raw)
    assert_not_nil result
    assert_equal 1, result['modules'].length
    assert_equal 'Widget', result['modules'].first['name']
  end

  test 'parse_schema_design_response handles plain JSON' do
    service = ApplicationPlannerService.new(entity: @entity, user: @user)
    raw = '{"modules": [{"name": "Test", "slug": "test"}]}'
    result = service.send(:parse_schema_design_response, raw)
    assert_not_nil result
    assert_equal 'Test', result['modules'].first['name']
  end

  test 'parse_schema_design_response returns nil for invalid JSON' do
    service = ApplicationPlannerService.new(entity: @entity, user: @user)
    result = service.send(:parse_schema_design_response, 'not json at all')
    assert_nil result
  end

  test 'build_schema_design_prompt includes name and description' do
    service = ApplicationPlannerService.new(entity: @entity, user: @user)
    prompt = service.send(:build_schema_design_prompt, 'Pet Grooming', 'Manage pet grooming appointments', {})
    assert_includes prompt, 'Pet Grooming'
    assert_includes prompt, 'pet grooming appointments'
  end

  test 'schema_design_system_prompt contains instructions for AI' do
    service = ApplicationPlannerService.new(entity: @entity, user: @user)
    prompt = service.send(:schema_design_system_prompt)
    assert_includes prompt, 'primary module'
    assert_includes prompt, 'sub-modules'
    assert_includes prompt, 'belongs_to'
    assert_includes prompt, 'JSON'
  end

  # ══════════════════════════════════════════════════════════════
  # APPLICATION PLANNER SERVICE — apply_ai_designed_schema
  # ══════════════════════════════════════════════════════════════

  test 'apply_ai_designed_schema creates modules from AI response' do
    service = ApplicationPlannerService.new(entity: @entity, user: @user)
    spec = { 'modules' => [], 'integrations' => [], 'workflows' => [] }
    ai_spec = {
      'modules' => [
        { 'name' => 'Appointment', 'slug' => 'appointment', 'is_primary' => true,
          'fields' => [{ 'name' => 'client', 'field_type' => 'string' }], 'views' => %w[list form] },
        { 'name' => 'Service', 'slug' => 'service',
          'fields' => [{ 'name' => 'name', 'field_type' => 'string' }], 'views' => %w[list form] }
      ],
      'workflows' => [
        { 'name' => 'Appointment Reminder', 'trigger' => 'schedule', 'actions' => ['send_reminder'] }
      ],
      'suggested_integrations' => [
        { 'name' => 'google_calendar', 'description' => 'Sync appointments' }
      ]
    }

    result = service.send(:apply_ai_designed_schema, spec, 'Pet Grooming', ai_spec)
    assert_equal 2, result['modules'].length
    assert result['agent'].present?
    assert_equal 1, result['workflows'].length
    assert_equal 1, result['integrations'].length
  end

  test 'apply_ai_designed_schema falls back to minimal when no modules' do
    service = ApplicationPlannerService.new(entity: @entity, user: @user)
    spec = { 'modules' => [], 'integrations' => [], 'workflows' => [] }
    ai_spec = { 'modules' => [] }

    result = service.send(:apply_ai_designed_schema, spec, 'Empty App', ai_spec)
    assert result['modules'].length >= 1  # At least the minimal module
  end

  test 'build_custom_spec falls back to minimal when AI unavailable' do
    service = ApplicationPlannerService.new(entity: @entity, user: @user)
    spec = { 'modules' => [], 'integrations' => [], 'workflows' => [] }

    # AI will fail since we're not mocking Bedrock — should fall back to minimal
    result = service.send(:build_custom_spec, spec, 'Mystery App', 'Something custom', {})
    assert result['modules'].length >= 1
    assert result['modules'].first['name'] == 'Mystery App'
    assert result['agent'].present?
  end

  # ══════════════════════════════════════════════════════════════
  # ARCHETYPE INTELLIGENCE — HELPER METHODS
  # ══════════════════════════════════════════════════════════════

  test 'sub_models_for returns sub_models for new archetypes' do
    %i[education fleet_management restaurant].each do |key|
      subs = Modules::ArchetypeIntelligence.sub_models_for(key)
      assert subs.present?, "#{key} should have sub_models"
      assert subs.is_a?(Array)
    end
  end

  test 'canvas_views_for returns views for new archetypes' do
    %i[education fleet_management restaurant].each do |key|
      views = Modules::ArchetypeIntelligence.canvas_views_for(key)
      assert views.present?, "#{key} should have canvas_views"
      assert views.is_a?(Array)
    end
  end

  # ══════════════════════════════════════════════════════════════
  # NEW ARCHETYPES — INTEGRATION SUGGESTIONS
  # ══════════════════════════════════════════════════════════════

  test 'education archetype suggests zoom integration' do
    integrations = Modules::ArchetypeIntelligence::ARCHETYPES[:education][:suggested_integrations]
    slugs = integrations.map { |i| i[:name] }
    assert_includes slugs, 'zoom'
  end

  test 'fleet_management archetype suggests google_maps' do
    integrations = Modules::ArchetypeIntelligence::ARCHETYPES[:fleet_management][:suggested_integrations]
    slugs = integrations.map { |i| i[:name] }
    assert_includes slugs, 'google_maps'
  end

  test 'restaurant archetype suggests square' do
    integrations = Modules::ArchetypeIntelligence::ARCHETYPES[:restaurant][:suggested_integrations]
    slugs = integrations.map { |i| i[:name] }
    assert_includes slugs, 'square'
  end

  # ══════════════════════════════════════════════════════════════
  # NEW ARCHETYPES — WORKFLOWS
  # ══════════════════════════════════════════════════════════════

  test 'education archetype has relevant workflows' do
    workflows = Modules::ArchetypeIntelligence::ARCHETYPES[:education][:suggested_workflows]
    names = workflows.map { |w| w[:name] }
    assert names.any? { |n| n.include?('Enroll') || n.include?('Grade') || n.include?('Completion') }
  end

  test 'fleet_management archetype has relevant workflows' do
    workflows = Modules::ArchetypeIntelligence::ARCHETYPES[:fleet_management][:suggested_workflows]
    names = workflows.map { |w| w[:name] }
    assert names.any? { |n| n.include?('Maintenance') || n.include?('Trip') || n.include?('Fuel') }
  end

  test 'restaurant archetype has relevant workflows' do
    workflows = Modules::ArchetypeIntelligence::ARCHETYPES[:restaurant][:suggested_workflows]
    names = workflows.map { |w| w[:name] }
    assert names.any? { |n| n.include?('Order') || n.include?('Inventory') }
  end

  # ══════════════════════════════════════════════════════════════
  # NEW ARCHETYPES — SCHEDULED TASKS
  # ══════════════════════════════════════════════════════════════

  test 'education archetype has scheduled tasks' do
    tasks = Modules::ArchetypeIntelligence::ARCHETYPES[:education][:suggested_scheduled_tasks]
    assert tasks.present?
    assert tasks.any? { |t| t[:name].include?('Assignment') || t[:name].include?('Progress') }
  end

  test 'fleet_management archetype has scheduled tasks' do
    tasks = Modules::ArchetypeIntelligence::ARCHETYPES[:fleet_management][:suggested_scheduled_tasks]
    assert tasks.present?
    assert tasks.any? { |t| t[:name].include?('Inspection') || t[:name].include?('Fleet') }
  end

  test 'restaurant archetype has scheduled tasks' do
    tasks = Modules::ArchetypeIntelligence::ARCHETYPES[:restaurant][:suggested_scheduled_tasks]
    assert tasks.present?
    assert tasks.any? { |t| t[:name].include?('Inventory') || t[:name].include?('Reservation') || t[:name].include?('Sales') }
  end

  # ══════════════════════════════════════════════════════════════
  # RESTAURANT ARCHETYPE — KANBAN SUPPORT
  # ══════════════════════════════════════════════════════════════

  test 'restaurant order sub_model has kanban view' do
    subs = Modules::ArchetypeIntelligence::ARCHETYPES[:restaurant][:sub_models]
    order = subs.find { |s| s[:name] == 'Order' }
    assert_not_nil order
    assert_includes order[:canvas_views], 'kanban'
  end

  test 'restaurant reservation sub_model has calendar view' do
    subs = Modules::ArchetypeIntelligence::ARCHETYPES[:restaurant][:sub_models]
    reservation = subs.find { |s| s[:name] == 'Reservation' }
    assert_not_nil reservation
    assert_includes reservation[:canvas_views], 'calendar'
  end

  # ══════════════════════════════════════════════════════════════
  # COMPLETE ARCHETYPE VALIDATION
  # ══════════════════════════════════════════════════════════════

  test 'all archetypes have valid structure' do
    # CRM uses native capabilities instead of core_fields/sub_models
    native_archetypes = %i[crm]
    required_keys = %i[triggers name description canvas_views]
    
    Modules::ArchetypeIntelligence::ARCHETYPES.each do |key, archetype|
      required_keys.each do |rk|
        assert archetype[rk].present?, "Archetype #{key} missing #{rk}"
      end
      
      unless native_archetypes.include?(key)
        assert archetype[:core_fields].present?, "Archetype #{key} missing core_fields"
        assert archetype[:sub_models].present?, "Archetype #{key} missing sub_models"
      end
    end
  end

  test 'all archetype sub_models have valid relationship types' do
    valid_types = %w[belongs_to standalone has_many]
    
    Modules::ArchetypeIntelligence::ARCHETYPES.each do |key, archetype|
      next unless archetype[:sub_models]
      archetype[:sub_models].each do |sub|
        rel_type = sub[:relationship][:type].to_s
        assert_includes valid_types, rel_type,
          "#{key}/#{sub[:name]} has invalid relationship type: #{rel_type}"
      end
    end
  end
end
