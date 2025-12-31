# frozen_string_literal: true

# ValidateModuleTool
#
# Platform Factory tool that validates a complete module
# by testing all its components.
#
class Tools::ValidateModuleTool < Tools::BaseTool
  def self.metadata
    {
      name: 'validate_module',
      description: 'Validates a complete module by testing all its components: models, canvases, tools, and webhooks. Returns a comprehensive test report.',
      category: 'platform_factory',
      input_schema: {
        type: 'object',
        properties: {
          module_slug: {
            type: 'string',
            description: 'Slug of the module to validate'
          },
          run_integration_tests: {
            type: 'boolean',
            description: 'Whether to run integration tests (slower but more thorough)'
          }
        },
        required: %w[module_slug]
      }
    }
  end

  def execute(args)
    log_execution(args)

    module_slug = get_arg(args, :module_slug)
    run_integration = get_arg(args, :run_integration_tests, false)

    return error_response('Module slug is required') if module_slug.blank?

    # Find the module
    app_module = AppModule.find_by(entity: entity, slug: module_slug)
    return error_response("Module not found: #{module_slug}") unless app_module

    # Update status
    app_module.start_testing!

    # Run validations
    results = {
      module: validate_module_definition(app_module),
      models: validate_models(app_module),
      canvases: validate_canvases(app_module),
      tools: validate_tools(app_module),
      webhooks: validate_webhooks(app_module)
    }

    # Run integration tests if requested
    if run_integration
      results[:integration] = run_integration_tests(app_module)
    end

    # Calculate overall status
    all_passed = results.values.all? { |r| r[:status] == 'pass' }
    has_warnings = results.values.any? { |r| r[:warnings]&.any? }

    # Update module with results
    app_module.record_test_results!(results)

    if all_passed
      app_module.mark_deployed! unless has_warnings
    else
      errors = results.values.flat_map { |r| r[:errors] || [] }
      app_module.mark_failed!(errors.join('; '))
    end

    success_response(
      module_slug: module_slug,
      overall_status: all_passed ? (has_warnings ? 'pass_with_warnings' : 'pass') : 'fail',
      results: results,
      summary: build_summary(results),
      next_step: all_passed ? 'Module is ready! Use activate! to make it live.' : 'Fix the errors and run validate_module again.'
    )
  end

  private

  def validate_module_definition(app_module)
    errors = []
    warnings = []

    # Check required fields
    errors << 'Module name is required' if app_module.name.blank?
    errors << 'Module slug is required' if app_module.slug.blank?

    # Check components
    if app_module.components.blank?
      warnings << 'Module has no components defined'
    end

    # Check for at least one canvas
    if app_module.module_canvases.empty?
      warnings << 'Module has no canvases - users won\'t be able to interact with it'
    end

    # Check for at least one model
    if app_module.module_codes.models.empty?
      warnings << 'Module has no data models - consider adding one if you need to store data'
    end

    {
      status: errors.empty? ? 'pass' : 'fail',
      errors: errors,
      warnings: warnings,
      checked: %w[name slug components canvases models]
    }
  end

  def validate_models(app_module)
    errors = []
    warnings = []
    validated = []

    app_module.module_codes.models.each do |model_code|
      result = validate_model(model_code)
      validated << { name: model_code.name, status: result[:status] }
      errors.concat(result[:errors].map { |e| "#{model_code.name}: #{e}" })
      warnings.concat(result[:warnings].map { |w| "#{model_code.name}: #{w}" })
    end

    {
      status: errors.empty? ? 'pass' : 'fail',
      errors: errors,
      warnings: warnings,
      models_validated: validated
    }
  end

  def validate_model(model_code)
    errors = []
    warnings = []

    # Validate syntax
    unless model_code.validated? || model_code.deployed?
      model_code.validate_syntax!
      if model_code.failed?
        errors << "Syntax error: #{model_code.validation_errors}"
      end
    end

    # Validate schema
    schema = model_code.schema_definition
    if schema.blank?
      warnings << 'No schema definition found'
    else
      # Check for entity_id (required for multi-tenancy)
      fields = schema['fields'] || schema[:fields] || []
      unless fields.any? { |f| f['name'] == 'entity_id' || f[:name] == 'entity_id' }
        warnings << 'Missing entity_id field - may have multi-tenancy issues'
      end

      # Check for indexes
      indexes = schema['indexes'] || schema[:indexes] || []
      if indexes.empty?
        warnings << 'No indexes defined - may have performance issues'
      end
    end

    {
      status: errors.empty? ? 'pass' : 'fail',
      errors: errors,
      warnings: warnings
    }
  end

  def validate_canvases(app_module)
    errors = []
    warnings = []
    validated = []

    app_module.module_canvases.each do |canvas|
      result = validate_canvas(canvas)
      validated << { name: canvas.name, status: result[:status] }
      errors.concat(result[:errors].map { |e| "#{canvas.name}: #{e}" })
      warnings.concat(result[:warnings].map { |w| "#{canvas.name}: #{w}" })
    end

    {
      status: errors.empty? ? 'pass' : 'fail',
      errors: errors,
      warnings: warnings,
      canvases_validated: validated
    }
  end

  def validate_canvas(canvas)
    errors = []
    warnings = []

    # Check HTML content
    if canvas.html_content.blank?
      errors << 'Canvas has no HTML content'
    else
      # Basic HTML validation
      unless canvas.html_content.include?('<div')
        warnings << 'Canvas HTML may be incomplete (no div elements found)'
      end
    end

    # Check data sources
    if canvas.data_sources.blank? && canvas.canvas_type.in?(%w[data_grid form])
      warnings << 'Canvas has no data sources - may not display any data'
    end

    {
      status: errors.empty? ? 'pass' : 'fail',
      errors: errors,
      warnings: warnings
    }
  end

  def validate_tools(app_module)
    tool_names = app_module.tools_list
    
    if tool_names.empty?
      return {
        status: 'pass',
        errors: [],
        warnings: ['No custom tools defined for this module'],
        tools_validated: []
      }
    end

    errors = []
    warnings = []
    validated = []

    tool_names.each do |tool_name|
      # Check if tool exists in catalog
      catalog = Tools::ToolCatalog.instance
      if catalog.get_tool(tool_name)
        validated << { name: tool_name, status: 'pass' }
      else
        # Check if it's a pending dynamic tool
        tool_def = ToolDefinition.find_by(name: tool_name, app_module: app_module)
        if tool_def
          validated << { name: tool_name, status: 'pending' }
          warnings << "Tool '#{tool_name}' is defined but not yet registered in catalog"
        else
          errors << "Tool '#{tool_name}' not found in catalog or module"
          validated << { name: tool_name, status: 'fail' }
        end
      end
    end

    {
      status: errors.empty? ? 'pass' : 'fail',
      errors: errors,
      warnings: warnings,
      tools_validated: validated
    }
  end

  def validate_webhooks(app_module)
    if app_module.module_webhooks.empty?
      return {
        status: 'pass',
        errors: [],
        warnings: [],
        webhooks_validated: []
      }
    end

    errors = []
    warnings = []
    validated = []

    app_module.module_webhooks.each do |webhook|
      result = validate_webhook(webhook)
      validated << { name: webhook.event_name, status: result[:status] }
      errors.concat(result[:errors].map { |e| "#{webhook.event_name}: #{e}" })
      warnings.concat(result[:warnings].map { |w| "#{webhook.event_name}: #{w}" })
    end

    {
      status: errors.empty? ? 'pass' : 'fail',
      errors: errors,
      warnings: warnings,
      webhooks_validated: validated
    }
  end

  def validate_webhook(webhook)
    errors = []
    warnings = []

    # Check target configuration
    case webhook.target_type
    when 'agent'
      unless AgentPlugin.exists?(id: webhook.target_id)
        errors << 'Target agent not found'
      end
    when 'tool'
      catalog = Tools::ToolCatalog.instance
      unless catalog.get_tool(webhook.target_tool)
        errors << "Target tool '#{webhook.target_tool}' not found"
      end
    end

    # Check authentication
    if webhook.auth_type == 'none'
      warnings << 'Webhook has no authentication - consider adding token or signature verification'
    end

    {
      status: errors.empty? ? 'pass' : 'fail',
      errors: errors,
      warnings: warnings
    }
  end

  def run_integration_tests(app_module)
    # TODO: Implement actual integration tests
    # For now, return a placeholder
    {
      status: 'skip',
      message: 'Integration tests not yet implemented',
      errors: [],
      warnings: []
    }
  end

  def build_summary(results)
    total_checks = 0
    passed = 0
    failed = 0
    warning_count = 0

    results.each do |_category, result|
      total_checks += 1
      case result[:status]
      when 'pass' then passed += 1
      when 'fail' then failed += 1
      end
      warning_count += (result[:warnings] || []).length
    end

    {
      total_checks: total_checks,
      passed: passed,
      failed: failed,
      warnings: warning_count,
      overall: failed.zero? ? (warning_count.zero? ? '✅ All checks passed' : '⚠️ Passed with warnings') : '❌ Some checks failed'
    }
  end
end


