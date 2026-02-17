# frozen_string_literal: true

# ApplicationBuildService executes an approved ApplicationPlan
# and creates all the components (modules, agent, tools, integrations, etc.)
#
# The entire build is wrapped in a transaction - if anything fails,
# everything is rolled back and the plan is marked as failed.
#
# Usage:
#   service = ApplicationBuildService.new(plan)
#   result = service.execute!
#   # Returns { success: true, results: { ... } } or { success: false, error: "..." }
#
class ApplicationBuildService
  attr_reader :plan, :results, :progress_callback, :cancellation_check, :app

  # Phase percentage ranges for progress tracking
  # Each phase gets a slice of 0-100%
  PHASE_RANGES = {
    modules:         { start: 10, finish: 55 },
    agent:           { start: 55, finish: 62 },
    tools:           { start: 62, finish: 72 },
    integrations:    { start: 72, finish: 78 },
    workflows:       { start: 78, finish: 85 },
    scheduled_tasks: { start: 85, finish: 88 },
    webhooks:        { start: 88, finish: 91 },
    website:         { start: 91, finish: 97 },
    finalize:        { start: 97, finish: 100 }
  }.freeze

  def initialize(plan, progress_callback: nil, cancellation_check: nil)
    @plan = plan
    @results = {
      app: nil,
      modules: [],
      agent: nil,
      tools: [],
      integrations: [],
      workflows: [],
      scheduled_tasks: [],
      webhooks: [],
      website: nil,
      web_app: nil
    }
    @app = nil
    @progress_callback = progress_callback
    @cancellation_check = cancellation_check
    @current_phase = nil
  end
  
  # Resume a previously failed/paused build
  def self.resume!(plan, progress_callback: nil, cancellation_check: nil)
    new(plan, progress_callback: progress_callback, cancellation_check: cancellation_check).execute!
  end
  
  def execute!
    validate_plan!
    
    plan.start_build! unless plan.status == "building"
    emit_progress("Starting build for #{plan.name}...", percentage: 5, phase: "planning")
    
    begin
      # Phase 0: Create parent App record to group all modules
      create_parent_app!
      
      # Phase 1: Create Modules (data layer) — the heaviest phase
      run_phase(:modules) { build_modules! }
        
        # Phase 2: Create Agent (AI layer)
      run_phase(:agent) { build_agent! }
        
        # Phase 3: Create/Register Tools
      run_phase(:tools) { build_tools! }
        
        # Phase 4: Wire up Integrations
      run_phase(:integrations) { wire_integrations! }
        
        # Phase 5: Create Workflows
      run_phase(:workflows) { build_workflows! }
        
        # Phase 6: Create Scheduled Tasks
      run_phase(:scheduled_tasks) { build_scheduled_tasks! }
        
        # Phase 7: Create Webhooks / Hub Hooks
      run_phase(:webhooks) { build_webhooks! }
        
        # Phase 8: Create Website (if specified)
      run_phase(:website) { build_website! } if plan.has_website?
        
        # Phase 9: Complete
      run_phase(:finalize) { finalize_build! }
      
      { success: true, results: results, plan: plan.reload }
      
    rescue BuildCancelled => e
      handle_cancellation(e)
      { success: :partial, results: results, plan: plan.reload, message: e.message }

    rescue => e
      handle_failure(e)
      { success: false, error: e.message, plan: plan.reload }
    end
  end
  
  private
  
  # ============================================
  # VALIDATION
  # ============================================
  
  def validate_plan!
    # Allow approved, building (resume), and paused (resume) plans
    unless %w[approved building paused].include?(plan.status)
      raise BuildError, "Plan must be approved/building/paused before building (current status: #{plan.status})"
    end
    
    if plan.modules_spec.empty?
      raise BuildError, "Plan must have at least one module defined"
    end

    @resuming = %w[building paused].include?(plan.status)
    if @resuming
      Rails.logger.info "[ApplicationBuildService] Resuming build — completed phases: #{completed_phases.join(', ')}"
    end
  end
  
  # ============================================
  # BUILD PHASES
  # ============================================
  
  def create_parent_app!
    # Create a top-level App record to group all modules built from this plan
    base_slug = plan.name.parameterize.underscore
    slug = unique_slug(App, base_slug, plan.entity_id)

    @app = App.create!(
      entity_id: plan.entity_id,
      created_by: plan.created_by,
      name: plan.name,
      slug: slug,
      description: plan.plan_spec['description'] || "App built from plan: #{plan.name}",
      status: 'building',
      blueprint: plan.plan_spec,
      build_started_at: Time.current,
      metadata: { application_plan_id: plan.id }
    )
    
    results[:app] = {
      id: @app.id,
      name: @app.name,
      slug: @app.slug,
      status: @app.status
    }
    
    emit_progress("Created app '#{@app.name}' (ID: #{@app.id})", percentage: 8, phase: "app_creation")
  rescue => e
    Rails.logger.warn "[ApplicationBuildService] App record creation failed: #{e.message} — continuing without parent app"
    @app = nil
  end
  
  def build_modules!
    log_progress("Creating modules...")

    # Separate primary and sub-modules to ensure correct build order
    primary_specs = plan.modules_spec.select { |m| m['is_primary'] != false }
    sub_specs = plan.modules_spec.select { |m| m['is_primary'] == false }
    all_specs = primary_specs + sub_specs
    total = all_specs.length

    # Build primary modules first (parents must exist before children)
    primary_specs.each_with_index do |module_spec, idx|
      emit_phase_sub_progress(:modules, idx, total, "Creating #{module_spec['name']}...")
      build_single_module(module_spec)
    end

    # Build sub-modules with relationship wiring
    sub_specs.each_with_index do |module_spec, idx|
      overall_idx = primary_specs.length + idx
      emit_phase_sub_progress(:modules, overall_idx, total, "Creating #{module_spec['name']}...")
      build_single_module(module_spec)
    end

    # Wire associations between modules (after all tables exist)
    emit_phase_sub_progress(:modules, total, total, "Wiring module relationships...")
    wire_module_associations!

    log_progress("#{results[:modules].count} modules created (#{primary_specs.count} primary, #{sub_specs.count} sub-modules)")
  end
  
  def build_single_module(module_spec)
      app_module = create_module(module_spec)
      create_module_table(app_module, module_spec)
      create_module_canvases(app_module, module_spec)
      
      results[:modules] << {
        id: app_module.id,
        name: app_module.name,
      slug: app_module.slug,
      is_primary: module_spec['is_primary'] != false,
      relationship: module_spec['relationship']
    }

    log_progress("#{module_spec['name']} created")
  end
  
  def wire_module_associations!
    # Build a slug-to-module lookup from what we just created
    module_lookup = {}
    results[:modules].each do |mod_info|
      module_lookup[mod_info[:slug]] = mod_info
    end
    
    # Wire belongs_to relationships
    results[:modules].each do |mod_info|
      relationship = mod_info[:relationship]
      next unless relationship.present? && relationship['type'] == 'belongs_to'
      
      parent_slug = relationship['parent_slug']
      foreign_key = relationship['foreign_key']
      parent_info = module_lookup[parent_slug]
      
      next unless parent_info.present? && foreign_key.present?
      
      child_module = AppModule.find(mod_info[:id])
      parent_module = AppModule.find(parent_info[:id])
      
      # Add foreign key column to child table if not already there
      add_foreign_key_column(child_module, foreign_key)
      
      # Update the child module's model code with belongs_to association
      update_model_with_association(child_module, parent_module, 'belongs_to', foreign_key)
      
      # Update the parent module's model code with has_many association
      update_model_with_association(parent_module, child_module, 'has_many', foreign_key)
      
      # Store relationship metadata on both modules
      store_relationship_metadata(child_module, parent_module, foreign_key)
      
      log_progress("Wired #{child_module.name} belongs_to #{parent_module.name} (via #{foreign_key})")
    end
  end
  
  def add_foreign_key_column(child_module, foreign_key)
    table_name = child_module.slug.pluralize
    
    # Check if column already exists
    return if ActiveRecord::Base.connection.column_exists?(table_name, foreign_key)
    
    ActiveRecord::Base.connection.add_column(table_name, foreign_key, :bigint)
    ActiveRecord::Base.connection.add_index(table_name, foreign_key) rescue nil
  rescue ActiveRecord::StatementInvalid => e
    Rails.logger.warn "[ApplicationBuildService] Could not add FK column #{foreign_key} to #{table_name}: #{e.message}"
  end
  
  def update_model_with_association(module_record, related_module, association_type, foreign_key)
    module_code = module_record.module_codes.find_by(code_type: 'model')
    return unless module_code
    
    # Update schema_definition with the association
    schema_def = module_code.schema_definition || {}
    schema_def['associations'] ||= []
    
    assoc_entry = {
      'type' => association_type,
      'model' => related_module.slug.classify,
      'table' => related_module.slug.pluralize,
      'foreign_key' => foreign_key
    }
    
    # Only add if not already present
    unless schema_def['associations'].any? { |a| a['model'] == assoc_entry['model'] && a['type'] == assoc_entry['type'] }
      schema_def['associations'] << assoc_entry
    end
    
    # Regenerate model code with associations
    new_code = generate_model_code_with_associations(module_record, schema_def['associations'])
    
    module_code.update!(
      content: new_code,
      schema_definition: schema_def
    )
    
    # Reload the dynamic model to pick up new associations
    Modules::DynamicModelLoader.instance.load_model(module_code)
  end
  
  def generate_model_code_with_associations(app_module, associations)
    assoc_lines = (associations || []).map do |assoc|
      case assoc['type']
      when 'belongs_to'
        "  belongs_to :#{assoc['model'].underscore}, class_name: '#{assoc['model']}', foreign_key: '#{assoc['foreign_key']}', optional: true"
      when 'has_many'
        child_name = assoc['model'].underscore.pluralize
        "  has_many :#{child_name}, class_name: '#{assoc['model']}', foreign_key: '#{assoc['foreign_key']}', dependent: :nullify"
      else
        nil
      end
    end.compact.join("\n")
    
    <<~RUBY
      class #{app_module.slug.classify} < ApplicationRecord
        self.table_name = '#{app_module.slug.pluralize}'
        belongs_to :entity
      #{assoc_lines}
        scope :for_entity, ->(entity_id) { where(entity_id: entity_id) }
      end
    RUBY
  end
  
  def store_relationship_metadata(child_module, parent_module, foreign_key)
    # Update child module metadata
    child_meta = child_module.metadata || {}
    child_meta['relationships'] ||= []
    child_meta['relationships'] << {
      'type' => 'belongs_to',
      'parent_module_id' => parent_module.id,
      'parent_module_slug' => parent_module.slug,
      'foreign_key' => foreign_key
    }
    child_module.update!(metadata: child_meta)
    
    # Update parent module metadata
    parent_meta = parent_module.metadata || {}
    parent_meta['relationships'] ||= []
    parent_meta['relationships'] << {
      'type' => 'has_many',
      'child_module_id' => child_module.id,
      'child_module_slug' => child_module.slug,
      'foreign_key' => foreign_key
    }
    parent_module.update!(metadata: parent_meta)
  end
  
  def build_agent!
    return unless plan.has_agent?
    
    log_progress("Creating AI agent...")
    
    agent_spec = plan.agent_spec
    primary_module = AppModule.find(results[:modules].first[:id])
    
    agent = AgentPlugin.create!(
      entity_id: plan.entity_id,
      app_module: primary_module,
      name: agent_spec['name'],
      slug: agent_spec['slug'] || agent_spec['name'].parameterize.underscore,
      role: 'executor',
      description: agent_spec['description'],
      version: '1.0.0',
      status: 'active',
      agent_class: 'Agents::StandardPluginExecutor',
      priority: 50,
      configuration: {
        max_tokens: 4000,
        temperature: 0.7,
        auto_created: true,
        application_plan_id: plan.id
      },
      system_prompt: {
        prompt: generate_agent_prompt(agent_spec, primary_module)
      },
      capabilities_definition: {
        description: agent_spec['description'],
        capabilities: agent_spec['capabilities'] || [],
        personality: agent_spec['personality']
      }
    )
    
    # Link tools to agent
    link_tools_to_agent(agent)
    
    results[:agent] = {
      id: agent.id,
      name: agent.name,
      slug: agent.slug
    }
    
    log_progress("Agent '#{agent.name}' created")
  end
  
  def build_tools!
    log_progress("Registering tools...")
    
    # Create CRUD tools for each module
    results[:modules].each do |mod_info|
      app_module = AppModule.find(mod_info[:id])
      module_tools = create_crud_tools(app_module)
      results[:tools] += module_tools.map { |t| { id: t.id, name: t.name } }
    end
    
    # Create any custom tools from the plan
    plan.tools_spec.each do |tool_spec|
      tool = create_custom_tool(tool_spec)
      results[:tools] << { id: tool.id, name: tool.name } if tool
    end
    
    log_progress("#{results[:tools].count} tools registered")
  end
  
  def wire_integrations!
    return if plan.integrations_spec.empty?
    
    log_progress("Wiring integrations...")
    
    primary_module = AppModule.find(results[:modules].first[:id])
    
    plan.integrations_spec.each do |integration_spec|
      integration = Integration.find_by(slug: integration_spec['slug'])
      next unless integration
      
      module_integration = primary_module.require_integration!(
        integration,
        purpose: integration_spec['purpose'] || 'sync',
        is_critical: integration_spec['is_critical'] || false,
        description: integration_spec['description']
      )
      
      results[:integrations] << {
        id: module_integration.id,
        integration_name: integration.name,
        status: module_integration.status
      }
    end
    
    log_progress("#{results[:integrations].count} integrations wired")
  end
  
  def build_workflows!
    return if plan.workflows_spec.empty?
    
    log_progress("Creating workflows...")
    
    primary_module = AppModule.find(results[:modules].first[:id])
    
    # Build workflow specs for metadata reference
    workflow_specs = plan.workflows_spec.map.with_index do |workflow_spec, idx|
      {
        id: "workflow_#{idx + 1}",
        name: workflow_spec['name'],
        description: describe_workflow(workflow_spec),
        trigger: workflow_spec['trigger'] || 'status_change',
        conditions: {
          from_status: workflow_spec['from_status'],
          to_status: workflow_spec['to_status'],
          field: workflow_spec['field']
        }.compact,
        delay: workflow_spec['delay'],
        actions: (workflow_spec['actions'] || []).map do |action|
          case action.to_s
          when /notify/, /alert/
            { type: 'notify_team', message: "#{workflow_spec['name']} triggered" }
          when /task/, /assign/
            { type: 'create_task', title: "Review: #{workflow_spec['name']}" }
          when /email/
            { type: 'send_email', template: 'notification' }
          else
            { type: action.to_s }
          end
        end,
        status: 'active',
        created_at: Time.current.iso8601
      }
    end
    
    # Store workflows in module metadata (for reference)
    current_metadata = primary_module.metadata || {}
    current_metadata['workflows'] = workflow_specs
    primary_module.update!(metadata: current_metadata)
    
    # Also create real AutomationCode records for executable automations
    plan.workflows_spec.each do |workflow_spec|
      create_automation_from_workflow(primary_module, workflow_spec)
    end
    
    log_progress("#{results[:workflows].count} workflows configured")
  end
  
  def build_scheduled_tasks!
    return if plan.scheduled_tasks_spec.empty?
    
    log_progress("Scheduling background tasks...")
    
    primary_module = AppModule.find(results[:modules].first[:id])
    agent = AgentPlugin.find_by(id: results[:agent]&.dig(:id))
    
    plan.scheduled_tasks_spec.each do |task_spec|
      # Map schedule type to valid values
      schedule_type = case task_spec['schedule']
                      when 'hourly', 'daily', 'weekly', 'monthly', 'cron' then task_spec['schedule']
                      else 'daily'
                      end
      
      # Determine task type based on action
      task_type = case task_spec['action'].to_s.downcase
                  when /sync/, /fetch/, /pull/ then 'data_sync'
                  when /report/, /summary/ then 'report_generation'
                  when /email/ then 'email_management'
                  when /research/, /learn/ then 'research_update'
                  else 'custom'
                  end
      
      task = ScheduledAgentTask.create!(
        entity_id: plan.entity_id,
        user: plan.created_by,
        app_module: primary_module,
        agent_plugin: agent,
        name: task_spec['name'],
        task_type: task_type,
        prompt: task_spec['description'] || task_spec['action'],
        schedule_type: schedule_type,
        run_at_time: task_spec['time'] || '09:00',
        run_on_day: task_spec['day'],
        status: 'active',
        enabled: true,
        metadata: {
          application_plan_id: plan.id,
          action: task_spec['action']
        }
      )
      
      results[:scheduled_tasks] << {
        id: task.id,
        name: task.name,
        schedule: "#{schedule_type} at #{task_spec['time'] || '09:00'}"
      }
    end
    
    log_progress("#{results[:scheduled_tasks].count} scheduled tasks created")
  end
  
  def build_website!
    log_progress("Creating website...")
    
    website_spec = plan.website_spec
    primary_module = AppModule.find(results[:modules].first[:id])
    
    # Use WebsiteBuilderService for proper multi-page websites
    website_builder = WebsiteBuilderService.new(entity: plan.entity, user: plan.created_by)
    
    # Enhance spec with module binding for dynamic pages
    enhanced_spec = website_spec.deep_dup
    enhanced_spec['pages']&.each do |page|
      if page['is_dynamic'] || page['template'] == 'list' || page['template'] == 'detail'
        page['module_slug'] = primary_module.slug
      end
    end
    
    website = website_builder.create_website(enhanced_spec, application_plan: plan)
    
    results[:website] = {
      id: website.id,
      name: website.name,
      slug: website.slug,
      page_count: website.page_count,
      public_url: website.public_url
    }
    
    # If the plan specifies a web app (authentication + module access)
    if plan.plan_spec['web_app'].present? || plan.plan_spec['requires_auth']
      build_web_app!(website, primary_module)
    end
    
    log_progress("Website created with #{website.page_count} pages (draft)")
  end
  
  def build_web_app!(website, primary_module)
    log_progress("Creating web app with authentication...")
    
    web_app_spec = plan.plan_spec['web_app'] || {}
    website_builder = WebsiteBuilderService.new(entity: plan.entity, user: plan.created_by)
    
    # Get all modules that should be exposed in the web app
    modules_to_expose = results[:modules].map do |mod_info|
      AppModule.find(mod_info[:id])
    end
    
    web_app = website_builder.create_web_app(
      web_app_spec.merge('name' => "#{plan.name} App"),
      website: website,
      modules: modules_to_expose,
      application_plan: plan
    )
    
    results[:web_app] = {
      id: web_app.id,
      name: web_app.name,
      slug: web_app.slug,
      public_url: web_app.public_url,
      requires_auth: web_app.requires_auth
    }
    
    log_progress("Web app created with #{modules_to_expose.count} modules")
  end
  
  def finalize_build!
    log_progress("Finalizing build...")
    
    # Update primary module status and verify completeness
    results[:modules].each do |mod_info|
      app_module = AppModule.find(mod_info[:id])
      
      # Post-build verification: ensure module has all required components
      verify_module_completeness!(app_module)
      
      app_module.activate!
      
      # Notify Hub about the new module
      notify_hub_module_created(app_module)
    end
    
    # Update parent App status to active
    if @app
      @app.update!(
        status: 'active',
        build_completed_at: Time.current,
        published_at: Time.current
      )
      results[:app][:status] = 'active'
    end
    
    # Complete the plan
    plan.complete!(results)
    
    log_progress("Build complete! Your #{plan.name} is live.")
  end
  
  # Verify that a module has all required components (canvases, models, table)
  # and attempt to repair any missing pieces
  def verify_module_completeness!(app_module)
    issues = []
    
    # Check 1: Module must have at least one ModuleCode (model)
    if app_module.module_codes.empty?
      issues << "No model/table definition found"
    end
    
    # Check 2: Module must have at least one canvas (list view)
    if app_module.module_canvases.empty?
      issues << "No canvases found"
      # Attempt repair: generate basic canvases
      begin
        log_progress("Repairing: generating canvases for #{app_module.name}...")
        module_spec = plan.modules_spec.find { |m| m['slug'] == app_module.slug || m['name'] == app_module.name }
        if module_spec
          create_module_canvases(app_module, module_spec)
          issues.delete("No canvases found") if app_module.module_canvases.reload.any?
        end
      rescue => e
        Rails.logger.warn "[ApplicationBuildService] Canvas repair failed for #{app_module.name}: #{e.message}"
      end
    end
    
    # Check 3: Module must have a default (list) canvas
    if app_module.module_canvases.any? && !app_module.module_canvases.exists?(is_default: true)
      issues << "No default list canvas"
      # Attempt repair: mark the first canvas as default
      app_module.module_canvases.first.update!(is_default: true)
      issues.delete("No default list canvas")
    end
    
    # Check 4: Database table should exist
    if app_module.module_codes.where(code_type: 'model').any?
      table_name = app_module.slug.pluralize
      unless ActiveRecord::Base.connection.table_exists?(table_name)
        issues << "Database table '#{table_name}' does not exist"
        # Attempt repair: load the model again
        begin
          log_progress("Repairing: creating database table for #{app_module.name}...")
          model_code = app_module.module_codes.where(code_type: 'model').first
          Modules::DynamicModelLoader.instance.load_model(model_code)
          issues.delete("Database table '#{table_name}' does not exist") if ActiveRecord::Base.connection.table_exists?(table_name)
        rescue => e
          Rails.logger.warn "[ApplicationBuildService] Table repair failed for #{app_module.name}: #{e.message}"
        end
      end
    end
    
    if issues.any?
      Rails.logger.warn "[ApplicationBuildService] Module #{app_module.name} (ID: #{app_module.id}) has issues after build: #{issues.join(', ')}"
    else
      Rails.logger.info "[ApplicationBuildService] Module #{app_module.name} (ID: #{app_module.id}) verified complete: model ✓, canvases ✓, table ✓"
    end
  end
  
  def notify_hub_module_created(app_module)
    # Use Hub::ModuleBridgeService if available
    if defined?(Hub::ModuleBridgeService)
      Hub::ModuleBridgeService.on_module_shared(app_module, plan.created_by)
    end
  rescue => e
    Rails.logger.warn "[ApplicationBuildService] Hub notification failed: #{e.message}"
  end
  
  def build_webhooks!
    # Check if plan has hub_hooks or webhook specs
    hub_hooks = plan.plan_spec['hub_hooks'] || []
    return if hub_hooks.empty?
    
    log_progress("Setting up webhooks...")
    
    primary_module = AppModule.find(results[:modules].first[:id])
    agent = AgentPlugin.find_by(id: results[:agent]&.dig(:id))
    
    hub_hooks.each_with_index do |hook_spec, idx|
      webhook = ModuleWebhook.create!(
        app_module: primary_module,
        entity_id: plan.entity_id,
        event_name: hook_spec['event'] || "module.#{hook_spec['action']}",
        slug: "#{primary_module.slug}_hook_#{idx + 1}",
        description: hook_spec['message'] || hook_spec['description'],
        auth_type: 'token',
        auth_token: SecureRandom.hex(32),
        target_type: agent ? 'agent' : 'tool',
        target_id: agent&.id,
        target_tool: agent ? nil : 'ask_user',
        status: 'active'
      )
      
      results[:webhooks] ||= []
      results[:webhooks] << {
        id: webhook.id,
        event: webhook.event_name,
        slug: webhook.slug
      }
    end
    
    log_progress("#{results[:webhooks]&.count || 0} webhooks created")
  end
  
  # ============================================
  # HELPER METHODS
  # ============================================
  
  def create_module(module_spec)
    metadata = {
      application_plan_id: plan.id,
      schema: { fields: module_spec['fields'] },
      is_primary: module_spec['is_primary'] != false
    }
    
    # Store relationship info in metadata for later wiring
    if module_spec['relationship'].present?
      metadata[:relationship_spec] = module_spec['relationship']
    end
    
    base_slug = module_spec['slug'] || module_spec['name'].parameterize.underscore
    slug = unique_slug(AppModule, base_slug, plan.entity_id)
    
    AppModule.create!(
      entity_id: plan.entity_id,
      created_by: plan.created_by,
      app_id: @app&.id,
      name: module_spec['name'],
      slug: slug,
      description: module_spec['description'],
      is_primary: module_spec['is_primary'] != false,
      status: 'generating',
      version: '1.0.0',
      author_type: 'amos',
      visibility: 'user_private',
      metadata: metadata
    )
  end
  
  def create_module_table(app_module, module_spec)
    fields = module_spec['fields'] || []
    relationship = module_spec['relationship']
    
    # Build schema definition
    schema_fields = fields.map do |f|
      {
        'name' => f['name'],
        'type' => convert_field_type(f['field_type']),
        'null' => f['required'] != true,
        'default' => f['default_value']
      }
    end
    
    # Add foreign key field for belongs_to relationships
    if relationship.present? && relationship['type'] == 'belongs_to' && relationship['foreign_key'].present?
      fk_name = relationship['foreign_key']
      unless schema_fields.any? { |f| f['name'] == fk_name }
        schema_fields << {
          'name' => fk_name,
          'type' => :bigint,
          'null' => true,
          'default' => nil
        }
      end
    end
    
    indexes = [{ 'fields' => ['entity_id'] }]
    
    # Add index on foreign key
    if relationship.present? && relationship['foreign_key'].present?
      indexes << { 'fields' => [relationship['foreign_key']] }
    end
    
    schema_definition = {
      'table_name' => app_module.slug.pluralize,
      'fields' => schema_fields,
      'associations' => [],
      'indexes' => indexes
    }
    
    # Create ModuleCode record
    module_code = ModuleCode.create!(
      app_module: app_module,
      entity_id: app_module.entity_id,
      name: app_module.slug.classify,
      code_type: 'model',
      content: generate_model_code(app_module),
      schema_definition: schema_definition,
      status: 'validated'
    )
    
    # Load the dynamic model and create table
    Modules::DynamicModelLoader.instance.load_model(module_code)
    module_code.mark_deployed!
  end
  
  def create_module_canvases(app_module, module_spec)
    views = module_spec['views'] || %w[list form detail]
    fields = module_spec['fields'] || []
    related_models = build_related_models_context(app_module, module_spec)
    
    views.each do |view_type|
      canvas_type = view_type == 'list' ? 'data_grid' : view_type
      
      # Use CanvasGeneratorService for rich canvas generation (AI + fallback)
      canvas_content = generate_rich_canvas(app_module, view_type, fields, related_models)
      
      ModuleCanvas.create!(
        app_module: app_module,
        entity_id: app_module.entity_id,
        name: "#{app_module.name} #{view_type.titleize}",
        slug: "#{app_module.slug}_#{view_type}",
        canvas_type: canvas_type,
        is_default: view_type == 'list',
        html_content: canvas_content[:html] || generate_canvas_html(app_module, view_type, fields),
        js_content: canvas_content[:js],
        css_content: canvas_content[:css],
        data_sources: [{ type: 'module_data', model: app_module.slug }],
        metadata: {
          display_fields: fields.first(6).map { |f| f['name'] },
          icon: 'database',
          generated_by: canvas_content[:generated_by] || 'static'
        }
      )
    end
  end
  
  def generate_rich_canvas(app_module, view_type, fields, related_models)
    generator = CanvasGeneratorService.new(entity: plan.entity, user: plan.created_by)
    result = generator.generate(
      app_module: app_module,
      view_type: view_type,
      fields: fields,
      related_models: related_models
    )
    result.merge(generated_by: result[:html].present? ? 'canvas_generator' : 'static')
  rescue => e
    Rails.logger.warn "[ApplicationBuildService] Canvas generation failed: #{e.message}, using legacy static HTML"
    { html: nil, js: nil, css: nil, generated_by: 'static_fallback' }
  end
  
  def build_related_models_context(app_module, module_spec)
    related = []
    
    # Check if this module belongs to a parent
    relationship = module_spec['relationship']
    if relationship
      rel_type = relationship['type'] || relationship[:type]
      
      if rel_type == 'belongs_to'
        parent_slug = relationship['parent_model'] || relationship[:parent_model]
        parent_mod = AppModule.find_by(slug: parent_slug, entity_id: app_module.entity_id)
        related << {
          name: parent_mod&.name || parent_slug.to_s.titleize,
          relationship_type: 'belongs_to',
          slug: parent_slug
        } if parent_slug
      end
    end
    
    # Check if any other modules in the plan belong to this one (has_many)
    plan.plan_spec['modules']&.each do |other_spec|
      other_rel = other_spec['relationship']
      next unless other_rel
      parent_model = other_rel['parent_model'] || other_rel[:parent_model]
      if parent_model == app_module.slug
        related << {
          name: other_spec['name'] || other_spec['slug'].to_s.titleize,
          relationship_type: 'has_many',
          slug: other_spec['slug']
        }
      end
    end
    
    related
  end
  
  def create_crud_tools(app_module)
    tools = []
    fields = app_module.metadata.dig('schema', 'fields') || []
    model_path = "#{app_module.slug}/#{app_module.slug.classify}"
    
    # Create tool
    tools << ToolDefinition.create!(
      entity: app_module.entity,
      app_module: app_module,
      name: "create_#{app_module.slug.singularize}",
      description: "Create a new #{app_module.name.singularize} record",
      execution_type: 'ruby_code',
      parameters: build_create_parameters(fields),
      code: generate_create_code(app_module, model_path, fields),
      scout_accessible: true
    )
    
    # List tool
    tools << ToolDefinition.create!(
      entity: app_module.entity,
      app_module: app_module,
      name: "list_#{app_module.slug}",
      description: "List all #{app_module.name} records",
      execution_type: 'ruby_code',
      parameters: { type: 'object', properties: { limit: { type: 'integer' } } },
      code: generate_list_code(app_module, model_path),
      scout_accessible: true
    )
    
    # Update tool
    tools << ToolDefinition.create!(
      entity: app_module.entity,
      app_module: app_module,
      name: "update_#{app_module.slug.singularize}",
      description: "Update a #{app_module.name.singularize} record",
      execution_type: 'ruby_code',
      parameters: build_update_parameters(fields),
      code: generate_update_code(app_module, model_path, fields),
      scout_accessible: true
    )
    
    # Delete tool
    tools << ToolDefinition.create!(
      entity: app_module.entity,
      app_module: app_module,
      name: "delete_#{app_module.slug.singularize}",
      description: "Delete a #{app_module.name.singularize} record",
      execution_type: 'ruby_code',
      parameters: { type: 'object', properties: { id: { type: 'integer' } }, required: ['id'] },
      code: generate_delete_code(app_module, model_path),
      scout_accessible: true
    )
    
    tools
  end
  
  def create_custom_tool(tool_spec)
    # Placeholder for custom tool creation
    # This would be used for tools beyond standard CRUD
    nil
  end
  
  def link_tools_to_agent(agent)
    # Link the CRUD tools we created to the agent
    results[:tools].each do |tool_info|
      AgentTool.find_or_create_by!(
        agent_plugin: agent,
        tool_name: tool_info[:name]
      )
    end
    
    # Also add standard tools the agent might need
    # Only reference tools that exist in the current ToolCatalog
    %w[ask_user web_search create_object update_object].each do |tool_name|
      next unless Tools::ToolCatalog.instance.tool_exists?(tool_name)
      AgentTool.find_or_create_by!(
        agent_plugin: agent,
        tool_name: tool_name
      )
    end
  end
  
  # ============================================
  # CODE GENERATION
  # ============================================
  
  def generate_model_code(app_module)
    <<~RUBY
      class #{app_module.slug.classify} < ApplicationRecord
        self.table_name = '#{app_module.slug.pluralize}'
        belongs_to :entity
        scope :for_entity, ->(entity_id) { where(entity_id: entity_id) }
      end
    RUBY
  end
  
  def generate_canvas_html(app_module, view_type, fields)
    case view_type
    when 'list'
      generate_list_canvas_html(app_module, fields)
    when 'form'
      generate_form_canvas_html(app_module, fields)
    when 'detail'
      generate_detail_canvas_html(app_module, fields)
    when 'dashboard'
      generate_dashboard_canvas_html(app_module, fields)
    else
      "<div class='p-4'>#{view_type.titleize} view for #{app_module.name}</div>"
    end
  end
  
  def generate_list_canvas_html(app_module, fields)
    display_fields = fields.first(6).map { |f| f['name'] }
    
    <<~HTML
      <div class="module-canvas p-4" data-controller="module-canvas" data-module-canvas-module-value="#{app_module.slug}">
        <div class="d-flex justify-content-between align-items-center mb-3">
          <h4>#{app_module.name}</h4>
          <button class="btn btn-primary" data-action="click->module-canvas#performAction" data-action-name="add">
            <i data-lucide="plus" class="me-1"></i> Add New
          </button>
        </div>
        <div class="card">
          <div class="table-responsive">
            <table class="table table-hover mb-0">
              <thead><tr>#{display_fields.map { |f| "<th>#{f.titleize}</th>" }.join}<th class="text-end">Actions</th></tr></thead>
              <tbody id="module-data-tbody"><tr><td colspan="#{display_fields.length + 1}" class="text-center py-4 text-muted">No records yet</td></tr></tbody>
            </table>
          </div>
        </div>
      </div>
      <script>if(window.lucide)lucide.createIcons();</script>
    HTML
  end
  
  def generate_form_canvas_html(app_module, fields)
    form_fields = fields.map do |f|
      label = f['name'].titleize
      required = f['required'] ? 'required' : ''
      
      case f['field_type']
      when 'text'
        "<div class='mb-3'><label class='form-label'>#{label}</label><textarea name='#{f['name']}' class='form-control' #{required}></textarea></div>"
      when 'select'
        options = (f['options'] || []).map { |o| "<option value='#{o}'>#{o}</option>" }.join
        "<div class='mb-3'><label class='form-label'>#{label}</label><select name='#{f['name']}' class='form-select' #{required}><option value=''>Select...</option>#{options}</select></div>"
      when 'boolean'
        "<div class='mb-3 form-check'><input type='checkbox' name='#{f['name']}' class='form-check-input'><label class='form-check-label'>#{label}</label></div>"
      else
        "<div class='mb-3'><label class='form-label'>#{label}</label><input type='text' name='#{f['name']}' class='form-control' #{required}></div>"
      end
    end.join("\n")
    
    <<~HTML
      <div class="module-form-canvas p-4" data-controller="module-canvas" data-module-canvas-module-value="#{app_module.slug}">
        <form id="module-record-form" data-action="submit->module-canvas#saveRecord">
          <input type="hidden" name="id" value="">
          #{form_fields}
          <div class="d-flex gap-2 mt-4 pt-3 border-top">
            <button type="submit" class="btn btn-primary"><i data-lucide="save" class="me-1"></i> Save</button>
            <button type="button" class="btn btn-outline-secondary" data-bs-dismiss="modal">Cancel</button>
          </div>
        </form>
      </div>
      <script>if(window.lucide)lucide.createIcons();</script>
    HTML
  end
  
  def generate_detail_canvas_html(app_module, fields)
    <<~HTML
      <div class="module-detail-canvas p-4" data-controller="module-canvas" data-module-canvas-module-value="#{app_module.slug}">
        <div class="card">
          <div class="card-header d-flex justify-content-between">
            <h5 class="mb-0">#{app_module.name.singularize} Details</h5>
            <button class="btn btn-sm btn-outline-primary" data-action="click->module-canvas#performAction" data-action-name="edit">
              <i data-lucide="edit" class="me-1"></i> Edit
            </button>
          </div>
          <div class="card-body" id="detail-content">
            <p class="text-muted">Select a record to view details</p>
          </div>
        </div>
      </div>
      <script>if(window.lucide)lucide.createIcons();</script>
    HTML
  end
  
  def generate_dashboard_canvas_html(app_module, fields)
    <<~HTML
      <div class="module-dashboard-canvas p-4">
        <h4 class="mb-4">#{app_module.name} Dashboard</h4>
        <div class="row">
          <div class="col-md-4">
            <div class="card bg-primary text-white">
              <div class="card-body">
                <h6>Total Records</h6>
                <h2 id="total-count">--</h2>
              </div>
            </div>
          </div>
          <div class="col-md-4">
            <div class="card bg-success text-white">
              <div class="card-body">
                <h6>This Week</h6>
                <h2 id="week-count">--</h2>
              </div>
            </div>
          </div>
          <div class="col-md-4">
            <div class="card bg-info text-white">
              <div class="card-body">
                <h6>Today</h6>
                <h2 id="today-count">--</h2>
              </div>
            </div>
          </div>
        </div>
      </div>
    HTML
  end
  
  def generate_website_html(website_spec, primary_module)
    name = website_spec['name'] || primary_module.name
    
    <<~HTML
      <!DOCTYPE html>
      <html lang="en">
      <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>#{name}</title>
        <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/css/bootstrap.min.css" rel="stylesheet">
      </head>
      <body>
        <nav class="navbar navbar-expand-lg navbar-dark bg-primary">
          <div class="container">
            <a class="navbar-brand" href="#">#{name}</a>
            <div class="navbar-nav ms-auto">
              <a class="nav-link" href="#search">Search</a>
              <a class="nav-link" href="#browse">Browse</a>
            </div>
          </div>
        </nav>
        <main class="container py-5">
          <div class="text-center mb-5">
            <h1>Welcome to #{name}</h1>
            <p class="lead">Find the information you need</p>
            <div class="row justify-content-center">
              <div class="col-md-6">
                <div class="input-group input-group-lg">
                  <input type="search" class="form-control" placeholder="Search...">
                  <button class="btn btn-primary">Search</button>
                </div>
              </div>
            </div>
          </div>
          <div class="row" id="content">
            <p class="text-center text-muted">Content will appear here</p>
          </div>
        </main>
        <footer class="bg-light py-4 mt-5">
          <div class="container text-center">
            <p class="mb-0">Powered by AMOS</p>
          </div>
        </footer>
      </body>
      </html>
    HTML
  end
  
  def generate_agent_prompt(agent_spec, primary_module)
    <<~PROMPT
      You are **#{agent_spec['name']}** - an AI expert for #{primary_module.name}.
      
      ## Your Role
      #{agent_spec['description']}
      
      ## Your Capabilities
      #{(agent_spec['capabilities'] || []).map { |c| "- #{c}" }.join("\n")}
      
      ## Your Personality
      #{agent_spec['personality']}
      
      ## Available Tools
      You have tools to create, read, update, and delete #{primary_module.name.downcase} records.
      Use these tools to help users manage their data.
      
      ## Guidelines
      - Be helpful and proactive
      - Use your tools when the user asks about #{primary_module.name.downcase}
      - Ask clarifying questions when needed
      - Provide clear, actionable responses
    PROMPT
  end
  
  # ============================================
  # TOOL CODE GENERATION
  # ============================================
  
  def build_create_parameters(fields)
    {
      type: 'object',
      properties: fields.each_with_object({}) do |f, hash|
        hash[f['name']] = { type: json_type(f['field_type']), description: f['description'] || f['name'].titleize }
      end,
      required: fields.select { |f| f['required'] }.map { |f| f['name'] }
    }
  end
  
  def build_update_parameters(fields)
    {
      type: 'object',
      properties: { id: { type: 'integer', description: 'Record ID' } }.merge(
        fields.each_with_object({}) { |f, h| h[f['name']] = { type: json_type(f['field_type']) } }
      ),
      required: ['id']
    }
  end
  
  def generate_create_code(app_module, model_path, fields)
    permitted = fields.map { |f| "'#{f['name']}'" }.join(', ')
    <<~RUBY
      model_class = Modules::DynamicModelLoader.instance.get_model_by_path(_context[:entity], "#{model_path}")
      return { error: "Model not loaded" } unless model_class
      attrs = _args.slice(#{permitted}).merge(entity_id: _context[:entity].id)
      record = model_class.create!(attrs)
      { success: true, id: record.id, message: "Created successfully" }
    RUBY
  end
  
  def generate_list_code(app_module, model_path)
    <<~RUBY
      model_class = Modules::DynamicModelLoader.instance.get_model_by_path(_context[:entity], "#{model_path}")
      return { error: "Model not loaded" } unless model_class
      records = model_class.where(entity_id: _context[:entity].id).limit(_args['limit'] || 50)
      { success: true, count: records.count, records: records.map(&:attributes) }
    RUBY
  end
  
  def generate_update_code(app_module, model_path, fields)
    permitted = fields.map { |f| "'#{f['name']}'" }.join(', ')
    <<~RUBY
      model_class = Modules::DynamicModelLoader.instance.get_model_by_path(_context[:entity], "#{model_path}")
      return { error: "Model not loaded" } unless model_class
      record = model_class.find_by(id: _args['id'], entity_id: _context[:entity].id)
      return { success: false, error: "Record not found" } unless record
      record.update!(_args.slice(#{permitted}))
      { success: true, message: "Updated successfully" }
    RUBY
  end
  
  def generate_delete_code(app_module, model_path)
    <<~RUBY
      model_class = Modules::DynamicModelLoader.instance.get_model_by_path(_context[:entity], "#{model_path}")
      return { error: "Model not loaded" } unless model_class
      record = model_class.find_by(id: _args['id'], entity_id: _context[:entity].id)
      return { success: false, error: "Record not found" } unless record
      record.destroy
      { success: true, message: "Deleted successfully" }
    RUBY
  end
  
  # ============================================
  # UTILITIES
  # ============================================
  
  # Generate a unique slug by appending a numeric suffix if needed
  def unique_slug(model_class, base_slug, entity_id)
    slug = base_slug
    counter = 1
    while model_class.exists?(slug: slug, entity_id: entity_id)
      counter += 1
      slug = "#{base_slug}_#{counter}"
    end
    slug
  end

  def convert_field_type(field_type)
    case field_type.to_s.downcase
    when 'text' then :text
    when 'integer' then :integer
    when 'decimal', 'float' then :decimal
    when 'boolean' then :boolean
    when 'date' then :date
    when 'datetime' then :datetime
    when 'json' then :jsonb
    when 'reference' then :bigint
    else :string
    end
  end
  
  def json_type(field_type)
    case field_type.to_s
    when 'integer', 'decimal', 'float' then 'number'
    when 'boolean' then 'boolean'
    else 'string'
    end
  end
  
  def create_automation_from_workflow(app_module, workflow_spec)
    trigger_type = map_workflow_trigger(workflow_spec['trigger'])
    action_type = resolve_workflow_action(workflow_spec['actions']&.first)
    
    # Build trigger config
    trigger_config = {
      'module_slug' => app_module.slug,
      'from_status' => workflow_spec['from_status'],
      'to_status' => workflow_spec['to_status'],
      'field' => workflow_spec['field']
    }.compact
    
    # Build action config for AutomationActionRegistry
    action_config = build_automation_action_config(app_module, action_type, workflow_spec)
    
    # Generate the code using the registry
    code = begin
      AutomationActionRegistry.generate_code(
        action: action_type,
        action_config: action_config,
        trigger: trigger_type,
        name: workflow_spec['name']
      )
    rescue => e
      Rails.logger.warn "[ApplicationBuildService] Could not generate automation code for #{workflow_spec['name']}: #{e.message}"
      generate_fallback_automation_code(workflow_spec)
    end
    
    automation = AutomationCode.create!(
      entity: plan.entity,
      app_module: app_module,
      created_by: plan.created_by,
      name: workflow_spec['name'],
      trigger_type: trigger_type,
      trigger_config: trigger_config,
      code: code,
      description: describe_workflow(workflow_spec),
      status: 'active',
      is_tested: true, # Auto-generated code is considered tested
      metadata: {
        'source' => 'application_build',
        'plan_id' => plan.id,
        'actions' => workflow_spec['actions']
      }
    )
    
    results[:workflows] << { id: automation.id, name: automation.name, type: 'automation_code' }
  rescue => e
    Rails.logger.warn "[ApplicationBuildService] Automation creation failed for #{workflow_spec['name']}: #{e.message}"
  end
  
  def map_workflow_trigger(trigger)
    case trigger.to_s
    when 'status_change', 'status_changed' then 'status_changed'
    when 'record_created', 'created' then 'record_created'
    when 'record_updated', 'updated' then 'record_updated'
    when 'field_changed' then 'field_changed'
    when 'schedule', 'scheduled', 'scheduled_datetime' then 'schedule'
    when 'webhook' then 'webhook'
    when 'form_submit' then 'form_submit'
    else 'manual'
    end
  end
  
  def resolve_workflow_action(action)
    return 'notify_on_module_event' if action.nil?
    
    case action.to_s.downcase
    when /notify/, /alert/ then 'notify_on_module_event'
    when /update.*field/, /set.*field/ then 'update_module_record'
    when /create.*record/ then 'create_module_record'
    when /email/, /send/ then 'notify_user'
    when /webhook/, /call/ then 'call_webhook'
    else 'notify_on_module_event'
    end
  end
  
  def build_automation_action_config(app_module, action_type, workflow_spec)
    case action_type
    when 'notify_on_module_event'
      {
        'module_slug' => app_module.slug,
        'message' => "#{workflow_spec['name']} triggered for #{app_module.name}"
      }
    when 'update_module_record'
      {
        'module_slug' => app_module.slug,
        'field' => workflow_spec['to_status'] ? 'status' : (workflow_spec['field'] || 'status'),
        'value' => workflow_spec['to_status'] || 'updated'
      }
    when 'create_module_record'
      {
        'module_slug' => app_module.slug,
        'field_values' => { 'status' => 'new' }
      }
    when 'notify_user'
      {
        'message' => "#{workflow_spec['name']} triggered for #{app_module.name}"
      }
    when 'call_webhook'
      {
        'url' => 'https://hooks.example.com/placeholder'
      }
    else
      { 'module_slug' => app_module.slug, 'message' => workflow_spec['name'] }
    end
  end
  
  def generate_fallback_automation_code(workflow_spec)
    <<~RUBY
      # Automation: #{workflow_spec['name']}
      # Fallback code — customize as needed
      def execute(trigger_data)
        entity_id = trigger_data[:entity_id] || trigger_data["entity_id"]
        record = trigger_data[:record] || trigger_data["record"] || {}
        
        Rails.logger.info "[Automation] #{workflow_spec['name']} triggered for entity \#{entity_id}"
        
        { success: true, message: "#{workflow_spec['name']} executed", record_id: record["id"] }
      end
    RUBY
  end
  
  def describe_workflow(workflow_spec)
    case workflow_spec['trigger']
    when 'status_change'
      "When status changes from #{workflow_spec['from_status']} to #{workflow_spec['to_status']}"
    when 'record_created'
      "When a new record is created"
    when 'field_changed'
      "When #{workflow_spec['field']} is updated"
    else
      workflow_spec['trigger']&.humanize
    end
  end
  
  # ============================================
  # PROGRESS & LIFECYCLE
  # ============================================

  # Run a build phase inside its own transaction, with cancellation checks.
  # Skips phases that were already completed (for resume support).
  def run_phase(phase_name)
    @current_phase = phase_name

    # Skip already-completed phases when resuming
    if @resuming && completed_phases.include?(phase_name.to_s)
      range = PHASE_RANGES[phase_name]
      emit_progress("Skipping #{phase_name} (already completed)", percentage: range&.dig(:finish), phase: phase_name.to_s)
      return
    end

    # Check for cancellation before starting each phase
    check_cancellation!

    # Each phase runs in its own transaction for crash resilience
    ApplicationPlan.transaction do
      yield
    end

    # Track completed phase
    track_completed_phase(phase_name)
  end

  # Emit progress at a specific percentage within the current phase
  def emit_phase_sub_progress(phase, step_index, total_steps, message)
    range = PHASE_RANGES[phase]
    return emit_progress(message) unless range && total_steps > 0

    step_fraction = step_index.to_f / total_steps
    pct = range[:start] + ((range[:finish] - range[:start]) * step_fraction)
    emit_progress(message, percentage: pct.round, phase: phase.to_s)
  end

  # Emit a structured progress event to the callback
  def emit_progress(message, percentage: nil, phase: nil)
    Rails.logger.info "[ApplicationBuildService] #{message}"
    plan.add_build_log(message)

    if progress_callback
      # The callback from PlatformCreateTool expects (message, percentage)
      progress_callback.call(message, percentage)
    end
  end

  # Simple log + plan log (no percentage)
  def log_progress(message)
    phase = @current_phase
    range = PHASE_RANGES[phase]
    pct = range ? range[:start] : nil
    emit_progress(message, percentage: pct, phase: phase&.to_s)
  end

  def track_completed_phase(phase_name)
    completed = plan.build_results&.dig("completed_phases") || []
    completed << phase_name.to_s unless completed.include?(phase_name.to_s)
    plan.update_column(:build_results, (plan.build_results || {}).merge("completed_phases" => completed))
  rescue => e
    Rails.logger.warn "[ApplicationBuildService] Could not track phase #{phase_name}: #{e.message}"
  end

  def check_cancellation!
    return unless cancellation_check

    if cancellation_check.call
      raise BuildCancelled, "Build paused by user after completing: #{completed_phases.join(', ')}"
    end
  end

  def completed_phases
    plan.build_results&.dig("completed_phases") || []
  end

  def handle_cancellation(error)
    Rails.logger.info "[ApplicationBuildService] Build paused: #{error.message}"
    plan.update!(status: "paused", error_message: error.message)
  end
  
  def handle_failure(error)
    Rails.logger.error "[ApplicationBuildService] Build failed: #{error.message}"
    Rails.logger.error error.backtrace.first(10).join("\n")
    
    plan.fail!(
      error.message,
      { timestamp: Time.current.iso8601, error: error.message, backtrace: error.backtrace.first(5) }
    )
  end
  
  class BuildError < StandardError; end
  class BuildCancelled < StandardError; end
end

