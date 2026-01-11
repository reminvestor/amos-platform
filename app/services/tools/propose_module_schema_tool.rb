# frozen_string_literal: true

module Tools
  # Proposes a complete module schema to the user for review and feedback
  # Part of the interactive module design flow
  # 
  # Now supports the full design spec:
  # - Fields (data model)
  # - Integrations (external connections)
  # - Workflows (status-triggered automations)
  # - Scheduled Tasks (time-based automations)
  # - Hub Hooks (team collaboration)
  #
  class ProposeModuleSchemaTool < BaseTool
    def self.metadata
      {
        name: 'propose_module_schema',
        description: 'Propose a COMPLETE module design including data model, integrations, workflows, and automations. ' \
                     'Shows the user what will be created and asks for their approval.',
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
            # ============================================
            # PHASE 1: DATA MODEL
            # ============================================
            fields: {
              type: 'array',
              items: {
                type: 'object',
                properties: {
                  name: { type: 'string', description: 'Field name (snake_case)' },
                  field_type: { 
                    type: 'string', 
                    enum: %w[string text integer decimal boolean date datetime json reference select multi_select user_select],
                    description: 'Data type for the field'
                  },
                  required: { type: 'boolean', description: 'Whether the field is required' },
                  description: { type: 'string', description: 'What this field is for' },
                  default_value: { type: 'string', description: 'Default value if any' },
                  options: { 
                    type: 'array', 
                    items: { type: 'string' },
                    description: 'For select/enum fields, the available options'
                  },
                  reference_model: {
                    type: 'string',
                    description: 'For reference fields, which model to link to (e.g., Contact, Campaign)'
                  },
                  ui_component: {
                    type: 'string',
                    enum: %w[rich_text_editor code_editor color_picker file_upload],
                    description: 'Special UI component override'
                  }
                },
                required: %w[name field_type]
              },
              description: 'The fields/columns for the data model'
            },
            relationships: {
              type: 'array',
              items: {
                type: 'object',
                properties: {
                  type: { type: 'string', enum: %w[belongs_to has_many has_one] },
                  model: { type: 'string' },
                  description: { type: 'string' }
                }
              },
              description: 'Relationships to other models'
            },
            suggested_views: {
              type: 'array',
              items: { type: 'string' },
              description: 'UI views/canvases (list, detail, form, calendar, kanban, dashboard)'
            },
            # ============================================
            # PHASE 2: INTEGRATIONS
            # ============================================
            integrations: {
              type: 'array',
              items: {
                type: 'object',
                properties: {
                  name: { type: 'string', description: 'Integration name (e.g., instagram, hubspot, stripe)' },
                  type: { type: 'string', enum: %w[oauth api_key webhook], description: 'Connection type' },
                  description: { type: 'string', description: 'What this integration does' },
                  required_scopes: { type: 'array', items: { type: 'string' } },
                  sync_direction: { type: 'string', enum: %w[inbound outbound bidirectional] }
                },
                required: %w[name type]
              },
              description: 'External platform integrations to set up'
            },
            # ============================================
            # PHASE 3: AUTOMATIONS
            # ============================================
            workflows: {
              type: 'array',
              items: {
                type: 'object',
                properties: {
                  name: { type: 'string', description: 'Workflow name' },
                  trigger: { type: 'string', enum: %w[status_change record_created field_changed scheduled_datetime webhook no_activity] },
                  from_status: { type: 'string', description: 'For status_change: previous status' },
                  to_status: { type: 'string', description: 'For status_change: new status' },
                  field: { type: 'string', description: 'For field_changed/scheduled_datetime: field name' },
                  delay: { type: 'string', description: 'Delay before actions (e.g., 24_hours, 1_week)' },
                  actions: { 
                    type: 'array', 
                    items: { type: 'string' },
                    description: 'Actions to take (notify_team, send_email, update_status, fetch_metrics, etc.)'
                  }
                },
                required: %w[name trigger actions]
              },
              description: 'Status-triggered and event-driven workflows'
            },
            scheduled_tasks: {
              type: 'array',
              items: {
                type: 'object',
                properties: {
                  name: { type: 'string', description: 'Task name' },
                  schedule: { type: 'string', enum: %w[daily weekly monthly triggered] },
                  time: { type: 'string', description: 'Time of day (HH:MM format, e.g., 09:00)' },
                  day: { type: 'string', description: 'Day of week (monday, etc.) or day of month (1-31, last)' },
                  action: { type: 'string', description: 'Action to perform' },
                  description: { type: 'string', description: 'What this task does' },
                  target_agent: { type: 'string', description: 'Agent to handle the task (optional)' }
                },
                required: %w[name schedule action]
              },
              description: 'Time-based scheduled automations'
            },
            # ============================================
            # PHASE 4: HUB INTEGRATION
            # ============================================
            hub_hooks: {
              type: 'array',
              items: {
                type: 'object',
                properties: {
                  event: { type: 'string', description: 'Event name (e.g., record_created, status_changed, high_engagement)' },
                  action: { type: 'string', enum: %w[notify_team dm_owner celebrate alert_urgent request_review] },
                  message: { type: 'string', description: 'Message template with {{placeholders}}' },
                  threshold: { type: 'string', description: 'For threshold events (e.g., above_average, > 1000)' },
                  mention: { type: 'string', description: 'User/group to mention' }
                },
                required: %w[event action]
              },
              description: 'Team collaboration and Hub notifications'
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
      
      # Build the complete schema including all phases
      proposed_schema = build_complete_schema
      
      # Auto-detect archetype and enhance suggestions
      archetype_result = detect_and_enhance_schema(proposed_schema, session)
      
      # Merge archetype suggestions into schema (if user hasn't specified)
      if archetype_result[:archetype] != :custom
        proposed_schema = merge_archetype_suggestions(proposed_schema, archetype_result[:data])
      end
      
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
      
      Rails.logger.info "[ProposeModuleSchema] Design proposed with #{proposed_schema['integrations']&.count || 0} integrations, " \
                        "#{proposed_schema['workflows']&.count || 0} workflows, " \
                        "#{proposed_schema['scheduled_tasks']&.count || 0} scheduled tasks"
      
      {
        success: true,
        session_id: session.id,
        module_name: session.module_name,
        archetype_detected: archetype_result[:archetype],
        message: "I've prepared the complete design preview for #{session.module_name}. " \
                 "The design is now displayed in the canvas. " \
                 "IMPORTANT: You MUST now call the ask_user tool to wait for the user's approval. " \
                 "Ask them to say 'build it' if they approve, or to describe any changes they want.",
        components_proposed: {
          fields: proposed_schema['fields']&.count || 0,
          integrations: proposed_schema['integrations']&.count || 0,
          workflows: proposed_schema['workflows']&.count || 0,
          scheduled_tasks: proposed_schema['scheduled_tasks']&.count || 0,
          hub_hooks: proposed_schema['hub_hooks']&.count || 0
        },
        canvas_loaded: true,
        next_action: "call_ask_user",
        prompt_for_user: "I've loaded a **Design Preview** in your canvas showing everything I'll build. " \
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
    
    def build_complete_schema
      {
        'module_name' => get_arg(@args, :module_name),
        'description' => get_arg(@args, :description),
        # Phase 1: Data Model
        'fields' => get_arg(@args, :fields) || [],
        'relationships' => get_arg(@args, :relationships) || [],
        'suggested_views' => get_arg(@args, :suggested_views) || %w[list form detail],
        # Phase 2: Integrations
        'integrations' => get_arg(@args, :integrations) || [],
        # Phase 3: Automations
        'workflows' => get_arg(@args, :workflows) || [],
        'scheduled_tasks' => get_arg(@args, :scheduled_tasks) || [],
        # Phase 4: Hub Hooks
        'hub_hooks' => get_arg(@args, :hub_hooks) || []
      }
    end
    
    def detect_and_enhance_schema(schema, session)
      module_name = schema['module_name'] || session.module_name || ''
      description = schema['description'] || session.user_description || ''
      
      Modules::ArchetypeIntelligence.detect(name: module_name, description: description)
    end
    
    def merge_archetype_suggestions(schema, archetype_data)
      return schema unless archetype_data
      
      # Only add suggestions if user didn't provide them
      if schema['integrations'].blank? && archetype_data[:suggested_integrations].present?
        schema['integrations'] = archetype_data[:suggested_integrations].map do |i|
          { 'name' => i[:name], 'type' => i[:type], 'description' => i[:description] }
        end
      end
      
      if schema['workflows'].blank? && archetype_data[:suggested_workflows].present?
        schema['workflows'] = archetype_data[:suggested_workflows].map do |w|
          {
            'name' => w[:name],
            'trigger' => w[:trigger].to_s,
            'from_status' => w[:from_status],
            'to_status' => w[:to_status],
            'field' => w[:field],
            'delay' => w[:delay],
            'actions' => w[:actions]
          }.compact
        end
      end
      
      if schema['scheduled_tasks'].blank? && archetype_data[:suggested_scheduled_tasks].present?
        schema['scheduled_tasks'] = archetype_data[:suggested_scheduled_tasks].map do |t|
          {
            'name' => t[:name],
            'schedule' => t[:schedule],
            'time' => t[:time],
            'day' => t[:day],
            'action' => t[:action],
            'description' => t[:description]
          }.compact
        end
      end
      
      if schema['hub_hooks'].blank? && archetype_data[:suggested_hub_hooks].present?
        schema['hub_hooks'] = archetype_data[:suggested_hub_hooks].map do |h|
          {
            'event' => h[:event],
            'action' => h[:action].to_s,
            'message' => h[:message],
            'threshold' => h[:threshold],
            'mention' => h[:mention]
          }.compact
        end
      end
      
      # Also enhance core fields if none provided
      if schema['fields'].blank? && archetype_data[:core_fields].present?
        schema['fields'] = archetype_data[:core_fields].map do |f|
          {
            'name' => f[:name],
            'field_type' => f[:type],
            'required' => f[:required],
            'options' => f[:options],
            'ui_component' => f[:ui_component],
            'default_value' => f[:default]
          }.compact
        end
      end
      
      schema
    end
    
    def build_design_for_canvas(proposed_schema, session)
      fields = proposed_schema['fields'] || []
      views = proposed_schema['suggested_views'] || %w[list form detail]
      integrations = proposed_schema['integrations'] || []
      workflows = proposed_schema['workflows'] || []
      scheduled_tasks = proposed_schema['scheduled_tasks'] || []
      hub_hooks = proposed_schema['hub_hooks'] || []
      
      {
        name: proposed_schema['module_name'] || session.module_name,
        description: proposed_schema['description'] || "Custom module for #{session.module_name}",
        
        # Phase 1: Data Model
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
                description: f['description'],
                options: f['options'],
                ui_component: f['ui_component']
              }.compact
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
          when 'kanban'
            { name: 'Kanban Board', description: 'Drag-and-drop status management' }
          when 'calendar'
            { name: 'Calendar View', description: 'See records by date' }
          else
            { name: v.to_s.titleize, description: nil }
          end
        end,
        
        # Phase 2: Integrations
        integrations: integrations.map do |i|
          {
            name: i['name']&.titleize || i['name'],
            type: i['type'],
            description: i['description']
          }
        end,
        
        # Phase 3: Automations
        workflows: workflows.map do |w|
          {
            name: w['name'],
            trigger: w['trigger'],
            description: describe_workflow(w)
          }
        end,
        
        scheduled_tasks: scheduled_tasks.map do |t|
          {
            name: t['name'],
            schedule: t['schedule'],
            time: t['time'],
            description: t['description']
          }
        end,
        
        # Phase 4: Hub Hooks
        hub_hooks: hub_hooks.map do |h|
          {
            event: h['event'],
            action: h['action'],
            message: h['message']
          }
        end,
        
        features: build_feature_list(proposed_schema, session),
        ai_capabilities: [
          "Create new #{session.module_name&.downcase || 'records'}",
          "Search and filter your data",
          "Generate reports and analytics",
          "Answer questions about your #{session.module_name&.downcase || 'data'}",
          "Help with data entry and updates",
          "Run automations and sync data"
        ]
      }
    end
    
    def describe_workflow(workflow)
      case workflow['trigger']
      when 'status_change'
        "When status changes#{workflow['from_status'] ? " from #{workflow['from_status']}" : ''}#{workflow['to_status'] ? " to #{workflow['to_status']}" : ''}"
      when 'record_created'
        "When a new record is created"
      when 'field_changed'
        "When #{workflow['field']} is updated"
      when 'scheduled_datetime'
        "At the scheduled time in #{workflow['field']}"
      when 'webhook'
        "When external webhook is triggered"
      when 'no_activity'
        "When no activity for #{workflow['days'] || 7} days"
      else
        workflow['trigger']&.humanize
      end
    end
    
    def build_feature_list(proposed_schema, session)
      features = []
      fields = proposed_schema['fields'] || []
      integrations = proposed_schema['integrations'] || []
      workflows = proposed_schema['workflows'] || []
      scheduled_tasks = proposed_schema['scheduled_tasks'] || []
      
      features << "Track #{fields.count} different pieces of information"
      features << "Full search and filtering capabilities"
      features << "Export data to CSV/Excel"
      features << "Mobile-friendly interface"
      features << "AI-powered assistance"
      
      if integrations.any?
        features << "#{integrations.count} external integrations"
      end
      
      if workflows.any?
        features << "#{workflows.count} automated workflows"
      end
      
      if scheduled_tasks.any?
        features << "#{scheduled_tasks.count} scheduled automations"
      end
      
      features
    end
  end
end
