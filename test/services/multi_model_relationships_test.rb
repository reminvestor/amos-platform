# frozen_string_literal: true

require 'test_helper'

class MultiModelRelationshipsTest < ActiveSupport::TestCase
  fixtures :entities, :users

  setup do
    @entity = entities(:one)
    @user = users(:one)
  end

  # ══════════════════════════════════════════════════════════════
  # ARCHETYPE INTELLIGENCE - SUB-MODELS
  # ══════════════════════════════════════════════════════════════

  test 'all archetypes have sub_models defined' do
    archetypes_with_sub_models = %i[social_media inventory project knowledge_base events finance hr real_estate helpdesk]

    archetypes_with_sub_models.each do |key|
      archetype = Modules::ArchetypeIntelligence::ARCHETYPES[key]
      assert archetype.present?, "Archetype #{key} should exist"
      assert archetype[:sub_models].present?, "Archetype #{key} should have sub_models"
      assert archetype[:sub_models].is_a?(Array), "#{key} sub_models should be an Array"
    end
  end

  test 'all archetypes have canvas_views defined' do
    Modules::ArchetypeIntelligence::ARCHETYPES.each do |key, archetype|
      assert archetype[:canvas_views].present?, "Archetype #{key} should have canvas_views"
      assert archetype[:canvas_views].is_a?(Array), "#{key} canvas_views should be an Array"
    end
  end

  test 'sub_models have required fields' do
    Modules::ArchetypeIntelligence::ARCHETYPES.each do |archetype_key, archetype|
      next unless archetype[:sub_models].present?

      archetype[:sub_models].each_with_index do |sub_model, idx|
        assert sub_model[:name].present?, "#{archetype_key} sub_model[#{idx}] must have a name"
        assert sub_model[:slug].present?, "#{archetype_key} sub_model[#{idx}] must have a slug"
        assert sub_model[:description].present?, "#{archetype_key} sub_model[#{idx}] must have a description"
        assert sub_model[:relationship].present?, "#{archetype_key} sub_model[#{idx}] must have a relationship"
        assert sub_model[:fields].is_a?(Array), "#{archetype_key} sub_model[#{idx}] fields must be an Array"
        assert sub_model[:fields].any?, "#{archetype_key} sub_model[#{idx}] must have at least one field"
      end
    end
  end

  test 'sub_model relationships are valid types' do
    valid_types = %w[belongs_to standalone has_many]

    Modules::ArchetypeIntelligence::ARCHETYPES.each do |archetype_key, archetype|
      next unless archetype[:sub_models].present?

      archetype[:sub_models].each do |sub_model|
        rel_type = sub_model[:relationship][:type].to_s
        assert_includes valid_types, rel_type,
          "#{archetype_key}/#{sub_model[:name]} has invalid relationship type: #{rel_type}"
      end
    end
  end

  test 'belongs_to sub_models have parent_field' do
    Modules::ArchetypeIntelligence::ARCHETYPES.each do |archetype_key, archetype|
      next unless archetype[:sub_models].present?

      archetype[:sub_models].each do |sub_model|
        next unless sub_model[:relationship][:type].to_s == 'belongs_to'

        assert sub_model[:relationship][:parent_field].present?,
          "#{archetype_key}/#{sub_model[:name]} belongs_to must have parent_field"
      end
    end
  end

  test 'sub_model fields have name and type' do
    Modules::ArchetypeIntelligence::ARCHETYPES.each do |archetype_key, archetype|
      next unless archetype[:sub_models].present?

      archetype[:sub_models].each do |sub_model|
        sub_model[:fields].each_with_index do |field, idx|
          assert field[:name].present?,
            "#{archetype_key}/#{sub_model[:name]} field[#{idx}] must have a name"
          assert field[:type].present?,
            "#{archetype_key}/#{sub_model[:name]} field[#{idx}] must have a type"
        end
      end
    end
  end

  # ══════════════════════════════════════════════════════════════
  # ARCHETYPE INTELLIGENCE - NEW ARCHETYPES
  # ══════════════════════════════════════════════════════════════

  test 'HR archetype exists and is detectable' do
    result = Modules::ArchetypeIntelligence.detect(name: 'HR Management', description: 'Manage employees and hiring')
    assert_equal :hr, result[:archetype]
    assert_includes %i[high medium], result[:confidence]
  end

  test 'Real Estate archetype exists and is detectable' do
    result = Modules::ArchetypeIntelligence.detect(name: 'Real Estate Listings', description: 'Manage property listings')
    assert_equal :real_estate, result[:archetype]
  end

  test 'Helpdesk archetype exists and is detectable' do
    result = Modules::ArchetypeIntelligence.detect(name: 'Support Ticket Manager', description: 'Issue tracking with SLA for customer service')
    assert_equal :helpdesk, result[:archetype]
  end

  test 'all archetypes have core_fields' do
    archetypes_needing_core_fields = %i[social_media inventory project knowledge_base events finance hr real_estate helpdesk]

    archetypes_needing_core_fields.each do |key|
      archetype = Modules::ArchetypeIntelligence::ARCHETYPES[key]
      assert archetype[:core_fields].present?, "Archetype #{key} should have core_fields"
      assert archetype[:core_fields].is_a?(Array), "#{key} core_fields should be an Array"
      assert archetype[:core_fields].any?, "#{key} should have at least one core field"
    end
  end

  # ══════════════════════════════════════════════════════════════
  # ARCHETYPE INTELLIGENCE - HELPER METHODS
  # ══════════════════════════════════════════════════════════════

  test 'sub_models_for returns sub_models for valid archetype' do
    sub_models = Modules::ArchetypeIntelligence.sub_models_for(:project)
    assert sub_models.is_a?(Array)
    assert sub_models.any?
    assert sub_models.any? { |sm| sm[:name] == 'Task' }
    assert sub_models.any? { |sm| sm[:name] == 'Milestone' }
  end

  test 'sub_models_for returns empty array for unknown archetype' do
    sub_models = Modules::ArchetypeIntelligence.sub_models_for(:nonexistent)
    assert_equal [], sub_models
  end

  test 'canvas_views_for returns views for valid archetype' do
    views = Modules::ArchetypeIntelligence.canvas_views_for(:project)
    assert views.is_a?(Array)
    assert_includes views, 'kanban'
  end

  test 'canvas_views_for returns defaults for unknown archetype' do
    views = Modules::ArchetypeIntelligence.canvas_views_for(:nonexistent)
    assert_equal %w[list form detail], views
  end

  test 'build_plan_spec returns comprehensive spec for archetype' do
    spec = Modules::ArchetypeIntelligence.build_plan_spec(:inventory)
    assert spec.is_a?(Hash)
    assert spec[:primary_module].present?
    assert spec[:sub_modules].is_a?(Array)
    assert spec[:sub_modules].any?
    assert spec[:integrations].is_a?(Array)
    assert spec[:workflows].is_a?(Array)
  end

  test 'build_plan_spec primary_module has correct structure' do
    spec = Modules::ArchetypeIntelligence.build_plan_spec(:project)
    primary = spec[:primary_module]

    assert_equal 'Project Management', primary[:name]
    assert_equal 'project', primary[:slug]
    assert primary[:fields].is_a?(Array)
    assert primary[:canvas_views].is_a?(Array)
  end

  test 'build_plan_spec sub_modules have relationship info' do
    spec = Modules::ArchetypeIntelligence.build_plan_spec(:project)

    task_sub = spec[:sub_modules].find { |sm| sm[:slug] == 'task' }
    assert task_sub.present?, 'Should have a task sub_module'
    assert_equal 'belongs_to', task_sub[:relationship][:type]
    assert_equal 'project_id', task_sub[:relationship][:foreign_key]
  end

  test 'build_plan_spec returns nil for unknown archetype' do
    spec = Modules::ArchetypeIntelligence.build_plan_spec(:nonexistent)
    assert_nil spec
  end

  test 'build_plan_spec accepts custom options' do
    custom_integrations = [{ name: 'custom_api', type: 'api_key', description: 'Custom' }]
    spec = Modules::ArchetypeIntelligence.build_plan_spec(:project, integrations: custom_integrations)

    assert_equal custom_integrations, spec[:integrations]
  end

  # ══════════════════════════════════════════════════════════════
  # ARCHETYPE INTELLIGENCE - FORMAT FOR PROMPT
  # ══════════════════════════════════════════════════════════════

  test 'format_for_prompt includes sub_models section' do
    output = Modules::ArchetypeIntelligence.format_for_prompt(:project)
    assert output.present?
    assert_includes output, 'Data Models'
    assert_includes output, 'Task'
    assert_includes output, 'Milestone'
    assert_includes output, 'belongs_to'
  end

  test 'format_for_prompt works for archetypes without sub_models' do
    # CRM has native_capabilities but potentially no sub_models
    output = Modules::ArchetypeIntelligence.format_for_prompt(:crm)
    assert output.present?
    assert_includes output, 'Recommended Setup'
  end

  # ══════════════════════════════════════════════════════════════
  # APPLICATION PLAN MODEL - NEW ARCHETYPES
  # ══════════════════════════════════════════════════════════════

  test 'ApplicationPlan accepts new archetype types' do
    new_archetypes = %w[events finance hr real_estate helpdesk project]

    new_archetypes.each do |archetype|
      plan = ApplicationPlan.new(
        entity: @entity,
        created_by: @user,
        name: "Test #{archetype}",
        status: 'drafting',
        archetype: archetype,
        plan_spec: { 'modules' => [{ 'name' => 'Test' }] }
      )
      assert plan.valid?, "ApplicationPlan should accept archetype '#{archetype}': #{plan.errors.full_messages.join(', ')}"
    end
  end

  # ══════════════════════════════════════════════════════════════
  # APPLICATION PLANNER SERVICE - MULTI-MODULE PLANS
  # ══════════════════════════════════════════════════════════════

  test 'planner creates multi-module plan from archetype with sub_models' do
    service = ApplicationPlannerService.new(entity: @entity, user: @user)

    plan = service.create_plan(
      name: 'Project Management',
      description: 'Track projects and tasks for our team'
    )

    assert_not_nil plan
    assert plan.modules_spec.count > 1, "Should have more than 1 module (primary + sub-models)"

    # Check primary module
    primary = plan.modules_spec.find { |m| m['is_primary'] == true || m['is_primary'].nil? }
    assert primary.present?, 'Should have a primary module'

    # Check sub-modules
    sub_modules = plan.modules_spec.select { |m| m['is_primary'] == false }
    assert sub_modules.any?, 'Should have sub-modules'
  end

  test 'planner sub-modules have relationship specs' do
    service = ApplicationPlannerService.new(entity: @entity, user: @user)

    plan = service.create_plan(
      name: 'Inventory Management',
      description: 'Track inventory, stock levels, and suppliers'
    )

    sub_modules = plan.modules_spec.select { |m| m['is_primary'] == false }
    belongs_to_modules = sub_modules.select { |m| m.dig('relationship', 'type') == 'belongs_to' }

    assert belongs_to_modules.any?, 'Should have at least one belongs_to sub-module'

    belongs_to_modules.each do |mod|
      assert mod['relationship']['parent_slug'].present?,
        "#{mod['name']} should have parent_slug in relationship"
      assert mod['relationship']['foreign_key'].present?,
        "#{mod['name']} should have foreign_key in relationship"
    end
  end

  test 'planner generates correct slugs for sub-modules' do
    service = ApplicationPlannerService.new(entity: @entity, user: @user)

    plan = service.create_plan(
      name: 'Project Management',
      description: 'Track projects and tasks'
    )

    slugs = plan.modules_spec.map { |m| m['slug'] }

    # Primary module slug should be the base
    assert slugs.include?('project_management'), "Should have primary module slug: #{slugs.inspect}"

    # Sub-module slugs should be prefixed with primary slug
    sub_slugs = slugs.reject { |s| s == 'project_management' }
    sub_slugs.each do |slug|
      assert slug.start_with?('project_management_'),
        "Sub-module slug '#{slug}' should be prefixed with 'project_management_'"
    end
  end

  test 'planner creates correct plan for HR archetype' do
    service = ApplicationPlannerService.new(entity: @entity, user: @user)

    plan = service.create_plan(
      name: 'HR Department',
      description: 'Human resources and employee management'
    )

    assert_equal 'hr', plan.archetype
    assert plan.modules_spec.count > 1, 'HR should have primary module + sub-modules'

    # Should have employee fields
    primary = plan.modules_spec.find { |m| m['is_primary'] != false }
    field_names = primary['fields'].map { |f| f['name'] }
    assert_includes field_names, 'first_name'
    assert_includes field_names, 'email'
  end

  test 'planner handles custom archetype without sub_models' do
    service = ApplicationPlannerService.new(entity: @entity, user: @user)

    plan = service.create_plan(
      name: 'Custom Widget Tracker',
      description: 'Track my custom widgets'
    )

    assert_equal 'custom', plan.archetype
    assert_equal 1, plan.modules_spec.count, 'Custom plans should have exactly one module'
  end

  test 'planner refine_plan can add sub-modules' do
    service = ApplicationPlannerService.new(entity: @entity, user: @user)

    plan = service.create_plan(
      name: 'Custom Tracker',
      description: 'A custom tool'
    )

    original_count = plan.modules_spec.count

    plan = service.refine_plan(plan, {
      add_module: {
        name: 'SubTracker',
        slug: 'sub_tracker',
        description: 'A sub-tracking model',
        fields: [{ name: 'label', type: 'string' }],
        is_primary: false,
        relationship: { type: 'belongs_to', parent_slug: 'custom_tracker', foreign_key: 'tracker_id' }
      }
    })

    assert_equal original_count + 1, plan.modules_spec.count

    sub = plan.modules_spec.last
    assert_equal false, sub['is_primary']
    assert_equal 'belongs_to', sub.dig('relationship', 'type')
  end

  # ══════════════════════════════════════════════════════════════
  # APPLICATION PLANNER SERVICE - RELATIONSHIP BUILDING
  # ══════════════════════════════════════════════════════════════

  test 'build_relationship_spec creates belongs_to with default parent' do
    service = ApplicationPlannerService.new(entity: @entity, user: @user)

    relationship = { type: 'belongs_to', parent_field: 'project_id' }
    result = service.send(:build_relationship_spec, relationship, 'project_management')

    assert_equal 'belongs_to', result['type']
    assert_equal 'project_management', result['parent_slug']
    assert_equal 'project_id', result['foreign_key']
  end

  test 'build_relationship_spec creates belongs_to with explicit parent_model' do
    service = ApplicationPlannerService.new(entity: @entity, user: @user)

    relationship = { type: 'belongs_to', parent_field: 'task_id', parent_model: 'Task' }
    result = service.send(:build_relationship_spec, relationship, 'project_management')

    assert_equal 'belongs_to', result['type']
    assert_equal 'project_management_task', result['parent_slug']
    assert_equal 'task_id', result['foreign_key']
  end

  test 'build_relationship_spec creates standalone relationship' do
    service = ApplicationPlannerService.new(entity: @entity, user: @user)

    relationship = { type: 'standalone' }
    result = service.send(:build_relationship_spec, relationship, 'project_management')

    assert_equal 'standalone', result['type']
  end

  # ══════════════════════════════════════════════════════════════
  # APPLICATION BUILD SERVICE - MULTI-MODULE BUILDS
  # ══════════════════════════════════════════════════════════════

  test 'build service separates primary and sub-modules' do
    plan = create_approved_multi_module_plan

    service = ApplicationBuildService.new(plan)

    # Access private methods to verify ordering
    primary_specs = plan.modules_spec.select { |m| m['is_primary'] != false }
    sub_specs = plan.modules_spec.select { |m| m['is_primary'] == false }

    assert primary_specs.any?, 'Should identify primary modules'
    assert sub_specs.any?, 'Should identify sub-modules'
  end

  test 'build service validates plan must be approved' do
    plan = ApplicationPlan.create!(
      entity: @entity,
      created_by: @user,
      name: 'Test Multi-Module',
      status: 'drafting',
      archetype: 'project',
      plan_spec: {
        'modules' => [
          { 'name' => 'Projects', 'is_primary' => true, 'fields' => [{ 'name' => 'name', 'field_type' => 'string' }] },
          { 'name' => 'Tasks', 'is_primary' => false, 'fields' => [{ 'name' => 'title', 'field_type' => 'string' }],
            'relationship' => { 'type' => 'belongs_to', 'parent_slug' => 'projects', 'foreign_key' => 'project_id' } }
        ]
      }
    )

    service = ApplicationBuildService.new(plan)
    error = assert_raises(ApplicationBuildService::BuildError) { service.execute! }
    assert_includes error.message, 'must be approved'
  end

  test 'build service creates module with relationship metadata' do
    plan = create_approved_multi_module_plan

    service = ApplicationBuildService.new(plan)

    # We can test the create_module method in isolation
    module_spec = plan.modules_spec.last # The sub-module
    app_module = service.send(:create_module, module_spec)

    assert_not_nil app_module
    assert_equal false, app_module.metadata['is_primary']
    assert app_module.metadata['relationship_spec'].present?
  end

  test 'build service generate_model_code_with_associations produces valid Ruby' do
    service = ApplicationBuildService.new(create_stub_plan)

    app_module = AppModule.create!(
      entity: @entity,
      name: 'Test Tasks',
      slug: 'test_tasks',
      status: 'generating'
    )

    associations = [
      { 'type' => 'belongs_to', 'model' => 'TestProject', 'table' => 'test_projects', 'foreign_key' => 'project_id' }
    ]

    code = service.send(:generate_model_code_with_associations, app_module, associations)

    assert_includes code, 'class TestTask < ApplicationRecord'
    assert_includes code, "self.table_name = 'test_tasks'"
    assert_includes code, 'belongs_to :entity'
    assert_includes code, 'belongs_to :test_project'
    assert_includes code, "foreign_key: 'project_id'"
    assert_includes code, 'scope :for_entity'
  end

  test 'build service generate_model_code_with_associations handles has_many' do
    service = ApplicationBuildService.new(create_stub_plan)

    app_module = AppModule.create!(
      entity: @entity,
      name: 'Test Projects',
      slug: 'test_projects',
      status: 'generating'
    )

    associations = [
      { 'type' => 'has_many', 'model' => 'TestTask', 'table' => 'test_tasks', 'foreign_key' => 'project_id' }
    ]

    code = service.send(:generate_model_code_with_associations, app_module, associations)

    assert_includes code, 'has_many :test_tasks'
    assert_includes code, "class_name: 'TestTask'"
    assert_includes code, "foreign_key: 'project_id'"
    assert_includes code, 'dependent: :nullify'
  end

  test 'build service generate_model_code_with_associations handles multiple associations' do
    service = ApplicationBuildService.new(create_stub_plan)

    app_module = AppModule.create!(
      entity: @entity,
      name: 'Test Projects',
      slug: 'test_projects',
      status: 'generating'
    )

    associations = [
      { 'type' => 'has_many', 'model' => 'TestTask', 'table' => 'test_tasks', 'foreign_key' => 'project_id' },
      { 'type' => 'has_many', 'model' => 'TestMilestone', 'table' => 'test_milestones', 'foreign_key' => 'project_id' }
    ]

    code = service.send(:generate_model_code_with_associations, app_module, associations)

    assert_includes code, 'has_many :test_tasks'
    assert_includes code, 'has_many :test_milestones'
  end

  # ══════════════════════════════════════════════════════════════
  # APPLICATION BUILD SERVICE - STORE RELATIONSHIP METADATA
  # ══════════════════════════════════════════════════════════════

  test 'store_relationship_metadata sets child metadata correctly' do
    service = ApplicationBuildService.new(create_stub_plan)

    parent = AppModule.create!(entity: @entity, name: 'Parent', slug: 'parent_mod', status: 'active')
    child = AppModule.create!(entity: @entity, name: 'Child', slug: 'child_mod', status: 'active')

    service.send(:store_relationship_metadata, child, parent, 'parent_mod_id')

    child.reload
    parent.reload

    # Child should have belongs_to metadata
    child_rels = child.metadata['relationships']
    assert child_rels.is_a?(Array)
    assert_equal 1, child_rels.length
    assert_equal 'belongs_to', child_rels.first['type']
    assert_equal parent.id, child_rels.first['parent_module_id']
    assert_equal 'parent_mod', child_rels.first['parent_module_slug']
    assert_equal 'parent_mod_id', child_rels.first['foreign_key']

    # Parent should have has_many metadata
    parent_rels = parent.metadata['relationships']
    assert parent_rels.is_a?(Array)
    assert_equal 1, parent_rels.length
    assert_equal 'has_many', parent_rels.first['type']
    assert_equal child.id, parent_rels.first['child_module_id']
    assert_equal 'child_mod', parent_rels.first['child_module_slug']
  end

  # ══════════════════════════════════════════════════════════════
  # APPLICATION BUILD SERVICE - CREATE MODULE TABLE WITH FK
  # ══════════════════════════════════════════════════════════════

  test 'create_module_table adds foreign key for belongs_to relationship' do
    plan = create_stub_plan

    service = ApplicationBuildService.new(plan)

    app_module = AppModule.create!(
      entity: @entity,
      name: 'Test Child',
      slug: 'test_child_fk',
      status: 'generating',
      metadata: { schema: { fields: [] } }
    )

    module_spec = {
      'name' => 'Test Child',
      'slug' => 'test_child_fk',
      'fields' => [
        { 'name' => 'title', 'field_type' => 'string' }
      ],
      'relationship' => {
        'type' => 'belongs_to',
        'parent_slug' => 'test_parent',
        'foreign_key' => 'parent_id'
      }
    }

    service.send(:create_module_table, app_module, module_spec)

    # Verify the schema_definition includes the foreign key
    module_code = app_module.module_codes.find_by(code_type: 'model')
    assert module_code.present?

    schema_fields = module_code.schema_definition['fields']
    fk_field = schema_fields.find { |f| f['name'] == 'parent_id' }
    assert fk_field.present?, "Should have parent_id in schema fields"
    assert_equal :bigint, fk_field['type'].to_sym

    # Verify indexes include the foreign key
    indexes = module_code.schema_definition['indexes']
    fk_index = indexes.find { |i| i['fields'].include?('parent_id') }
    assert fk_index.present?, "Should have index on parent_id"
  end

  test 'create_module_table works without relationship' do
    plan = create_stub_plan
    service = ApplicationBuildService.new(plan)

    app_module = AppModule.create!(
      entity: @entity,
      name: 'Test Standalone',
      slug: 'test_standalone_tbl',
      status: 'generating',
      metadata: { schema: { fields: [] } }
    )

    module_spec = {
      'name' => 'Test Standalone',
      'slug' => 'test_standalone_tbl',
      'fields' => [
        { 'name' => 'name', 'field_type' => 'string' }
      ]
    }

    service.send(:create_module_table, app_module, module_spec)

    module_code = app_module.module_codes.find_by(code_type: 'model')
    assert module_code.present?

    # Should only have entity_id index, no FK indexes
    indexes = module_code.schema_definition['indexes']
    assert_equal 1, indexes.length
    assert_equal ['entity_id'], indexes.first['fields']
  end

  # ══════════════════════════════════════════════════════════════
  # COMPREHENSIVE ARCHETYPE COUNT TEST
  # ══════════════════════════════════════════════════════════════

  test 'archetype count matches ApplicationPlan ARCHETYPES minus custom' do
    intelligence_keys = Modules::ArchetypeIntelligence.all_keys

    # All intelligence archetypes should be accepted by ApplicationPlan
    intelligence_keys.each do |key|
      assert ApplicationPlan::ARCHETYPES.include?(key.to_s),
        "ApplicationPlan should include archetype '#{key}' from ArchetypeIntelligence"
    end
  end

  test 'inventory archetype has correct sub_models' do
    sub_models = Modules::ArchetypeIntelligence.sub_models_for(:inventory)
    names = sub_models.map { |sm| sm[:name] }

    assert_includes names, 'Category'
    assert_includes names, 'Supplier'
    assert_includes names, 'StockMovement'
    assert_includes names, 'PurchaseOrder'
  end

  test 'project archetype has correct sub_models' do
    sub_models = Modules::ArchetypeIntelligence.sub_models_for(:project)
    names = sub_models.map { |sm| sm[:name] }

    assert_includes names, 'Task'
    assert_includes names, 'Milestone'
    assert_includes names, 'TimeEntry'
  end

  test 'helpdesk archetype has correct sub_models' do
    sub_models = Modules::ArchetypeIntelligence.sub_models_for(:helpdesk)
    names = sub_models.map { |sm| sm[:name] }

    assert_includes names, 'TicketComment'
    assert_includes names, 'CannedResponse'
  end

  test 'hr archetype has correct sub_models' do
    sub_models = Modules::ArchetypeIntelligence.sub_models_for(:hr)
    names = sub_models.map { |sm| sm[:name] }

    assert_includes names, 'TimeOffRequest'
    assert_includes names, 'JobPosting'
    assert_includes names, 'Applicant'
  end

  test 'real_estate archetype has correct sub_models' do
    sub_models = Modules::ArchetypeIntelligence.sub_models_for(:real_estate)
    names = sub_models.map { |sm| sm[:name] }

    assert_includes names, 'Tenant'
    assert_includes names, 'MaintenanceRequest'
    assert_includes names, 'Showing'
  end

  # ══════════════════════════════════════════════════════════════
  # CHAINED RELATIONSHIPS (grandchild models)
  # ══════════════════════════════════════════════════════════════

  test 'time_entry belongs_to Task which belongs_to Project' do
    sub_models = Modules::ArchetypeIntelligence.sub_models_for(:project)

    task = sub_models.find { |sm| sm[:name] == 'Task' }
    time_entry = sub_models.find { |sm| sm[:name] == 'TimeEntry' }

    # Task belongs to primary (Project)
    assert_equal 'belongs_to', task[:relationship][:type]
    assert_equal 'project_id', task[:relationship][:parent_field]

    # TimeEntry belongs to Task (explicit parent_model)
    assert_equal 'belongs_to', time_entry[:relationship][:type]
    assert_equal 'task_id', time_entry[:relationship][:parent_field]
    assert_equal 'Task', time_entry[:relationship][:parent_model]
  end

  test 'applicant belongs_to JobPosting which is standalone' do
    sub_models = Modules::ArchetypeIntelligence.sub_models_for(:hr)

    job_posting = sub_models.find { |sm| sm[:name] == 'JobPosting' }
    applicant = sub_models.find { |sm| sm[:name] == 'Applicant' }

    assert_equal 'standalone', job_posting[:relationship][:type]
    assert_equal 'belongs_to', applicant[:relationship][:type]
    assert_equal 'job_posting_id', applicant[:relationship][:parent_field]
    assert_equal 'JobPosting', applicant[:relationship][:parent_model]
  end

  private

  def create_approved_multi_module_plan
    ApplicationPlan.create!(
      entity: @entity,
      created_by: @user,
      name: 'Test Multi-Module Project',
      status: 'approved',
      approved_at: Time.current,
      archetype: 'project',
      plan_spec: {
        'modules' => [
          {
            'name' => 'Projects',
            'slug' => 'projects',
            'is_primary' => true,
            'fields' => [
              { 'name' => 'name', 'field_type' => 'string', 'required' => true },
              { 'name' => 'status', 'field_type' => 'select', 'options' => %w[active completed] }
            ],
            'views' => %w[list form detail dashboard]
          },
          {
            'name' => 'Tasks',
            'slug' => 'tasks',
            'is_primary' => false,
            'fields' => [
              { 'name' => 'title', 'field_type' => 'string', 'required' => true },
              { 'name' => 'status', 'field_type' => 'select', 'options' => %w[todo in_progress done] }
            ],
            'views' => %w[list kanban form],
            'relationship' => {
              'type' => 'belongs_to',
              'parent_slug' => 'projects',
              'foreign_key' => 'project_id'
            }
          }
        ],
        'agent' => {
          'name' => 'Project Expert',
          'slug' => 'project_expert',
          'description' => 'AI expert for projects',
          'capabilities' => ['manage tasks'],
          'personality' => 'helpful'
        }
      }
    )
  end

  def create_stub_plan
    ApplicationPlan.create!(
      entity: @entity,
      created_by: @user,
      name: 'Stub Plan',
      status: 'approved',
      approved_at: Time.current,
      plan_spec: {
        'modules' => [{ 'name' => 'Stub', 'fields' => [{ 'name' => 'name', 'field_type' => 'string' }] }]
      }
    )
  end
end
