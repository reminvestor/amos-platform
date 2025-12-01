# frozen_string_literal: true

module Tools
  class SaveVisualizationTool < BaseTool
    def self.metadata
      {
        name: "save_visualization",
        description: "Save a visualization, report, or dashboard for later reference. Use this when a user wants to keep a visualization they've created.",
        category: "scheduling",
        input_schema: {
          type: "object",
          properties: {
            name: {
              type: "string",
              description: "A name for the saved visualization"
            },
            description: {
              type: "string",
              description: "Optional description of what this visualization shows"
            },
            category: {
              type: "string",
              enum: %w[sales marketing finance support hr operations general],
              description: "Category for organization. Defaults to 'general'."
            },
            pinned: {
              type: "boolean",
              description: "Whether to pin this visualization for quick access. Defaults to false."
            },
            auto_refresh: {
              type: "boolean",
              description: "Whether to automatically refresh this visualization periodically. Defaults to false."
            },
            refresh_schedule: {
              type: "string",
              description: "Cron expression for auto-refresh (e.g., '0 9 * * *' for daily at 9am). Required if auto_refresh is true."
            }
          },
          required: ["name"]
        }
      }
    end

    def execute(args)
      log_execution(args)

      name = get_arg(args, :name)
      description = get_arg(args, :description)
      category = get_arg(args, :category, 'general')
      pinned = get_arg(args, :pinned, false)
      auto_refresh = get_arg(args, :auto_refresh, false)
      refresh_schedule = get_arg(args, :refresh_schedule)

      if name.blank?
        return error_response("name is required")
      end

      if auto_refresh && refresh_schedule.blank?
        return error_response("refresh_schedule is required when auto_refresh is true")
      end

      begin
        # Check if there's a recent dynamic content to save
        # Look in the current session or context
        dynamic_content = find_recent_dynamic_content

        unless dynamic_content
          return error_response("No recent visualization found to save. Create a visualization first using create_dynamic_visualization.")
        end

        # Create the saved visualization
        saved_viz = SavedVisualization.create!(
          entity: @entity,
          user: @user,
          dynamic_content: dynamic_content,
          scout_conversation_id: dynamic_content.scout_conversation_id,
          name: name,
          description: description || dynamic_content.subtitle,
          visualization_type: dynamic_content.content_type,
          source_type: 'dynamic_content',
          source_session_id: @context[:session_id],
          canvas_data_cache: dynamic_content.to_canvas_data,
          category: category,
          pinned: pinned,
          auto_refresh: auto_refresh,
          refresh_schedule: refresh_schedule
        )

        success_response(
          visualization_id: saved_viz.id,
          name: saved_viz.name,
          category: saved_viz.category,
          pinned: saved_viz.pinned?,
          auto_refresh: saved_viz.auto_refresh?,
          message: "💾 Saved visualization '#{name}'#{pinned ? ' (pinned)' : ''}#{auto_refresh ? ' with auto-refresh enabled' : ''}."
        )
      rescue ActiveRecord::RecordInvalid => e
        error_response("Failed to save visualization: #{e.message}")
      rescue => e
        Rails.logger.error "Error saving visualization: #{e.message}"
        error_response("Failed to save visualization: #{e.message}")
      end
    end

    private

    def find_recent_dynamic_content
      # First, try to find content from the current session
      if @context[:session_id].present?
        content = DynamicContent.where(
          entity: @entity,
          user: @user,
          session_id: @context[:session_id]
        ).order(created_at: :desc).first

        return content if content
      end

      # Fall back to most recent content from this user (within last hour)
      DynamicContent.where(
        entity: @entity,
        user: @user
      ).where('created_at > ?', 1.hour.ago)
       .order(created_at: :desc)
       .first
    end
  end
end

