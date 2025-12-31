# frozen_string_literal: true

module Tools
  # ListAppsTool - Lists all apps for the current entity
  #
  class ListAppsTool < BaseTool
    def self.metadata
      {
        name: "list_apps",
        description: "List all apps for the current organization, with their status and key information.",
        category: "app_building",
        input_schema: {
          type: "object",
          properties: {
            status: { type: "string", description: "Filter by status: designing, planning, building, preview, active, archived, or 'all'" },
            include_modules: { type: "boolean", description: "Include module details in response (default: false)" }
          },
          required: []
        }
      }
    end
    
    def execute(args)
      log_execution(args)
      
      status_filter = get_arg(args, :status)
      include_modules = get_arg(args, :include_modules) || false
      
      apps = App.where(entity_id: entity.id).order(updated_at: :desc)
      
      if status_filter.present? && status_filter != 'all'
        apps = apps.where(status: status_filter)
      end
      
      if apps.empty?
        return success_response(
          count: 0,
          apps: [],
          message: status_filter ? 
            "No apps found with status '#{status_filter}'." : 
            "You haven't created any apps yet. Say 'I want to build a new app' to get started!"
        )
      end
      
      apps_data = apps.map do |app|
        data = {
          id: app.id,
          name: app.name,
          slug: app.slug,
          status: app.status,
          description: app.description,
          icon: app.blueprint.dig('app', 'icon') || 'grid',
          modules_count: app.app_modules.count,
          has_assistant: app.app_assistant.present?,
          created_at: app.created_at,
          updated_at: app.updated_at,
          published_at: app.published_at
        }
        
        if include_modules
          data[:modules] = app.app_modules.map do |mod|
            {
              name: mod.name,
              slug: mod.slug,
              is_primary: mod.is_primary,
              canvases_count: mod.module_canvases.count
            }
          end
        end
        
        data
      end
      
      # Group by status for summary
      by_status = apps.group_by(&:status).transform_values(&:count)
      
      success_response(
        count: apps.count,
        apps: apps_data,
        by_status: by_status,
        load_canvas: 'app_designer',
        message: <<~MSG
          📱 **Your Apps** (#{apps.count} total)
          
          #{apps_data.map { |a| format_app_line(a) }.join("\n")}
          
          #{format_status_summary(by_status)}
        MSG
      )
    end
    
    private
    
    def format_app_line(app)
      status_emoji = case app[:status]
                     when 'active' then '🟢'
                     when 'preview' then '🔵'
                     when 'building' then '🟡'
                     when 'designing', 'planning' then '⚪'
                     when 'archived' then '⚫'
                     else '⚪'
                     end
      
      "#{status_emoji} **#{app[:name]}** (#{app[:status]}) - #{app[:modules_count]} modules"
    end
    
    def format_status_summary(by_status)
      return "" if by_status.empty?
      
      parts = []
      parts << "#{by_status['active']} active" if by_status['active']
      parts << "#{by_status['preview']} in preview" if by_status['preview']
      parts << "#{by_status['building']} building" if by_status['building']
      in_design = (by_status['designing'] || 0) + (by_status['planning'] || 0)
      parts << "#{in_design} in design" if in_design > 0
      
      "_Status: #{parts.join(', ')}_"
    end
  end
end

