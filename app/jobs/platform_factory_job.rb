# frozen_string_literal: true

# PlatformFactoryJob
#
# Background job that orchestrates the Platform Factory to build a module.
# Runs through design → generate → deploy → test phases.
#
class PlatformFactoryJob < ApplicationJob
  queue_as :default

  def perform(execution_id, spec)
    @execution = AgentPluginExecution.find(execution_id)
    @spec = spec.deep_symbolize_keys
    @app_module = AppModule.find(@spec[:module_id])
    @entity = Entity.find(@spec[:entity_id])
    @user = User.find(@spec[:user_id])

    Rails.logger.info "[PlatformFactory] Starting build for module: #{@app_module.name}"

    begin
      @execution.update!(status: 'running', started_at: Time.current)
      broadcast_progress('starting', 'Platform Factory is analyzing your requirements...')

      # Phase 1: Design Schema
      broadcast_progress('designing', 'Designing data models...')
      schema = design_schema
      return handle_failure('Schema design failed') unless schema[:success]

      # Phase 2: Generate Models
      broadcast_progress('generating', 'Generating model code...')
      models = generate_models(schema[:schema])
      return handle_failure('Model generation failed') unless models[:success]

      # Phase 3: Generate Canvases
      broadcast_progress('generating', 'Creating user interfaces...')
      canvases = generate_canvases(schema[:schema])
      return handle_failure('Canvas generation failed') unless canvases[:success]

      # Phase 4: Generate Tools
      broadcast_progress('generating', 'Building tools...')
      tools = generate_tools(schema[:schema])
      # Tools are optional, continue even if some fail

      # Phase 5: Deploy
      broadcast_progress('deploying', 'Deploying module...')
      deploy_result = deploy_module(models[:models], canvases[:canvases])
      return handle_failure('Deployment failed') unless deploy_result[:success]

      # Phase 6: Validate
      broadcast_progress('validating', 'Running validation tests...')
      validation = validate_module
      
      # Finalize
      if validation[:overall_status] != 'fail'
        @app_module.mark_deployed!
        broadcast_progress('complete', "Your #{@app_module.name} module is ready!")
        
        @execution.update!(
          status: 'completed',
          completed_at: Time.current,
          output_response: build_success_response(schema, models, canvases, tools, validation)
        )
        
        # Notify user
        notify_user_complete
      else
        handle_failure("Validation failed: #{validation[:summary][:overall]}")
      end

    rescue => e
      Rails.logger.error "[PlatformFactory] Error: #{e.message}"
      Rails.logger.error e.backtrace.first(10).join("\n")
      handle_failure(e.message)
    end
  end

  private

  # ============================================
  # PHASE IMPLEMENTATIONS
  # ============================================

  def design_schema
    tool = Tools::DesignModuleSchemaTool.new(
      user: @user,
      entity: @entity,
      context: { platform_factory: true }
    )

    result = tool.execute(
      module_name: @app_module.name,
      requirements: @spec[:requirements],
      existing_models: @spec[:existing_models] || []
    )

    { success: result[:error].blank?, schema: result[:schema], error: result[:error] }
  end

  def generate_models(schema)
    models = []
    errors = []

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
      end
    end

    { success: errors.empty?, models: models, errors: errors }
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

    { success: errors.count < schema[:models].count, canvases: canvases, errors: errors }
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
    tools = []
    errors = []

    (schema[:models] || []).each do |model_schema|
      # Generate CRUD tools for each model
      tool = Tools::GenerateToolDefinitionTool.new(
        user: @user,
        entity: @entity,
        context: { platform_factory: true }
      )

      result = tool.execute(
        module_slug: @app_module.slug,
        tool_name: "manage_#{model_schema[:name].underscore}",
        description: "Manage #{model_schema[:name]} records",
        tool_type: 'crud',
        model_name: model_schema[:name]
      )

      if result[:error].blank?
        tools.concat(result[:tools_created] || [])
      else
        errors << result[:error]
      end
    end

    { success: true, tools: tools, errors: errors }  # Tools are optional
  end

  def deploy_module(models, canvases)
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

      register_tool.execute(
        module_slug: @app_module.slug,
        canvas_slug: canvas_slug,
        add_to_menu: true,
        set_as_default: canvas_slug.include?('overview')
      )
    end

    { success: true }
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
  # HELPERS
  # ============================================

  def broadcast_progress(phase, message)
    ActionCable.server.broadcast(
      "scout_#{@user.id}",
      {
        type: 'platform_factory_progress',
        module_slug: @app_module.slug,
        module_name: @app_module.name,
        phase: phase,
        message: message,
        timestamp: Time.current.iso8601
      }
    )
  end

  def handle_failure(error)
    @app_module.mark_failed!(error)
    @execution.update!(
      status: 'failed',
      completed_at: Time.current,
      error_message: error
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
      next_steps: [
        "Load the module by saying 'Show me #{@app_module.name}'",
        "Add data using the tools",
        "Ask me to customize or add features"
      ]
    }
  end

  def notify_user_complete
    # Create a work item for the user
    AgentWorkItem.create!(
      entity: @entity,
      user: @user,
      agent_plugin: @execution.agent_plugin,
      work_item_type: 'module_complete',
      title: "#{@app_module.name} Module Ready!",
      summary: "Your custom #{@app_module.name} module has been built and is ready to use.",
      content: {
        module_slug: @app_module.slug,
        module_name: @app_module.name,
        canvases: @app_module.canvases_list,
        tools: @app_module.tools_list
      },
      priority: 'high',
      status: 'pending'
    )
  end

  def notify_user_failed(error)
    AgentWorkItem.create!(
      entity: @entity,
      user: @user,
      agent_plugin: @execution.agent_plugin,
      work_item_type: 'module_failed',
      title: "Module Build Failed: #{@app_module.name}",
      summary: "The Platform Factory encountered an error building your module.",
      content: {
        module_slug: @app_module.slug,
        module_name: @app_module.name,
        error: error
      },
      priority: 'high',
      status: 'pending'
    )
  end
end


