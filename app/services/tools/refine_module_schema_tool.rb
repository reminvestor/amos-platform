# frozen_string_literal: true

module Tools
  # Refines a proposed module schema based on user feedback
  class RefineModuleSchemaTool < BaseTool
    def self.metadata
      {
        name: 'refine_module_schema',
        description: 'Modify an existing module schema proposal based on user feedback. ' \
                     'Can add, remove, or modify fields without reproposing the entire schema.',
        category: 'module_building',
        input_schema: {
          type: 'object',
          properties: {
            session_id: {
              type: 'integer',
              description: 'The design session ID (omit to use the active session)'
            },
            action: {
              type: 'string',
              enum: %w[add_field remove_field modify_field update_name add_relationship add_view remove_view],
              description: 'What modification to make: add_field, remove_field, modify_field, update_name, add_relationship, add_view, or remove_view'
            },
            view_definition: {
              type: 'object',
              properties: {
                name: { type: 'string', description: 'View name (e.g., "Add Item Form")' },
                view_type: { type: 'string', enum: %w[dashboard data_grid form report wizard], description: 'Type of view' },
                description: { type: 'string', description: 'What this view is for' }
              },
              description: 'For add_view, the view definition'
            },
            field_name: {
              type: 'string',
              description: 'Name of the field to add/remove/modify'
            },
            field_definition: {
              type: 'object',
              properties: {
                name: { type: 'string' },
                field_type: { type: 'string' },
                required: { type: 'boolean' },
                description: { type: 'string' },
                options: { type: 'array', items: { type: 'string' } }
              },
              description: 'For add_field or modify_field, the field definition'
            },
            new_name: {
              type: 'string',
              description: 'For update_name, the new module name'
            },
            user_feedback: {
              type: 'string',
              description: "The user's feedback that prompted this change"
            }
          },
          required: %w[action]
        }
      }
    end

    def execute(args)
      log_execution(args)
      
      entity = @entity
      @args = args
      
      action = get_arg(args, :action)
      
      # Validate required args
      if error = validate_required_args(args, [:action])
        return error
      end
      
      # Find session
      session = find_session(entity)
      return session if session.is_a?(Hash) # Error response
      
      # Record the feedback
      user_feedback = get_arg(args, :user_feedback)
      session.receive_feedback!(user_feedback) if user_feedback
      
      # Apply the modification
      case action
      when 'add_field'
        add_field(session)
      when 'remove_field'
        remove_field(session)
      when 'modify_field'
        modify_field(session)
      when 'update_name'
        update_name(session)
      when 'add_relationship'
        add_relationship(session)
      when 'add_view'
        add_view(session)
      when 'remove_view'
        remove_view(session)
      else
        return { success: false, error: "Unknown action: #{action}" }
      end
      
      # Re-propose the updated schema
      session.status = 'awaiting_feedback'
      session.iteration_count += 1
      session.save!
      
      {
        success: true,
        message: "I've updated the design. Here's the revised schema:",
        schema_summary: {
          module_name: session.proposed_schema['module_name'] || session.module_name,
          fields: session.proposed_schema['fields'].map { |f| format_field(f) },
          relationships: session.proposed_schema['relationships'] || []
        },
        iteration: session.iteration_count,
        prompt: "Does this look better? Let me know if you want any other changes, or say 'build it' to proceed."
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
      
      session
    end
    
    def add_field(session)
      field = get_arg(@args, :field_definition) || {}
      field['name'] ||= get_arg(@args, :field_name)
      field['field_type'] ||= 'string'
      
      session.add_field_to_proposal(field)
    end
    
    def remove_field(session)
      session.remove_field_from_proposal(get_arg(@args, :field_name))
    end
    
    def modify_field(session)
      updates = get_arg(@args, :field_definition) || {}
      session.modify_field_in_proposal(get_arg(@args, :field_name), updates)
    end
    
    def update_name(session)
      session.proposed_schema['module_name'] = get_arg(@args, :new_name)
      session.module_name = get_arg(@args, :new_name)
      session.save!
    end
    
    def add_relationship(session)
      session.proposed_schema['relationships'] ||= []
      session.proposed_schema['relationships'] << get_arg(@args, :field_definition)
      session.save!
    end
    
    def format_field(field)
      base = "#{field['name']} (#{field['field_type']})"
      base += " - required" if field['required']
      base += " - #{field['description']}" if field['description']
      base
    end
  end
end
