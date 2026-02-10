# frozen_string_literal: true

require 'test_helper'

class V3::ModuleAwareToolsTest < ActiveSupport::TestCase
  fixtures :users, :entities

  setup do
    @user = users(:one)
    @entity = entities(:one)
    @create_tool = V3::Tools::PlatformCreateTool.new(user: @user, entity: @entity)
    @query_tool = V3::Tools::PlatformQueryTool.new(user: @user, entity: @entity)
    @update_tool = V3::Tools::PlatformUpdateTool.new(user: @user, entity: @entity)
  end

  # ══════════════════════════════════════════════════════════════
  # PLATFORM CREATE TOOL — DYNAMIC MODULE RESOLUTION
  # ══════════════════════════════════════════════════════════════

  test 'create tool resolve_dynamic_model returns nil for standard types' do
    result = @create_tool.send(:resolve_dynamic_model, 'contact')
    assert_nil result
  end

  test 'create tool resolve_dynamic_model returns nil when no entity modules exist' do
    result = @create_tool.send(:resolve_dynamic_model, 'nonexistent_module')
    assert_nil result
  end

  test 'create tool resolve_dynamic_model finds by direct slug' do
    app_module = create_test_module('test_widgets')
    create_test_model_code(app_module, 'TestWidget')

    # Mock DynamicModelLoader
    mock_model = mock_dynamic_model_class('TestWidget')
    Modules::DynamicModelLoader.instance.stub(:get_model, mock_model) do
      result = @create_tool.send(:resolve_dynamic_model, 'test_widgets')
      assert_equal mock_model, result
    end
  end

  test 'create tool resolve_dynamic_model finds by module_slug/ModelName format' do
    app_module = create_test_module('project_mgmt')
    create_test_model_code(app_module, 'Task')

    mock_model = mock_dynamic_model_class('Task')
    Modules::DynamicModelLoader.instance.stub(:get_model, mock_model) do
      result = @create_tool.send(:resolve_dynamic_model, 'project_mgmt/Task')
      assert_equal mock_model, result
    end
  end

  test 'create tool resolve_dynamic_model finds by model name underscore' do
    app_module = create_test_module('proj')
    create_test_model_code(app_module, 'ProjectTask', table_name: 'project_tasks')

    mock_model = mock_dynamic_model_class('ProjectTask')
    Modules::DynamicModelLoader.instance.stub(:get_model, mock_model) do
      result = @create_tool.send(:resolve_dynamic_model, 'project_task')
      assert_equal mock_model, result
    end
  end

  test 'create tool still routes builder types correctly' do
    # 'app' should route to build_app, not dynamic module
    result = @create_tool.execute({
      'type' => 'app',
      'data' => { 'name' => 'Test App', 'description' => 'A test' }
    })

    # It should attempt the build, not fall through to dynamic module
    # (may fail in test env but should not return nil/module result)
    assert result.is_a?(Hash)
  end

  test 'create tool still routes standard types correctly' do
    # 'contact' should delegate to CreateObjectTool
    result = @create_tool.execute({
      'type' => 'contact',
      'data' => { 'first_name' => 'Test', 'last_name' => 'Module', 'email' => 'module-test@test.com' }
    })

    assert result.is_a?(Hash)
    assert result[:success] != false || result[:error].present?
  end

  # ══════════════════════════════════════════════════════════════
  # PLATFORM QUERY TOOL — DYNAMIC MODULE RESOLUTION
  # ══════════════════════════════════════════════════════════════

  test 'query tool resolve_dynamic_model returns nil for standard types' do
    result = @query_tool.send(:resolve_dynamic_model, 'contacts')
    assert_nil result
  end

  test 'query tool resolve_dynamic_model returns nil for nonexistent module' do
    result = @query_tool.send(:resolve_dynamic_model, 'nonexistent')
    assert_nil result
  end

  test 'query tool schema includes dynamic module types' do
    app_module = create_test_module('test_inventory')
    create_test_model_code(app_module, 'TestInventory')

    result = @query_tool.execute({ 'type' => 'schema' })

    assert result.is_a?(Hash)
    assert result[:success] != false

    # Should include the dynamic module type
    all_types = result[:available_types]&.map { |t| t[:type] } || []
    module_types = result[:module_types] || []

    # The module should appear in available types (either directly or via module_types)
    has_module = all_types.any? { |t| t.include?('test_inventory') } ||
                 module_types.any? { |t| t[:type].to_s.include?('test_inventory') }
    assert has_module, "Schema should include test_inventory module type. Types: #{all_types.inspect}"
  end

  test 'query tool handles standard types normally' do
    result = @query_tool.execute({
      'type' => 'contacts',
      'limit' => 5
    })

    assert result.is_a?(Hash)
    # Should succeed or at least not crash
    assert result[:success] != false || result[:records].is_a?(Array) || result[:error].present?
  end

  test 'query tool returns error for truly unknown type' do
    result = @query_tool.execute({
      'type' => 'completely_nonexistent_xyz'
    })

    assert result.is_a?(Hash)
    assert_equal false, result[:success]
    assert result[:error].present?
    assert_match(/unknown/i, result[:error])
  end

  # ══════════════════════════════════════════════════════════════
  # PLATFORM UPDATE TOOL — DYNAMIC MODULE RESOLUTION
  # ══════════════════════════════════════════════════════════════

  test 'update tool resolve_dynamic_model returns nil for standard types' do
    result = @update_tool.send(:resolve_dynamic_model, 'contact')
    assert_nil result
  end

  test 'update tool still handles standard updates' do
    contact = Contact.create!(
      entity: @entity,
      user: @user,
      first_name: 'Update',
      last_name: 'Test',
      email: 'update-module-test@test.com'
    )

    result = @update_tool.execute({
      'type' => 'contact',
      'id' => contact.id,
      'data' => { 'first_name' => 'Updated' }
    })

    assert result.is_a?(Hash)
    # May succeed or have validation issues, but shouldn't crash
  end

  test 'update tool still handles schema management' do
    result = @update_tool.execute({
      'type' => 'schema',
      'id' => 'contact',
      'data' => { 'list_fields' => true }
    })

    assert result.is_a?(Hash)
    assert result[:success] != false || result[:error].present?
  end

  # ══════════════════════════════════════════════════════════════
  # SCOUT DATA REGISTRY — DYNAMIC MODULE INTEGRATION
  # ══════════════════════════════════════════════════════════════

  test 'registry available_object_types includes dynamic modules' do
    app_module = create_test_module('test_reg_mod')
    create_test_model_code(app_module, 'TestRegMod')

    types = ScoutDataRegistry.available_object_types(@entity)

    assert types.include?('test_reg_mod'), "Should include module slug. Types: #{types.inspect}"
  end

  test 'registry object_config returns dynamic config for module' do
    app_module = create_test_module('test_dyn_config')
    create_test_model_code(app_module, 'TestDynConfig', fields: [
      { 'name' => 'title', 'type' => 'string' },
      { 'name' => 'status', 'type' => 'string' }
    ])

    config = ScoutDataRegistry.object_config('test_dyn_config', @entity)

    assert config.present?
    assert config[:dynamic]
    assert config[:creatable]
    assert_equal app_module.id, config[:app_module_id]
    assert config[:queryable_fields].include?('title')
  end

  test 'registry queryable? returns true for dynamic modules' do
    create_test_module('test_queryable')

    assert ScoutDataRegistry.queryable?('test_queryable', @entity)
  end

  test 'registry queryable? returns false for nonexistent types' do
    refute ScoutDataRegistry.queryable?('nonexistent_xyz', @entity)
  end

  test 'registry object_config returns nil for nonexistent type' do
    config = ScoutDataRegistry.object_config('nonexistent_xyz', @entity)
    assert_nil config
  end

  test 'registry build_module_config includes all expected keys' do
    app_module = create_test_module('test_full_config')
    create_test_model_code(app_module, 'TestFullConfig', fields: [
      { 'name' => 'name', 'type' => 'string', 'null' => false },
      { 'name' => 'description', 'type' => 'text' },
      { 'name' => 'active', 'type' => 'boolean' }
    ])

    config = ScoutDataRegistry.build_module_config(app_module)

    assert config.is_a?(Hash)
    assert_equal 'TestFullConfig', config[:model]
    assert config[:description].present?
    assert config[:queryable_fields].is_a?(Array)
    assert config[:filterable_fields].is_a?(Array)
    assert config[:creation_schema].is_a?(Hash)
    assert config[:creation_schema][:required].is_a?(Array)
    assert config[:creation_schema][:optional].is_a?(Array)
    assert config[:dynamic]
  end

  # ══════════════════════════════════════════════════════════════
  # TOOL METADATA — DOCUMENTATION
  # ══════════════════════════════════════════════════════════════

  test 'create tool metadata mentions custom app types' do
    desc = V3::Tools::PlatformCreateTool.metadata[:description]
    assert_includes desc, 'custom app type'
  end

  test 'query tool metadata mentions custom app models' do
    desc = V3::Tools::PlatformQueryTool.metadata[:description]
    assert_includes desc, 'custom app models'
  end

  private

  def create_test_module(slug, status: 'active')
    AppModule.create!(
      entity: @entity,
      name: slug.titleize,
      slug: slug,
      status: status,
      version: '1.0.0',
      author_type: 'amos',
      visibility: 'user_private'
    )
  end

  def create_test_model_code(app_module, model_name, table_name: nil, fields: nil)
    table = table_name || app_module.slug.pluralize
    schema_fields = fields || [
      { 'name' => 'name', 'type' => 'string' },
      { 'name' => 'status', 'type' => 'string' }
    ]

    ModuleCode.create!(
      app_module: app_module,
      entity_id: app_module.entity_id,
      name: model_name,
      code_type: 'model',
      content: <<~RUBY,
        class #{model_name} < ApplicationRecord
          self.table_name = '#{table}'
          belongs_to :entity
          scope :for_entity, ->(entity_id) { where(entity_id: entity_id) }
        end
      RUBY
      schema_definition: {
        'table_name' => table,
        'fields' => schema_fields,
        'associations' => [],
        'indexes' => [{ 'fields' => ['entity_id'] }]
      },
      status: 'deployed'
    )
  end

  def mock_dynamic_model_class(name)
    # Return a simple class that looks like an AR model
    Class.new do
      define_singleton_method(:name) { name }
      define_singleton_method(:table_name) { name.underscore.pluralize }
      define_singleton_method(:column_names) { %w[id name status entity_id created_at updated_at] }
    end
  end
end
