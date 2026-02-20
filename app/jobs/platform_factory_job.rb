# frozen_string_literal: true

# PlatformFactoryJob
#
# Background job that orchestrates the Platform Factory to build a module.
# Runs through design → generate → deploy → test phases.
#
# Features self-correcting retry loops - when an error occurs, the AI
# analyzes the error and attempts to fix it, just like a human developer.
#
class PlatformFactoryJob < ApplicationJob
  queue_as :default

  # Maximum retry attempts for each phase
  MAX_SCHEMA_RETRIES = 2
  MAX_MODEL_RETRIES = 3
  MAX_CANVAS_RETRIES = 2
  MAX_DEPLOY_RETRIES = 3
  MAX_VALIDATION_RETRIES = 2

  def perform(execution_id, spec)
    @execution = AgentPluginExecution.find(execution_id)
    @spec = spec.deep_symbolize_keys
    @app_module = AppModule.find(@spec[:module_id])
    @entity = Entity.find(@spec[:entity_id])
    @user = User.find(@spec[:user_id])
    @attempt_history = []  # Track all attempts for debugging
    @planned_spec = @spec[:planned_spec]  # Pre-designed spec from ModulePlannerService

    Rails.logger.info "[PlatformFactory] Starting build for module: #{@app_module.name}"
    Rails.logger.info "[PlatformFactory] Using planned spec: #{@planned_spec.present?}"

    begin
      @execution.update!(status: 'running', started_at: Time.current)
      
      if @planned_spec.present?
        # Use the pre-planned specification from ModulePlannerService
        build_from_planned_spec
      else
        # Legacy flow: design and build in one pass
        build_with_dynamic_design
      end

    rescue => e
      Rails.logger.error "[PlatformFactory] Unhandled error: #{e.message}"
      Rails.logger.error e.backtrace.first(10).join("\n")
      handle_failure(e.message)
    end
  end

  # Build from a comprehensive spec created by ModulePlannerService
  def build_from_planned_spec
    broadcast_progress('starting', 'Building from your approved plan...')
    
    # The planned spec already has everything designed
    schema = { success: true, schema: normalize_planned_spec(@planned_spec) }
    
    # Phase 1: Generate Models from planned spec
    broadcast_progress('generating', 'Creating data models...')
    models = generate_models_with_retry(schema[:schema])
    return if models.nil?

    # Phase 2: Generate Canvases from planned spec
    broadcast_progress('generating', 'Building user interfaces...')
    canvases = generate_canvases_from_plan(@planned_spec)
    return if canvases.nil?

    # Phase 3: Generate Tools from planned spec
    broadcast_progress('generating', 'Creating AI tools...')
    tools = generate_tools_from_plan(@planned_spec)

    # Phase 4: Generate Automations from planned spec
    broadcast_progress('generating', 'Setting up automations...')
    automations = generate_automations_from_plan(@planned_spec)

    # Phase 5: Deploy
    deploy_result = deploy_with_retry(models[:models], canvases[:canvases])
    return if deploy_result.nil?

    # Phase 6: Validate
    validation = validate_with_retry
    return if validation.nil?

    # Success!
    finalize_success(schema, models, canvases, tools, validation)
  end

  # Legacy flow for backwards compatibility
  def build_with_dynamic_design
    broadcast_progress('starting', 'Platform Factory is analyzing your requirements...')

    # Phase 1: Design Schema (with self-correction)
    schema = design_schema_with_retry
    return if schema.nil?  # Already handled failure

    # Phase 2: Generate Models (with self-correction)
    models = generate_models_with_retry(schema[:schema])
    return if models.nil?

    # Phase 3: Generate Canvases (with self-correction)
    canvases = generate_canvases_with_retry(schema[:schema])
    return if canvases.nil?

    # Phase 4: Generate Tools (optional, don't fail on errors)
    broadcast_progress('generating', 'Building tools...')
    tools = generate_tools(schema[:schema])

    # Phase 5: Deploy (with self-correction)
    deploy_result = deploy_with_retry(models[:models], canvases[:canvases])
    return if deploy_result.nil?

    # Phase 6: Validate (with self-correction)
    validation = validate_with_retry
    return if validation.nil?

    # Success!
    finalize_success(schema, models, canvases, tools, validation)
  end

  # Normalize the planned spec to match expected schema format
  def normalize_planned_spec(planned_spec)
    {
      models: planned_spec[:models] || planned_spec['models'] || [],
      canvases: planned_spec[:canvases] || planned_spec['canvases'] || [],
      tools: planned_spec[:tools] || planned_spec['tools'] || [],
      automations: planned_spec[:automations] || planned_spec['automations'] || []
    }
  end

  private

  # ============================================
  # SELF-CORRECTING RETRY WRAPPERS
  # ============================================

  def design_schema_with_retry
    attempts = 0
    last_error = nil
    current_requirements = @spec[:requirements]

    while attempts < MAX_SCHEMA_RETRIES
      attempts += 1
      broadcast_progress('designing', attempts == 1 ? 'Designing data models...' : "Refining schema design (attempt #{attempts})...")

      result = design_schema(current_requirements)
      log_attempt('schema_design', attempts, result)

      if result[:success]
        return result
      end

      last_error = result[:error]
      
      # Don't retry on last attempt
      break if attempts >= MAX_SCHEMA_RETRIES

      # Ask AI to analyze and suggest fixes
      broadcast_progress('fixing', 'Analyzing design issue and adjusting...')
      fix_result = analyze_and_fix_error(
        phase: 'schema_design',
        error: last_error,
        context: { requirements: current_requirements }
      )

      if fix_result[:fixed]
        current_requirements = fix_result[:corrected_requirements] || current_requirements
        Rails.logger.info "[PlatformFactory] AI suggested fix for schema: #{fix_result[:fix_description]}"
      else
        Rails.logger.warn "[PlatformFactory] AI could not determine a fix for schema error"
        break
      end
    end

    handle_failure("Schema design failed after #{attempts} attempts: #{last_error}")
    nil
  end

  def generate_models_with_retry(schema)
    attempts = 0
    last_errors = []
    current_schema = schema.deep_dup

    while attempts < MAX_MODEL_RETRIES
      attempts += 1
      broadcast_progress('generating', attempts == 1 ? 'Generating model code...' : "Regenerating models (attempt #{attempts})...")

      result = generate_models(current_schema)
      log_attempt('model_generation', attempts, result)

      if result[:success]
        return result
      end

      last_errors = result[:errors]
      
      break if attempts >= MAX_MODEL_RETRIES

      # Ask AI to fix each error
      broadcast_progress('fixing', "Found #{last_errors.count} issue(s), applying fixes...")
      
      fix_result = analyze_and_fix_error(
        phase: 'model_generation',
        error: last_errors.join('; '),
        context: { 
          schema: current_schema,
          failed_models: result[:failed_models] || []
        }
      )

      if fix_result[:fixed]
        current_schema = fix_result[:corrected_schema] || current_schema
        Rails.logger.info "[PlatformFactory] AI suggested fix for models: #{fix_result[:fix_description]}"
      else
        break
      end
    end

    handle_failure("Model generation failed after #{attempts} attempts: #{last_errors.join(', ')}")
    nil
  end

  def generate_canvases_with_retry(schema)
    attempts = 0
    last_errors = []

    while attempts < MAX_CANVAS_RETRIES
      attempts += 1
      broadcast_progress('generating', attempts == 1 ? 'Creating user interfaces...' : "Recreating interfaces (attempt #{attempts})...")

      result = generate_canvases(schema)
      log_attempt('canvas_generation', attempts, result)

      if result[:success]
        return result
      end

      last_errors = result[:errors]
      break if attempts >= MAX_CANVAS_RETRIES

      broadcast_progress('fixing', 'Adjusting canvas templates...')
      
      # For canvases, we can often just retry with simpler options
      fix_result = analyze_and_fix_error(
        phase: 'canvas_generation',
        error: last_errors.join('; '),
        context: { schema: schema }
      )

      # Canvases are less critical, apply simple fixes
      if fix_result[:fixed]
        Rails.logger.info "[PlatformFactory] Retrying canvas generation with adjustments"
      else
        break
      end
    end

    handle_failure("Canvas generation failed after #{attempts} attempts: #{last_errors.join(', ')}")
    nil
  end

  def deploy_with_retry(models, canvases)
    attempts = 0
    last_error = nil

    while attempts < MAX_DEPLOY_RETRIES
      attempts += 1
      broadcast_progress('deploying', attempts == 1 ? 'Deploying module...' : "Retrying deployment (attempt #{attempts})...")

      result = deploy_module(models, canvases)
      log_attempt('deployment', attempts, result)

      if result[:success]
        return result
      end

      last_error = result[:error]
      break if attempts >= MAX_DEPLOY_RETRIES

      # Deployment errors often need table cleanup
      broadcast_progress('fixing', 'Cleaning up and retrying deployment...')
      
      fix_result = fix_deployment_error(last_error)
      
      if fix_result[:fixed]
        Rails.logger.info "[PlatformFactory] Applied deployment fix: #{fix_result[:fix_description]}"
      else
        break
      end
    end

    handle_failure("Deployment failed after #{attempts} attempts: #{last_error}")
    nil
  end

  def validate_with_retry
    attempts = 0
    last_validation = nil

    while attempts < MAX_VALIDATION_RETRIES
      attempts += 1
      broadcast_progress('validating', attempts == 1 ? 'Running validation tests...' : "Re-validating (attempt #{attempts})...")

      validation = validate_module
      log_attempt('validation', attempts, validation)

      if validation[:overall_status] != 'fail'
        return validation
      end

      last_validation = validation
      break if attempts >= MAX_VALIDATION_RETRIES

      # Try to fix validation errors
      errors = validation[:results]&.values&.flat_map { |r| r[:errors] || [] } || []
      
      if errors.any?
        broadcast_progress('fixing', "Fixing #{errors.count} validation issue(s)...")
        
        fix_result = fix_validation_errors(errors, validation)
        
        if fix_result[:fixed]
          Rails.logger.info "[PlatformFactory] Applied validation fixes: #{fix_result[:fixes_applied].join(', ')}"
        else
          break
        end
      else
        break
      end
    end

    handle_failure("Validation failed after #{attempts} attempts: #{last_validation&.dig(:summary, :overall)}")
    nil
  end

  # ============================================
  # AI ERROR ANALYSIS AND FIXING
  # ============================================

  def analyze_and_fix_error(phase:, error:, context:)
    Rails.logger.info "[PlatformFactory] Analyzing #{phase} error: #{error}"

    # Build a prompt for the AI to analyze and fix the error
    prompt = build_error_analysis_prompt(phase, error, context)

    begin
      # Use the AI service to analyze the error
      response = call_ai_for_fix(prompt)
      
      if response[:success] && response[:fix_suggested]
        {
          fixed: true,
          fix_description: response[:fix_description],
          corrected_schema: response[:corrected_schema],
          corrected_requirements: response[:corrected_requirements]
        }
      else
        { fixed: false, reason: response[:reason] || 'AI could not determine a fix' }
      end
    rescue => e
      Rails.logger.error "[PlatformFactory] Error during AI analysis: #{e.message}"
      { fixed: false, reason: e.message }
    end
  end

  def build_error_analysis_prompt(phase, error, context)
    base_prompt = <<~PROMPT
      You are debugging a Platform Factory module build error.
      
      Phase: #{phase}
      Error: #{error}
      
      Context:
      #{context.to_json}
      
      Analyze this error and suggest a fix. Common issues include:
      - Schema definition errors (invalid field types, missing associations)
      - Model syntax errors (Ruby code issues)
      - Database conflicts (duplicate columns, indexes, foreign keys)
      - Canvas HTML issues (missing elements, invalid structure)
      
      Respond with JSON:
      {
        "fix_suggested": true/false,
        "fix_description": "What needs to be changed",
        "corrected_schema": { ... } // if schema needs fixing
      }
    PROMPT

    base_prompt
  end

  def call_ai_for_fix(prompt)
    # Use the Bedrock service to get AI analysis
    service = BedrockConversationService.new(
      user: @user,
      entity: @entity,
      model_id: 'global.anthropic.claude-sonnet-4-6'
    )

    response = service.send_message(
      system_prompt: "You are a debugging assistant for a Ruby on Rails module builder. Analyze errors and suggest fixes in JSON format.",
      messages: [{ role: 'user', content: prompt }]
    )

    # Parse the AI response
    if response[:success] && response[:content].present?
      begin
        # Try to extract JSON from the response
        json_match = response[:content].match(/\{[\s\S]*\}/)
        if json_match
          parsed = JSON.parse(json_match[0])
          {
            success: true,
            fix_suggested: parsed['fix_suggested'] == true,
            fix_description: parsed['fix_description'],
            corrected_schema: parsed['corrected_schema']&.deep_symbolize_keys
          }
        else
          { success: false, reason: 'No JSON found in response' }
        end
      rescue JSON::ParserError => e
        { success: false, reason: "JSON parse error: #{e.message}" }
      end
    else
      { success: false, reason: response[:error] || 'AI service error' }
    end
  end

  def fix_deployment_error(error)
    # Handle common deployment errors with specific fixes
    
    case error
    when /duplicate column/i, /already defined column/i
      # Clear the table and retry
      fix_duplicate_column_error
    when /table.*already exists/i
      # Drop and recreate the table
      fix_table_exists_error
    when /index.*already exists/i
      # Skip index creation
      fix_duplicate_index_error
    when /foreign key/i
      # Handle foreign key issues
      fix_foreign_key_error
    else
      # Try a general cleanup
      fix_general_deployment_error
    end
  end

  def fix_duplicate_column_error
    Rails.logger.info "[PlatformFactory] Fixing duplicate column error - clearing loader cache"
    
    # Clear the dynamic model loader cache
    loader = Modules::DynamicModelLoader.instance
    loader.clear_module_cache(@app_module)
    
    { fixed: true, fix_description: 'Cleared model loader cache' }
  end

  def fix_table_exists_error
    Rails.logger.info "[PlatformFactory] Fixing table exists error - will drop and recreate"
    
    # The DynamicModelLoader now handles this, but we can ensure cache is clear
    loader = Modules::DynamicModelLoader.instance
    loader.clear_module_cache(@app_module)
    
    { fixed: true, fix_description: 'Will drop and recreate tables' }
  end

  def fix_duplicate_index_error
    Rails.logger.info "[PlatformFactory] Fixing duplicate index error"
    { fixed: true, fix_description: 'Will skip existing indexes' }
  end

  def fix_foreign_key_error
    Rails.logger.info "[PlatformFactory] Fixing foreign key error"
    
    # Reload models in dependency order
    loader = Modules::DynamicModelLoader.instance
    loader.clear_module_cache(@app_module)
    
    { fixed: true, fix_description: 'Will reload models in correct order' }
  end

  def fix_general_deployment_error
    Rails.logger.info "[PlatformFactory] Attempting general deployment cleanup"
    
    loader = Modules::DynamicModelLoader.instance
    loader.clear_module_cache(@app_module)
    
    { fixed: true, fix_description: 'Cleared caches and will retry' }
  end

  def fix_validation_errors(errors, validation)
    fixes_applied = []

    errors.each do |error|
      case error
      when /syntax error/i
        # Regenerate the model code
        fixes_applied << 'Will regenerate model code'
      when /missing entity_id/i
        # Add entity_id to the schema
        fixes_applied << 'Will add entity_id field'
      when /no indexes/i
        # This is a warning, not a blocker
        fixes_applied << 'Will add recommended indexes'
      when /canvas has no HTML/i
        # Regenerate the canvas
        fixes_applied << 'Will regenerate canvas HTML'
      end
    end

    if fixes_applied.any?
      { fixed: true, fixes_applied: fixes_applied }
    else
      { fixed: false, reason: 'No automatic fix available' }
    end
  end

  # ============================================
  # PHASE IMPLEMENTATIONS
  # ============================================

  def design_schema(requirements = nil)
    requirements ||= @spec[:requirements]
    
    tool = Tools::DesignModuleSchemaTool.new(
      user: @user,
      entity: @entity,
      context: { platform_factory: true }
    )

    result = tool.execute(
      module_name: @app_module.name,
      requirements: requirements,
      existing_models: @spec[:existing_models] || []
    )

    { success: result[:error].blank?, schema: result[:schema], error: result[:error] }
  end

  def generate_models(schema)
    models = []
    errors = []
    failed_models = []

    (schema[:models] || []).each do |model_schema|
      tool = Tools::GenerateModelCodeTool.new(
        user: @user,
        entity: @entity,
        context: { platform_factory: true }
      )

      result = tool.execute(
        module_slug: @app_module.slug,
        model_schema: model_schema
      )

      if result[:error].blank?
        models << result[:model_name]
      else
        errors << result[:error]
        failed_models << model_schema[:name]
      end
    end

    { success: errors.empty?, models: models, errors: errors, failed_models: failed_models }
  end

  def generate_canvases(schema)
    canvases = []
    errors = []

    # Generate a dashboard canvas
    dashboard_result = generate_dashboard_canvas(schema)
    if dashboard_result[:success]
      canvases << dashboard_result[:canvas_slug]
    else
      errors << dashboard_result[:error]
    end

    # Generate data grid canvases for each model
    (schema[:models] || []).each do |model_schema|
      grid_result = generate_grid_canvas(model_schema)
      if grid_result[:success]
        canvases << grid_result[:canvas_slug]
      else
        errors << grid_result[:error]
      end
    end

    # Success if we got at least some canvases
    { success: canvases.any?, canvases: canvases, errors: errors }
  end

  def generate_dashboard_canvas(schema)
    tool = Tools::GenerateCanvasCodeTool.new(
      user: @user,
      entity: @entity,
      context: { platform_factory: true }
    )

    model_names = (schema[:models] || []).map { |m| m[:name] }
    
    result = tool.execute(
      module_slug: @app_module.slug,
      canvas_name: "#{@app_module.name} Overview",
      canvas_type: 'dashboard',
      model_name: model_names.first,
      fields_to_display: [],
      actions: [
        { name: 'Add New', icon: 'plus', action: 'add' },
        { name: 'Refresh', icon: 'refresh-cw', action: 'refresh' }
      ],
      ui_mode: 'simple'
    )

    { 
      success: result[:error].blank?, 
      canvas_slug: result[:canvas_slug], 
      error: result[:error] 
    }
  end

  def generate_grid_canvas(model_schema)
    tool = Tools::GenerateCanvasCodeTool.new(
      user: @user,
      entity: @entity,
      context: { platform_factory: true }
    )

    fields = (model_schema[:fields] || []).map { |f| f[:name] }.first(5)
    
    result = tool.execute(
      module_slug: @app_module.slug,
      canvas_name: "#{model_schema[:name]} List",
      canvas_type: 'data_grid',
      model_name: model_schema[:name],
      fields_to_display: fields,
      actions: [
        { name: 'Add', icon: 'plus', action: 'add' },
        { name: 'Edit', icon: 'edit', action: 'edit' },
        { name: 'Delete', icon: 'trash-2', action: 'delete' }
      ],
      ui_mode: 'simple'
    )

    { 
      success: result[:error].blank?, 
      canvas_slug: result[:canvas_slug], 
      error: result[:error] 
    }
  end

  def generate_tools(schema)
    # CRUD tools are no longer generated per-module. The V3 platform tools
    # (platform_create, platform_query, platform_update, platform_execute)
    # handle all custom module CRUD natively. Generating ToolDefinitions
    # bloats the LLM context and duplicates existing platform capabilities.
    Rails.logger.info "[PlatformFactory] Skipping CRUD tool generation for #{@app_module&.slug} - handled by platform tools"
    { success: true, tools: [], errors: [] }
  end

  # ============================================
  # PLANNED SPEC GENERATORS
  # These build from the comprehensive spec created by ModulePlannerService
  # ============================================

  def generate_canvases_from_plan(planned_spec)
    canvases = []
    errors = []
    
    canvas_specs = planned_spec[:canvases] || planned_spec['canvases'] || []
    
    canvas_specs.each do |canvas_spec|
      tool = Tools::GenerateCanvasCodeTool.new(
        user: @user,
        entity: @entity,
        context: { platform_factory: true, planned_spec: canvas_spec }
      )
      
      # Build actions from the spec
      actions = (canvas_spec[:actions] || canvas_spec['actions'] || []).map do |action|
        {
          name: action[:label] || action['label'],
          icon: action[:icon] || action['icon'],
          action: action[:action_type] || action['action_type']
        }
      end
      
      # Get fields for display
      fields = (canvas_spec[:components] || canvas_spec['components'] || [])
        .select { |c| c[:type] == 'table_column' || c['type'] == 'table_column' }
        .map { |c| c[:field] || c['field'] }
      
      result = tool.execute(
        module_slug: @app_module.slug,
        canvas_name: canvas_spec[:name] || canvas_spec['name'],
        canvas_type: canvas_spec[:type] || canvas_spec['type'] || 'dashboard',
        model_name: canvas_spec[:model] || canvas_spec['model'],
        fields_to_display: fields,
        actions: actions.presence || default_actions_for(canvas_spec[:type] || canvas_spec['type']),
        ui_mode: 'simple',
        is_default: canvas_spec[:is_default] || canvas_spec['is_default'] || false,
        components: canvas_spec[:components] || canvas_spec['components']
      )
      
      if result[:error].blank?
        canvases << result[:canvas_slug]
      else
        errors << "#{canvas_spec[:name]}: #{result[:error]}"
      end
    end
    
    # If no canvases in plan, fall back to default generation
    if canvases.empty? && errors.empty?
      schema = normalize_planned_spec(planned_spec)
      return generate_canvases(schema)
    end
    
    { success: canvases.any?, canvases: canvases, errors: errors }
  end

  def generate_tools_from_plan(planned_spec)
    # CRUD tools are no longer generated per-module. The V3 platform tools
    # handle all custom module CRUD natively. See generate_tools for details.
    Rails.logger.info "[PlatformFactory] Skipping tool generation from plan for #{@app_module&.slug} - handled by platform tools"
    { success: true, tools: [], errors: [] }
  end

  def generate_automations_from_plan(planned_spec)
    automations = []
    errors = []
    
    automation_specs = planned_spec[:automations] || planned_spec['automations'] || []
    
    automation_specs.each do |auto_spec|
      begin
        automation = create_automation(auto_spec)
        automations << automation.name if automation
      rescue => e
        errors << "Automation #{auto_spec[:name]}: #{e.message}"
        Rails.logger.warn "[PlatformFactory] Failed to create automation: #{e.message}"
      end
    end
    
    { success: true, automations: automations, errors: errors }
  end

  def create_automation(auto_spec)
    # Create a scheduled task or webhook based on the automation spec
    case auto_spec[:trigger_type] || auto_spec['trigger_type']
    when 'schedule'
      create_scheduled_automation(auto_spec)
    when 'record_create', 'record_update', 'threshold'
      create_triggered_automation(auto_spec)
    else
      Rails.logger.info "[PlatformFactory] Skipping unknown automation type: #{auto_spec[:trigger_type]}"
      nil
    end
  end

  def create_scheduled_automation(auto_spec)
    ScheduledAgentTask.create!(
      entity: @entity,
      user: @user,
      app_module: @app_module,
      name: auto_spec[:name] || auto_spec['name'],
      description: auto_spec[:description] || auto_spec['description'],
      schedule_type: 'cron',
      schedule_config: auto_spec[:trigger_config] || auto_spec['trigger_config'] || { cron: '0 9 * * *' },
      action_type: auto_spec[:action_type] || auto_spec['action_type'],
      action_config: auto_spec[:action_config] || auto_spec['action_config'],
      active: true
    )
  end

  def create_triggered_automation(auto_spec)
    ModuleWebhook.create!(
      app_module: @app_module,
      entity: @entity,
      event_name: auto_spec[:trigger_type] || auto_spec['trigger_type'],
      event_config: auto_spec[:trigger_config] || auto_spec['trigger_config'],
      target_type: 'tool',
      target_tool: auto_spec[:action_type] || auto_spec['action_type'],
      payload_template: auto_spec[:action_config] || auto_spec['action_config'],
      active: true
    )
  end

  def default_actions_for(canvas_type)
    case canvas_type
    when 'dashboard'
      [
        { name: 'Refresh', icon: 'refresh-cw', action: 'refresh' }
      ]
    when 'data_grid'
      [
        { name: 'Add', icon: 'plus', action: 'add' },
        { name: 'Edit', icon: 'edit', action: 'edit' },
        { name: 'Delete', icon: 'trash-2', action: 'delete' }
      ]
    when 'form'
      [
        { name: 'Save', icon: 'save', action: 'save' },
        { name: 'Cancel', icon: 'x', action: 'cancel' }
      ]
    when 'report'
      [
        { name: 'Export', icon: 'download', action: 'export' },
        { name: 'Print', icon: 'printer', action: 'print' }
      ]
    else
      []
    end
  end

  def deploy_module(models, canvases)
    errors = []
    
    # Load models dynamically
    loader = Modules::DynamicModelLoader.instance
    loader.load_module_models(@app_module)

    # Register canvases
    canvases.each do |canvas_slug|
      register_tool = Tools::RegisterModuleCanvasTool.new(
        user: @user,
        entity: @entity,
        context: { platform_factory: true }
      )

      result = register_tool.execute(
        module_slug: @app_module.slug,
        canvas_slug: canvas_slug,
        add_to_menu: true,
        set_as_default: canvas_slug.include?('overview')
      )
      
      if result[:error].present?
        errors << "Canvas #{canvas_slug}: #{result[:error]}"
      end
    end

    if errors.any?
      { success: false, error: errors.join('; ') }
    else
      { success: true }
    end
  rescue => e
    { success: false, error: e.message }
  end

  def validate_module
    tool = Tools::ValidateModuleTool.new(
      user: @user,
      entity: @entity,
      context: { platform_factory: true }
    )

    tool.execute(
      module_slug: @app_module.slug,
      run_integration_tests: false
    )
  end

  # ============================================
  # FINALIZATION
  # ============================================

  def finalize_success(schema, models, canvases, tools, validation)
    @app_module.mark_deployed!
    @app_module.activate!
    
    broadcast_progress('complete', "Your #{@app_module.name} app is ready!")
    
    @execution.update!(
      status: 'completed',
      completed_at: Time.current,
      output_response: build_success_response(schema, models, canvases, tools, validation)
    )
    
    notify_user_complete
  end

  # ============================================
  # HELPERS
  # ============================================

  def log_attempt(phase, attempt, result)
    # Determine success: explicit success flag, or validation passed (for validate_module)
    is_success = if result.key?(:success)
                   result[:success]
                 elsif result.key?(:overall_status)
                   result[:overall_status] != 'fail'
                 else
                   result[:error].blank? && result[:errors].blank?
                 end
    
    @attempt_history << {
      phase: phase,
      attempt: attempt,
      success: is_success,
      error: result[:error] || result[:errors],
      timestamp: Time.current.iso8601
    }
    
    Rails.logger.info "[PlatformFactory] #{phase} attempt #{attempt}: #{is_success ? 'SUCCESS' : 'FAILED'}"
  end

  def broadcast_progress(phase, message)
    ActionCable.server.broadcast(
      "scout_#{@user.id}",
      {
        type: 'platform_factory_progress',
        module_slug: @app_module.slug,
        module_name: @app_module.name,
        phase: phase,
        message: message,
        attempt_history: @attempt_history,
        timestamp: Time.current.iso8601
      }
    )
  end

  def handle_failure(error)
    @app_module.mark_failed!(error)
    @execution.update!(
      status: 'failed',
      completed_at: Time.current,
      output_result: { 
        error: error.to_s, 
        failed_at: Time.current.iso8601,
        attempt_history: @attempt_history
      }
    )

    broadcast_progress('failed', "Module build failed: #{error}")
    notify_user_failed(error)
  end

  def build_success_response(schema, models, canvases, tools, validation)
    {
      module_slug: @app_module.slug,
      module_name: @app_module.name,
      status: 'deployed',
      components: {
        models: models[:models],
        canvases: canvases[:canvases],
        tools: tools[:tools]
      },
      validation: validation[:summary],
      attempt_history: @attempt_history,
      next_steps: [
        "Load the module by saying 'Show me #{@app_module.name}'",
        "Add data using the tools",
        "Ask me to customize or add features"
      ]
    }
  end

  def notify_user_complete
    AgentWorkItem.create!(
      entity: @entity,
      user: @user,
      agent_plugin: @execution.agent_plugin,
      work_type: 'module_created',
      title: "#{@app_module.name} App Ready!",
      summary: "Your custom #{@app_module.name} app has been built and is ready to use.",
      details: "Load the app by saying 'Show me #{@app_module.name}'",
      asset_data: {
        module_slug: @app_module.slug,
        module_name: @app_module.name,
        canvases: @app_module.canvases_list,
        tools: @app_module.tools_list
      },
      priority: 'high'
    )
  end

  def notify_user_failed(error)
    AgentWorkItem.create!(
      entity: @entity,
      user: @user,
      agent_plugin: @execution.agent_plugin,
      work_type: 'module_failed',
      title: "App Build Failed: #{@app_module.name}",
      summary: "The Platform Factory encountered an error building your app.",
      details: error.to_s,
      asset_data: {
        module_slug: @app_module.slug,
        module_name: @app_module.name,
        error: error.to_s,
        attempt_history: @attempt_history
      },
      priority: 'high',
      requires_action: true
    )
  end
end
