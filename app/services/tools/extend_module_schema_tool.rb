# frozen_string_literal: true

module Tools
  # Extends an existing module's schema by adding new fields
  # This allows users to evolve their modules over time
  class ExtendModuleSchemaTool < BaseTool
    def self.metadata
      {
        name: 'extend_module_schema',
        description: 'Add new fields to an existing installed module. ' \
                     'Use this when users want to extend their module with additional data fields.',
        category: 'module_building',
        input_schema: {
          type: 'object',
          properties: {
            module_slug: {
              type: 'string',
              description: 'Slug of the module to extend'
            },
            module_id: {
              type: 'integer',
              description: 'ID of the module to extend (alternative to slug)'
            },
            new_fields: {
              type: 'array',
              items: {
                type: 'object',
                properties: {
                  name: { type: 'string', description: 'Field name (snake_case)' },
                  field_type: { 
                    type: 'string', 
                    enum: %w[string text integer decimal boolean date datetime json],
                    description: 'Data type for the field'
                  },
                  required: { type: 'boolean', description: 'Whether the field is required' },
                  default_value: { type: 'string', description: 'Default value for existing records' },
                  description: { type: 'string', description: 'What this field is for' }
                },
                required: %w[name field_type]
              },
              description: 'New fields to add to the module'
            }
          },
          required: %w[new_fields]
        }
      }
    end

    def execute(args)
      log_execution(args)
      
      entity = @entity
      @args = args
      
      # Validate required args
      if error = validate_required_args(args, [:new_fields])
        return error
      end
      
      # Find the module
      app_module = find_module(entity)
      return app_module if app_module.is_a?(Hash) # Error response
      
      new_fields = get_arg(args, :new_fields) || []
      return { success: false, error: 'No fields provided' } if new_fields.empty?
      
      # Add the new fields
      added_fields = []
      new_fields.each do |field_def|
        field = create_field_definition(entity, app_module, field_def)
        added_fields << field if field
      end
      
      # Update the module's schema configuration
      update_module_schema(app_module, new_fields)
      
      # Queue regeneration of model code if needed
      regenerate_model_if_needed(app_module)
      
      {
        success: true,
        message: "Added #{added_fields.count} new field(s) to '#{app_module.name}':",
        fields_added: added_fields.map { |f| "#{f.name} (#{f.field_type})" },
        module_id: app_module.id,
        note: "Existing records will have #{added_fields.count > 1 ? 'these fields' : 'this field'} available immediately."
      }
    end
    
    private
    
    def find_module(entity)
      module_id = get_arg(@args, :module_id)
      module_slug = get_arg(@args, :module_slug)
      
      if module_id
        app_module = @entity.app_modules.find_by(id: module_id)
      elsif module_slug
        app_module = @entity.app_modules.find_by(slug: module_slug)
      else
        # Try to find the most recently active module
        app_module = @entity.app_modules.where(status: 'active').order(updated_at: :desc).first
      end
      
      return { success: false, error: 'Module not found' } unless app_module
      app_module
    end
    
    def create_field_definition(entity, app_module, field_def)
      CustomFieldDefinition.create!(
        entity: entity,
        app_module: app_module,
        name: field_def['name'],
        field_type: field_def['field_type'] || 'string',
        target_model: app_module.slug.singularize.camelize,
        required: field_def['required'] || false,
        default_value: field_def['default_value'],
        description: field_def['description'],
        configuration: {
          added_at: Time.current.iso8601,
          via: 'extend_module_schema'
        }
      )
    rescue ActiveRecord::RecordInvalid => e
      Rails.logger.error "Failed to create field definition: #{e.message}"
      nil
    end
    
    def update_module_schema(app_module, new_fields)
      schema = app_module.configuration['schema'] || { 'fields' => [] }
      schema['fields'] ||= []
      
      new_fields.each do |field|
        schema['fields'] << field.stringify_keys
      end
      
      app_module.configuration['schema'] = schema
      app_module.configuration['last_extended_at'] = Time.current.iso8601
      app_module.increment!(:version) if app_module.respond_to?(:increment!)
      app_module.save!
    end
    
    def regenerate_model_if_needed(app_module)
      # If the module has model code, queue regeneration
      model_code = app_module.module_codes.models.first
      return unless model_code
      
      # Mark as needing update
      model_code.update!(status: 'needs_regeneration')
      
      # Could queue a job here to regenerate the model
      # PlatformFactoryJob.perform_later(...)
    end
  end
end

