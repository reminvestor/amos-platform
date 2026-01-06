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
      
      # Broadcast canvas load to show the design preview
      session_id = @context[:session_id] if @context
      if session_id
        ActionCable.server.broadcast(
          "scout_channel_#{session_id}",
          {
            type: 'canvas_load',
            canvas_type: 'module_design_preview',
            canvas_title: "Design Preview: #{session.module_name}",
            canvas_data: {
              session_id: session.id,
              design: build_design_for_canvas(proposed_schema, session)
            }
          }
        )
      end
      
      # Return success - the agent should call ask_user SEPARATELY to wait for approval
      # DO NOT call ask_user from within this tool (causes nested tool call issues)
      Rails.logger.info "[ProposeModuleSchema] Design proposed, returning. Agent should now call ask_user."
      
      {
        success: true,
        session_id: session.id,
        module_name: session.module_name,
        message: "I've prepared the design preview for #{session.module_name}. " \
                 "The design is now displayed in the canvas. " \
                 "IMPORTANT: You MUST now call the ask_user tool to wait for the user's approval. " \
                 "Ask them to say 'build it' if they approve, or to describe any changes they want.",
        canvas_loaded: true,
        next_action: "call_ask_user",
        prompt_for_user: "I've loaded a **Design Preview** in your canvas showing exactly what I'll build. " \
                         "Take a look and let me know:\n\n" \
                         "✅ Say **\"build it\"** or **\"looks good\"** to create it\n" \
                         "✏️ Or tell me what you'd like to change"
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
    
    def format_proposal_for_user(schema, session)
      module_name = schema['module_name'] || session.module_name || 'Your Module'
      fields = schema['fields'] || []
      views = schema['suggested_views'] || %w[list form detail]
      
      # Build a user-friendly proposal message
      message = <<~PROPOSAL
        # 📋 Proposed Design: #{module_name}
        
        #{schema['description']}
        
        ## 📦 What You'll Track (#{fields.count} fields)
        
        #{format_fields_for_display(fields)}
        
        ## 📊 Views You'll Get
        
        #{format_views_for_display(views)}
        
        ## 🤖 What I'll Be Able To Help With
        
        - Add new #{module_name.downcase} records
        - Search and filter your data
        - Generate reports
        - Answer questions about your #{module_name.downcase}
        
        ---
        
        **Does this look right?**
        
        - Say **"build it"** or **"looks good"** to create this module
        - Or tell me what changes you'd like (e.g., "add a notes field", "remove supplier", "I also need to track warranty dates")
      PROPOSAL
      
      message.strip
    end
    
    def format_fields_for_display(fields)
      fields.map do |field|
        name = (field['name'] || '').to_s.titleize
        type_display = case field['field_type']
        when 'string' then '📝 Text'
        when 'text' then '📄 Long text'
        when 'integer' then '🔢 Number'
        when 'decimal' then '💰 Decimal'
        when 'boolean' then '✅ Yes/No'
        when 'date' then '📅 Date'
        when 'datetime' then '🕐 Date & Time'
        when 'json' then '📊 Structured data'
        when 'reference' then "🔗 Link to #{field['reference_model']}"
        else field['field_type']
        end
        
        required = field['required'] ? ' (required)' : ''
        desc = field['description'] ? " - #{field['description']}" : ''
        
        "- **#{name}** #{type_display}#{required}#{desc}"
      end.join("\n")
    end
    
    def format_views_for_display(views)
      views.map do |view|
        case view.to_s.downcase
        when 'list', 'data_grid' then '- 📋 **List View** - See all records with search and filters'
        when 'form' then '- ✏️ **Form** - Add and edit records easily'
        when 'detail' then '- 📄 **Detail View** - See full information for any record'
        when 'dashboard' then '- 📊 **Dashboard** - Overview with stats and charts'
        when 'calendar' then '- 📅 **Calendar View** - See records by date'
        else "- #{view.to_s.titleize}"
        end
      end.join("\n")
    end
    
    def build_design_for_canvas(proposed_schema, session)
      fields = proposed_schema['fields'] || []
      views = proposed_schema['suggested_views'] || %w[list form detail]
      
      {
        name: proposed_schema['module_name'] || session.module_name,
        description: proposed_schema['description'] || "Custom module for #{session.module_name}",
        models: [
          {
            name: (proposed_schema['module_name'] || session.module_name).to_s.singularize.classify,
            description: proposed_schema['description'],
            fields: fields.map do |f|
              {
                name: f['name'],
                type: f['field_type'],
                field_type: f['field_type'],
                required: f['required'] || false,
                description: f['description']
              }
            end
          }
        ],
        views: views.map do |v|
          case v.to_s.downcase
          when 'list', 'data_grid'
            { name: 'List View', description: 'See all records with search and filters' }
          when 'form'
            { name: 'Add/Edit Form', description: 'Add and edit records easily' }
          when 'detail'
            { name: 'Detail View', description: 'See full information for any record' }
          when 'dashboard'
            { name: 'Dashboard', description: 'Overview with stats and charts' }
          else
            { name: v.to_s.titleize, description: nil }
          end
        end,
        features: build_feature_list(proposed_schema, session),
        ai_capabilities: [
          "Create new #{session.module_name&.downcase || 'records'}",
          "Search and filter your data",
          "Generate reports and analytics",
          "Answer questions about your #{session.module_name&.downcase || 'data'}",
          "Help with data entry and updates",
          "Set up automations and alerts"
        ]
      }
    end
    
    def build_feature_list(proposed_schema, session)
      features = []
      fields = proposed_schema['fields'] || []
      
      features << "Track #{fields.count} different pieces of information"
      features << "Full search and filtering capabilities"
      features << "Export data to CSV/Excel"
      features << "Mobile-friendly interface"
      features << "AI-powered assistance"
      features << "Secure, multi-tenant data storage"
      
      features
    end
  end
end
