# frozen_string_literal: true

module Tools
  # LoadDmCanvasTool
  #
  # Allows agents in DM (direct message) mode to display a canvas alongside the conversation.
  # This gives agents the same visual communication power that Amos has in the main chat.
  #
  # Usage:
  # - Show data tables, design previews, charts, or custom HTML
  # - Canvas slides in from the right, conversation shrinks
  # - User can close the canvas or agent can close it
  #
  class LoadDmCanvasTool < BaseTool
    def self.metadata
      {
        name: "load_dm_canvas",
        description: "Display a canvas panel alongside the DM conversation. Use this to show data tables, designs, charts, or custom visualizations to the user. The canvas appears on the right side while the conversation stays on the left.",
        category: "communication",
        input_schema: {
          type: "object",
          properties: {
            canvas_type: {
              type: "string",
              enum: ["data_table", "design_preview", "freeform", "chart"],
              description: "Type of canvas to display: 'data_table' for tabular data, 'design_preview' for schema/field displays, 'freeform' for custom HTML, 'chart' for data visualization"
            },
            canvas_title: {
              type: "string",
              description: "Title shown in the canvas header (e.g., 'Analytics Dashboard', 'Module Design')"
            },
            canvas_data: {
              type: "object",
              description: "Data for the canvas. Structure depends on canvas_type. For data_table: {headers: [], rows: [[]]}. For design_preview: {name, description, fields: [{name, type, required}]}. For freeform: {html: '...'}. For chart: {title, type, data: {...}}"
            }
          },
          required: ["canvas_type", "canvas_title", "canvas_data"]
        }
      }
    end

    def execute(args)
      canvas_type = args["canvas_type"]
      canvas_title = args["canvas_title"]
      canvas_data = args["canvas_data"]

      Rails.logger.info "🖼️ LoadDmCanvasTool: #{canvas_type} - #{canvas_title}"

      # Get the thread ID from context (set when agent is in DM mode)
      thread_id = context[:hub_thread_id] || context["hub_thread_id"]
      
      unless thread_id
        # Not in DM mode - try to broadcast via scout channel instead
        session_id = context[:session_id] || context["session_id"]
        
        if session_id
          # Broadcast to question queue canvas panel instead
          broadcast_to_question_queue(session_id, canvas_type, canvas_title, canvas_data)
          return success_response("Canvas displayed in agent response panel")
        else
          return error_response("Cannot display canvas: Not in DM mode and no session context")
        end
      end

      # For freeform, optionally render HTML content
      canvas_html = nil
      if canvas_type == "freeform" && canvas_data["html"]
        canvas_html = sanitize_html(canvas_data["html"])
      end

      # Broadcast canvas to the DM thread
      HubChannel.broadcast_canvas_to_thread(
        thread_id,
        canvas_type: canvas_type,
        canvas_title: canvas_title,
        canvas_data: canvas_data,
        canvas_html: canvas_html
      )

      success_response("Canvas '#{canvas_title}' displayed successfully")
    end

    private

    def broadcast_to_question_queue(session_id, canvas_type, canvas_title, canvas_data)
      # Broadcast canvas update event for the question queue overlay
      ActionCable.server.broadcast(
        "scout_channel_#{session_id}",
        {
          type: 'agent_canvas_update',
          canvas_type: canvas_type,
          canvas_title: canvas_title,
          canvas_data: canvas_data
        }
      )
    end

    def sanitize_html(html)
      # Basic HTML sanitization - remove script tags and dangerous attributes
      # In production, use a proper sanitizer like Loofah
      sanitized = html.to_s
      sanitized = sanitized.gsub(/<script\b[^<]*(?:(?!<\/script>)<[^<]*)*<\/script>/mi, '')
      sanitized = sanitized.gsub(/\s+on\w+\s*=/i, ' data-removed=')
      sanitized = sanitized.gsub(/javascript:/i, 'blocked:')
      sanitized
    end

    def success_response(message)
      {
        success: true,
        message: message
      }
    end

    def error_response(message)
      {
        success: false,
        error: message
      }
    end
  end
end

