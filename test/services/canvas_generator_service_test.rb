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
    expected = %w[list kanban form detail dashboard calendar freeform]
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
  # STATIC FALLBACK — FREEFORM VIEW
  # ══════════════════════════════════════════════════════════════

  test 'static freeform canvas generates html js and css' do
    result = @service.send(:generate_static, @app_module, 'freeform', @fields, [])
    assert result[:html].present?, 'HTML should be generated'
    assert result[:js].present?, 'JS should be generated'
    assert result[:css].present?, 'CSS should be generated'
  end

  test 'static freeform canvas html contains module slug' do
    result = @service.send(:generate_static, @app_module, 'freeform', @fields, [])
    assert_includes result[:html], @app_module.slug
  end

  test 'static freeform canvas html contains data-controller stimulus attribute' do
    result = @service.send(:generate_static, @app_module, 'freeform', @fields, [])
    assert_includes result[:html], 'data-controller="module-canvas"'
  end

  test 'static freeform canvas html contains stat cards' do
    result = @service.send(:generate_static, @app_module, 'freeform', @fields, [])
    assert_includes result[:html], 'stat-total'
    assert_includes result[:html], 'stat-week'
  end

  test 'static freeform canvas html contains add new button' do
    result = @service.send(:generate_static, @app_module, 'freeform', @fields, [])
    assert_includes result[:html], 'Add New'
  end

  test 'static freeform canvas js contains api base path' do
    result = @service.send(:generate_static, @app_module, 'freeform', @fields, [])
    assert_includes result[:js], '/api/modules/'
    assert_includes result[:js], @app_module.slug
  end

  test 'static freeform canvas js contains fetch and loadData' do
    result = @service.send(:generate_static, @app_module, 'freeform', @fields, [])
    assert_includes result[:js], 'fetch('
    assert_includes result[:js], 'loadData'
  end

  test 'static freeform canvas uses card-based layout for records' do
    result = @service.send(:generate_static, @app_module, 'freeform', @fields, [])
    assert_includes result[:html], 'record-cards'
    assert_includes result[:js], 'record-card'
  end

  test 'static freeform canvas includes search functionality' do
    result = @service.send(:generate_static, @app_module, 'freeform', @fields, [])
    assert_includes result[:js], 'search'
    assert_includes result[:html], 'search-input'
  end

  test 'static freeform canvas passes quality validation' do
    result = @service.send(:generate_static, @app_module, 'freeform', @fields, [])
    issues = @service.send(:analyze_canvas_quality, result[:html], result[:js])
    assert_empty issues, "Static freeform template should have 0 quality issues but found: #{issues.inspect}"
  end

  # ══════════════════════════════════════════════════════════════
  # FREEFORM — DESCRIPTION PARAMETER
  # ══════════════════════════════════════════════════════════════

  test 'generate accepts optional description parameter' do
    result = @service.generate(
      app_module: @app_module,
      view_type: 'freeform',
      fields: @fields,
      description: 'modern card-based dashboard with charts'
    )
    assert result[:html].present?
  end

  test 'freeform view_type_instructions includes user description when provided' do
    @service.instance_variable_set(:@description, 'sleek timeline layout')
    instructions = @service.send(:view_type_instructions, 'freeform', @fields)
    assert_includes instructions, 'sleek timeline layout'
    assert_includes instructions, "User's design intent"
  end

  test 'freeform view_type_instructions works without description' do
    @service.instance_variable_set(:@description, nil)
    instructions = @service.send(:view_type_instructions, 'freeform', @fields)
    assert_includes instructions, 'FULL creative freedom'
    refute_includes instructions, "User's design intent"
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
    assert list_canvas.is_default, 'List canvas should be default'
    assert_equal 'data_grid', list_canvas.canvas_type
    assert_equal 'static', list_canvas.metadata['generated_by'], 'Static templates used for initial build'

    form_canvas = canvases.find_by(slug: 'tasks_form')
    assert_not_nil form_canvas
    assert form_canvas.html_content.present?
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

  test 'build service creates static canvases with ai_upgrade_pending flag' do
    plan = create_test_plan
    build_service = ApplicationBuildService.new(plan)

    app_module = create_test_module('standalone')
    module_spec = { 'name' => 'Standalone', 'slug' => 'standalone', 'views' => %w[list], 'fields' => [{ 'name' => 'title', 'type' => 'string' }] }

    build_service.send(:create_module_canvases, app_module, module_spec)

    canvas = app_module.module_canvases.first
    assert_not_nil canvas
    assert_equal 'static', canvas.metadata['generated_by']
    assert_equal true, canvas.metadata['ai_upgrade_pending']
  end

  test 'build service creates canvases for modules with relationships' do
    plan = create_test_plan(modules: [
      { 'name' => 'Projects', 'slug' => 'projects' },
      { 'name' => 'Tasks', 'slug' => 'tasks', 'relationship' => { 'type' => 'belongs_to', 'parent_model' => 'projects' } }
    ])
    build_service = ApplicationBuildService.new(plan)

    task_module = create_test_module('tasks_rel')
    module_spec = {
      'name' => 'Tasks',
      'slug' => 'tasks_rel',
      'views' => %w[list form],
      'fields' => [{ 'name' => 'title', 'type' => 'string' }],
      'relationship' => { 'type' => 'belongs_to', 'parent_model' => 'projects' }
    }

    build_service.send(:create_module_canvases, task_module, module_spec)
    assert_equal 2, task_module.module_canvases.count
  end

  test 'build service skips locked canvases during rebuild' do
    plan = create_test_plan
    build_service = ApplicationBuildService.new(plan)

    app_module = create_test_module('locktest')
    module_spec = { 'name' => 'LockTest', 'slug' => 'locktest', 'views' => %w[list], 'fields' => [{ 'name' => 'title', 'type' => 'string' }] }

    build_service.send(:create_module_canvases, app_module, module_spec)
    canvas = app_module.module_canvases.first
    original_html = canvas.html_content
    canvas.update!(locked_at: Time.current, lock_reason: 'user_customized')

    build_service.send(:create_module_canvases, app_module, module_spec)
    canvas.reload
    assert_equal original_html, canvas.html_content, 'Locked canvas should not be overwritten'
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

  # ══════════════════════════════════════════════════════════════
  # CANVAS QUALITY VALIDATION — analyze_canvas_quality
  # ══════════════════════════════════════════════════════════════

  test 'quality check passes for well-wired canvas' do
    html = <<~HTML
      <div>
        <button data-action="click->module-canvas#performAction" data-action-name="add">Add</button>
        <button type="submit">Save</button>
        <button data-bs-toggle="modal" data-bs-target="#editModal">Edit</button>
        <button data-bs-dismiss="modal">Close</button>
        <button onclick="doStuff()">Do</button>
        <button id="refresh-btn">Refresh</button>
        <a href="/somewhere">Link</a>
        <form id="my-form"><input type="text"></form>
        <div id="editModal" class="modal"></div>
      </div>
    HTML
    js = <<~JS
      function doStuff() { console.log('hi'); }
      document.getElementById('refresh-btn').addEventListener('click', () => {});
      document.getElementById('my-form').addEventListener('submit', (e) => {});
    JS

    issues = @service.send(:analyze_canvas_quality, html, js)
    assert_empty issues, "Expected 0 issues but found: #{issues.inspect}"
  end

  test 'quality check detects unwired buttons' do
    html = '<div><button class="btn btn-primary">Click Me</button></div>'
    js = 'console.log("no handlers");'

    issues = @service.send(:analyze_canvas_quality, html, js)
    assert issues.any? { |i| i[:type] == :unwired_button }, "Should detect unwired button"
  end

  test 'quality check allows buttons with data-action' do
    html = '<button data-action="click->module-canvas#performAction">OK</button>'
    issues = @service.send(:analyze_canvas_quality, html, '')
    refute issues.any? { |i| i[:type] == :unwired_button }
  end

  test 'quality check allows buttons with onclick' do
    html = '<button onclick="handleClick()">OK</button>'
    js = 'function handleClick() {}'
    issues = @service.send(:analyze_canvas_quality, html, js)
    refute issues.any? { |i| i[:type] == :unwired_button }
  end

  test 'quality check allows submit buttons' do
    html = '<button type="submit">Save</button>'
    issues = @service.send(:analyze_canvas_quality, html, '')
    refute issues.any? { |i| i[:type] == :unwired_button }
  end

  test 'quality check allows buttons with data-bs-toggle' do
    html = '<button data-bs-toggle="modal" data-bs-target="#myModal">Open</button><div id="myModal"></div>'
    issues = @service.send(:analyze_canvas_quality, html, '')
    refute issues.any? { |i| i[:type] == :unwired_button }
  end

  test 'quality check allows buttons with data-bs-dismiss' do
    html = '<button data-bs-dismiss="modal">Close</button>'
    issues = @service.send(:analyze_canvas_quality, html, '')
    refute issues.any? { |i| i[:type] == :unwired_button }
  end

  test 'quality check allows buttons with ID referenced in JS' do
    html = '<button id="export-btn">Export</button>'
    js = "document.getElementById('export-btn').addEventListener('click', () => {});"
    issues = @service.send(:analyze_canvas_quality, html, js)
    refute issues.any? { |i| i[:type] == :unwired_button }
  end

  test 'quality check detects dead links with href hash' do
    html = '<a href="#">Go Nowhere</a>'
    js = ''
    issues = @service.send(:analyze_canvas_quality, html, js)
    assert issues.any? { |i| i[:type] == :dead_link }, "Should detect dead link"
  end

  test 'quality check ignores normal links' do
    html = '<a href="/dashboard">Dashboard</a>'
    issues = @service.send(:analyze_canvas_quality, html, '')
    refute issues.any? { |i| i[:type] == :dead_link }
  end

  test 'quality check allows hash links with data-bs-toggle' do
    html = '<a href="#" data-bs-toggle="dropdown">Menu</a>'
    issues = @service.send(:analyze_canvas_quality, html, '')
    refute issues.any? { |i| i[:type] == :dead_link }
  end

  test 'quality check allows hash links with onclick' do
    html = '<a href="#" onclick="navigate()">Go</a>'
    js = 'function navigate() {}'
    issues = @service.send(:analyze_canvas_quality, html, js)
    refute issues.any? { |i| i[:type] == :dead_link }
  end

  test 'quality check detects unwired forms' do
    html = '<form class="needs-validation"><input type="text" name="title"></form>'
    js = 'console.log("loaded");'
    issues = @service.send(:analyze_canvas_quality, html, js)
    assert issues.any? { |i| i[:type] == :unwired_form }, "Should detect unwired form"
  end

  test 'quality check allows forms with data-action submit' do
    html = '<form data-action="submit->module-canvas#saveRecord"><input></form>'
    issues = @service.send(:analyze_canvas_quality, html, '')
    refute issues.any? { |i| i[:type] == :unwired_form }
  end

  test 'quality check allows forms with onsubmit' do
    html = '<form onsubmit="return handleSubmit()"><input></form>'
    issues = @service.send(:analyze_canvas_quality, html, '')
    refute issues.any? { |i| i[:type] == :unwired_form }
  end

  test 'quality check allows forms with ID referenced in JS' do
    html = '<form id="canvas-form"><input></form>'
    js = "document.getElementById('canvas-form').addEventListener('submit', (e) => {});"
    issues = @service.send(:analyze_canvas_quality, html, js)
    refute issues.any? { |i| i[:type] == :unwired_form }
  end

  test 'quality check allows forms with real action URL' do
    html = '<form action="/api/submit"><input></form>'
    issues = @service.send(:analyze_canvas_quality, html, '')
    refute issues.any? { |i| i[:type] == :unwired_form }
  end

  test 'quality check detects missing modal targets' do
    html = '<button data-bs-toggle="modal" data-bs-target="#editModal">Edit</button>'
    issues = @service.send(:analyze_canvas_quality, html, '')
    assert issues.any? { |i| i[:type] == :missing_modal && i[:modal_id] == 'editModal' },
           "Should detect missing modal #editModal"
  end

  test 'quality check passes when modal target exists' do
    html = <<~HTML
      <button data-bs-toggle="modal" data-bs-target="#editModal">Edit</button>
      <div id="editModal" class="modal fade"><div class="modal-dialog"></div></div>
    HTML
    issues = @service.send(:analyze_canvas_quality, html, '')
    refute issues.any? { |i| i[:type] == :missing_modal }
  end

  test 'quality check detects undefined onclick functions' do
    html = '<button onclick="deleteRecord(5)">Delete</button>'
    js = 'function loadData() { fetch("/api/data"); }'
    issues = @service.send(:analyze_canvas_quality, html, js)
    assert issues.any? { |i| i[:type] == :undefined_function && i[:function] == 'deleteRecord' },
           "Should detect undefined function deleteRecord"
  end

  test 'quality check passes when onclick function is defined' do
    html = '<button onclick="deleteRecord(5)">Delete</button>'
    js = 'function deleteRecord(id) { fetch("/api/" + id, { method: "DELETE" }); }'
    issues = @service.send(:analyze_canvas_quality, html, js)
    refute issues.any? { |i| i[:type] == :undefined_function }
  end

  test 'quality check handles arrow function definitions for onclick' do
    html = '<button onclick="doExport()">Export</button>'
    js = 'const doExport = () => { window.open("/export"); };'
    issues = @service.send(:analyze_canvas_quality, html, js)
    refute issues.any? { |i| i[:type] == :undefined_function }
  end

  test 'quality check handles async function definitions for onclick' do
    html = '<button onclick="fetchData()">Load</button>'
    js = 'async function fetchData() { await fetch("/api"); }'
    issues = @service.send(:analyze_canvas_quality, html, js)
    refute issues.any? { |i| i[:type] == :undefined_function }
  end

  test 'quality check detects missing HTML elements referenced in JS' do
    html = '<div id="content">Hello</div>'
    js = <<~JS
      document.getElementById('content').innerHTML = 'Updated';
      document.getElementById('missing-element').textContent = 'Oops';
    JS
    issues = @service.send(:analyze_canvas_quality, html, js)
    assert issues.any? { |i| i[:type] == :missing_element && i[:element_id] == 'missing-element' },
           "Should detect missing element 'missing-element'"
  end

  test 'quality check passes when all JS-referenced IDs exist in HTML' do
    html = '<div id="data-tbody"></div><span id="record-count"></span>'
    js = <<~JS
      document.getElementById('data-tbody').innerHTML = '';
      document.getElementById('record-count').textContent = '5';
    JS
    issues = @service.send(:analyze_canvas_quality, html, js)
    refute issues.any? { |i| i[:type] == :missing_element }
  end

  test 'quality check skips dynamically created IDs in JS' do
    html = '<div id="container"></div>'
    # ID "dynamic-item" appears twice: once in innerHTML creation and once in getElementById
    js = <<~JS
      document.getElementById('container').innerHTML = '<div id="dynamic-item">test</div>';
      document.getElementById('dynamic-item').click();
    JS
    issues = @service.send(:analyze_canvas_quality, html, js)
    refute issues.any? { |i| i[:type] == :missing_element && i[:element_id] == 'dynamic-item' },
           "Should skip dynamically created elements"
  end

  test 'quality check handles querySelector with hash selector' do
    html = '<div id="app">App</div>'
    js = "document.querySelector('#missing-div').style.display = 'none';"
    issues = @service.send(:analyze_canvas_quality, html, js)
    assert issues.any? { |i| i[:type] == :missing_element && i[:element_id] == 'missing-div' }
  end

  test 'quality check returns empty array for blank html' do
    issues = @service.send(:analyze_canvas_quality, '', 'console.log("test");')
    assert_empty issues
  end

  test 'quality check returns empty array for nil html' do
    issues = @service.send(:analyze_canvas_quality, nil, nil)
    assert_empty issues
  end

  test 'quality check handles nil js gracefully' do
    html = '<button class="btn">Click</button>'
    issues = @service.send(:analyze_canvas_quality, html, nil)
    assert issues.any? { |i| i[:type] == :unwired_button }
  end

  test 'quality check detects multiple issues at once' do
    html = <<~HTML
      <button class="btn">Unwired 1</button>
      <button class="btn btn-danger">Unwired 2</button>
      <a href="#">Dead Link</a>
      <form><input type="text"></form>
      <button data-bs-toggle="modal" data-bs-target="#ghostModal">Open</button>
    HTML
    js = "document.getElementById('nonexistent').click();"

    issues = @service.send(:analyze_canvas_quality, html, js)
    types = issues.map { |i| i[:type] }

    assert_includes types, :unwired_button
    assert_includes types, :dead_link
    assert_includes types, :unwired_form
    assert_includes types, :missing_modal
    assert_includes types, :missing_element
    assert issues.length >= 5, "Should find at least 5 issues, found #{issues.length}"
  end

  # ══════════════════════════════════════════════════════════════
  # CANVAS QUALITY VALIDATION — validate_and_fix_canvas
  # ══════════════════════════════════════════════════════════════

  test 'validate_and_fix returns result unchanged when no issues' do
    result = {
      html: '<button data-action="click->module-canvas#performAction">Add</button>',
      js: 'console.log("loaded");',
      css: '.test { color: red; }'
    }
    validated = @service.send(:validate_and_fix_canvas, result)
    assert_equal result, validated
  end

  test 'validate_and_fix returns result for blank html' do
    result = { html: '', js: '', css: '' }
    validated = @service.send(:validate_and_fix_canvas, result)
    assert_equal result, validated
  end

  test 'validate_and_fix returns result for nil html' do
    result = { html: nil, js: nil, css: nil }
    validated = @service.send(:validate_and_fix_canvas, result)
    assert_equal result, validated
  end

  test 'validate_and_fix skips AI fix when too many issues' do
    # Generate HTML with many unwired buttons (exceeds MAX_QUALITY_ISSUES_FOR_FIX)
    buttons = 15.times.map { |i| "<button class='btn'>Button #{i}</button>" }.join("\n")
    result = { html: "<div>#{buttons}</div>", js: '', css: '' }

    # Should NOT call bedrock (no stub needed — it would error if called)
    validated = @service.send(:validate_and_fix_canvas, result)
    # Returns original since too many issues
    assert_equal result[:html], validated[:html]
  end

  test 'validate_and_fix attempts AI fix and returns improved result' do
    original = {
      html: '<button class="btn">Unwired</button>',
      js: 'console.log("no handlers");',
      css: '.btn { color: blue; }'
    }

    fixed_html = '<button id="action-btn" class="btn">Unwired</button>'
    fixed_js = "document.getElementById('action-btn').addEventListener('click', () => { alert('clicked'); });"

    # Stub the bedrock client to return a "fixed" canvas
    mock_response = mock_bedrock_response(<<~TEXT)
      ```html
      #{fixed_html}
      ```
      ```javascript
      #{fixed_js}
      ```
      ```css
      .btn { color: blue; }
      ```
    TEXT

    mock_client = mock('bedrock_client')
    mock_client.stubs(:converse).returns(mock_response)
    @service.stubs(:bedrock_client).returns(mock_client)

    validated = @service.send(:validate_and_fix_canvas, original)

    # Should return the fixed version since it resolved the unwired button
    assert_includes validated[:js], 'addEventListener'
    assert_includes validated[:html], 'action-btn'
  end

  test 'validate_and_fix returns original when AI fix does not improve' do
    original = {
      html: '<button class="btn">Unwired</button>',
      js: '',
      css: ''
    }

    # Stub bedrock to return equally bad code (still unwired)
    mock_response = mock_bedrock_response(<<~TEXT)
      ```html
      <button class="btn">Still Unwired</button>
      ```
      ```javascript
      console.log("still no handler");
      ```
      ```css
      .btn {}
      ```
    TEXT

    mock_client = mock('bedrock_client')
    mock_client.stubs(:converse).returns(mock_response)
    @service.stubs(:bedrock_client).returns(mock_client)

    validated = @service.send(:validate_and_fix_canvas, original)

    # Should return original since fix didn't help
    assert_equal original[:html], validated[:html]
  end

  test 'validate_and_fix returns original when AI fix raises error' do
    original = {
      html: '<button class="btn">Unwired</button>',
      js: '',
      css: ''
    }

    mock_client = mock('bedrock_client')
    mock_client.stubs(:converse).raises(StandardError.new("Bedrock timeout"))
    @service.stubs(:bedrock_client).returns(mock_client)

    validated = @service.send(:validate_and_fix_canvas, original)

    # Should return original gracefully
    assert_equal original[:html], validated[:html]
  end

  # ══════════════════════════════════════════════════════════════
  # CANVAS QUALITY VALIDATION — ai_fix_canvas_issues
  # ══════════════════════════════════════════════════════════════

  test 'ai_fix builds prompt with all issue types' do
    issues = [
      { type: :unwired_button, detail: 'class="btn"' },
      { type: :dead_link, detail: 'href="#"' },
      { type: :unwired_form, detail: 'class="form"' },
      { type: :missing_modal, modal_id: 'editModal' },
      { type: :undefined_function, function: 'doStuff' },
      { type: :missing_element, element_id: 'data-table' }
    ]

    result = { html: '<div>test</div>', js: 'var x = 1;', css: '.x {}' }

    captured_messages = nil
    mock_response = mock_bedrock_response("```html\n<div>fixed</div>\n```\n```javascript\nvar x = 2;\n```\n```css\n.x {}\n```")

    mock_client = mock('bedrock_client')
    mock_client.expects(:converse).with do |params|
      captured_messages = params[:messages]
      true
    end.returns(mock_response)
    @service.stubs(:bedrock_client).returns(mock_client)

    @service.send(:ai_fix_canvas_issues, result, issues)

    # Verify the prompt contains issue descriptions
    prompt_text = captured_messages.first[:content].first[:text]
    assert_includes prompt_text, 'UNWIRED BUTTON'
    assert_includes prompt_text, 'DEAD LINK'
    assert_includes prompt_text, 'UNWIRED FORM'
    assert_includes prompt_text, 'MISSING MODAL'
    assert_includes prompt_text, 'UNDEFINED FUNCTION'
    assert_includes prompt_text, 'MISSING ELEMENT'
    assert_includes prompt_text, 'doStuff'
    assert_includes prompt_text, 'editModal'
    assert_includes prompt_text, 'data-table'
  end

  test 'ai_fix returns parsed canvas response' do
    issues = [{ type: :unwired_button, detail: 'class="btn"' }]
    result = { html: '<button class="btn">X</button>', js: '', css: '' }

    mock_response = mock_bedrock_response(<<~TEXT)
      ```html
      <button id="x-btn" class="btn">X</button>
      ```
      ```javascript
      document.getElementById('x-btn').addEventListener('click', () => {});
      ```
      ```css
      .btn { cursor: pointer; }
      ```
    TEXT

    mock_client = mock('bedrock_client')
    mock_client.stubs(:converse).returns(mock_response)
    @service.stubs(:bedrock_client).returns(mock_client)

    fixed = @service.send(:ai_fix_canvas_issues, result, issues)
    assert_includes fixed[:html], 'x-btn'
    assert_includes fixed[:js], 'addEventListener'
    assert_includes fixed[:css], 'cursor'
  end

  test 'ai_fix uses low temperature for precise corrections' do
    issues = [{ type: :unwired_button, detail: 'class="btn"' }]
    result = { html: '<button class="btn">X</button>', js: '', css: '' }

    mock_response = mock_bedrock_response("```html\n<div></div>\n```\n```javascript\n\n```\n```css\n\n```")

    mock_client = mock('bedrock_client')
    mock_client.expects(:converse).with do |params|
      params[:inference_config][:temperature] == 0.2
    end.returns(mock_response)
    @service.stubs(:bedrock_client).returns(mock_client)

    @service.send(:ai_fix_canvas_issues, result, issues)
  end

  test 'canvas_fix_system_prompt includes technical context' do
    prompt = @service.send(:canvas_fix_system_prompt)
    assert_includes prompt, 'Bootstrap 5'
    assert_includes prompt, 'module-canvas'
    assert_includes prompt, 'CSRF'
    assert_includes prompt, 'html'
    assert_includes prompt, 'javascript'
    assert_includes prompt, 'css'
  end

  # ══════════════════════════════════════════════════════════════
  # CANVAS QUALITY VALIDATION — static templates pass validation
  # ══════════════════════════════════════════════════════════════

  test 'static list template passes quality validation' do
    result = @service.send(:generate_static, @app_module, 'list', @fields, [])
    issues = @service.send(:analyze_canvas_quality, result[:html], result[:js])
    assert_empty issues, "Static list template should have 0 quality issues but found: #{issues.inspect}"
  end

  test 'static kanban template passes quality validation' do
    result = @service.send(:generate_static, @app_module, 'kanban', @fields, [])
    issues = @service.send(:analyze_canvas_quality, result[:html], result[:js])
    assert_empty issues, "Static kanban template should have 0 quality issues but found: #{issues.inspect}"
  end

  test 'static form template passes quality validation' do
    result = @service.send(:generate_static, @app_module, 'form', @fields, [])
    issues = @service.send(:analyze_canvas_quality, result[:html], result[:js])
    assert_empty issues, "Static form template should have 0 quality issues but found: #{issues.inspect}"
  end

  test 'static detail template passes quality validation' do
    result = @service.send(:generate_static, @app_module, 'detail', @fields, [])
    issues = @service.send(:analyze_canvas_quality, result[:html], result[:js])
    assert_empty issues, "Static detail template should have 0 quality issues but found: #{issues.inspect}"
  end

  test 'static dashboard template passes quality validation' do
    result = @service.send(:generate_static, @app_module, 'dashboard', @fields, [])
    issues = @service.send(:analyze_canvas_quality, result[:html], result[:js])
    assert_empty issues, "Static dashboard template should have 0 quality issues but found: #{issues.inspect}"
  end

  test 'static calendar template passes quality validation' do
    result = @service.send(:generate_static, @app_module, 'calendar', @fields, [])
    issues = @service.send(:analyze_canvas_quality, result[:html], result[:js])
    assert_empty issues, "Static calendar template should have 0 quality issues but found: #{issues.inspect}"
  end

  # ══════════════════════════════════════════════════════════════
  # CONSTANTS
  # ══════════════════════════════════════════════════════════════

  test 'MAX_QUALITY_ISSUES_FOR_FIX is defined' do
    assert_equal 10, CanvasGeneratorService::MAX_QUALITY_ISSUES_FOR_FIX
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

  # Helper to build a mock Bedrock response structure
  def mock_bedrock_response(text_content)
    content_block = stub(text: text_content)
    content_block.stubs(:respond_to?).with(:text).returns(true)

    message = stub(content: [content_block])
    output = stub(message: message)
    stub(output: output)
  end
end
