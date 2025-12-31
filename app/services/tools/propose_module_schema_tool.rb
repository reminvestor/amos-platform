# frozen_string_literal: true

module Tools
  # Proposes a module schema to the user for review and feedback
  # Part of the interactive module design flow
  class ProposeModuleSchemaTool < BaseTool
    def self.metadata
      {
        name: 'propose_module_schema',
        description: 'Propose a data structure/schema for a module being designed. ' \
                     'Shows the user what fields and relationships will be created and asks for their approval or feedback.',
        category: 'module_building',
        input_schema: {
          type: 'object',
          properties: {
            session_id: {
              type: 'integer',
              description: 'The design session ID (omit to use the active session)'
            },
            module_name: {
              type: 'string',
              description: 'Updated module name if refined from user input'
            },
            description: {
              type: 'string',
              description: 'Updated description of what the module does'
            },
            fields: {
              type: 'array',
              items: {
                type: 'object',
                properties: {
                  name: { type: 'string', description: 'Field name (snake_case)' },
                  field_type: { 
                    type: 'string', 
                    enum: %w[string text integer decimal boolean date datetime json reference],
                    description: 'Data type for the field'
                  },
                  required: { type: 'boolean', description: 'Whether the field is required' },
                  description: { type: 'string', description: 'What this field is for' },
                  default_value: { type: 'string', description: 'Default value if any' },
                  options: { 
                    type: 'array', 
                    items: { type: 'string' },
                    description: 'For enum/select fields, the available options'
                  },
                  reference_model: {
                    type: 'string',
                    description: 'For reference fields, which model to link to (e.g., Contact, Campaign)'
                  }
                },
                required: %w[name field_type]
              },
              description: 'The fields/columns to create for this module'
            },
            relationships: {
              type: 'array',
              items: {
                type: 'object',
                properties: {
                  type: { 
                    type: 'string', 
                    enum: %w[belongs_to has_many has_one],
                    description: 'Type of relationship'
                  },
                  model: { type: 'string', description: 'Related model name' },
                  description: { type: 'string', description: 'Purpose of this relationship' }
                }
              },
              description: 'Relationships to other models'
            },
            suggested_views: {
              type: 'array',
              items: { type: 'string' },
              description: 'UI views/canvases that will be created (e.g., list, detail, form, calendar)'
            }
          },
          required: %w[fields]
        }
      }
    end

    def execute(args)
      log_execution(args)
      
      entity = @entity
      @args = args  # Store for helper methods
      
      # Validate required args
      if error = validate_required_args(args, [:fields])
        return error
      end
      
      # Find or validate session
      session = find_session(entity)
      return session if session.is_a?(Hash) # Error response
      
      # Update session with proposed schema
      proposed_schema = build_schema
      session.propose_schema!(proposed_schema)
      
      # Format for user display
      {
        success: true,
        session_id: session.id,
        module_name: session.module_name,
        message: format_proposal_message(proposed_schema),
        schema_summary: {
          fields: proposed_schema['fields'].map { |f| format_field(f) },
          relationships: proposed_schema['relationships'] || [],
          views: proposed_schema['suggested_views'] || %w[list form detail]
        },
        iteration: session.iteration_count,
        prompt: "Does this look right? You can:\n" \
                "• Say 'looks good' or 'build it' to proceed\n" \
                "• Ask to add, remove, or modify fields\n" \
                "• Provide any other feedback to refine the design"
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
        return { success: false, error: 'No active design session. Use start_module_design first.' } unless session
      end
      
      session
    end
    
    def build_schema
      {
        'module_name' => get_arg(@args, :module_name),
        'description' => get_arg(@args, :description),
        'fields' => get_arg(@args, :fields) || [],
        'relationships' => get_arg(@args, :relationships) || [],
        'suggested_views' => get_arg(@args, :suggested_views) || %w[list form detail]
      }
    end
    
    def format_proposal_message(schema)
      field_count = schema['fields'].count
      "Here's my proposed structure for #{schema['module_name'] || 'your module'} with #{field_count} fields:"
    end
    
    def format_field(field)
      base = "#{field['name']} (#{field['field_type']})"
      base += " - required" if field['required']
      base += " - #{field['description']}" if field['description']
      base
    end
  end
end
