# frozen_string_literal: true

# Controller for serving public module canvases
# These are user-created canvases that have been published for public access
class PublicCanvasesController < ApplicationController
  skip_before_action :authenticate_user!
  layout false
  
  def show
    @canvas = ModuleCanvas.published.find_by!(public_slug: params[:slug])
    @canvas.increment_view!
    
    # Get data context from the module
    @data_context = build_data_context
    
    render html: render_canvas_html.html_safe
  rescue ActiveRecord::RecordNotFound
    render file: Rails.root.join('public/404.html'), status: :not_found, layout: false
  end
  
  private
  
  def build_data_context
    context = {}
    
    # Fetch data from configured data sources
    @canvas.data_sources.each do |ds|
      case ds['type']
      when 'static'
        context[ds['key']] = ds['value']
      when 'model'
        # Only public data
        context[ds['key']] = fetch_public_model_data(ds)
      end
    end
    
    context
  end
  
  def fetch_public_model_data(data_source)
    model_name = data_source['model']
    return [] unless model_name.present?
    
    # Only allow safe public queries
    model_class = model_name.safe_constantize
    return [] unless model_class
    
    records = model_class.where(entity_id: @canvas.entity_id)
    
    # Apply public filters only
    if data_source['public_filter'].present?
      records = records.where(data_source['public_filter'])
    end
    
    records.limit(data_source['limit'] || 50).to_a
  rescue StandardError => e
    Rails.logger.error("Error fetching public model data: #{e.message}")
    []
  end
  
  def render_canvas_html
    content = @canvas.render_html(@data_context)
    
    <<~HTML
      <!DOCTYPE html>
      <html lang="en">
      <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>#{ERB::Util.html_escape(@canvas.name)}</title>
        <meta name="description" content="#{ERB::Util.html_escape(@canvas.description || '')}">
        <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/css/bootstrap.min.css" rel="stylesheet">
        <style>
          #{@canvas.css_content}
        </style>
      </head>
      <body>
        #{content}
        <script src="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/js/bootstrap.bundle.min.js"></script>
        <script>
          window.canvasData = #{@data_context.to_json};
          #{@canvas.js_content}
        </script>
      </body>
      </html>
    HTML
  end
end
