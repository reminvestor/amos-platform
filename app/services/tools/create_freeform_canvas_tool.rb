# frozen_string_literal: true

module Tools
  # CreateFreeformCanvasTool
  # Gives the AI complete creative freedom to generate custom HTML/CSS/JS visualizations
  # without any template constraints. The AI decides the best way to display data.
  #
  # Use this when:
  # - The user wants something creative/custom (infographics, interactive tools, etc.)
  # - Standard charts/tables don't fit the use case
  # - The AI needs full control over presentation
  #
  class CreateFreeformCanvasTool < BaseTool
    # CDN libraries the AI can use in freeform mode
    AVAILABLE_LIBRARIES = {
      "chart.js" => "https://cdn.jsdelivr.net/npm/chart.js@4.4.1/dist/chart.umd.min.js",
      "d3" => "https://cdn.jsdelivr.net/npm/d3@7.8.5/dist/d3.min.js",
      "plotly" => "https://cdn.plot.ly/plotly-2.27.0.min.js",
      "anime" => "https://cdn.jsdelivr.net/npm/animejs@3.2.2/lib/anime.min.js",
      "three" => "https://cdn.jsdelivr.net/npm/three@0.160.0/build/three.min.js",
      "gsap" => "https://cdn.jsdelivr.net/npm/gsap@3.12.4/dist/gsap.min.js",
      "mermaid" => "https://cdn.jsdelivr.net/npm/mermaid@10.6.1/dist/mermaid.min.js",
      "vis-network" => "https://cdn.jsdelivr.net/npm/vis-network@9.1.6/dist/vis-network.min.js",
      "leaflet" => "https://cdn.jsdelivr.net/npm/leaflet@1.9.4/dist/leaflet.js",
      "lodash" => "https://cdn.jsdelivr.net/npm/lodash@4.17.21/lodash.min.js"
    }.freeze

    AVAILABLE_CSS = {
      "leaflet" => "https://cdn.jsdelivr.net/npm/leaflet@1.9.4/dist/leaflet.css",
      "vis-network" => "https://cdn.jsdelivr.net/npm/vis-network@9.1.6/dist/dist/vis-network.min.css"
    }.freeze

    def self.metadata
      {
        name: "create_freeform_canvas",
        description: <<~DESC.squish,
          PRIMARY VISUALIZATION TOOL - Create ANY visualization with full HTML/CSS/JS freedom.
          
          This is your go-to tool for displaying anything to users: dashboards, reports, 
          tables, charts, infographics, interactive tools, custom designs, or any visual content.
          
          You have COMPLETE creative control - design exactly what's best for the request.
          
          CAPABILITIES:
          - Dashboards with KPIs, metrics, and charts
          - Data tables with sorting, filtering, pagination
          - Reports with sections and formatting
          - Interactive visualizations
          - Infographics and creative displays
          - Any HTML/CSS/JS you can write
          
          LIBRARIES AVAILABLE: #{AVAILABLE_LIBRARIES.keys.join(', ')}
          Just add them to 'libraries' array and they load automatically.
          
          BEST PRACTICES:
          - Use CSS variables for theme awareness: --text-primary, --bg-primary, --purple
          - Keep designs clean - show content, not data structure keys
          - Make it beautiful and functional
        DESC
        category: "analytics",
        input_schema: {
          type: "object",
          properties: {
            title: {
              type: "string",
              description: "Title for the visualization (displayed in header)"
            },
            html: {
              type: "string",
              description: "Your custom HTML content. You have FULL creative freedom here. Include any structure, layout, or content you want."
            },
            css: {
              type: "string",
              description: "Your custom CSS styles. Design exactly how you want it to look. Use CSS variables for theme-awareness: --text-primary, --text-secondary, --bg-primary, --bg-secondary, --border-color, --purple"
            },
            javascript: {
              type: "string",
              description: "Your custom JavaScript. Full access to DOM, fetch API, etc. Code runs after DOM is ready."
            },
            libraries: {
              type: "array",
              items: { type: "string" },
              description: "Optional: CDN libraries to load. Available: #{AVAILABLE_LIBRARIES.keys.join(', ')}"
            },
            data: {
              type: "object",
              description: "Optional: Data object that will be available as window.canvasData in your JavaScript"
            }
          },
          required: %w[title html]
        }
      }
    end

    def execute(args)
      log_execution(args)

      title = get_arg(args, :title)
      # Accept either 'html' or 'content' as the HTML parameter (models sometimes use 'content')
      html = get_arg(args, :html) || get_arg(args, :content)
      css = get_arg(args, :css, "")
      javascript = get_arg(args, :javascript, "")
      libraries = get_arg(args, :libraries, [])
      data = get_arg(args, :data, {})

      # Validate required args - html MUST have actual content
      if title.blank?
        return error_response("Missing required argument: title. Please provide a title for the visualization.")
      end
      
      if html.blank?
        # Don't load an empty canvas - return error so model can retry
        return error_response(
          "Missing required argument: html. Please provide the HTML content for the visualization. " \
          "You have full creative freedom - generate HTML with tables, cards, charts, or any layout you want."
        )
      end

      # Build library script tags
      library_scripts = build_library_tags(libraries)
      library_css = build_css_tags(libraries)

      # Pass data to JavaScript context
      data_script = data.present? ? "window.canvasData = #{data.to_json};" : ""

      # Load the freeform canvas - only if we have valid content
      load_freeform_canvas(
        title: title,
        html: html,
        css: css,
        javascript: javascript,
        library_scripts: library_scripts,
        library_css: library_css,
        data_script: data_script
      )

      success_response(
        title: title,
        canvas_loaded: true,
        libraries_loaded: libraries,
        message: "Created custom visualization: #{title}"
      )
    rescue => e
      Rails.logger.error "Freeform canvas creation failed: #{e.message}"
      error_response("Failed to create visualization: #{e.message}")
    end

    private

    def build_library_tags(libraries)
      return "" if libraries.blank?

      libraries.filter_map do |lib|
        lib_key = lib.to_s.downcase.strip
        url = AVAILABLE_LIBRARIES[lib_key]
        next unless url

        %(<script src="#{url}"></script>)
      end.join("\n")
    end

    def build_css_tags(libraries)
      return "" if libraries.blank?

      libraries.filter_map do |lib|
        lib_key = lib.to_s.downcase.strip
        url = AVAILABLE_CSS[lib_key]
        next unless url

        %(<link rel="stylesheet" href="#{url}">)
      end.join("\n")
    end

    def load_freeform_canvas(title:, html:, css:, javascript:, library_scripts:, library_css:, data_script:)
      @context[:canvas_suggestion] = "freeform_canvas"
      @context[:canvas_data] = {
        title: title,
        html: html,
        css: css,
        javascript: javascript,
        library_scripts: library_scripts,
        library_css: library_css,
        data_script: data_script,
        artifact_type: "freeform_visualization"
      }
    end
  end
end
