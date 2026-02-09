# frozen_string_literal: true

require 'test_helper'

class CanvasGeneratorServiceTest < ActiveSupport::TestCase
  fixtures :entities, :users

  setup do
    @entity = entities(:one)
    @user = users(:one)
    @service = CanvasGeneratorService.new(entity: @entity, user: @user)
    @app_module = create_test_module('project_tasks')
    @fields = [
      { 'name' => 'title', 'type' => 'string', 'required' => true },
      { 'name' => 'description', 'type' => 'text' },
      { 'name' => 'status', 'type' => 'select', 'options' => %w[todo in_progress done] },
      { 'name' => 'priority', 'type' => 'select', 'options' => %w[low medium high urgent] },
      { 'name' => 'assignee', 'type' => 'string' },
      { 'name' => 'due_date', 'type' => 'date' },
      { 'name' => 'estimated_hours', 'type' => 'decimal' }
    ]
  end

  # ══════════════════════════════════════════════════════════════
  # SERVICE INSTANTIATION
  # ══════════════════════════════════════════════════════════════

  test 'service initializes with entity and user' do
    service = CanvasGeneratorService.new(entity: @entity, user: @user)
    assert_not_nil service
  end

  test 'SUPPORTED_VIEW_TYPES includes all expected types' do
    expected = %w[list kanban form detail dashboard calendar]
    expected.each do |type|
      assert_includes CanvasGeneratorService::SUPPORTED_VIEW_TYPES, type
    end
  end

  # ══════════════════════════════════════════════════════════════
  # STATIC FALLBACK — LIST VIEW
  # ══════════════════════════════════════════════════════════════

  test 'static list canvas generates html js and css' do
    result = @service.send(:generate_static, @app_module, 'list', @fields, [])
    assert result[:html].present?, 'HTML should be generated'
    assert result[:js].present?, 'JS should be generated'
    assert result[:css].present?, 'CSS should be generated'
  end

  test 'static list canvas html contains module slug' do
    result = @service.send(:generate_static, @app_module, 'list', @fields, [])
    assert_includes result[:html], @app_module.slug
  end

  test 'static list canvas html contains data-controller stimulus attribute' do
    result = @service.send(:generate_static, @app_module, 'list', @fields, [])
    assert_includes result[:html], 'data-controller="module-canvas"'
  end

  test 'static list canvas html contains field headers' do
    result = @service.send(:generate_static, @app_module, 'list', @fields, [])
    assert_includes result[:html], 'Title'
    assert_includes result[:html], 'Status'
  end

  test 'static list canvas html contains add new button' do
    result = @service.send(:generate_static, @app_module, 'list', @fields, [])
    assert_includes result[:html], 'Add New'
  end

  test 'static list canvas js contains api base path' do
    result = @service.send(:generate_static, @app_module, 'list', @fields, [])
    # The JS uses template literals: `/api/modules/${moduleSlug}/models/${modelName}`
    assert_includes result[:js], '/api/modules/'
    assert_includes result[:js], @app_module.slug
  end

  test 'static list canvas js contains fetch call' do
    result = @service.send(:generate_static, @app_module, 'list', @fields, [])
    assert_includes result[:js], 'fetch('
    assert_includes result[:js], 'loadData'
  end

  test 'static list canvas js includes search functionality' do
    result = @service.send(:generate_static, @app_module, 'list', @fields, [])
    assert_includes result[:js], 'search'
  end

  test 'static list canvas js includes status color mapping' do
    result = @service.send(:generate_static, @app_module, 'list', @fields, [])
    assert_includes result[:js], 'statusColor'
  end

  # ══════════════════════════════════════════════════════════════
  # STATIC FALLBACK — KANBAN VIEW
  # ══════════════════════════════════════════════════════════════

  test 'static kanban canvas generates html js and css' do
    result = @service.send(:generate_static, @app_module, 'kanban', @fields, [])
    assert result[:html].present?
    assert result[:js].present?
    assert result[:css].present?
  end

  test 'static kanban canvas contains status columns' do
    result = @service.send(:generate_static, @app_module, 'kanban', @fields, [])
    assert_includes result[:html], 'Todo'
    assert_includes result[:html], 'In Progress'
    assert_includes result[:html], 'Done'
  end

  test 'static kanban canvas html has drag attributes' do
    result = @service.send(:generate_static, @app_module, 'kanban', @fields, [])
    assert_includes result[:html], 'kanban-column'
    assert_includes result[:html], 'kanban-drop-zone'
  end

  test 'static kanban canvas js has drag and drop handlers' do
    result = @service.send(:generate_static, @app_module, 'kanban', @fields, [])
    assert_includes result[:js], 'dragstart'
    assert_includes result[:js], 'dragover'
    assert_includes result[:js], 'drop'
  end

  test 'static kanban canvas js updates status on drop' do
    result = @service.send(:generate_static, @app_module, 'kanban', @fields, [])
    assert_includes result[:js], 'PATCH'
    assert_includes result[:js], 'newStatus'
  end

  test 'static kanban canvas uses custom status options from fields' do
    result = @service.send(:generate_static, @app_module, 'kanban', @fields, [])
    # The status field has options [todo, in_progress, done]
    assert_includes result[:html], 'data-status="todo"'
    assert_includes result[:html], 'data-status="in_progress"'
    assert_includes result[:html], 'data-status="done"'
  end

  # ══════════════════════════════════════════════════════════════
  # STATIC FALLBACK — FORM VIEW
  # ══════════════════════════════════════════════════════════════

  test 'static form canvas generates html js and css' do
    result = @service.send(:generate_static, @app_module, 'form', @fields, [])
    assert result[:html].present?
    assert result[:js].present?
    assert result[:css].present?
  end

  test 'static form canvas contains form fields for each field' do
    result = @service.send(:generate_static, @app_module, 'form', @fields, [])
    assert_includes result[:html], "name='title'"
    assert_includes result[:html], "name='description'"
    assert_includes result[:html], "name='status'"
    assert_includes result[:html], "name='due_date'"
  end

  test 'static form canvas uses appropriate input types' do
    result = @service.send(:generate_static, @app_module, 'form', @fields, [])
    assert_includes result[:html], 'textarea'  # text type
    assert_includes result[:html], 'form-select' # select type
    assert_includes result[:html], "type='date'" # date type
    assert_includes result[:html], "step='0.01'" # decimal type
  end

  test 'static form canvas includes required attribute for required fields' do
    result = @service.send(:generate_static, @app_module, 'form', @fields, [])
    # title is required
    assert_match(/name='title'.*required/m, result[:html])
  end

  test 'static form canvas js handles form submission' do
    result = @service.send(:generate_static, @app_module, 'form', @fields, [])
    assert_includes result[:js], 'submit'
    assert_includes result[:js], 'POST'
    assert_includes result[:js], 'PATCH'
  end

  # ══════════════════════════════════════════════════════════════
  # STATIC FALLBACK — DETAIL VIEW
  # ══════════════════════════════════════════════════════════════

  test 'static detail canvas generates html js and css' do
    result = @service.send(:generate_static, @app_module, 'detail', @fields, [])
    assert result[:html].present?
    assert result[:js].present?
    assert result[:css].present?
  end

  test 'static detail canvas includes edit and delete buttons' do
    result = @service.send(:generate_static, @app_module, 'detail', @fields, [])
    assert_includes result[:html], 'Edit'
    assert_includes result[:html], 'Delete'
  end

  # ══════════════════════════════════════════════════════════════
  # STATIC FALLBACK — DASHBOARD VIEW
  # ══════════════════════════════════════════════════════════════

  test 'static dashboard canvas generates html js and css' do
    result = @service.send(:generate_static, @app_module, 'dashboard', @fields, [])
    assert result[:html].present?
    assert result[:js].present?
    assert result[:css].present?
  end

  test 'static dashboard canvas includes stat cards' do
    result = @service.send(:generate_static, @app_module, 'dashboard', @fields, [])
    assert_includes result[:html], 'stat-total'
    assert_includes result[:html], 'stat-week'
    assert_includes result[:html], 'stat-month'
    assert_includes result[:html], 'stat-today'
  end

  test 'static dashboard canvas includes chart when status field exists' do
    result = @service.send(:generate_static, @app_module, 'dashboard', @fields, [])
    assert_includes result[:html], 'status-chart'
    assert_includes result[:html], 'chart.js'
    assert_includes result[:js], 'Chart'
  end

  test 'static dashboard canvas auto-refreshes' do
    result = @service.send(:generate_static, @app_module, 'dashboard', @fields, [])
    assert_includes result[:js], 'setInterval'
    assert_includes result[:js], '60000'
  end

  # ══════════════════════════════════════════════════════════════
  # STATIC FALLBACK — CALENDAR VIEW
  # ══════════════════════════════════════════════════════════════

  test 'static calendar canvas generates html js and css' do
    result = @service.send(:generate_static, @app_module, 'calendar', @fields, [])
    assert result[:html].present?
    assert result[:js].present?
    assert result[:css].present?
  end

  test 'static calendar canvas includes month navigation' do
    result = @service.send(:generate_static, @app_module, 'calendar', @fields, [])
    assert_includes result[:html], 'prev-month'
    assert_includes result[:html], 'next-month'
    assert_includes result[:html], 'month-title'
  end

  test 'static calendar canvas uses date field from fields' do
    result = @service.send(:generate_static, @app_module, 'calendar', @fields, [])
    assert_includes result[:js], 'due_date' # the date field from @fields
  end

  test 'static calendar canvas renders month grid' do
    result = @service.send(:generate_static, @app_module, 'calendar', @fields, [])
    assert_includes result[:js], 'renderCalendar'
    assert_includes result[:js], 'daysInMonth'
  end

  # ══════════════════════════════════════════════════════════════
  # GENERATE METHOD — FALLBACK BEHAVIOR
  # ══════════════════════════════════════════════════════════════

  test 'generate falls back to static on unsupported view type' do
    result = @service.generate(
      app_module: @app_module,
      view_type: 'unsupported_type',
      fields: @fields
    )
    # Should fall back to list
    assert result[:html].present?
    assert result[:js].present?
  end

  test 'generate normalizes view type to lowercase' do
    result = @service.generate(
      app_module: @app_module,
      view_type: 'LIST',
      fields: @fields
    )
    assert result[:html].present?
  end

  test 'generate returns hash with html js css keys' do
    result = @service.generate(
      app_module: @app_module,
      view_type: 'list',
      fields: @fields
    )
    assert result.key?(:html)
    assert result.key?(:js)
    assert result.key?(:css)
  end

  # ══════════════════════════════════════════════════════════════
  # RESPONSE PARSING
  # ══════════════════════════════════════════════════════════════

  test 'parse_canvas_response extracts labeled code blocks' do
    raw = <<~TEXT
      ```html
      <div>Hello</div>
      ```
      ```javascript
      console.log('hi');
      ```
      ```css
      .test { color: red; }
      ```
    TEXT

    result = @service.send(:parse_canvas_response, raw)
    assert_equal '<div>Hello</div>', result[:html]
    assert_equal "console.log('hi');", result[:js]
    assert_equal '.test { color: red; }', result[:css]
  end

  test 'parse_canvas_response handles js shorthand' do
    raw = <<~TEXT
      ```html
      <div>Test</div>
      ```
      ```js
      alert('x');
      ```
      ```css
      body {}
      ```
    TEXT

    result = @service.send(:parse_canvas_response, raw)
    assert_equal '<div>Test</div>', result[:html]
    assert_equal "alert('x');", result[:js]
    assert_equal 'body {}', result[:css]
  end

  test 'parse_canvas_response falls back to unlabeled blocks' do
    raw = <<~TEXT
      ```
      <div>Unlabeled</div>
      ```
      ```
      console.log('second');
      ```
      ```
      .cls { margin: 0; }
      ```
    TEXT

    result = @service.send(:parse_canvas_response, raw)
    assert_equal '<div>Unlabeled</div>', result[:html]
    assert_equal "console.log('second');", result[:js]
    assert_equal '.cls { margin: 0; }', result[:css]
  end

  test 'parse_canvas_response returns nil keys when no blocks found' do
    result = @service.send(:parse_canvas_response, 'No code blocks here')
    assert_nil result[:html]
    assert_nil result[:js]
    assert_nil result[:css]
  end

  # ══════════════════════════════════════════════════════════════
  # PROMPT BUILDING
  # ══════════════════════════════════════════════════════════════

  test 'build_canvas_prompt includes module info' do
    prompt = @service.send(:build_canvas_prompt, @app_module, 'list', @fields, [])
    assert_includes prompt, @app_module.name
    assert_includes prompt, @app_module.slug
    assert_includes prompt, 'LIST'
  end

  test 'build_canvas_prompt includes field descriptions' do
    prompt = @service.send(:build_canvas_prompt, @app_module, 'list', @fields, [])
    assert_includes prompt, 'title (string)'
    assert_includes prompt, 'description (text)'
    assert_includes prompt, 'status (select)'
    assert_includes prompt, '[required]'
  end

  test 'build_canvas_prompt includes related models when provided' do
    related = [{ 'name' => 'SubTask', 'relationship_type' => 'has_many' }]
    prompt = @service.send(:build_canvas_prompt, @app_module, 'list', @fields, related)
    assert_includes prompt, 'RELATED MODELS'
    assert_includes prompt, 'SubTask'
    assert_includes prompt, 'has_many'
  end

  test 'build_canvas_prompt omits related models section when empty' do
    prompt = @service.send(:build_canvas_prompt, @app_module, 'list', @fields, [])
    refute_includes prompt, 'RELATED MODELS'
  end

  test 'build_canvas_prompt includes api path' do
    prompt = @service.send(:build_canvas_prompt, @app_module, 'list', @fields, [])
    assert_includes prompt, "/api/modules/#{@app_module.slug}/models/"
  end

  # ══════════════════════════════════════════════════════════════
  # VIEW TYPE INSTRUCTIONS
  # ══════════════════════════════════════════════════════════════

  test 'view_type_instructions returns instructions for all supported types' do
    CanvasGeneratorService::SUPPORTED_VIEW_TYPES.each do |vt|
      instructions = @service.send(:view_type_instructions, vt, @fields)
      assert instructions.present?, "Instructions for #{vt} should not be blank"
    end
  end

  test 'kanban instructions include status options from fields' do
    instructions = @service.send(:view_type_instructions, 'kanban', @fields)
    assert_includes instructions, 'todo'
    assert_includes instructions, 'in_progress'
    assert_includes instructions, 'done'
  end

  test 'calendar instructions mention date field' do
    instructions = @service.send(:view_type_instructions, 'calendar', @fields)
    assert_includes instructions, 'date'
  end

  test 'dashboard instructions mention chart' do
    instructions = @service.send(:view_type_instructions, 'dashboard', @fields)
    assert_includes instructions, 'chart'
  end

  test 'system prompt includes bootstrap and api path info' do
    prompt = @service.send(:canvas_system_prompt)
    assert_includes prompt, 'Bootstrap 5'
    assert_includes prompt, '/api/modules/'
    assert_includes prompt, 'X-CSRF-Token'
    assert_includes prompt, 'Lucide'
  end

  # ══════════════════════════════════════════════════════════════
  # APPLICATION BUILD SERVICE INTEGRATION
  # ══════════════════════════════════════════════════════════════

  test 'build service create_module_canvases calls canvas generator' do
    plan = create_test_plan
    build_service = ApplicationBuildService.new(plan)

    module_spec = {
      'name' => 'Tasks',
      'slug' => 'tasks',
      'views' => %w[list form detail],
      'fields' => @fields
    }

    # Create the module first
    app_module = create_test_module('tasks')

    # The build service should attempt to use CanvasGeneratorService
    # which will fall back to static templates since there's no actual Bedrock
    build_service.send(:create_module_canvases, app_module, module_spec)

    canvases = app_module.module_canvases.reload
    assert_equal 3, canvases.count

    list_canvas = canvases.find_by(slug: 'tasks_list')
    assert_not_nil list_canvas
    assert list_canvas.html_content.present?, 'List canvas should have HTML'
    assert list_canvas.js_content.present?, 'List canvas should have JS from generator'
    assert list_canvas.css_content.present?, 'List canvas should have CSS from generator'
    assert list_canvas.is_default, 'List canvas should be default'
    assert_equal 'data_grid', list_canvas.canvas_type

    form_canvas = canvases.find_by(slug: 'tasks_form')
    assert_not_nil form_canvas
    assert form_canvas.html_content.present?
    assert form_canvas.js_content.present?
    assert_equal 'form', form_canvas.canvas_type

    detail_canvas = canvases.find_by(slug: 'tasks_detail')
    assert_not_nil detail_canvas
    assert detail_canvas.html_content.present?
    assert_equal 'detail', detail_canvas.canvas_type
  end

  test 'build service stores generated_by metadata' do
    plan = create_test_plan
    build_service = ApplicationBuildService.new(plan)

    module_spec = {
      'name' => 'Widgets',
      'slug' => 'widgets',
      'views' => %w[list],
      'fields' => [{ 'name' => 'title', 'type' => 'string' }]
    }

    app_module = create_test_module('widgets')
    build_service.send(:create_module_canvases, app_module, module_spec)

    canvas = app_module.module_canvases.first
    assert_not_nil canvas.metadata['generated_by']
  end

  test 'build service build_related_models_context returns empty for modules without relationships' do
    plan = create_test_plan
    build_service = ApplicationBuildService.new(plan)

    app_module = create_test_module('standalone')
    module_spec = { 'name' => 'Standalone', 'slug' => 'standalone' }

    result = build_service.send(:build_related_models_context, app_module, module_spec)
    assert_equal [], result
  end

  test 'build service build_related_models_context finds parent for belongs_to' do
    plan = create_test_plan(modules: [
      { 'name' => 'Projects', 'slug' => 'projects' },
      { 'name' => 'Tasks', 'slug' => 'tasks', 'relationship' => { 'type' => 'belongs_to', 'parent_model' => 'projects' } }
    ])
    build_service = ApplicationBuildService.new(plan)
    parent_module = create_test_module('projects')

    task_module = create_test_module('tasks_child')
    module_spec = {
      'name' => 'Tasks',
      'slug' => 'tasks',
      'relationship' => { 'type' => 'belongs_to', 'parent_model' => 'projects' }
    }

    result = build_service.send(:build_related_models_context, task_module, module_spec)
    assert result.any? { |r| r[:relationship_type] == 'belongs_to' }
  end

  test 'build service build_related_models_context finds children for has_many' do
    plan = create_test_plan(modules: [
      { 'name' => 'Projects2', 'slug' => 'projects2' },
      { 'name' => 'Tasks2', 'slug' => 'tasks2', 'relationship' => { 'type' => 'belongs_to', 'parent_model' => 'projects2' } }
    ])
    build_service = ApplicationBuildService.new(plan)
    parent_module = create_test_module('projects2')

    module_spec = { 'name' => 'Projects2', 'slug' => 'projects2' }
    result = build_service.send(:build_related_models_context, parent_module, module_spec)
    assert result.any? { |r| r[:relationship_type] == 'has_many' && r[:slug] == 'tasks2' }
  end

  # ══════════════════════════════════════════════════════════════
  # MODULE CANVAS MODEL — to_canvas_response
  # ══════════════════════════════════════════════════════════════

  test 'to_canvas_response includes js_content and css_content' do
    app_module = create_test_module('response_test')
    canvas = ModuleCanvas.create!(
      app_module: app_module,
      entity: @entity,
      name: 'Test Canvas',
      slug: 'response_test_list',
      canvas_type: 'data_grid',
      html_content: '<div>HTML</div>',
      js_content: 'console.log("test");',
      css_content: '.test { color: red; }',
      data_sources: []
    )

    response = canvas.to_canvas_response
    assert_equal '<div>HTML</div>', response[:content]
    assert_equal 'console.log("test");', response[:js_content]
    assert_equal '.test { color: red; }', response[:css_content]
    assert_equal 'Test Canvas', response[:title]
    assert_equal 'response_test', response[:data][:module_slug]
    assert_equal 'response_test_list', response[:data][:canvas_slug]
  end

  test 'to_canvas_response handles nil js and css content' do
    app_module = create_test_module('no_js_test')
    canvas = ModuleCanvas.create!(
      app_module: app_module,
      entity: @entity,
      name: 'Plain Canvas',
      slug: 'no_js_test_list',
      canvas_type: 'data_grid',
      html_content: '<div>Plain</div>',
      data_sources: []
    )

    response = canvas.to_canvas_response
    assert_nil response[:js_content]
    assert_nil response[:css_content]
    assert_equal '<div>Plain</div>', response[:content]
  end

  # ══════════════════════════════════════════════════════════════
  # STATIC TEMPLATES — FIELD TYPE HANDLING
  # ══════════════════════════════════════════════════════════════

  test 'static form handles boolean fields correctly' do
    fields = [{ 'name' => 'is_active', 'type' => 'boolean' }]
    result = @service.send(:generate_static, @app_module, 'form', fields, [])
    assert_includes result[:html], 'form-check-input'
    assert_includes result[:html], "type='checkbox'"
  end

  test 'static form handles integer fields correctly' do
    fields = [{ 'name' => 'count', 'type' => 'integer' }]
    result = @service.send(:generate_static, @app_module, 'form', fields, [])
    assert_includes result[:html], "type='number'"
  end

  test 'static form handles datetime fields correctly' do
    fields = [{ 'name' => 'starts_at', 'type' => 'datetime' }]
    result = @service.send(:generate_static, @app_module, 'form', fields, [])
    assert_includes result[:html], "type='datetime-local'"
  end

  test 'static kanban uses default columns when no status field' do
    fields = [{ 'name' => 'title', 'type' => 'string' }]
    result = @service.send(:generate_static, @app_module, 'kanban', fields, [])
    assert_includes result[:html], 'data-status="todo"'
    assert_includes result[:html], 'data-status="in_progress"'
    assert_includes result[:html], 'data-status="done"'
  end

  test 'static dashboard works without status field' do
    fields = [{ 'name' => 'name', 'type' => 'string' }]
    result = @service.send(:generate_static, @app_module, 'dashboard', fields, [])
    assert result[:html].present?
    assert result[:js].present?
    # Should not include chart when no status field
    refute_includes result[:html], 'status-chart'
  end

  test 'static calendar uses created_at as fallback date field' do
    fields = [{ 'name' => 'title', 'type' => 'string' }]
    result = @service.send(:generate_static, @app_module, 'calendar', fields, [])
    assert_includes result[:js], 'created_at'
  end

  # ══════════════════════════════════════════════════════════════
  # STATIC TEMPLATES — SYMBOL KEY SUPPORT
  # ══════════════════════════════════════════════════════════════

  test 'static templates handle fields with symbol keys' do
    fields = [
      { name: 'title', type: 'string', required: true },
      { name: 'status', type: 'select', options: %w[open closed] }
    ]
    result = @service.send(:generate_static, @app_module, 'list', fields, [])
    assert result[:html].present?
    assert_includes result[:html], 'Title'
    assert_includes result[:html], 'Status'
  end

  test 'static kanban handles fields with symbol keys' do
    fields = [
      { name: 'title', type: 'string' },
      { name: 'status', type: 'select', options: %w[new doing done] }
    ]
    result = @service.send(:generate_static, @app_module, 'kanban', fields, [])
    assert_includes result[:html], 'data-status="new"'
    assert_includes result[:html], 'data-status="doing"'
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

  def create_test_plan(modules: nil)
    plan_spec = { 'modules' => modules || [] }
    ApplicationPlan.create!(
      entity: @entity,
      created_by: @user,
      name: 'Test Plan',
      description: 'Test application plan',
      archetype: 'custom',
      plan_spec: plan_spec,
      status: 'approved'
    )
  end
end
