# frozen_string_literal: true

module Tools
  # Approves the current module design and kicks off the build process
  class ApproveModuleDesignTool < BaseTool
    def self.metadata
      {
        name: 'approve_module_design',
        description: 'Approve the proposed module schema and start building. ' \
                     "Use this when the user confirms they're happy with the proposed design.",
        category: 'module_building',
        input_schema: {
          type: 'object',
          properties: {
            session_id: {
              type: 'integer',
              description: 'The design session ID (omit to use the active session)'
            },
            user_confirmation: {
              type: 'string',
              description: "The user's approval message for logging"
            }
          },
          required: []
        }
      }
    end

    def execute(args)
      log_execution(args)
      
      entity = @entity
      @args = args
      
      # Find session
      session = find_session(entity)
      return session if session.is_a?(Hash) # Error response
      
      # Validate we have a schema to build
      unless session.has_proposed_schema?
        return {
          success: false,
          error: 'No schema has been proposed yet. Use propose_module_schema first.'
        }
      end
      
      # Approve and transition to building
      session.approve_schema!
      
      # Create the module record
      app_module = create_module(entity, session)
      
      # Create the ModuleCode record and database table
      model_code = create_module_code(app_module, session.final_schema)
      
      # Load the dynamic model and create the table
      if model_code
        begin
          Modules::DynamicModelLoader.instance.load_model(model_code)
          model_code.mark_deployed!
          Rails.logger.info "[ApproveModuleDesign] Created table and model for #{app_module.slug}"
        rescue => e
          Rails.logger.error "[ApproveModuleDesign] Failed to create table: #{e.message}"
        end
      end
      
      # Create canvases from the schema
      canvases = create_basic_canvases(app_module, session.final_schema)
      
      # Create CRUD tools for the module
      tools = create_crud_tools(app_module, session.final_schema)
      
      # Update components to list what was created
      table_name = app_module.slug.pluralize
      app_module.update!(
        status: 'active',
        icon: session.final_schema.dig('module', 'icon') || 'calendar',
        components: {
          'canvases' => canvases.map { |c| { 'slug' => c.slug, 'name' => c.name, 'type' => c.canvas_type } },
          'data_models' => [{ 'name' => app_module.slug.classify, 'table' => table_name, 'fields_count' => session.field_count }],
          'tools' => tools.map { |t| { 'name' => t.name, 'id' => t.id } },
          'webhooks' => []
        }
      )
      session.update!(status: 'completed', app_module: app_module)
      
      # Generate automation configurations (workflows, scheduled tasks, webhooks)
      begin
        automation_result = Modules::AutomationGenerator.new(app_module: app_module, user: @user).generate!
        Rails.logger.info "[ApproveModuleDesign] Generated automations: #{automation_result[:workflows].length} workflows, #{automation_result[:scheduled_tasks].length} task templates"
      rescue => e
        Rails.logger.warn "[ApproveModuleDesign] Automation generation failed (non-fatal): #{e.message}"
      end
      
      # Get the list canvas slug for loading
      # Canvas format is: module_<canvas.slug> where canvas.slug is the full slug from ModuleCanvas
      list_canvas = canvases.find { |c| c.canvas_type == 'data_grid' }
      canvas_slug = list_canvas ? "module_#{list_canvas.slug}" : "module_#{app_module.slug}_list"
      
      # Broadcast canvas load to show the new module
      scout_session_id = @context[:session_id] if @context
      if scout_session_id
        ActionCable.server.broadcast(
          "scout_channel_#{scout_session_id}",
          {
            type: 'canvas_load',
            canvas_type: canvas_slug,
            canvas_title: app_module.name,
            canvas_data: {}
          }
        )
        Rails.logger.info "[ApproveModuleDesign] Broadcast canvas load for #{canvas_slug}"
      end
      
      {
        success: true,
        message: "✅ Your '#{app_module.name}' is live!",
        built: [
          "📊 Data model with #{session.field_count} fields",
          "🎨 Views for managing records",
          "🔧 Full CRUD capabilities",
          "⚡ Automations ready to configure"
        ],
        module_id: app_module.id,
        module_slug: app_module.slug,
        canvas_loaded: canvas_slug,
        canvas_suggestion: {
          type: canvas_slug,
          data: {}
        },
        # Ecosystem value - what they can NOW do because of this
        ecosystem_powers: [
          "🤖 Ask me anything about your #{app_module.name} data",
          "🔗 Connect it to workflows and automations",
          "📊 Include it in reports and dashboards",
          "🤝 Other agents can now access your #{app_module.name} too",
          "📥 Export data anytime as CSV, PDF, or Excel"
        ],
        next_steps: [
          "Say 'add a new #{app_module.name.singularize}' to create records",
          "Ask me to customize or add features anytime"
        ]
      }
    end
    
    private
    
    def find_session(entity)
      session_id = get_arg(@args, :session_id)
      if session_id
        session = ModuleDesignSession.find_by(id: session_id, entity_id: entity.id)
        return { success: false, error: 'Design session not found' } unless session
      else
        session = ModuleDesignSession.active.for_entity(entity.id).first
        return { success: false, error: 'No active design session.' } unless session
      end
      
      unless session.awaiting_feedback? || session.refining?
        return { 
          success: false, 
          error: "Session is in '#{session.status}' state. Need a proposed schema to approve." 
        }
      end
      
      session
    end
    
    def create_module(entity, session)
      AppModule.create!(
        entity: entity,
        created_by: @user,  # CRITICAL: Track who created this module for visibility/permissions
        name: session.final_schema['module_name'] || session.module_name,
        slug: (session.final_schema['module_name'] || session.module_name).parameterize.underscore,
        description: session.final_schema['description'] || session.user_description,
        status: 'generating',  # Valid status: draft, designing, generating, testing, deployed, active, disabled, failed
        version: '1.0.0',
        author_type: 'amos',
        visibility: 'user_private',  # Default: only creator sees it until they share
        metadata: {
          schema: session.final_schema,
          design_session_id: session.id
        }
      )
    end
    
    def create_module_code(app_module, schema)
      # Build schema definition for DynamicModelLoader
      fields = (schema['fields'] || []).map do |f|
        {
          'name' => f['name'],
          'type' => convert_field_type(f['field_type'] || f['type'] || 'string'),
          'null' => f['required'] != true,
          'default' => f['default_value']
        }
      end
      
      schema_definition = {
        'table_name' => app_module.slug.pluralize,
        'fields' => fields,
        'associations' => [],
        'indexes' => [
          { 'fields' => ['entity_id'] }
        ]
      }
      
      # Create the ModuleCode record
      ModuleCode.create!(
        app_module: app_module,
        entity_id: app_module.entity_id,
        name: app_module.slug.classify,
        code_type: 'model',
        content: generate_model_code(app_module, schema),
        schema_definition: schema_definition,
        status: 'validated'
      )
    rescue => e
      Rails.logger.error "[ApproveModuleDesign] Failed to create ModuleCode: #{e.message}"
      nil
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
    
    def generate_model_code(app_module, schema)
      # Generate a simple model class definition
      model_name = app_module.slug.classify
      table_name = app_module.slug.pluralize
      
      <<~RUBY
        # Auto-generated model for #{app_module.name}
        class #{model_name} < ApplicationRecord
          self.table_name = '#{table_name}'
          
          belongs_to :entity
          
          # Scopes
          scope :for_entity, ->(entity_id) { where(entity_id: entity_id) }
        end
      RUBY
    end
    
    SUPPORTED_FIELD_TYPES = %w[string text integer decimal boolean date datetime json enum select reference].freeze
    REFERENCEABLE_MODELS = %w[LandingPage Contact Campaign User EmailTemplate Opportunity].freeze

    def create_basic_canvases(app_module, schema)
      canvases = []
      
      # Validate and normalize field definitions
      validated_fields = validate_and_normalize_fields(schema['fields'] || [])
      
      # Create a list/grid canvas
      # Store display fields in metadata so controller can render the table
      display_fields = validated_fields.first(6).map { |f| f['name'] }
      
      canvases << ModuleCanvas.create!(
        app_module: app_module,
        entity_id: app_module.entity_id,
        name: "#{app_module.name} List",
        slug: "#{app_module.slug}_list",
        canvas_type: 'data_grid',
        is_default: true,
        html_content: generate_list_canvas_html(app_module, schema),
        data_sources: [{ type: 'module_data', model: app_module.slug }],
        metadata: {
          display_fields: display_fields,
          icon: schema.dig('module', 'icon') || 'database',
          description: "List view for #{app_module.name} records"
        }
      )
      
      # Create a form canvas with ALL validated fields
      canvases << ModuleCanvas.create!(
        app_module: app_module,
        entity_id: app_module.entity_id,
        name: "#{app_module.name} Form",
        slug: "#{app_module.slug}_form",
        canvas_type: 'form',
        html_content: generate_form_canvas_html(app_module, schema),
        data_sources: [],
        metadata: {
          fields: validated_fields,  # Use validated fields
          icon: schema.dig('module', 'icon') || 'database'
        }
      )
      
      Rails.logger.info "[ApproveModuleDesign] Created #{canvases.length} canvases with #{validated_fields.length} fields"
      
      canvases
    end

    # Validates field definitions and fixes common issues
    def validate_and_normalize_fields(fields)
      fields.map do |field|
        normalized = field.stringify_keys.dup
        field_name = normalized['name']
        field_type = normalized['field_type'] || normalized['type']
        
        # Auto-detect reference fields by _id suffix
        if field_name.to_s.end_with?('_id') && field_type.blank?
          normalized['field_type'] = 'reference'
          # Try to infer reference_model from field name
          inferred_model = field_name.to_s.gsub(/_id$/, '').classify
          normalized['reference_model'] ||= inferred_model if REFERENCEABLE_MODELS.include?(inferred_model)
          Rails.logger.info "[ApproveModuleDesign] Auto-detected reference field: #{field_name} -> #{inferred_model}"
        end
        
        # Ensure field_type is set
        if normalized['field_type'].blank? && normalized['type'].present?
          normalized['field_type'] = normalized['type']
        end
        
        # Warn about missing field_type
        if normalized['field_type'].blank?
          Rails.logger.warn "[ApproveModuleDesign] Field '#{field_name}' has no field_type, defaulting to 'string'"
          normalized['field_type'] = 'string'
        end
        
        # Warn about reference fields without reference_model
        if normalized['field_type'] == 'reference' && normalized['reference_model'].blank? && normalized['references'].blank?
          Rails.logger.warn "[ApproveModuleDesign] Reference field '#{field_name}' missing reference_model"
        end
        
        # Warn about enum fields without options
        if %w[enum select].include?(normalized['field_type']) && (normalized['options'].blank? || !normalized['options'].is_a?(Array))
          Rails.logger.warn "[ApproveModuleDesign] Enum field '#{field_name}' missing options array"
        end
        
        normalized
      end
    end
    
    def create_crud_tools(app_module, schema)
      tools = []
      model_name = app_module.slug.classify
      model_path = "#{app_module.slug}/#{model_name}"
      fields = schema['fields'] || []
      
      # Build permitted fields list (excluding system fields)
      permitted_fields = fields.map { |f| f['name'] }.reject { |n| %w[id entity_id created_at updated_at].include?(n) }
      
      # Create tool - creates a new record
      tools << ToolDefinition.create!(
        entity: app_module.entity,
        app_module: app_module,
        name: "create_#{app_module.slug}",
        description: "Create a new #{app_module.name.singularize} record",
        execution_type: 'ruby_code',
        parameters: {
          type: 'object',
          properties: fields.each_with_object({}) do |f, hash|
            hash[f['name']] = { type: ruby_type_to_json(f['field_type'] || f['type']), description: f['description'] || f['name'].titleize }
          end,
          required: fields.select { |f| f['required'] }.map { |f| f['name'] }
        },
        code: generate_create_tool_code(app_module, model_path, permitted_fields),
        scout_accessible: true
      )
      
      # List tool - fetches all records
      tools << ToolDefinition.create!(
        entity: app_module.entity,
        app_module: app_module,
        name: "list_#{app_module.slug.pluralize}",
        description: "List all #{app_module.name} records",
        execution_type: 'ruby_code',
        parameters: {
          type: 'object',
          properties: {
            limit: { type: 'integer', description: 'Max records to return', default: 50 },
            search: { type: 'string', description: 'Search term' }
          }
        },
        code: generate_list_tool_code(app_module, model_path),
        scout_accessible: true
      )
      
      # Update tool
      tools << ToolDefinition.create!(
        entity: app_module.entity,
        app_module: app_module,
        name: "update_#{app_module.slug}",
        description: "Update an existing #{app_module.name.singularize} record",
        execution_type: 'ruby_code',
        parameters: {
          type: 'object',
          properties: { id: { type: 'integer', description: 'Record ID' } }.merge(
            fields.each_with_object({}) { |f, h| h[f['name']] = { type: ruby_type_to_json(f['field_type'] || f['type']) } }
          ),
          required: ['id']
        },
        code: generate_update_tool_code(app_module, model_path, permitted_fields),
        scout_accessible: true
      )
      
      # Delete tool
      tools << ToolDefinition.create!(
        entity: app_module.entity,
        app_module: app_module,
        name: "delete_#{app_module.slug}",
        description: "Delete a #{app_module.name.singularize} record",
        execution_type: 'ruby_code',
        parameters: {
          type: 'object',
          properties: { id: { type: 'integer', description: 'Record ID to delete' } },
          required: ['id']
        },
        code: generate_delete_tool_code(app_module, model_path),
        scout_accessible: true
      )
      
      Rails.logger.info "[ApproveModuleDesign] Created #{tools.length} CRUD tools for #{app_module.slug}"
      tools
    rescue => e
      Rails.logger.error "[ApproveModuleDesign] Failed to create tools: #{e.message}"
      []
    end
    
    def ruby_type_to_json(ruby_type)
      case ruby_type.to_s
      when 'integer', 'decimal', 'float' then 'number'
      when 'boolean' then 'boolean'
      else 'string'
      end
    end
    
    def generate_create_tool_code(app_module, model_path, permitted_fields)
      fields_list = permitted_fields.map { |f| "'#{f}'" }.join(', ')
      <<~RUBY
        model_class = Modules::DynamicModelLoader.instance.get_model_by_path(_context[:entity], "#{model_path}")
        return { error: "Model not loaded" } unless model_class
        
        permitted = [#{fields_list}]
        attrs = _args.slice(*permitted).merge(entity_id: _context[:entity].id)
        record = model_class.create!(attrs)
        { success: true, id: record.id, message: "#{app_module.name.singularize} created successfully" }
      RUBY
    end
    
    def generate_list_tool_code(app_module, model_path)
      <<~RUBY
        model_class = Modules::DynamicModelLoader.instance.get_model_by_path(_context[:entity], "#{model_path}")
        return { error: "Model not loaded" } unless model_class
        
        records = model_class.where(entity_id: _context[:entity].id).limit(_args['limit'] || 50)
        { success: true, count: records.count, records: records.map(&:attributes) }
      RUBY
    end
    
    def generate_update_tool_code(app_module, model_path, permitted_fields)
      fields_list = permitted_fields.map { |f| "'#{f}'" }.join(', ')
      <<~RUBY
        model_class = Modules::DynamicModelLoader.instance.get_model_by_path(_context[:entity], "#{model_path}")
        return { error: "Model not loaded" } unless model_class
        
        record = model_class.find_by(id: _args['id'], entity_id: _context[:entity].id)
        return { success: false, error: "Record not found" } unless record
        
        permitted = [#{fields_list}]
        record.update!(_args.slice(*permitted))
        { success: true, message: "#{app_module.name.singularize} updated successfully" }
      RUBY
    end
    
    def generate_delete_tool_code(app_module, model_path)
      <<~RUBY
        model_class = Modules::DynamicModelLoader.instance.get_model_by_path(_context[:entity], "#{model_path}")
        return { error: "Model not loaded" } unless model_class
        
        record = model_class.find_by(id: _args['id'], entity_id: _context[:entity].id)
        return { success: false, error: "Record not found" } unless record
        
        record.destroy
        { success: true, message: "#{app_module.name.singularize} deleted successfully" }
      RUBY
    end

    def generate_list_canvas_html(app_module, schema)
      fields = schema['fields']&.first(6) || []
      display_fields = fields.map { |f| f['name'] }
      icon = schema.dig('module', 'icon') || 'database'
      model_name = app_module.slug.classify
      
      # Generate proper Stimulus-connected canvas with working buttons
      <<~HTML
        <div class="module-canvas p-4" 
             data-controller="module-canvas" 
             data-module-canvas-module-value="#{app_module.slug}"
             data-module-canvas-model-value="#{model_name}">
          
          <div class="canvas-actions-bar d-flex justify-content-end gap-2 mb-3">
            <button class="btn btn-sm btn-outline-secondary" 
                    data-action="click->module-canvas#performAction" 
                    data-action-name="refresh">
              <i data-lucide="refresh-cw" class="me-1"></i> Refresh
            </button>
            <button class="btn btn-sm btn-primary" 
                    data-action="click->module-canvas#performAction" 
                    data-action-name="add">
              <i data-lucide="plus" class="me-1"></i> Add New
            </button>
          </div>
          
          <div class="card">
            <div class="card-body">
              <div class="table-responsive">
                <table class="table table-hover">
                  <thead>
                    <tr>
                      #{display_fields.map { |f| "<th>#{f.titleize}</th>" }.join("\n                      ")}
                      <th class="text-end">Actions</th>
                    </tr>
                  </thead>
                  <tbody id="module-data-tbody">
                    <!-- Data loaded dynamically -->
                    <tr>
                      <td colspan="#{display_fields.length + 1}" class="text-center text-muted py-4">
                        <i data-lucide="inbox" class="mb-2" style="width: 48px; height: 48px;"></i>
                        <p class="mb-0">No records yet. Click "Add New" to create one.</p>
                      </td>
                    </tr>
                  </tbody>
                </table>
              </div>
            </div>
          </div>
        </div>
        
        <!-- Add/Edit Modal -->
        <div class="modal fade" id="moduleFormModal" tabindex="-1">
          <div class="modal-dialog modal-lg">
            <div class="modal-content">
              <div class="modal-header">
                <h5 class="modal-title">#{app_module.name.singularize}</h5>
                <button type="button" class="btn-close" data-bs-dismiss="modal"></button>
              </div>
              <div class="modal-body" id="moduleFormContent">
                <!-- Form loaded here -->
              </div>
            </div>
          </div>
        </div>
        
        <script>
          if (window.lucide) lucide.createIcons();
        </script>
      HTML
    end
    
    def generate_form_canvas_html(app_module, schema)
      fields = schema['fields'] || []
      model_name = app_module.slug.classify
      
      form_fields = fields.map do |f|
        field_type = case f['field_type'] || f['type']
                     when 'text' then 'textarea'
                     when 'boolean' then 'checkbox'
                     when 'date' then 'date'
                     when 'datetime' then 'datetime-local'
                     when 'integer', 'decimal' then 'number'
                     when 'enum', 'select' then 'select'
                     else 'text'
                     end
        
        field_name = f['name']
        label = (f['label'] || f['name']).to_s.titleize
        required_attr = f['required'] ? 'required' : ''
        required_star = f['required'] ? '<span class="text-danger">*</span>' : ''
        
        if field_type == 'textarea'
          <<~FIELD
            <div class="mb-3">
              <label class="form-label">#{label} #{required_star}</label>
              <textarea name="#{field_name}" class="form-control" rows="3" #{required_attr}></textarea>
            </div>
          FIELD
        elsif field_type == 'checkbox'
          <<~FIELD
            <div class="mb-3 form-check">
              <input type="checkbox" name="#{field_name}" class="form-check-input" id="field_#{field_name}">
              <label class="form-check-label" for="field_#{field_name}">#{label}</label>
            </div>
          FIELD
        elsif field_type == 'select' && f['options'].is_a?(Array)
          options = f['options'].map { |o| "<option value=\"#{o}\">#{o}</option>" }.join("\n              ")
          <<~FIELD
            <div class="mb-3">
              <label class="form-label">#{label} #{required_star}</label>
              <select name="#{field_name}" class="form-select" #{required_attr}>
                <option value="">Select...</option>
                #{options}
              </select>
            </div>
          FIELD
        else
          <<~FIELD
            <div class="mb-3">
              <label class="form-label">#{label} #{required_star}</label>
              <input type="#{field_type}" name="#{field_name}" class="form-control" #{required_attr}>
            </div>
          FIELD
        end
      end.join("\n")
      
      <<~HTML
        <div class="module-form-canvas p-4" 
             data-controller="module-canvas"
             data-module-canvas-module-value="#{app_module.slug}"
             data-module-canvas-model-value="#{model_name}">
          
          <form id="module-record-form" data-action="submit->module-canvas#saveRecord">
            <input type="hidden" name="id" id="record-id" value="">
            
            <div class="row">
              <div class="col-md-8">
                #{form_fields}
              </div>
            </div>
            
            <div class="d-flex gap-2 mt-4 pt-3 border-top">
              <button type="submit" class="btn btn-primary">
                <i data-lucide="save" class="me-1"></i> Save
              </button>
              <button type="button" class="btn btn-outline-secondary" data-bs-dismiss="modal">
                Cancel
              </button>
            </div>
          </form>
        </div>
        <script>if (window.lucide) lucide.createIcons();</script>
      HTML
    end
  end
end
