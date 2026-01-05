# frozen_string_literal: true

module Tools
  # PublishAppTool - Publishes an app from preview to active status
  #
  # Validates the app is ready and transitions it to active status.
  #
  class PublishAppTool < BaseTool
    def self.metadata
      {
        name: "publish_app",
        description: "Publish an app from preview mode to active status. Makes the app available for production use.",
        category: "app_building",
        input_schema: {
          type: "object",
          properties: {
            app_id: { type: "integer", description: "The ID of the app to publish" },
            app_slug: { type: "string", description: "The slug of the app to publish" },
            confirm: { type: "boolean", description: "Confirm publishing (default: false for safety)" }
          },
          required: []
        }
      }
    end
    
    def execute(args)
      log_execution(args)
      
      app_id = get_arg(args, :app_id)
      app_slug = get_arg(args, :app_slug)
      confirm = get_arg(args, :confirm)
      
      # Find the app
      app = if app_id
              App.find_by(id: app_id, entity_id: entity.id)
            elsif app_slug
              App.find_by(slug: app_slug, entity_id: entity.id)
            else
              return error_response("Please specify app_id or app_slug")
            end
      
      unless app
        return error_response("App not found")
      end
      
      unless app.preview?
        case app.status
        when 'active'
          return success_response(
            already_published: true,
            message: "**#{app.name}** is already published and active!"
          )
        when 'designing', 'planning'
          return error_response(
            "App '#{app.name}' is still in design phase. Build it first.",
            status: app.status
          )
        when 'building'
          return error_response(
            "App '#{app.name}' is currently being built. Wait for build to complete.",
            status: app.status
          )
        else
          return error_response(
            "App '#{app.name}' cannot be published from status: #{app.status}"
          )
        end
      end
      
      # Validate app is ready
      validation = validate_app_for_publish(app)
      unless validation[:valid]
        return error_response(
          "App '#{app.name}' is not ready to publish",
          issues: validation[:issues],
          suggestion: "Fix these issues and try again"
        )
      end
      
      # Require confirmation
      unless confirm
        return success_response(
          requires_confirmation: true,
          app_id: app.id,
          app_name: app.name,
          validation: validation,
          message: <<~MSG
            ⚠️ **Ready to Publish #{app.name}?**
            
            This will:
            - Make the app available for production use
            - Enable all workflows and automations
            - Make the app visible in the main menu
            
            **Validation passed:**
            #{validation[:checks].map { |c| "✅ #{c}" }.join("\n")}
            
            Say "Yes, publish #{app.name}" to confirm.
          MSG
        )
      end
      
      # Publish the app
      app.publish!
      
      # Activate all modules
      app.app_modules.each do |mod|
        mod.activate! unless mod.active?
      end
      
      # Enable app assistant if present
      if app.app_assistant
        app.app_assistant.update!(is_active: true)
      end
      
      success_response(
        app_id: app.id,
        app_name: app.name,
        status: 'active',
        published: true,
        published_at: app.published_at,
        version: app.version,
        message: <<~MSG
          🎉 **#{app.name}** is now live!
          
          - Version: #{app.version}
          - Published: #{app.published_at.strftime('%B %d, %Y at %I:%M %p')}
          - Modules: #{app.app_modules.count}
          #{app.app_assistant ? "- AI Assistant: #{app.app_assistant.name} is ready to help!" : ""}
          
          Your app is now available for use. Would you like to open it?
        MSG
      )
    end
    
    private
    
    def validate_app_for_publish(app)
      issues = []
      checks = []
      
      # Check modules exist
      if app.app_modules.empty?
        issues << "App has no modules"
      else
        checks << "#{app.app_modules.count} module(s) configured"
      end
      
      # Check each module has canvases
      app.app_modules.each do |mod|
        if mod.module_canvases.empty?
          issues << "Module '#{mod.name}' has no canvases"
        end
        
        # Check model exists
        model_code = mod.module_codes.where(code_type: 'model', status: 'deployed').first
        unless model_code
          issues << "Module '#{mod.name}' has no deployed data model"
        end
      end
      
      if issues.empty?
        checks << "All modules have canvases and data models"
      end
      
      # Check blueprint exists
      if app.blueprint.blank?
        issues << "App has no blueprint"
      else
        checks << "Blueprint is complete"
      end
      
      # Check primary module is set
      unless app.primary_module
        issues << "No primary module designated"
      else
        checks << "Primary module: #{app.primary_module.name}"
      end
      
      {
        valid: issues.empty?,
        issues: issues,
        checks: checks
      }
    end
  end
end

