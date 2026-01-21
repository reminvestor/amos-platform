# frozen_string_literal: true

module Tools
  # LoadDesignCanvasTool - Loads various design-related canvases in the Design Space
  #
  # Supported canvas types:
  # - design_preview: iFrame preview of web app/website/landing page
  # - workflow_editor: Visual workflow/automation editor
  # - component_gallery: Browse Bootstrap components
  # - landing_page_editor: Edit landing pages
  #
  class LoadDesignCanvasTool < BaseTool
    def self.metadata
      {
        name: 'load_design_canvas',
        description: 'Load a design-related canvas in the Design Space. Use this to show previews, ' \
                     'workflow editors, component galleries, or landing page editors to the user.',
        category: 'design',
        input_schema: {
          type: 'object',
          properties: {
            canvas_type: {
              type: 'string',
              enum: %w[design_preview workflow_editor component_gallery landing_page_editor],
              description: 'The type of canvas to load.'
            },
            # For design_preview
            preview_type: {
              type: 'string',
              enum: %w[web_app website landing_page component],
              description: 'For design_preview: What type of content is being previewed.'
            },
            preview_url: {
              type: 'string',
              description: 'For design_preview: URL to load in the preview iFrame.'
            },
            web_app_id: {
              type: 'integer',
              description: 'For design_preview: ID of web app to preview (auto-generates URL).'
            },
            website_id: {
              type: 'integer',
              description: 'For design_preview: ID of website to preview (auto-generates URL).'
            },
            component_type: {
              type: 'string',
              description: 'For component preview: Component type (hero, features, pricing, etc.).'
            },
            component_variant: {
              type: 'string',
              description: 'For component preview: Component variant (gradient, split, etc.).'
            },
            html_content: {
              type: 'string',
              description: 'For design_preview: Raw HTML content to render (if no URL).'
            },
            title: {
              type: 'string',
              description: 'Title to display in the canvas header.'
            },
            edit_mode: {
              type: 'boolean',
              description: 'Whether to enable edit mode initially (default: false).'
            },
            # For workflow_editor
            workflow_id: {
              type: 'integer',
              description: 'For workflow_editor: ID of the automation/workflow to edit.'
            },
            workflow_name: {
              type: 'string',
              description: 'For workflow_editor: Name of the workflow.'
            },
            nodes: {
              type: 'array',
              description: 'For workflow_editor: Array of workflow nodes.'
            },
            edges: {
              type: 'array',
              description: 'For workflow_editor: Array of connections between nodes.'
            },
            automations: {
              type: 'array',
              description: 'For workflow_editor: Array of automation summaries to display.'
            },
            # For component_gallery
            category: {
              type: 'string',
              enum: %w[hero features testimonials pricing forms navigation footer cta],
              description: 'For component_gallery: Component category to show.'
            },
            design_system: {
              type: 'string',
              enum: %w[modern minimal corporate playful elegant dark_mode],
              description: 'For component_gallery: Design system/theme to apply.'
            },
            # For landing_page_editor
            landing_page_id: {
              type: 'integer',
              description: 'For landing_page_editor: ID of the landing page to edit.'
            }
          },
          required: %w[canvas_type]
        }
      }
    end

    def execute(args)
      canvas_type = args['canvas_type']
      
      case canvas_type
      when 'design_preview'
        load_design_preview(args)
      when 'workflow_editor'
        load_workflow_editor(args)
      when 'component_gallery'
        load_component_gallery(args)
      when 'landing_page_editor'
        load_landing_page_editor(args)
      else
        error_response("Unknown canvas type: #{canvas_type}")
      end
    end

    private

    def load_design_preview(args)
      # Generate preview URL if ID is provided
      preview_url = args['preview_url']
      preview_type = args['preview_type'] || 'web_app'
      title = args['title'] || 'Preview'
      
      # Auto-generate URLs based on IDs
      if preview_url.blank?
        case preview_type
        when 'web_app'
          if args['web_app_id'].present?
            preview_url = "/design_preview/web_app/#{args['web_app_id']}"
          end
        when 'website'
          if args['website_id'].present?
            preview_url = "/design_preview/website/#{args['website_id']}"
          end
        when 'landing_page'
          if args['landing_page_id'].present?
            preview_url = "/design_preview/landing_page/#{args['landing_page_id']}"
          end
        when 'component'
          if args['component_type'].present?
            params = {
              type: args['component_type'],
              variant: args['component_variant'] || 'gradient',
              design_system: args['design_system'] || 'modern'
            }
            preview_url = "/design_preview/component?#{params.to_query}"
          end
        end
      end
      
      data = {
        preview_type: preview_type,
        preview_url: preview_url,
        html_content: args['html_content'],
        title: title,
        edit_mode: args['edit_mode'] || false
      }

      broadcast_canvas_load(
        type: 'design_preview',
        data: data
      )

      success_response(
        message: "Loaded #{data[:preview_type]} preview: #{data[:title]}",
        canvas_type: 'design_preview',
        edit_mode: data[:edit_mode]
      )
    end

    def load_workflow_editor(args)
      # If workflow_id provided, load the automation
      if args['workflow_id']
        automation = AutomationCode.find_by(id: args['workflow_id'], entity: @entity)
        if automation
          nodes = build_workflow_nodes(automation)
          data = {
            workflow_name: automation.name,
            workflow_id: automation.id,
            nodes: nodes,
            edges: build_workflow_edges(nodes)
          }
        else
          return error_response("Automation ##{args['workflow_id']} not found")
        end
      elsif args['nodes']
        # Use provided nodes
        data = {
          workflow_name: args['workflow_name'] || 'Workflow',
          nodes: args['nodes'],
          edges: args['edges'] || []
        }
      elsif args['automations']
        # Show automations list
        data = {
          automations: args['automations']
        }
      else
        # Load all automations for this entity
        automations = AutomationCode.for_entity(@entity).active.map do |a|
          {
            id: a.id,
            name: a.name,
            status: a.status,
            trigger_description: "#{a.trigger_type}: #{a.trigger_config}",
            execution_count: a.execution_count
          }
        end
        data = { automations: automations }
      end

      broadcast_canvas_load(
        type: 'workflow_editor',
        data: data
      )

      success_response(
        message: "Loaded workflow editor",
        canvas_type: 'workflow_editor',
        workflow_count: data[:automations]&.size || 1
      )
    end

    def load_component_gallery(args)
      data = {
        category: args['category'] || 'hero',
        design_system: args['design_system'] || 'modern'
      }

      broadcast_canvas_load(
        type: 'component_gallery',
        data: data
      )

      success_response(
        message: "Loaded component gallery - #{data[:category].titleize} components",
        canvas_type: 'component_gallery',
        category: data[:category],
        design_system: data[:design_system]
      )
    end

    def load_landing_page_editor(args)
      landing_page_id = args['landing_page_id']
      
      if landing_page_id
        landing_page = LandingPage.find_by(id: landing_page_id, entity: @entity)
        return error_response("Landing page ##{landing_page_id} not found") unless landing_page

        broadcast_canvas_load(
          type: 'landing_page_editor',
          data: {
            landing_page_id: landing_page.id,
            landing_page_title: landing_page.title,
            landing_page_slug: landing_page.slug
          }
        )

        success_response(
          message: "Loaded landing page editor for '#{landing_page.title}'",
          canvas_type: 'landing_page_editor',
          landing_page_id: landing_page.id
        )
      else
        # Show list of landing pages
        landing_pages = LandingPage.where(entity: @entity).limit(20).map do |lp|
          { id: lp.id, title: lp.title, slug: lp.slug, status: lp.status }
        end

        broadcast_canvas_load(
          type: 'landing_page_list',
          data: { landing_pages: landing_pages }
        )

        success_response(
          message: "Showing #{landing_pages.size} landing pages",
          canvas_type: 'landing_page_list'
        )
      end
    end

    def build_workflow_nodes(automation)
      nodes = []
      
      # Add trigger node
      nodes << {
        id: 'trigger',
        type: 'trigger',
        label: trigger_label(automation),
        description: automation.trigger_config.to_json
      }

      # Parse the code to extract actions (simplified)
      # In a real implementation, we'd parse the Ruby AST
      code = automation.code || ''
      
      if code.include?('send_slack_message')
        nodes << {
          id: 'action_slack',
          type: 'notification',
          label: 'Send Slack Message'
        }
      end

      if code.include?('send_email')
        nodes << {
          id: 'action_email',
          type: 'notification',
          label: 'Send Email'
        }
      end

      if code.include?('http_post') || code.include?('http_get')
        nodes << {
          id: 'action_http',
          type: 'integration',
          label: 'HTTP Request'
        }
      end

      if code.include?('update_record')
        nodes << {
          id: 'action_update',
          type: 'action',
          label: 'Update Record'
        }
      end

      if code.include?('create_record')
        nodes << {
          id: 'action_create',
          type: 'action',
          label: 'Create Record'
        }
      end

      nodes
    end

    def build_workflow_edges(nodes)
      edges = []
      nodes.each_with_index do |node, index|
        next if index == 0
        edges << { from: nodes[index - 1][:id], to: node[:id] }
      end
      edges
    end

    def trigger_label(automation)
      case automation.trigger_type
      when 'record_created' then "When #{automation.trigger_config['model'] || 'record'} is created"
      when 'record_updated' then "When #{automation.trigger_config['model'] || 'record'} is updated"
      when 'status_changed' then "When status changes to #{automation.trigger_config['to']}"
      when 'field_changed' then "When #{automation.trigger_config['field']} changes"
      when 'schedule' then "On schedule: #{automation.trigger_config['schedule']}"
      when 'webhook' then "Webhook: #{automation.trigger_config['path']}"
      when 'form_submit' then "Form submission: #{automation.trigger_config['form_id']}"
      else automation.trigger_type.titleize
      end
    end
  end
end
