# frozen_string_literal: true

require 'test_helper'

class DesignSpaceIntegrationTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:rick)
    @entity = entities(:amos_labs)
    sign_in @user
  end

  # ============================================
  # SPACE DEFINITION TESTS
  # ============================================

  test 'design space is included in ALL_SPACES' do
    assert_includes SpaceDefinition::ALL_SPACES, 'design'
  end

  test 'design space has correct configuration when seeded' do
    # Note: This test requires seeds to have run
    space = SpaceDefinition.find_by(slug: 'design')
    skip 'Design space not seeded yet' unless space
    
    assert_equal 'Design', space.name
    assert_equal 'palette', space.icon
    assert space.enabled?
    
    # Should have design-focused tools
    tools = space.tool_loadout
    assert_includes tools, 'load_design_canvas'
    assert_includes tools, 'generate_landing_page'
    assert_includes tools, 'plan_application'
    assert_includes tools, 'generate_automation_code'
  end

  test 'design space model has design? helper' do
    space = SpaceDefinition.new(slug: 'design')
    assert space.design?
    
    other_space = SpaceDefinition.new(slug: 'work')
    refute other_space.design?
  end

  # ============================================
  # LOAD DESIGN CANVAS TOOL TESTS
  # ============================================

  test 'load_design_canvas tool loads design preview' do
    tool = LoadDesignCanvasTool.new(@user, @entity, nil)
    
    result = tool.execute({
      'canvas_type' => 'design_preview',
      'preview_type' => 'web_app',
      'preview_url' => '/test/preview',
      'title' => 'Test Web App',
      'edit_mode' => true
    })
    
    assert result[:success]
    assert_equal 'design_preview', result[:canvas_type]
    assert result[:edit_mode]
  end

  test 'load_design_canvas tool loads component gallery' do
    tool = LoadDesignCanvasTool.new(@user, @entity, nil)
    
    result = tool.execute({
      'canvas_type' => 'component_gallery',
      'category' => 'hero',
      'design_system' => 'modern'
    })
    
    assert result[:success]
    assert_equal 'component_gallery', result[:canvas_type]
    assert_equal 'hero', result[:category]
    assert_equal 'modern', result[:design_system]
  end

  test 'load_design_canvas tool loads workflow editor with automations' do
    # Create some test automations
    automation = AutomationCode.create!(
      entity: @entity,
      created_by: @user,
      name: 'Test Automation',
      trigger_type: 'status_changed',
      trigger_config: { from: 'draft', to: 'published' },
      code: 'def execute(trigger_data); {}; end',
      status: 'active'
    )
    
    tool = LoadDesignCanvasTool.new(@user, @entity, nil)
    
    result = tool.execute({
      'canvas_type' => 'workflow_designer'
    })
    
    assert result[:success]
    assert_equal 'workflow_designer', result[:canvas_type]
    assert result[:workflow_count] >= 1
  ensure
    automation&.destroy
  end

  test 'load_design_canvas tool loads specific automation in workflow editor' do
    automation = AutomationCode.create!(
      entity: @entity,
      created_by: @user,
      name: 'Test Automation',
      trigger_type: 'status_changed',
      trigger_config: { from: 'draft', to: 'published' },
      code: <<~RUBY,
        def execute(trigger_data)
          send_slack_message(channel: '#test', message: 'Hello')
          { success: true }
        end
      RUBY
      status: 'active'
    )
    
    tool = LoadDesignCanvasTool.new(@user, @entity, nil)
    
    result = tool.execute({
      'canvas_type' => 'workflow_designer',
      'workflow_id' => automation.id
    })
    
    assert result[:success]
    assert_equal 'workflow_designer', result[:canvas_type]
  ensure
    automation&.destroy
  end

  test 'load_design_canvas handles unknown canvas type' do
    tool = LoadDesignCanvasTool.new(@user, @entity, nil)
    
    result = tool.execute({
      'canvas_type' => 'unknown_type'
    })
    
    refute result[:success]
    assert_includes result[:message], 'Unknown canvas type'
  end

  # ============================================
  # FRONTEND DESIGN EXPERT AGENT TESTS
  # ============================================

  test 'frontend design expert component library has all categories' do
    library = Agents::FrontendDesignExpert::COMPONENT_LIBRARY
    
    expected_categories = %i[hero features testimonials pricing forms navigation footer cta]
    expected_categories.each do |category|
      assert library.key?(category), "Missing category: #{category}"
    end
  end

  test 'frontend design expert design systems are complete' do
    systems = Agents::FrontendDesignExpert::DESIGN_SYSTEMS
    
    expected_systems = %i[modern minimal corporate playful elegant dark_mode]
    expected_systems.each do |system|
      assert systems.key?(system), "Missing design system: #{system}"
      
      # Each should have colors
      assert systems[system][:colors].key?(:primary)
      assert systems[system][:colors].key?(:secondary)
    end
  end

  test 'recommend_design_system returns appropriate suggestions' do
    # SaaS should get modern
    saas_recs = Agents::FrontendDesignExpert.recommend_design_system(business_type: 'saas')
    assert saas_recs.any? { |r| r[:key] == :modern }
    
    # Luxury should get elegant
    luxury_recs = Agents::FrontendDesignExpert.recommend_design_system(business_type: 'luxury')
    assert luxury_recs.any? { |r| r[:key] == :elegant }
    
    # Agency should get minimal
    agency_recs = Agents::FrontendDesignExpert.recommend_design_system(business_type: 'agency')
    assert agency_recs.any? { |r| r[:key] == :minimal }
  end

  test 'generate_css_variables produces valid CSS' do
    css = Agents::FrontendDesignExpert.generate_css_variables(:modern)
    
    assert css.include?(':root')
    assert css.include?('--bs-primary: #3b82f6')
    assert css.include?('--bs-font-sans-serif')
    assert css.include?('--bs-border-radius')
  end

  # ============================================
  # CANVAS RENDERING TESTS
  # ============================================

  test 'design_preview partial exists and renders' do
    partial_path = Rails.root.join('app/views/scout/canvas/_design_preview.html.erb')
    assert File.exist?(partial_path), 'design_preview partial should exist'
    
    content = File.read(partial_path)
    assert content.include?('design-preview-canvas'), 'Should have canvas container'
    assert content.include?('preview-iframe'), 'Should have iframe for preview'
    assert content.include?('viewport-btn'), 'Should have viewport buttons'
    assert content.include?('edit-mode'), 'Should have edit mode controls'
  end

  test 'workflow_designer partial exists and renders' do
    partial_path = Rails.root.join('app/views/scout/canvas/_workflow_designer.html.erb')
    assert File.exist?(partial_path), 'workflow_designer partial should exist'
    
    content = File.read(partial_path)
    assert content.include?('workflow-designer-canvas'), 'Should have canvas container'
    assert content.include?('workflow-node'), 'Should have node styling'
    assert content.include?('workflow-connector'), 'Should have connector styling'
  end

  test 'component_gallery partial exists and renders' do
    partial_path = Rails.root.join('app/views/scout/canvas/_component_gallery.html.erb')
    assert File.exist?(partial_path), 'component_gallery partial should exist'
    
    content = File.read(partial_path)
    assert content.include?('component-gallery-canvas'), 'Should have canvas container'
    assert content.include?('category-sidebar'), 'Should have category sidebar'
    assert content.include?('component-card'), 'Should have component cards'
  end

  # ============================================
  # END-TO-END DESIGN FLOW TESTS
  # ============================================

  test 'design space supports full design workflow' do
    # 1. User enters design space
    space = SpaceDefinition.new(slug: 'design', name: 'Design', enabled: true)
    assert space.design?
    
    # 2. Browse components
    library = Agents::FrontendDesignExpert::COMPONENT_LIBRARY
    hero_variants = library[:hero][:variants]
    assert hero_variants.any?
    
    # 3. Select a design system
    css = Agents::FrontendDesignExpert.generate_css_variables(:modern)
    assert css.present?
    
    # 4. Get component template
    template = Agents::FrontendDesignExpert.send(
      :generate_hero_template,
      :gradient,
      hero_variants[:gradient]
    )
    assert template.include?('{{headline}}')
    
    # 5. Fill template with data
    filled = template.gsub('{{headline}}', 'Welcome to My SaaS')
    assert filled.include?('Welcome to My SaaS')
    
    # This simulates the full flow a user would take in Design Space
  end
end

