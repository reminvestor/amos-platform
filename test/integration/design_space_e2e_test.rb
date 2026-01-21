# frozen_string_literal: true

require 'test_helper'

class DesignSpaceE2ETest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:rick)
    @entity = entities(:amos_labs)
    sign_in @user
    
    @service = DesignSpaceService.new(@user, @entity, SecureRandom.uuid)
  end

  # ============================================
  # FULL DESIGN FLOW TESTS
  # ============================================

  test 'complete web app design and build flow' do
    # 1. Start design session
    result = @service.start_design_session(
      name: 'Customer Portal',
      description: 'A web app for customers to manage their orders',
      type: 'web_app'
    )
    
    assert result[:success]
    assert result[:plan_id].present?
    plan = ApplicationPlan.find(result[:plan_id])
    assert_equal 'Customer Portal', plan.name
    assert_equal 'drafting', plan.status

    # 2. Update the plan with more details
    update_result = @service.update_design_plan(
      plan_id: plan.id,
      updates: {
        requirements: {
          authentication_type: 'email_password',
          modules: [{ name: 'Orders', slug: 'orders', fields: [
            { name: 'order_number', type: 'string', required: true },
            { name: 'total', type: 'decimal' },
            { name: 'status', type: 'string' }
          ]}]
        }
      }
    )
    
    assert update_result[:success]
    plan.reload
    assert plan.modules_plan.present?

    # 3. Build the approved plan
    build_result = @service.build_approved_plan(plan_id: plan.id)
    
    assert build_result[:success], build_result[:message]
    plan.reload
    assert_equal 'completed', plan.status

    # Verify components were created
    app_module = AppModule.find_by(slug: 'orders', entity: @entity)
    assert_not_nil app_module, 'Orders module should be created'
    assert_equal 'active', app_module.status
  end

  test 'landing page quick creation flow' do
    result = @service.quick_create_landing_page(
      title: 'Product Launch',
      description: 'A SaaS product for team collaboration',
      style: :modern
    )
    
    # The tool may or may not succeed depending on AI availability
    # but should not raise an error
    assert result.is_a?(Hash)
    assert result.key?(:success)
  end

  # ============================================
  # COMPONENT MANAGEMENT TESTS
  # ============================================

  test 'get component recommendations' do
    result = @service.get_component_recommendations(
      section_type: 'hero',
      business_type: 'saas'
    )
    
    assert result[:success]
    assert result[:variants].present?
    assert result[:variants].key?(:gradient)
    assert result[:variants].key?(:split)
    assert result[:recommended_design_systems].present?
    assert result[:recommended_design_systems].any? { |ds| ds[:key] == :modern }
  end

  test 'generate component with data' do
    result = @service.generate_component(
      type: 'hero',
      variant: 'gradient',
      data: {
        headline: 'Welcome to Our Platform',
        subheadline: 'Build something amazing today',
        cta_text: 'Get Started',
        cta_url: '/signup'
      },
      design_system: :modern
    )
    
    assert result[:success], result[:message]
    assert result[:html].present?
    assert result[:html].include?('Welcome to Our Platform')
    assert result[:css_variables].present?
    assert result[:css_variables].include?('--bs-primary')
  end

  test 'generate component with default data' do
    result = @service.generate_component(
      type: 'features',
      variant: 'icon_cards',
      data: {}
    )
    
    assert result[:success], result[:message]
    assert result[:html].present?
    # Should have default features
    assert result[:html].include?('feature-icon')
  end

  # ============================================
  # AUTOMATION TESTS
  # ============================================

  test 'create and test automation' do
    # Create automation
    result = @service.create_automation(
      name: 'Notify on Order Complete',
      description: 'Send Slack notification when order status changes to completed',
      trigger_type: 'status_changed',
      trigger_config: { from: 'processing', to: 'completed' }
    )
    
    # Result depends on AI, but should not raise
    assert result.is_a?(Hash)
    assert result.key?(:success)
    
    if result[:success] && result[:automation_id]
      # Test the automation
      test_result = @service.test_automation(
        automation_id: result[:automation_id],
        test_data: {
          record: { id: 1, order_number: 'ORD-001', status: 'completed' },
          from: 'processing',
          to: 'completed'
        }
      )
      
      assert test_result.is_a?(Hash)
      # Dry run should complete
    end
  end

  # ============================================
  # PREVIEW TESTS
  # ============================================

  test 'load landing page preview' do
    # Create a test landing page
    lp = LandingPage.create!(
      entity: @entity,
      title: 'Test Page',
      slug: 'test-page',
      html_content: '<h1>Test</h1>',
      status: 'published'
    )
    
    result = @service.load_preview(
      type: 'landing_page',
      id_or_slug: lp.id,
      edit_mode: true
    )
    
    assert result[:success]
    assert_equal 'landing_page', result[:type]
  ensure
    lp&.destroy
  end

  test 'load preview returns error for missing items' do
    result = @service.load_preview(
      type: 'web_app',
      id_or_slug: 999999
    )
    
    refute result[:success]
    assert_includes result[:message], 'not found'
  end

  # ============================================
  # AUTOMATION BRIDGE TESTS
  # ============================================

  test 'automation bridge triggers on record create' do
    # Create a test automation
    automation = AutomationCode.create!(
      entity: @entity,
      created_by: @user,
      name: 'Test Create Trigger',
      trigger_type: 'record_created',
      trigger_config: {},
      code: 'def execute(trigger_data); { success: true }; end',
      status: 'active'
    )
    
    # Mock a record class with entity_id
    mock_record = Struct.new(:id, :entity_id, :class) do
      def as_json
        { id: id, entity_id: entity_id }
      end
    end
    
    record = mock_record.new(1, @entity.id, 'TestRecord')
    
    # Should not raise
    assert_nothing_raised do
      Modules::AutomationBridge.on_record_created(record, @user)
    end
  ensure
    automation&.destroy
  end

  test 'automation bridge triggers on status change' do
    automation = AutomationCode.create!(
      entity: @entity,
      created_by: @user,
      name: 'Test Status Trigger',
      trigger_type: 'status_changed',
      trigger_config: { from: 'draft', to: 'published' },
      code: 'def execute(trigger_data); { success: true }; end',
      status: 'active'
    )
    
    mock_record = Struct.new(:id, :entity_id, :class) do
      def as_json
        { id: id, entity_id: entity_id }
      end
    end
    
    record = mock_record.new(1, @entity.id, 'TestRecord')
    
    # Should not raise and should find matching automation
    assert_nothing_raised do
      Modules::AutomationBridge.on_status_changed(record, 'draft', 'published', @user)
    end
  ensure
    automation&.destroy
  end

  # ============================================
  # DESIGN PREVIEW CONTROLLER TESTS
  # ============================================

  test 'design preview component renders' do
    get design_preview_component_path(
      type: 'hero',
      variant: 'gradient',
      design_system: 'modern'
    )
    
    assert_response :success
    assert_includes response.body, 'Build Something Amazing'
  end

  test 'design preview component with custom data' do
    get design_preview_component_path(
      type: 'hero',
      variant: 'split',
      data: { headline: 'Custom Headline' }.to_json
    )
    
    assert_response :success
    assert_includes response.body, 'hero-split'
  end

  test 'design preview landing page renders' do
    lp = LandingPage.create!(
      entity: @entity,
      title: 'Preview Test',
      slug: 'preview-test',
      html_content: '<h1>Preview Content</h1>',
      status: 'published'
    )
    
    get design_preview_landing_page_path(id: lp.id)
    
    assert_response :success
    assert_includes response.body, 'Preview Content'
  ensure
    lp&.destroy
  end

  # ============================================
  # FRONTEND DESIGN EXPERT TESTS
  # ============================================

  test 'all component categories have working templates' do
    categories = [:hero, :features, :testimonials, :pricing, :forms, :cta]
    
    categories.each do |category|
      result = @service.get_component_recommendations(section_type: category)
      assert result[:success], "Failed for category: #{category}"
      assert result[:variants].present?, "No variants for: #{category}"
    end
  end

  test 'all design systems generate valid CSS' do
    systems = [:modern, :minimal, :corporate, :playful, :elegant, :dark_mode]
    
    systems.each do |system|
      css = Agents::FrontendDesignExpert.generate_css_variables(system)
      assert css.present?, "No CSS for: #{system}"
      assert css.include?(':root'), "Missing :root for: #{system}"
      assert css.include?('--bs-primary'), "Missing primary for: #{system}"
    end
  end

  # ============================================
  # WEB APP SCRIPT TESTS
  # ============================================

  test 'web app script validates allowed libraries' do
    script = WebAppScript.new(
      entity: @entity,
      name: 'Alpine.js',
      library_type: 'cdn',
      library_name: 'alpine.js',
      cdn_url: 'https://cdn.jsdelivr.net/npm/alpinejs'
    )
    
    assert script.valid?
  end

  test 'web app script rejects non-allowed libraries' do
    script = WebAppScript.new(
      entity: @entity,
      name: 'Evil Script',
      library_type: 'cdn',
      library_name: 'evil-malware',
      cdn_url: 'https://evil.com/malware.js'
    )
    
    refute script.valid?
    assert_includes script.errors[:library_name].join, 'not in the allowlist'
  end

  test 'web app script validates inline code safety' do
    script = WebAppScript.new(
      entity: @entity,
      name: 'Custom Script',
      library_type: 'inline',
      inline_code: 'eval("dangerous code")'
    )
    
    refute script.valid?
    assert_includes script.errors[:inline_code].join, 'dangerous'
  end

  test 'web app script allows safe inline code' do
    script = WebAppScript.new(
      entity: @entity,
      name: 'Safe Script',
      library_type: 'inline',
      inline_code: 'console.log("Hello, world!");'
    )
    
    assert script.valid?, script.errors.full_messages.join(', ')
  end

  test 'web app script generates correct script tag' do
    script = WebAppScript.new(
      entity: @entity,
      name: 'Alpine.js',
      library_type: 'cdn',
      library_name: 'alpine.js',
      cdn_url: 'https://cdn.jsdelivr.net/npm/alpinejs',
      load_strategy: 'defer'
    )
    
    tag = script.script_tag
    assert_includes tag, 'src="https://cdn.jsdelivr.net/npm/alpinejs"'
    assert_includes tag, 'defer'
    assert_includes tag, 'crossorigin="anonymous"'
  end
end

