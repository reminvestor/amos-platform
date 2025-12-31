# frozen_string_literal: true

# DesignModuleSchemaTool
#
# Platform Factory tool that analyzes requirements and designs
# the data model schema for a new module.
#
class Tools::DesignModuleSchemaTool < Tools::BaseTool
  def self.metadata
    {
      name: 'design_module_schema',
      description: 'Analyzes requirements and designs the database schema for a new module. Returns a structured schema definition with models, fields, associations, and indexes.',
      category: 'platform_factory',
      input_schema: {
        type: 'object',
        properties: {
          module_name: {
            type: 'string',
            description: 'Name of the module being designed (e.g., "Inventory Management")'
          },
          requirements: {
            type: 'string',
            description: 'Detailed requirements describing what the module should do'
          },
          existing_models: {
            type: 'array',
            items: { type: 'string' },
            description: 'Optional list of existing models to reference or extend'
          }
        },
        required: %w[module_name requirements]
      }
    }
  end

  def execute(args)
    log_execution(args)

    module_name = get_arg(args, :module_name)
    requirements = get_arg(args, :requirements)
    existing_models = get_arg(args, :existing_models, [])

    return error_response('Module name is required') if module_name.blank?
    return error_response('Requirements are required') if requirements.blank?

    # Find or create the AppModule
    app_module = find_or_create_module(module_name)

    # Use AI to design the schema
    schema_design = design_schema_with_ai(module_name, requirements, existing_models)

    if schema_design[:error]
      return error_response(schema_design[:error])
    end

    # Save the schema to the module
    app_module.update!(
      components: app_module.components.merge(
        'data_models' => schema_design[:models].map { |m| m[:name] }
      ),
      metadata: app_module.metadata.merge(
        'schema_design' => schema_design,
        'designed_at' => Time.current.iso8601
      )
    )

    # Update module status
    app_module.start_design! if app_module.draft?

    success_response(
      module_id: app_module.id,
      module_slug: app_module.slug,
      schema: schema_design,
      models_count: schema_design[:models].length,
      message: "Designed schema with #{schema_design[:models].length} models for #{module_name}",
      next_step: 'Use generate_model_code to create the Ruby model classes'
    )
  end

  private

  def find_or_create_module(module_name)
    slug = module_name.parameterize.underscore
    
    AppModule.find_or_create_by!(entity: entity, slug: slug) do |m|
      m.name = module_name
      m.status = 'draft'
      m.author_type = 'amos'
      m.created_by = user
    end
  end

  def design_schema_with_ai(module_name, requirements, existing_models)
    # Build the prompt for schema design
    prompt = build_design_prompt(module_name, requirements, existing_models)

    # Call the AI service
    bedrock = BedrockService.new
    
    begin
      response = bedrock.send_message(
        schema_design_system_prompt,
        prompt,
        temperature: 0.2,
        json_mode: true
      )

      # Parse the response
      schema = JSON.parse(response)
      validate_schema(schema)
      
      symbolize_schema(schema)
    rescue JSON::ParserError => e
      { error: "Failed to parse schema design: #{e.message}" }
    rescue => e
      { error: "Schema design failed: #{e.message}" }
    end
  end

  def build_design_prompt(module_name, requirements, existing_models)
    prompt = <<~PROMPT
      Design a database schema for a module called "#{module_name}".

      ## Requirements
      #{requirements}

      ## Existing Models Available
      #{existing_models.any? ? existing_models.join(', ') : 'None - this is a standalone module'}

      ## Core Models Always Available
      - User (id, email, name)
      - Entity (id, name, slug) - the business/organization
      - Contact (id, entity_id, email, name)

      ## Instructions
      Design a complete schema that:
      1. Fulfills all the requirements
      2. Uses proper data types (string, text, integer, decimal, boolean, date, datetime, jsonb)
      3. Includes necessary associations (belongs_to, has_many)
      4. Adds appropriate indexes for query performance
      5. Includes validation rules
      6. Follows Rails conventions (snake_case, pluralized table names)

      Return a JSON object with this exact structure:
      {
        "models": [
          {
            "name": "ModelName",
            "table_name": "model_names",
            "description": "What this model represents",
            "fields": [
              { "name": "field_name", "type": "string", "null": false, "default": null }
            ],
            "associations": [
              { "type": "belongs_to", "model": "Entity", "optional": false }
            ],
            "indexes": [
              { "fields": ["entity_id", "created_at"], "unique": false }
            ],
            "validations": [
              { "type": "presence", "fields": ["name"] },
              { "type": "numericality", "field": "quantity", "options": { "greater_than_or_equal_to": 0 } }
            ],
            "scopes": [
              { "name": "active", "condition": "where(active: true)" },
              { "name": "recent", "condition": "order(created_at: :desc)" }
            ]
          }
        ],
        "relationships_diagram": "Optional text description of how models relate"
      }
    PROMPT

    prompt
  end

  def schema_design_system_prompt
    <<~SYSTEM
      You are an expert database architect specializing in Rails applications.
      
      Your task is to design clean, normalized database schemas that:
      - Follow Rails conventions
      - Are properly indexed for performance
      - Have appropriate validations
      - Support the required functionality
      
      Always return valid JSON. Never include code blocks or markdown.
      
      Include these fields on every model:
      - entity_id (references entity, required) - for multi-tenancy
      - created_at, updated_at (timestamps) - Rails handles automatically
      
      Use appropriate field types:
      - string: short text (< 255 chars)
      - text: long text
      - integer: whole numbers
      - decimal: money, measurements (use precision: 10, scale: 2 for money)
      - boolean: true/false
      - date: date only
      - datetime: date and time
      - jsonb: flexible structured data
    SYSTEM
  end

  def validate_schema(schema)
    raise 'Schema must have models array' unless schema['models'].is_a?(Array)
    raise 'Schema must have at least one model' if schema['models'].empty?

    schema['models'].each do |model|
      raise "Model must have name" unless model['name'].present?
      raise "Model must have fields" unless model['fields'].is_a?(Array)
    end
  end

  def symbolize_schema(schema)
    {
      models: schema['models'].map do |model|
        {
          name: model['name'],
          table_name: model['table_name'] || model['name'].underscore.pluralize,
          description: model['description'],
          fields: (model['fields'] || []).map { |f| f.transform_keys(&:to_sym) },
          associations: (model['associations'] || []).map { |a| a.transform_keys(&:to_sym) },
          indexes: (model['indexes'] || []).map { |i| i.transform_keys(&:to_sym) },
          validations: (model['validations'] || []).map { |v| v.transform_keys(&:to_sym) },
          scopes: (model['scopes'] || []).map { |s| s.transform_keys(&:to_sym) }
        }
      end,
      relationships_diagram: schema['relationships_diagram']
    }
  end
end


