# frozen_string_literal: true

module Tools
  # UpdateModuleTool - Updates an existing module with fixes or enhancements
  #
  # This tool allows agents to actually fix issues with modules by:
  # - Adding/removing/modifying fields
  # - Updating canvases
  # - Fixing actions
  # - Regenerating code
  #
  class UpdateModuleTool < BaseTool
    def self.metadata
      {
        name: "update_module",
        description: "Update an existing module with fixes or enhancements. Can add fields, fix canvases, update actions, or regenerate code.",
        category: "app_building",
        input_schema: {
          type: "object",
          properties: {
            module_slug: {
              type: "string",
              description: "The slug of the module to update"
            },
            action: {
              type: "string",
              enum: ["add_field", "remove_field", "update_field", "add_canvas", "update_canvas", "add_action", "update_action", "fix_canvas_buttons", "regenerate_model", "update_metadata"],
              description: "The type of update. REQUIRED PARAMS: add_field→field_definition, add_canvas→canvas_definition, update_canvas→canvas_slug+canvas_updates, update_field→field_name+field_definition"
            },
            canvas_definition: {
              type: "object",
              description: "REQUIRED for add_canvas action. Must include name and canvas_type.",
              properties: {
                name: { type: "string", description: "Canvas display name" },
                canvas_type: { type: "string", enum: ["dashboard", "data_grid", "form", "report", "wizard"], description: "Type of canvas" },
                html_content: { type: "string", description: "HTML content for the canvas" },
                data_sources: { type: "array", description: "Data sources for the canvas" },
                metadata: { type: "object", description: "Additional metadata" }
              }
            },
            field_definition: {
              type: "object",
              description: "REQUIRED for add_field/update_field. Must include name and field_type."
            },
            field_name: {
              type: "string",
              description: "REQUIRED for remove_field/update_field: the name of the field to modify"
            },
            canvas_slug: {
              type: "string",
              description: "REQUIRED for update_canvas: the slug of the existing canvas to update"
            },
            canvas_updates: {
              type: "object",
              description: "For update_canvas: the updates to apply { html_content, metadata, columns, filters, etc. }"
            },
            action_definition: {
              type: "object",
              description: "For add_action/update_action: the action definition"
            },
            action_slug: {
              type: "string",
              description: "For update_action: the slug of the action"
            },
            metadata_updates: {
              type: "object",
              description: "For update_metadata: updates to module metadata"
            }
          },
          required: ["module_slug", "action"]
        }
      }
    end

    def execute(args)
      log_execution(args)
      
      module_slug = get_arg(args, :module_slug)
      action = get_arg(args, :action)
      
      if error = validate_required_args(args, [:module_slug, :action])
        return error
      end
      
      # Find the module
      app_module = AppModule.find_by(slug: module_slug, entity_id: entity.id)
      unless app_module
        return error_response(
          "Module not found: #{module_slug}",
          available_modules: entity.app_modules.pluck(:slug)
        )
      end
      
      case action
      when 'add_field'
        add_field(app_module, args)
      when 'remove_field'
        remove_field(app_module, args)
      when 'update_field'
        update_field(app_module, args)
      when 'add_canvas'
        add_canvas(app_module, args)
      when 'update_canvas'
        update_canvas(app_module, args)
      when 'add_action'
        add_action(app_module, args)
      when 'update_action'
        update_action(app_module, args)
      when 'fix_canvas_buttons'
        fix_canvas_buttons(app_module, args)
      when 'regenerate_model'
        regenerate_model(app_module, args)
      when 'update_metadata'
        update_metadata(app_module, args)
      else
        error_response("Unknown action: #{action}")
      end
    end

    private

    def add_field(app_module, args)
      field_def = get_arg(args, :field_definition)
      unless field_def
        return error_response("field_definition is required for add_field")
      end
      
      field_def = field_def.stringify_keys
      
      # Validate field definition
      validation_result = validate_field_definition(field_def)
      if validation_result[:error]
        return error_response(validation_result[:error], suggestions: validation_result[:suggestions])
      end
      
      # Add to field_config
      fields = app_module.field_config['fields'] || []
      
      # Check if field already exists
      if fields.any? { |f| f['name'] == field_def['name'] }
        return error_response("Field '#{field_def['name']}' already exists")
      end
      
      fields << field_def
      app_module.update!(field_config: app_module.field_config.merge('fields' => fields))
      
      # Also update schema in metadata
      schema_fields = app_module.metadata.dig('schema', 'fields') || []
      schema_fields << field_def
      app_module.update!(
        metadata: app_module.metadata.deep_merge('schema' => { 'fields' => schema_fields })
      )
      
      # AUTO-SYNC: Update all canvases that should include this field
      canvases_updated = sync_field_to_canvases(app_module, field_def, :add)
      
      # Add column to database if model exists
      add_column_to_model(app_module, field_def)
      
      success_response(
        module_slug: app_module.slug,
        action: 'add_field',
        field_added: field_def['name'],
        canvases_synced: canvases_updated,
        message: "✅ Added field '#{field_def['name']}' to #{app_module.name} and synced to #{canvases_updated.length} canvas(es)"
      )
    end

    def remove_field(app_module, args)
      field_name = get_arg(args, :field_name)
      unless field_name
        return error_response("field_name is required for remove_field")
      end
      
      # Remove from field_config
      fields = app_module.field_config['fields'] || []
      original_count = fields.count
      fields.reject! { |f| f['name'] == field_name }
      
      if fields.count == original_count
        return error_response("Field '#{field_name}' not found")
      end
      
      app_module.update!(field_config: app_module.field_config.merge('fields' => fields))
      
      # Also remove from schema in metadata
      schema_fields = app_module.metadata.dig('schema', 'fields') || []
      schema_fields.reject! { |f| f['name'] == field_name }
      app_module.update!(
        metadata: app_module.metadata.deep_merge('schema' => { 'fields' => schema_fields })
      )
      
      # AUTO-SYNC: Remove from all canvases
      canvases_updated = sync_field_to_canvases(app_module, { 'name' => field_name }, :remove)
      
      success_response(
        module_slug: app_module.slug,
        action: 'remove_field',
        field_removed: field_name,
        canvases_synced: canvases_updated,
        message: "✅ Removed field '#{field_name}' from #{app_module.name} and synced to #{canvases_updated.length} canvas(es)"
      )
    end

    def update_field(app_module, args)
      field_name = get_arg(args, :field_name)
      field_def = get_arg(args, :field_definition)
      
      unless field_name && field_def
        return error_response("field_name and field_definition are required for update_field")
      end
      
      field_def = field_def.stringify_keys
      
      # Validate the updated field definition
      validation_result = validate_field_definition(field_def)
      if validation_result[:error]
        return error_response(validation_result[:error], suggestions: validation_result[:suggestions])
      end
      
      # Update in field_config
      fields = app_module.field_config['fields'] || []
      field_index = fields.find_index { |f| f['name'] == field_name }
      
      unless field_index
        return error_response("Field '#{field_name}' not found")
      end
      
      updated_field = fields[field_index].merge(field_def)
      fields[field_index] = updated_field
      app_module.update!(field_config: app_module.field_config.merge('fields' => fields))
      
      # Also update in schema metadata
      schema_fields = app_module.metadata.dig('schema', 'fields') || []
      schema_index = schema_fields.find_index { |f| f['name'] == field_name }
      if schema_index
        schema_fields[schema_index] = schema_fields[schema_index].merge(field_def)
        app_module.update!(
          metadata: app_module.metadata.deep_merge('schema' => { 'fields' => schema_fields })
        )
      end
      
      # AUTO-SYNC: Update field in all canvases
      canvases_updated = sync_field_to_canvases(app_module, updated_field, :update)
      
      success_response(
        module_slug: app_module.slug,
        action: 'update_field',
        field_updated: field_name,
        canvases_synced: canvases_updated,
        message: "✅ Updated field '#{field_name}' in #{app_module.name} and synced to #{canvases_updated.length} canvas(es)"
      )
    end

    def add_canvas(app_module, args)
      canvas_def = get_arg(args, :canvas_definition)
      
      # AUTO-COMPLETE: If canvas_definition is missing, use sensible defaults
      # This prevents the agent from getting stuck in a loop
      unless canvas_def
        canvas_def = {
          'name' => "#{app_module.name} Dashboard",
          'canvas_type' => 'dashboard'
        }
        Rails.logger.warn "[UpdateModule] canvas_definition was missing - auto-completing with defaults: #{canvas_def.inspect}"
      end
      
      canvas_def = canvas_def.stringify_keys
      canvas_name = canvas_def['name']
      canvas_type = canvas_def['canvas_type'] || 'dashboard'
      
      unless canvas_name
        return error_response("canvas_definition must include a 'name'")
      end
      
      # Generate slug from name
      canvas_slug = canvas_name.parameterize.underscore
      
      # Check if canvas already exists
      if app_module.module_canvases.exists?(slug: canvas_slug)
        return error_response("Canvas with slug '#{canvas_slug}' already exists",
          existing_canvases: app_module.module_canvases.pluck(:slug))
      end
      
      # Build data sources for the canvas
      data_sources = canvas_def['data_sources'] || [{ 'type' => 'module_data', 'model' => app_module.slug }]
      
      # Generate default HTML content based on canvas type
      html_content = canvas_def['html_content'] || generate_default_canvas_html(app_module, canvas_type, canvas_def)
      
      # Create the canvas
      canvas = ModuleCanvas.create!(
        app_module: app_module,
        entity: entity,
        name: canvas_name,
        slug: canvas_slug,
        canvas_type: canvas_type,
        html_content: html_content,
        data_sources: data_sources,
        metadata: canvas_def['metadata'] || {
          'icon' => app_module.icon || 'layout-dashboard',
          'description' => "#{canvas_type.titleize} view for #{app_module.name}"
        },
        is_default: false
      )
      
      # Register the canvas so it appears in the load_canvas enum
      register_canvas_with_scout(app_module, canvas)
      
      full_canvas_type = "module_#{app_module.slug}_#{canvas_slug}"
      
      success_response(
        module_slug: app_module.slug,
        action: 'add_canvas',
        canvas_created: canvas_slug,
        canvas_id: canvas.id,
        full_canvas_type: full_canvas_type,
        load_command: "load_canvas(canvas_name: '#{full_canvas_type}')",
        message: "✅ Created new #{canvas_type} canvas '#{canvas_name}' for #{app_module.name}. Load it with: load_canvas(canvas_name: '#{full_canvas_type}')"
      )
    end

    def update_canvas(app_module, args)
      canvas_slug = get_arg(args, :canvas_slug)
      canvas_updates = get_arg(args, :canvas_updates) || {}
      
      unless canvas_slug
        return error_response("canvas_slug is required for update_canvas")
      end
      
      canvas = app_module.module_canvases.find_by(slug: canvas_slug)
      unless canvas
        # Try fuzzy match
        canvas = app_module.module_canvases.find_by("slug LIKE ?", "%#{canvas_slug}%")
      end
      
      unless canvas
        return error_response(
          "Canvas not found: #{canvas_slug}",
          available_canvases: app_module.module_canvases.pluck(:slug)
        )
      end
      
      # Apply updates
      canvas.update!(canvas_updates.slice(
        'html_content', 'metadata', 'columns', 'filters', 'sorting',
        'layout', 'sections', 'tabs', 'card_config', 'data_sources'
      ))
      
      success_response(
        module_slug: app_module.slug,
        action: 'update_canvas',
        canvas_updated: canvas.slug,
        message: "✅ Updated canvas '#{canvas.name}' in #{app_module.name}"
      )
    end

    def add_action(app_module, args)
      action_def = get_arg(args, :action_definition)
      unless action_def
        return error_response("action_definition is required for add_action")
      end
      
      # Check if action already exists
      if app_module.module_actions.exists?(slug: action_def['slug'])
        return error_response("Action '#{action_def['slug']}' already exists")
      end
      
      action = ModuleAction.create!(
        app_module: app_module,
        entity: entity,
        name: action_def['name'],
        slug: action_def['slug'],
        icon: action_def['icon'] || 'play',
        style: action_def['style'] || 'primary',
        location: action_def['location'] || 'toolbar',
        target_field: action_def['target_field'],
        show_when: action_def['show_when'] || {},
        requires_role: action_def['requires_role'] || {},
        behavior_type: action_def['behavior_type'] || 'update',
        behavior_config: action_def['behavior_config'] || {},
        active: true
      )
      
      success_response(
        module_slug: app_module.slug,
        action: 'add_action',
        action_added: action.slug,
        message: "✅ Added action '#{action.name}' to #{app_module.name}"
      )
    end

    def update_action(app_module, args)
      action_slug = get_arg(args, :action_slug)
      action_def = get_arg(args, :action_definition)
      
      unless action_slug
        return error_response("action_slug is required for update_action")
      end
      
      action = app_module.module_actions.find_by(slug: action_slug)
      unless action
        return error_response(
          "Action not found: #{action_slug}",
          available_actions: app_module.module_actions.pluck(:slug)
        )
      end
      
      action.update!(action_def.slice(
        'name', 'icon', 'style', 'location', 'target_field',
        'show_when', 'requires_role', 'behavior_type', 'behavior_config', 'active'
      ))
      
      success_response(
        module_slug: app_module.slug,
        action: 'update_action',
        action_updated: action.slug,
        message: "✅ Updated action '#{action.name}' in #{app_module.name}"
      )
    end

    def fix_canvas_buttons(app_module, args)
      canvas_slug = get_arg(args, :canvas_slug)
      
      # Find the canvas
      canvas = if canvas_slug
                 app_module.module_canvases.find_by(slug: canvas_slug)
               else
                 app_module.module_canvases.find_by(is_default: true)
               end
      
      unless canvas
        return error_response("Canvas not found")
      end
      
      # Regenerate the canvas with working buttons
      # The key fix is ensuring the buttons use the correct JavaScript
      
      # Update canvas metadata to ensure proper rendering
      canvas.update!(
        metadata: canvas.metadata.merge(
          'display_fields' => canvas.columns.presence || app_module.enhanced_fields.first(5).map { |f| f['name'] },
          'icon' => app_module.icon,
          'buttons_fixed' => true,
          'fixed_at' => Time.current.iso8601
        )
      )
      
      success_response(
        module_slug: app_module.slug,
        action: 'fix_canvas_buttons',
        canvas_fixed: canvas.slug,
        message: "✅ Fixed buttons on canvas '#{canvas.name}'. Please reload the canvas to see the changes."
      )
    end

    def regenerate_model(app_module, args)
      # Get the current schema
      fields = app_module.enhanced_fields
      
      if fields.blank?
        return error_response("Module has no fields defined")
      end
      
      # Find or create the model code
      model_code = app_module.module_codes.find_by(code_type: 'model')
      
      schema_columns = [
        { 'name' => 'id', 'type' => 'bigint', 'primary' => true },
        { 'name' => 'entity_id', 'type' => 'bigint', 'null' => false, 'index' => true }
      ]
      
      fields.each do |field|
        next if %w[id entity_id created_at updated_at].include?(field['name'])
        
        schema_columns << {
          'name' => field['name'],
          'type' => map_field_to_db_type(field['type'] || field['field_type']),
          'null' => !field['required'],
          'default' => field['default']
        }
      end
      
      schema_columns += [
        { 'name' => 'created_at', 'type' => 'datetime', 'null' => false },
        { 'name' => 'updated_at', 'type' => 'datetime', 'null' => false }
      ]
      
      if model_code
        model_code.update!(
          schema_definition: {
            'table_name' => app_module.slug.pluralize,
            'columns' => schema_columns
          },
          fields: fields.map { |f| { 'name' => f['name'], 'type' => f['type'] || f['field_type'] } },
          status: 'deployed'
        )
      else
        model_code = ModuleCode.create!(
          app_module: app_module,
          entity: entity,
          name: app_module.slug.classify,
          code_type: 'model',
          status: 'deployed',
          schema_definition: {
            'table_name' => app_module.slug.pluralize,
            'columns' => schema_columns
          },
          fields: fields.map { |f| { 'name' => f['name'], 'type' => f['type'] || f['field_type'] } },
          associations: [{ 'type' => 'belongs_to', 'model' => 'Entity' }]
        )
      end
      
      # Reload the model
      Modules::DynamicModelLoader.instance.load_model(model_code)
      
      success_response(
        module_slug: app_module.slug,
        action: 'regenerate_model',
        model_regenerated: true,
        fields_count: fields.count,
        message: "✅ Regenerated model for #{app_module.name} with #{fields.count} fields"
      )
    end

    def update_metadata(app_module, args)
      metadata_updates = get_arg(args, :metadata_updates)
      unless metadata_updates
        return error_response("metadata_updates is required for update_metadata")
      end
      
      app_module.update!(metadata: app_module.metadata.deep_merge(metadata_updates.stringify_keys))
      
      success_response(
        module_slug: app_module.slug,
        action: 'update_metadata',
        message: "✅ Updated metadata for #{app_module.name}"
      )
    end

    # Validates a field definition and returns suggestions if issues found
    SUPPORTED_FIELD_TYPES = %w[string text integer decimal boolean date datetime json enum select reference].freeze
    REFERENCEABLE_MODELS = %w[LandingPage Contact Campaign User EmailTemplate Opportunity].freeze

    def validate_field_definition(field_def)
      field_name = field_def['name']
      field_type = field_def['field_type'] || field_def['type']
      
      # Check required name
      if field_name.blank?
        return { error: "Field must have a 'name'" }
      end
      
      # Check field_type
      if field_type.blank?
        # Try to infer from name
        if field_name.end_with?('_id')
          return { 
            error: "Field '#{field_name}' needs a field_type. Looks like a reference field.",
            suggestions: ["Add field_type: 'reference' and reference_model: 'ModelName'"]
          }
        else
          return { error: "Field '#{field_name}' must have a 'field_type'" }
        end
      end
      
      # Validate field type is supported
      unless SUPPORTED_FIELD_TYPES.include?(field_type.to_s.downcase)
        return {
          error: "Unsupported field_type '#{field_type}' for field '#{field_name}'",
          suggestions: ["Supported types: #{SUPPORTED_FIELD_TYPES.join(', ')}"]
        }
      end
      
      # Validate reference fields have reference_model
      if field_type.to_s.downcase == 'reference'
        ref_model = field_def['reference_model'] || field_def['references']
        if ref_model.blank?
          return {
            error: "Reference field '#{field_name}' must have 'reference_model' specified",
            suggestions: ["Known models: #{REFERENCEABLE_MODELS.join(', ')}"]
          }
        end
      end
      
      # Validate enum fields have options
      if %w[enum select].include?(field_type.to_s.downcase)
        options = field_def['options']
        if options.blank? || !options.is_a?(Array) || options.empty?
          return {
            error: "Enum field '#{field_name}' must have 'options' array",
            suggestions: ["Add options: ['option1', 'option2', ...]"]
          }
        end
      end
      
      { valid: true }
    end

    # Syncs a field change to all relevant canvases
    def sync_field_to_canvases(app_module, field_def, operation)
      updated_canvases = []
      field_name = field_def['name']
      
      app_module.module_canvases.each do |canvas|
        canvas_fields = canvas.metadata&.dig('fields') || []
        
        case operation
        when :add
          # Add field to form canvases
          if canvas.canvas_type == 'form'
            unless canvas_fields.any? { |f| f['name'] == field_name }
              canvas_fields << field_def
              canvas.update!(metadata: canvas.metadata.merge('fields' => canvas_fields))
              updated_canvases << canvas.slug
              Rails.logger.info "[UpdateModule] Synced field '#{field_name}' to canvas '#{canvas.slug}'"
            end
          end
          
        when :remove
          # Remove field from all canvases
          if canvas_fields.any? { |f| f['name'] == field_name }
            canvas_fields.reject! { |f| f['name'] == field_name }
            canvas.update!(metadata: canvas.metadata.merge('fields' => canvas_fields))
            updated_canvases << canvas.slug
            Rails.logger.info "[UpdateModule] Removed field '#{field_name}' from canvas '#{canvas.slug}'"
          end
          
          # Also remove from display_fields if present
          display_fields = canvas.metadata&.dig('display_fields') || []
          if display_fields.include?(field_name)
            display_fields.delete(field_name)
            canvas.update!(metadata: canvas.metadata.merge('display_fields' => display_fields))
          end
          
        when :update
          # Update field in all canvases that have it
          field_index = canvas_fields.find_index { |f| f['name'] == field_name }
          if field_index
            canvas_fields[field_index] = canvas_fields[field_index].merge(field_def)
            canvas.update!(metadata: canvas.metadata.merge('fields' => canvas_fields))
            updated_canvases << canvas.slug
            Rails.logger.info "[UpdateModule] Updated field '#{field_name}' in canvas '#{canvas.slug}'"
          end
        end
      end
      
      updated_canvases.uniq
    end

    def add_column_to_model(app_module, field_def)
      model_code = app_module.module_codes.find_by(code_type: 'model', status: 'deployed')
      return unless model_code
      
      # Get the dynamic model class
      model_class = Modules::DynamicModelLoader.instance.get_model(app_module, app_module.slug.classify)
      return unless model_class
      
      table_name = model_code.schema_definition['table_name'] || app_module.slug.pluralize
      column_name = field_def['name']
      column_type = map_field_to_db_type(field_def['field_type'] || field_def['type'] || 'string')
      
      # Check if column already exists
      return if ActiveRecord::Base.connection.column_exists?(table_name, column_name)
      
      # Add the column
      ActiveRecord::Base.connection.add_column(table_name, column_name, column_type.to_sym)
      
      # Reset column information
      model_class.reset_column_information
      
      Rails.logger.info "[UpdateModule] Added column #{column_name} to #{table_name}"
    rescue => e
      Rails.logger.error "[UpdateModule] Failed to add column: #{e.message}"
    end

    def map_field_to_db_type(field_type)
      case field_type.to_s.downcase
      when 'string', 'select', 'multi_select', 'user_select'
        'string'
      when 'text', 'rich_text'
        'text'
      when 'integer'
        'integer'
      when 'decimal', 'float'
        'decimal'
      when 'boolean'
        'boolean'
      when 'date'
        'date'
      when 'datetime'
        'datetime'
      when 'json', 'array', 'object', 'media_gallery'
        'jsonb'
      when 'reference'
        'bigint'
      else
        'string'
      end
    end

    # Generate default HTML content for different canvas types
    def generate_default_canvas_html(app_module, canvas_type, canvas_def = {})
      case canvas_type
      when 'dashboard'
        <<~HTML
          <div class="module-dashboard" data-module="#{app_module.slug}">
            <div class="dashboard-stats row mb-4">
              <div class="col-md-3">
                <div class="card bg-primary text-white">
                  <div class="card-body">
                    <h5 class="card-title">Total Records</h5>
                    <h2>{{total_count}}</h2>
                  </div>
                </div>
              </div>
              <div class="col-md-3">
                <div class="card bg-success text-white">
                  <div class="card-body">
                    <h5 class="card-title">This Week</h5>
                    <h2>{{week_count}}</h2>
                  </div>
                </div>
              </div>
              <div class="col-md-3">
                <div class="card bg-info text-white">
                  <div class="card-body">
                    <h5 class="card-title">Today</h5>
                    <h2>{{today_count}}</h2>
                  </div>
                </div>
              </div>
              <div class="col-md-3">
                <div class="card bg-warning text-dark">
                  <div class="card-body">
                    <h5 class="card-title">Trend</h5>
                    <h2>{{trend}}</h2>
                  </div>
                </div>
              </div>
            </div>
            <div class="dashboard-content">
              {{content}}
            </div>
          </div>
        HTML
      when 'report'
        <<~HTML
          <div class="module-report" data-module="#{app_module.slug}">
            <div class="report-header mb-4">
              <h3>#{app_module.name} Report</h3>
              <p class="text-muted">Generated: {{generated_at}}</p>
            </div>
            <div class="report-summary card mb-4">
              <div class="card-body">
                {{summary}}
              </div>
            </div>
            <div class="report-details">
              {{details}}
            </div>
          </div>
        HTML
      else
        <<~HTML
          <div class="module-canvas" data-module="#{app_module.slug}">
            <div class="canvas-content">
              {{content}}
            </div>
          </div>
        HTML
      end
    end

    # Register the canvas with Scout so it appears in the load_canvas tool enum
    def register_canvas_with_scout(app_module, canvas)
      # Update the module's component list
      canvases = app_module.canvases_list
      unless canvases.include?(canvas.slug)
        canvases << canvas.slug
        app_module.update!(components: app_module.components.merge('canvases' => canvases))
      end

      Rails.logger.info "[UpdateModule] Registered new canvas: #{app_module.slug}/#{canvas.slug}"
    end
  end
end

