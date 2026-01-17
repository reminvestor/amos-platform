# frozen_string_literal: true

require 'test_helper'
require 'ripper'

class AutomationRecipesTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @entity = entities(:one)
  end

  # ============================================
  # RECIPE STRUCTURE TESTS
  # ============================================

  test 'all recipes have required fields' do
    AutomationRecipes.all.each do |recipe|
      assert recipe[:id].present?, "Recipe missing ID"
      assert recipe[:name].present?, "Recipe #{recipe[:id]} missing name"
      assert recipe[:description].present?, "Recipe #{recipe[:id]} missing description"
      assert recipe[:category].present?, "Recipe #{recipe[:id]} missing category"
      assert recipe[:trigger_type].present?, "Recipe #{recipe[:id]} missing trigger_type"
      assert recipe[:code_template].present?, "Recipe #{recipe[:id]} missing code_template"
      assert recipe[:required_inputs].is_a?(Array), "Recipe #{recipe[:id]} required_inputs should be array"
    end
  end

  test 'all recipe code templates are valid Ruby' do
    AutomationRecipes.all.each do |recipe|
      code = recipe[:code_template]
      
      # Replace placeholders with dummy values for syntax check
      recipe[:required_inputs].each do |input|
        placeholder = "{{#{input[:name]}}}"
        code = code.gsub(placeholder, 'test_value')
      end
      
      # Also replace any remaining placeholders
      code = code.gsub(/\{\{[^}]+\}\}/, 'placeholder_value')
      
      # Use Ripper to check syntax
      sexp = Ripper.sexp(code)
      assert sexp.present?, "Recipe #{recipe[:id]} has invalid Ruby syntax"
    end
  end

  test 'recipes cover all expected categories' do
    categories = AutomationRecipes.categories
    
    assert_includes categories, :notifications
    assert_includes categories, :data
    assert_includes categories, :integrations
    assert_includes categories, :workflows
    assert_includes categories, :forms
  end

  # ============================================
  # RECIPE RETRIEVAL TESTS
  # ============================================

  test 'all returns all recipes as flat list' do
    recipes = AutomationRecipes.all
    
    assert recipes.is_a?(Array)
    assert recipes.size >= 10, "Should have at least 10 recipes"
    
    # All should have IDs
    assert recipes.all? { |r| r[:id].present? }
  end

  test 'find returns specific recipe' do
    recipe = AutomationRecipes.find('slack_on_status_change')
    
    assert_not_nil recipe
    assert_equal 'Slack on Status Change', recipe[:name]
    assert_equal 'status_changed', recipe[:trigger_type]
  end

  test 'find returns nil for unknown recipe' do
    recipe = AutomationRecipes.find('nonexistent_recipe')
    assert_nil recipe
  end

  test 'by_category returns recipes for category' do
    notification_recipes = AutomationRecipes.by_category(:notifications)
    
    assert notification_recipes.is_a?(Array)
    assert notification_recipes.size >= 2
    assert notification_recipes.all? { |r| r[:category] == 'Notifications' }
  end

  # ============================================
  # RECIPE APPLICATION TESTS
  # ============================================

  test 'apply creates automation from recipe' do
    result = AutomationRecipes.apply(
      recipe_id: 'slack_on_status_change',
      entity: @entity,
      user: @user,
      inputs: {
        from_status: 'draft',
        to_status: 'published',
        slack_channel: '#content'
      }
    )
    
    assert result[:success], result[:error]
    assert result[:automation].is_a?(AutomationCode)
    
    automation = result[:automation]
    assert_equal 'Slack on Status Change', automation.name
    assert_equal 'status_changed', automation.trigger_type
    assert_equal 'draft', automation.status # Should be draft until tested
    assert automation.code.include?('#content'), 'Slack channel should be substituted'
    assert automation.code.include?('published'), 'Status should be substituted'
  end

  test 'apply uses default values when inputs not provided' do
    result = AutomationRecipes.apply(
      recipe_id: 'slack_on_status_change',
      entity: @entity,
      user: @user,
      inputs: {} # No inputs, should use defaults
    )
    
    assert result[:success], result[:error]
    
    automation = result[:automation]
    # Should have default channel '#general'
    assert automation.code.include?('#general')
  end

  test 'apply attaches automation to module when provided' do
    # Create a test module
    app_module = AppModule.create!(
      entity: @entity,
      name: 'Test Module',
      slug: 'test-module',
      status: 'active'
    )
    
    result = AutomationRecipes.apply(
      recipe_id: 'email_on_create',
      entity: @entity,
      user: @user,
      inputs: { to_email: 'test@example.com' },
      app_module: app_module
    )
    
    assert result[:success]
    assert_equal app_module.id, result[:automation].app_module_id
  ensure
    # Must delete automation first due to foreign key
    result[:automation]&.destroy if result&.dig(:automation)
    app_module&.destroy
  end

  test 'apply returns error for unknown recipe' do
    result = AutomationRecipes.apply(
      recipe_id: 'nonexistent',
      entity: @entity,
      user: @user
    )
    
    refute result[:success]
    assert_equal 'Recipe not found', result[:error]
  end

  # ============================================
  # SUGGESTION TESTS
  # ============================================

  test 'suggest_for_module returns relevant recipes' do
    app_module = AppModule.new(
      entity: @entity,
      name: 'Tasks',
      slug: 'tasks',
      metadata: { 'archetype' => 'project_management' }
    )
    
    suggestions = AutomationRecipes.suggest_for_module(app_module)
    
    assert suggestions.is_a?(Array)
    assert suggestions.size >= 2
    
    # Should include SLA reminder for project management
    assert suggestions.any? { |r| r[:id] == 'sla_reminder' }, 'Should suggest SLA reminder'
  end

  test 'suggest_for_module returns generic suggestions for unknown archetype' do
    app_module = AppModule.new(
      entity: @entity,
      name: 'Custom',
      slug: 'custom',
      metadata: {}
    )
    
    suggestions = AutomationRecipes.suggest_for_module(app_module)
    
    assert suggestions.is_a?(Array)
    assert suggestions.size >= 2
    
    # Should always include status change notification
    assert suggestions.any? { |r| r[:id] == 'slack_on_status_change' }
  end

  # ============================================
  # SPECIFIC RECIPE TESTS
  # ============================================

  test 'approval_workflow recipe has correct structure' do
    recipe = AutomationRecipes.find('approval_workflow')
    
    assert_not_nil recipe
    assert_equal 'status_changed', recipe[:trigger_type]
    assert recipe[:trigger_config_template][:to].present?
    assert recipe[:code_template].include?('notify_role')
    assert recipe[:code_template].include?('send_slack_message')
  end

  test 'webhook_on_event recipe has correct structure' do
    recipe = AutomationRecipes.find('webhook_on_event')
    
    assert_not_nil recipe
    assert_equal 'record_created', recipe[:trigger_type]
    assert recipe[:required_inputs].any? { |i| i[:name] == 'webhook_url' }
    assert recipe[:code_template].include?('http_post')
  end

  test 'process_form_submission recipe has correct structure' do
    recipe = AutomationRecipes.find('process_form_submission')
    
    assert_not_nil recipe
    assert_equal 'form_submit', recipe[:trigger_type]
    assert recipe[:code_template].include?('create_record')
    assert recipe[:code_template].include?('send_email')
  end
end

