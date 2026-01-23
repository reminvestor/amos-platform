# frozen_string_literal: true

# CanvasHotReloader
#
# Manages hot-reloading of module canvases. When a canvas is updated,
# broadcasts the change to connected clients via ActionCable.
#
module Modules
  class CanvasHotReloader
    include Singleton

    # Broadcast a canvas update to all connected clients
    def reload_canvas(canvas)
      return unless canvas.is_a?(ModuleCanvas)

      # Build the canvas response
      response = canvas.to_canvas_response

      # Broadcast to the entity channel
      ActionCable.server.broadcast(
        "scout_canvas_#{canvas.entity_id}",
        {
          type: 'canvas_reload',
          canvas_type: canvas.full_canvas_type,
          canvas_slug: canvas.slug,
          module_slug: canvas.app_module.slug,
          content: response[:content],
          title: response[:title],
          data: response[:data]
        }
      )

      Rails.logger.info "[CanvasHotReloader] Broadcast update for #{canvas.full_canvas_type}"
    end

    # Notify that a new canvas is available
    def notify_new_canvas(canvas)
      ActionCable.server.broadcast(
        "scout_canvas_#{canvas.entity_id}",
        {
          type: 'canvas_available',
          canvas_type: canvas.full_canvas_type,
          canvas_slug: canvas.slug,
          module_slug: canvas.app_module.slug,
          module_name: canvas.app_module.name,
          canvas_name: canvas.name
        }
      )

      Rails.logger.info "[CanvasHotReloader] Notified new canvas: #{canvas.full_canvas_type}"
    end

    # Notify that a canvas was removed
    def notify_canvas_removed(canvas_type, entity_id)
      ActionCable.server.broadcast(
        "scout_canvas_#{entity_id}",
        {
          type: 'canvas_removed',
          canvas_type: canvas_type
        }
      )

      Rails.logger.info "[CanvasHotReloader] Notified removal: #{canvas_type}"
    end

    # Notify about module status changes
    def notify_module_update(app_module)
      ActionCable.server.broadcast(
        "scout_canvas_#{app_module.entity_id}",
        {
          type: 'module_update',
          module_slug: app_module.slug,
          module_name: app_module.name,
          status: app_module.status,
          canvases: app_module.canvases_list
        }
      )

      Rails.logger.info "[CanvasHotReloader] Notified module update: #{app_module.slug}"
    end

    # Preload canvases for an entity
    def preload_entity_canvases(entity)
      canvases = {}

      entity.app_modules.active.each do |app_module|
        app_module.module_canvases.each do |canvas|
          canvases[canvas.full_canvas_type] = {
            module_slug: app_module.slug,
            canvas_slug: canvas.slug,
            name: canvas.name,
            type: canvas.canvas_type,
            is_default: canvas.is_default
          }
        end
      end

      canvases
    end

    # Get available module canvases for an entity
    def available_canvases(entity)
      entity.app_modules.active.flat_map do |app_module|
        app_module.module_canvases.map do |canvas|
          {
            full_type: canvas.full_canvas_type,
            module_slug: app_module.slug,
            module_name: app_module.name,
            module_icon: app_module.icon,
            canvas_slug: canvas.slug,
            canvas_name: canvas.name,
            canvas_type: canvas.canvas_type,
            ui_mode: canvas.ui_mode,
            is_default: canvas.is_default
          }
        end
      end
    end
  end
end





