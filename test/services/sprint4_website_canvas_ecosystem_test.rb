# frozen_string_literal: true

require 'test_helper'

class Sprint4WebsiteCanvasEcosystemTest < ActiveSupport::TestCase
  fixtures :entities, :users

  setup do
    @entity = entities(:one)
    @user = users(:one)
  end

  # ══════════════════════════════════════════════════════════════
  # LIQUID TEMPLATE RENDERER — BASIC RENDERING
  # ══════════════════════════════════════════════════════════════

  test 'LiquidTemplateRenderer renders simple variables' do
    renderer = Modules::LiquidTemplateRenderer.new(entity: @entity)
    result = renderer.render(
      template_string: '<h1>{{ title }}</h1>',
      page_data: { 'title' => 'Hello World' }
    )
    assert_includes result, '<h1>Hello World</h1>'
  end

  test 'LiquidTemplateRenderer renders for loops' do
    renderer = Modules::LiquidTemplateRenderer.new(entity: @entity)
    result = renderer.render(
      template_string: '{% for item in items %}<p>{{ item }}</p>{% endfor %}',
      module_data: { 'items' => %w[Apple Banana Cherry] }
    )
    assert_includes result, '<p>Apple</p>'
    assert_includes result, '<p>Banana</p>'
    assert_includes result, '<p>Cherry</p>'
  end

  test 'LiquidTemplateRenderer renders conditionals' do
    renderer = Modules::LiquidTemplateRenderer.new(entity: @entity)
    result = renderer.render(
      template_string: '{% if show_banner %}<div>Banner</div>{% endif %}',
      page_data: { 'show_banner' => true }
    )
    assert_includes result, '<div>Banner</div>'
  end

  test 'LiquidTemplateRenderer handles empty template gracefully' do
    renderer = Modules::LiquidTemplateRenderer.new(entity: @entity)
    result = renderer.render(template_string: '', page_data: {})
    assert_equal '', result
  end

  test 'LiquidTemplateRenderer handles nil template gracefully' do
    renderer = Modules::LiquidTemplateRenderer.new(entity: @entity)
    result = renderer.render(template_string: nil, page_data: {})
    assert_equal '', result
  end

  test 'LiquidTemplateRenderer handles syntax errors gracefully' do
    renderer = Modules::LiquidTemplateRenderer.new(entity: @entity)
    result = renderer.render(
      template_string: '{% for item in %}broken{% endfor %}',
      page_data: {}
    )
    assert_includes result, 'Template error'
  end

  test 'LiquidTemplateRenderer provides global helpers' do
    renderer = Modules::LiquidTemplateRenderer.new(entity: @entity)
    result = renderer.render(
      template_string: '{{ current_year }} {{ entity_name }}',
      page_data: {}
    )
    assert_includes result, Time.current.year.to_s
    assert_includes result, @entity.name
  end

  # ══════════════════════════════════════════════════════════════
  # LIQUID CUSTOM FILTERS
  # ══════════════════════════════════════════════════════════════

  test 'currency filter formats numbers' do
    renderer = Modules::LiquidTemplateRenderer.new(entity: @entity)
    result = renderer.render(
      template_string: '{{ price | currency }}',
      page_data: { 'price' => 29.99 }
    )
    assert_includes result, '$29.99'
  end

  test 'currency filter handles custom symbol' do
    renderer = Modules::LiquidTemplateRenderer.new(entity: @entity)
    result = renderer.render(
      template_string: '{{ price | currency: "€" }}',
      page_data: { 'price' => 15.50 }
    )
    assert_includes result, '€15.50'
  end

  test 'status_badge filter creates bootstrap badge' do
    renderer = Modules::LiquidTemplateRenderer.new(entity: @entity)
    result = renderer.render(
      template_string: '{{ status | status_badge }}',
      page_data: { 'status' => 'active' }
    )
    assert_includes result, 'badge bg-success'
    assert_includes result, 'active'
  end

  test 'status_badge uses correct colors for different statuses' do
    renderer = Modules::LiquidTemplateRenderer.new(entity: @entity)

    # danger statuses
    result = renderer.render(template_string: '{{ s | status_badge }}', page_data: { 's' => 'urgent' })
    assert_includes result, 'bg-danger'

    # warning
    result = renderer.render(template_string: '{{ s | status_badge }}', page_data: { 's' => 'pending' })
    assert_includes result, 'bg-warning'

    # secondary
    result = renderer.render(template_string: '{{ s | status_badge }}', page_data: { 's' => 'draft' })
    assert_includes result, 'bg-secondary'
  end

  test 'format_date filter formats dates' do
    renderer = Modules::LiquidTemplateRenderer.new(entity: @entity)
    result = renderer.render(
      template_string: '{{ d | format_date }}',
      page_data: { 'd' => '2026-02-08' }
    )
    assert_includes result, 'Feb 08, 2026'
  end

  test 'default filter provides fallback' do
    renderer = Modules::LiquidTemplateRenderer.new(entity: @entity)
    result = renderer.render(
      template_string: '{{ missing | default: "N/A" }}',
      page_data: {}
    )
    assert_includes result, 'N/A'
  end

  test 'json filter serializes data' do
    renderer = Modules::LiquidTemplateRenderer.new(entity: @entity)
    result = renderer.render(
      template_string: '{{ data | json }}',
      page_data: { 'data' => { 'key' => 'value' } }
    )
    assert_includes result, '"key"'
    assert_includes result, '"value"'
  end

  # ══════════════════════════════════════════════════════════════
  # MODULE RECORD DROP
  # ══════════════════════════════════════════════════════════════

  test 'ModuleRecordDrop exposes hash values via liquid_method_missing' do
    record = { 'name' => 'Test', 'status' => 'active' }
    drop = Modules::ModuleRecordDrop.new(OpenStruct.new(record))
    assert_equal 'Test', drop.liquid_method_missing('name')
    assert_equal 'active', drop.liquid_method_missing('status')
  end

  test 'ModuleRecordDrop to_s returns name' do
    drop = Modules::ModuleRecordDrop.new(OpenStruct.new(name: 'Widget'))
    assert_equal 'Widget', drop.to_s
  end

  # ══════════════════════════════════════════════════════════════
  # WEBSITE TEMPLATE GENERATOR — LIST PAGE
  # ══════════════════════════════════════════════════════════════

  test 'WebsiteTemplateGenerator generates list page with Liquid syntax' do
    generator = WebsiteTemplateGenerator.new
    fields = [
      { 'name' => 'title', 'type' => 'string', 'required' => true },
      { 'name' => 'status', 'type' => 'select', 'options' => %w[draft published] },
      { 'name' => 'price', 'type' => 'decimal' }
    ]
    result = generator.generate(page_type: 'list', module_name: 'Products', module_slug: 'products', fields: fields)
    assert_includes result, '{% for item in products %}'
    assert_includes result, '{{ item.title }}'
    assert_includes result, '{% endfor %}'
    assert_includes result, 'Products'
  end

  test 'WebsiteTemplateGenerator list page uses status_badge for select fields' do
    generator = WebsiteTemplateGenerator.new
    fields = [{ 'name' => 'status', 'type' => 'select' }]
    result = generator.generate(page_type: 'list', module_name: 'Tasks', module_slug: 'tasks', fields: fields)
    assert_includes result, 'status_badge'
  end

  test 'WebsiteTemplateGenerator list page uses currency for decimal fields' do
    generator = WebsiteTemplateGenerator.new
    fields = [{ 'name' => 'amount', 'type' => 'decimal' }]
    result = generator.generate(page_type: 'list', module_name: 'Invoices', module_slug: 'invoices', fields: fields)
    assert_includes result, 'currency'
  end

  # ══════════════════════════════════════════════════════════════
  # WEBSITE TEMPLATE GENERATOR — DETAIL PAGE
  # ══════════════════════════════════════════════════════════════

  test 'WebsiteTemplateGenerator generates detail page with Liquid' do
    generator = WebsiteTemplateGenerator.new
    fields = [
      { 'name' => 'name', 'type' => 'string' },
      { 'name' => 'description', 'type' => 'text' },
      { 'name' => 'status', 'type' => 'select' }
    ]
    result = generator.generate(page_type: 'detail', module_name: 'Articles', module_slug: 'articles', fields: fields)
    assert_includes result, '{{ record.name }}'
    assert_includes result, '{% if record %}'
    assert_includes result, 'breadcrumb'
  end

  # ══════════════════════════════════════════════════════════════
  # WEBSITE TEMPLATE GENERATOR — FORM PAGE
  # ══════════════════════════════════════════════════════════════

  test 'WebsiteTemplateGenerator generates form page with fields' do
    generator = WebsiteTemplateGenerator.new
    fields = [
      { 'name' => 'title', 'type' => 'string', 'required' => true },
      { 'name' => 'body', 'type' => 'text' },
      { 'name' => 'priority', 'type' => 'select', 'options' => %w[low medium high] }
    ]
    result = generator.generate(page_type: 'form', module_name: 'Tickets', module_slug: 'tickets', fields: fields)
    assert_includes result, 'submission-form'
    assert_includes result, "name='title'"
    assert_includes result, 'textarea'
    assert_includes result, 'form-select'
    assert_includes result, '/api/modules/tickets'
  end

  # ══════════════════════════════════════════════════════════════
  # WEBSITE TEMPLATE GENERATOR — HOMEPAGE
  # ══════════════════════════════════════════════════════════════

  test 'WebsiteTemplateGenerator generates homepage with recent items' do
    generator = WebsiteTemplateGenerator.new
    fields = [{ 'name' => 'name', 'type' => 'string' }]
    result = generator.generate(page_type: 'homepage', module_name: 'Products', module_slug: 'products', fields: fields)
    assert_includes result, 'hero'
    assert_includes result, '{% for item in products'
    assert_includes result, 'limit:6'
    assert_includes result, '{{ site_name'
  end

  # ══════════════════════════════════════════════════════════════
  # WEBSITE TEMPLATE GENERATOR — LANDING PAGE
  # ══════════════════════════════════════════════════════════════

  test 'WebsiteTemplateGenerator generates landing page' do
    generator = WebsiteTemplateGenerator.new
    result = generator.generate(page_type: 'landing', module_name: 'Events', module_slug: 'events', fields: [])
    assert_includes result, '{{ title'
    assert_includes result, 'Browse'
    assert_includes result, 'Search'
    assert_includes result, 'Contact'
  end

  # ══════════════════════════════════════════════════════════════
  # WEBSITE PAGE — LIQUID DETECTION
  # ══════════════════════════════════════════════════════════════

  test 'WebsitePage liquid_template? detects liquid tags' do
    website = create_test_website
    page = WebsitePage.new(website: website, entity: @entity, name: 'Test', slug: 'test',
                           html_content: '{% for item in items %}{{ item }}{% endfor %}')
    assert page.liquid_template?
  end

  test 'WebsitePage liquid_template? returns false for plain HTML' do
    website = create_test_website
    page = WebsitePage.new(website: website, entity: @entity, name: 'Test', slug: 'test',
                           html_content: '<div>Hello</div>')
    refute page.liquid_template?
  end

  test 'WebsitePage liquid_template? returns false for blank content' do
    website = create_test_website
    page = WebsitePage.new(website: website, entity: @entity, name: 'Test', slug: 'test',
                           html_content: nil)
    refute page.liquid_template?
  end

  # ══════════════════════════════════════════════════════════════
  # WEBSITE PAGE — CONTENT BLOCKS WITH MODULE CANVAS
  # ══════════════════════════════════════════════════════════════

  test 'render_block handles module_canvas type' do
    website = create_test_website
    page = create_test_page(website)
    app_module = create_test_module('canvas_embed_test')
    
    canvas = ModuleCanvas.create!(
      app_module: app_module,
      entity: @entity,
      name: 'Embedded Dashboard',
      slug: 'canvas_embed_test_dash',
      canvas_type: 'dashboard',
      html_content: '<div class="dashboard">Dashboard Content</div>',
      js_content: 'console.log("dash");',
      css_content: '.dashboard { color: blue; }',
      data_sources: []
    )

    block = { 'type' => 'module_canvas', 'data' => { 'canvas_id' => canvas.id } }
    rendered = page.send(:render_block, block)
    assert_includes rendered, 'Dashboard Content'
    assert_includes rendered, 'console.log("dash")'
    assert_includes rendered, '.dashboard { color: blue; }'
  end

  test 'render_block handles missing canvas gracefully' do
    website = create_test_website
    page = create_test_page(website)
    
    block = { 'type' => 'module_canvas', 'data' => { 'canvas_id' => 999999 } }
    rendered = page.send(:render_block, block)
    assert_includes rendered, 'Canvas not found'
  end

  # ══════════════════════════════════════════════════════════════
  # AUTOMATION ACTION REGISTRY — NEW MODULE ACTIONS
  # ══════════════════════════════════════════════════════════════

  test 'AutomationActionRegistry includes module-aware actions' do
    actions = AutomationActionRegistry::ACTIONS
    assert actions.key?('update_module_record')
    assert actions.key?('create_module_record')
    assert actions.key?('notify_on_module_event')
  end

  test 'update_module_record action has correct required config' do
    config = AutomationActionRegistry::ACTIONS['update_module_record']
    assert_includes config[:required_config], 'module_slug'
    assert_includes config[:required_config], 'field'
    assert_includes config[:required_config], 'value'
  end

  test 'create_module_record action has correct required config' do
    config = AutomationActionRegistry::ACTIONS['create_module_record']
    assert_includes config[:required_config], 'module_slug'
    assert_includes config[:required_config], 'field_values'
  end

  test 'notify_on_module_event action has correct required config' do
    config = AutomationActionRegistry::ACTIONS['notify_on_module_event']
    assert_includes config[:required_config], 'module_slug'
    assert_includes config[:required_config], 'message'
  end

  test 'generate_code works for update_module_record' do
    code = AutomationActionRegistry.generate_code(
      action: 'update_module_record',
      action_config: { 'module_slug' => 'tasks', 'field' => 'status', 'value' => 'done' },
      trigger: 'status_changed',
      name: 'Mark Task Done'
    )
    assert_includes code, 'def execute(trigger_data)'
    assert_includes code, 'tasks'
    assert_includes code, 'status'
    assert_includes code, 'done'
    assert_includes code, 'DynamicModelLoader'
  end

  test 'generate_code works for create_module_record' do
    code = AutomationActionRegistry.generate_code(
      action: 'create_module_record',
      action_config: { 'module_slug' => 'tickets', 'field_values' => { 'status' => 'new', 'priority' => 'medium' } },
      trigger: 'webhook',
      name: 'Auto Create Ticket'
    )
    assert_includes code, 'def execute(trigger_data)'
    assert_includes code, 'tickets'
    assert_includes code, 'DynamicModelLoader'
    assert_includes code, 'create!'
  end

  test 'generate_code works for notify_on_module_event' do
    code = AutomationActionRegistry.generate_code(
      action: 'notify_on_module_event',
      action_config: { 'module_slug' => 'orders', 'message' => 'New order received!' },
      trigger: 'record_created',
      name: 'Order Notification'
    )
    assert_includes code, 'def execute(trigger_data)'
    assert_includes code, 'orders'
    assert_includes code, 'New order received!'
    assert_includes code, 'AgentWorkItem'
  end

  test 'available_actions includes new module actions' do
    actions = AutomationActionRegistry.available_actions
    action_names = actions.map { |a| a[:action] }
    assert_includes action_names, 'update_module_record'
    assert_includes action_names, 'create_module_record'
    assert_includes action_names, 'notify_on_module_event'
  end

  # ══════════════════════════════════════════════════════════════
  # WEBSITE BUILDER SERVICE — LIQUID TEMPLATE GENERATION
  # ══════════════════════════════════════════════════════════════

  test 'WebsiteBuilderService generates Liquid templates for dynamic pages' do
    app_module = create_test_module('products')
    app_module.update!(metadata: {
      'schema' => {
        'fields' => [
          { 'name' => 'name', 'field_type' => 'string' },
          { 'name' => 'price', 'field_type' => 'decimal' },
          { 'name' => 'status', 'field_type' => 'select' }
        ]
      }
    })
    
    service = WebsiteBuilderService.new(entity: @entity, user: @user)
    website = service.create_website({
      name: 'Product Store',
      slug: 'product_store',
      pages: [
        { name: 'Home', slug: 'index', template: 'homepage', is_homepage: true },
        { name: 'Browse Products', slug: 'browse', template: 'list', is_dynamic: true, module_slug: 'products' },
        { name: 'Product Detail', slug: 'detail', template: 'detail', is_dynamic: true, module_slug: 'products' }
      ]
    })
    
    browse_page = website.website_pages.find_by(slug: 'browse')
    assert_not_nil browse_page
    assert browse_page.is_dynamic
    # Dynamic pages should have Liquid templates
    assert browse_page.liquid_template?, "Browse page should have Liquid template content"
    assert_includes browse_page.html_content, '{% for item in products %}'

    detail_page = website.website_pages.find_by(slug: 'detail')
    assert_not_nil detail_page
    assert detail_page.liquid_template?
    assert_includes detail_page.html_content, '{{ record.'
  end

  # ══════════════════════════════════════════════════════════════
  # MODULE CANVAS — to_canvas_response WITH JS/CSS
  # ══════════════════════════════════════════════════════════════

  test 'ModuleCanvas to_canvas_response includes js and css' do
    app_module = create_test_module('response_check')
    canvas = ModuleCanvas.create!(
      app_module: app_module,
      entity: @entity,
      name: 'Rich Canvas',
      slug: 'response_check_list',
      canvas_type: 'data_grid',
      html_content: '<div>Rich</div>',
      js_content: 'alert("hello");',
      css_content: '.x { margin: 0; }',
      data_sources: []
    )
    
    response = canvas.to_canvas_response
    assert_equal 'Rich Canvas', response[:title]
    assert_equal 'alert("hello");', response[:js_content]
    assert_equal '.x { margin: 0; }', response[:css_content]
  end

  # ══════════════════════════════════════════════════════════════
  # APPLICATION BUILD SERVICE — AUTOMATION CREATION
  # ══════════════════════════════════════════════════════════════

  test 'build service map_workflow_trigger maps correctly' do
    plan = create_test_plan
    service = ApplicationBuildService.new(plan)
    
    assert_equal 'status_changed', service.send(:map_workflow_trigger, 'status_change')
    assert_equal 'record_created', service.send(:map_workflow_trigger, 'record_created')
    assert_equal 'field_changed', service.send(:map_workflow_trigger, 'field_changed')
    assert_equal 'schedule', service.send(:map_workflow_trigger, 'schedule')
    assert_equal 'webhook', service.send(:map_workflow_trigger, 'webhook')
    assert_equal 'manual', service.send(:map_workflow_trigger, 'unknown')
  end

  test 'build service resolve_workflow_action maps action strings' do
    plan = create_test_plan
    service = ApplicationBuildService.new(plan)
    
    assert_equal 'notify_on_module_event', service.send(:resolve_workflow_action, 'notify_team')
    assert_equal 'notify_on_module_event', service.send(:resolve_workflow_action, 'alert_admin')
    assert_equal 'update_module_record', service.send(:resolve_workflow_action, 'update_field')
    assert_equal 'notify_user', service.send(:resolve_workflow_action, 'send_email')
    assert_equal 'call_webhook', service.send(:resolve_workflow_action, 'call_api')
    assert_equal 'notify_on_module_event', service.send(:resolve_workflow_action, nil)
  end

  test 'build service generate_fallback_automation_code produces valid Ruby' do
    plan = create_test_plan
    service = ApplicationBuildService.new(plan)
    
    code = service.send(:generate_fallback_automation_code, { 'name' => 'Test Flow' })
    assert_includes code, 'def execute(trigger_data)'
    assert_includes code, 'Test Flow'
    assert_includes code, 'success: true'
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

  def create_test_website(name: 'Test Site')
    Website.create!(
      entity: @entity,
      created_by: @user,
      name: name,
      slug: name.parameterize,
      status: 'draft'
    )
  end

  def create_test_page(website, name: 'Test Page', slug: 'test-page')
    WebsitePage.create!(
      website: website,
      entity: @entity,
      name: name,
      slug: slug,
      template: 'content',
      status: 'draft'
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
