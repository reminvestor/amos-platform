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
      
      # Update components to list what was created
      table_name = app_module.slug.pluralize
      app_module.update!(
        status: 'active',
        icon: session.final_schema.dig('module', 'icon') || 'calendar',
        components: {
          'canvases' => canvases.map { |c| { 'slug' => c.slug, 'name' => c.name, 'type' => c.canvas_type } },
          'data_models' => [{ 'name' => app_module.slug.classify, 'table' => table_name, 'fields_count' => session.field_count }],
          'tools' => [],
          'webhooks' => []
        }
      )
      session.update!(status: 'completed', app_module: app_module)
      
      {
        success: true,
        message: "✅ Your '#{app_module.name}' module is ready!",
        built: [
          "📊 Data model with #{session.field_count} fields",
          "🎨 User interface for viewing and managing records",
          "🔧 Full CRUD capabilities via Amos"
        ],
        module_id: app_module.id,
        module_slug: app_module.slug,
        next_steps: [
          "Say 'show me #{app_module.name}' to view the module",
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
        name: session.final_schema['module_name'] || session.module_name,
        slug: (session.final_schema['module_name'] || session.module_name).parameterize.underscore,
        description: session.final_schema['description'] || session.user_description,
        status: 'generating',  # Valid status: draft, designing, generating, testing, deployed, active, disabled, failed
        version: '1.0.0',
        author_type: 'amos',
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
    
    def generate_list_canvas_html(app_module, schema)
      # This HTML is a fallback template - the controller dynamically generates
      # the actual content with real data via render_module_canvas_with_data()
      fields = schema['fields']&.first(6) || []
      display_fields = fields.map { |f| f['name'] }
      icon = schema.dig('module', 'icon') || 'database'
      
      # Store the display configuration in metadata
      # The controller uses this to render actual data
      <<~HTML
        <!-- Dynamic List Canvas: Content rendered by controller with live data -->
        <div class="module-canvas p-4" data-module="#{app_module.slug}" data-canvas-type="data_grid">
          <div class="d-flex justify-content-between align-items-center mb-4">
            <h3><i data-lucide="#{icon}"></i> #{app_module.name}</h3>
            <button class="btn btn-primary" onclick="sendMessageToAmos('Create a new #{app_module.name.singularize}')">
              <i data-lucide="plus"></i> Add New
            </button>
          </div>
          <div class="card">
            <div class="text-center py-4">
              <div class="spinner-border text-primary" role="status">
                <span class="visually-hidden">Loading...</span>
              </div>
              <p class="mt-2 text-muted">Loading data...</p>
            </div>
          </div>
        </div>
        <script>
          function sendMessageToAmos(message) {
            const input = document.getElementById('message-input');
            const form = document.getElementById('message-form');
            if (input && form) {
              input.value = message;
              form.dispatchEvent(new Event('submit', { bubbles: true }));
            }
          }
          if (window.lucide) lucide.createIcons();
        </script>
      HTML
    end
    
    def generate_form_canvas_html(app_module, schema)
      fields = schema['fields'] || []
      form_fields = fields.map do |f|
        field_type = case f['field_type'] || f['type']
                     when 'text' then 'textarea'
                     when 'boolean' then 'checkbox'
                     when 'date' then 'date'
                     when 'datetime' then 'datetime-local'
                     when 'integer', 'decimal' then 'number'
                     else 'text'
                     end
        
        label = (f['label'] || f['name']).to_s.titleize
        required = f['required'] ? 'required' : ''
        
        if field_type == 'textarea'
          "<div class='mb-3'><label class='form-label'>#{label}</label><textarea name='#{f['name']}' class='form-control' #{required}></textarea></div>"
        elsif field_type == 'checkbox'
          "<div class='mb-3 form-check'><input type='checkbox' name='#{f['name']}' class='form-check-input'><label class='form-check-label'>#{label}</label></div>"
        else
          "<div class='mb-3'><label class='form-label'>#{label}</label><input type='#{field_type}' name='#{f['name']}' class='form-control' #{required}></div>"
        end
      end.join("\n        ")
      
      <<~HTML
        <div class="module-form-canvas p-4" data-module="#{app_module.slug}">
          <h3><i data-lucide="edit"></i> New #{app_module.name.singularize}</h3>
          <form id="module-form" class="mt-4">
            #{form_fields}
            <div class="d-flex gap-2 mt-4">
              <button type="submit" class="btn btn-primary">Save</button>
              <button type="button" class="btn btn-outline-secondary" onclick="history.back()">Cancel</button>
            </div>
          </form>
        </div>
        <script>if (window.lucide) lucide.createIcons();</script>
      HTML
    end
  end
end
