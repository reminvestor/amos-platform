# frozen_string_literal: true

module Tools
  # PreviewAppTool - Opens an app in preview mode for testing
  #
  # Shows the primary module's default canvas and allows testing
  # all functionality before publishing.
  #
  class PreviewAppTool < BaseTool
    def self.metadata
      {
        name: "preview_app",
        description: "Open an app in preview mode to test it. Shows the app's primary module and allows testing all features.",
        category: "app_building",
        input_schema: {
          type: "object",
          properties: {
            app_id: { type: "integer", description: "The ID of the app to preview (optional if app_slug provided)" },
            app_slug: { type: "string", description: "The slug of the app to preview" },
            module_slug: { type: "string", description: "Optional: specific module to preview (defaults to primary)" },
            canvas_type: { type: "string", description: "Optional: specific canvas type to show (list, form, calendar, kanban)" }
          },
          required: []
        }
      }
    end
    
    def execute(args)
      log_execution(args)
      
      app_id = get_arg(args, :app_id)
      app_slug = get_arg(args, :app_slug)
      module_slug = get_arg(args, :module_slug)
      canvas_type = get_arg(args, :canvas_type)
      
      # Find the app
      app = if app_id
              App.find_by(id: app_id, entity_id: entity.id)
            elsif app_slug
              App.find_by(slug: app_slug, entity_id: entity.id)
            else
              # Find most recent app in preview or active status
              App.where(entity_id: entity.id)
                 .where(status: %w[preview active])
                 .order(updated_at: :desc)
                 .first
            end
      
      unless app
        return error_response(
          "App not found",
          suggestion: "Try listing apps with: 'Show me my apps'"
        )
      end
      
      unless app.preview? || app.active?
        return error_response(
          "App '#{app.name}' is not ready for preview. Status: #{app.status}",
          suggestion: app.planning? ? "Build the app first" : "Complete the design phase"
        )
      end
      
      # Find the module to show
      target_module = if module_slug
                        app.app_modules.find_by(slug: module_slug)
                      else
                        app.primary_module
                      end
      
      unless target_module
        return error_response(
          "No modules found in app '#{app.name}'",
          suggestion: "The app may not have been built correctly"
        )
      end
      
      # Find the canvas to show
      target_canvas = if canvas_type
                        target_module.module_canvases.find_by(canvas_type: canvas_type)
                      else
                        target_module.module_canvases.find_by(is_default: true) ||
                        target_module.module_canvases.first
                      end
      
      unless target_canvas
        return error_response(
          "No canvases found for module '#{target_module.name}'",
          suggestion: "The module may not have been built correctly"
        )
      end
      
      # Build canvas name for load_canvas
      canvas_name = "module_#{target_canvas.slug}"
      
      # Get app statistics
      stats = build_app_stats(app)
      
      success_response(
        app_id: app.id,
        app_name: app.name,
        app_status: app.status,
        module_name: target_module.name,
        module_slug: target_module.slug,
        canvas_name: canvas_name,
        canvas_type: target_canvas.canvas_type,
        stats: stats,
        available_modules: app.app_modules.map { |m| { name: m.name, slug: m.slug } },
        available_canvases: target_module.module_canvases.map { |c| 
          { name: c.name, slug: c.slug, type: c.canvas_type } 
        },
        has_assistant: app.app_assistant.present?,
        assistant_name: app.app_assistant&.name,
        load_canvas: canvas_name,
        message: <<~MSG
          🎯 **#{app.name}** is ready for testing!
          
          #{stats[:summary]}
          
          **Current View:** #{target_canvas.name} (#{target_canvas.canvas_type})
          
          **Available Modules:**
          #{app.app_modules.map { |m| "- #{m.name}" }.join("\n")}
          
          #{app.app_assistant ? "**AI Assistant:** #{app.app_assistant.name} is available to help!" : ""}
          
          Try it out! You can:
          - Create new records
          - Edit existing records
          - Test workflows and actions
          - Switch between views (list, form, calendar, board)
        MSG
      )
    end
    
    private
    
    def build_app_stats(app)
      modules = app.app_modules
      total_records = 0
      
      modules.each do |mod|
        begin
          model_code = mod.module_codes.where(code_type: 'model', status: 'deployed').first
          next unless model_code
          
          model_class = Modules::DynamicModelLoader.instance.get_model(mod, mod.slug.classify)
          model_class ||= Modules::DynamicModelLoader.instance.load_model(model_code)
          next unless model_class
          
          total_records += model_class.where(entity_id: entity.id).count
        rescue => e
          Rails.logger.warn "[PreviewApp] Could not count records for #{mod.slug}: #{e.message}"
        end
      end
      
      {
        modules_count: modules.count,
        canvases_count: modules.sum { |m| m.module_canvases.count },
        actions_count: modules.sum { |m| m.module_actions.count },
        records_count: total_records,
        has_workflows: app.metadata&.keys&.any? { |k| k.to_s.start_with?('workflow_') },
        summary: "#{modules.count} modules, #{total_records} records"
      }
    end
  end
end

