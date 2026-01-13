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
          Display data visualization using Bootstrap 5. EMBED DATA DIRECTLY in HTML - no JavaScript needed for basic displays.
          
          USE BOOTSTRAP CLASSES - available automatically:
          - Cards: <div class="card mb-3"><div class="card-body"><h5 class="card-title">Name</h5></div></div>
          - Tables: <table class="table table-striped">
          - Grids: <div class="row g-3"><div class="col-md-6">...</div></div>
          - Lists: <ul class="list-group">
          
          RULES:
          1. EMBED data in HTML - don't use JavaScript to render
          2. Use Bootstrap classes - minimal/no custom CSS needed
          3. Simple is better - cards or tables work for most cases
          4. For dark mode: use text-muted, text-primary (Bootstrap handles it)
          
          EXAMPLE: For 3 customers, output:
          html: "<div class='container py-4'><h2>Customers</h2><div class='card mb-2'><div class='card-body'><h5>John</h5><p class='text-muted'>john@email.com</p></div></div>...</div>"
          
          LIBRARIES (optional): #{AVAILABLE_LIBRARIES.keys.join(', ')}
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
              description: "Bootstrap 5 HTML with data EMBEDDED directly. Use Bootstrap classes: container, card, table, row/col, list-group. Example: <div class='container py-4'><div class='card'><div class='card-body'>...</div></div></div>"
            },
            css: {
              type: "string",
              description: "OPTIONAL - usually not needed since Bootstrap handles styling. Only add minimal CSS if absolutely necessary."
            },
            javascript: {
              type: "string",
              description: "OPTIONAL - usually not needed. Only use for interactive features. Access data via window.canvasData if needed."
            },
            libraries: {
              type: "array",
              items: { type: "string" },
              description: "Optional: CDN libraries to load. Available: #{AVAILABLE_LIBRARIES.keys.join(', ')}"
            },
            data: {
              type: "object",
              description: "IMPORTANT: Pass pre-fetched data here. This becomes window.canvasData in your JavaScript. Fetch data FIRST using execute_integration or get_data, then pass the results here. Example: {customers: [{id: 1, name: 'John'}]}"
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

      # Clean and repair model-generated content
      html, javascript, css = clean_model_content(html, javascript, css)

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

    # Clean and repair common issues in model-generated content
    def clean_model_content(html, javascript, css)
      # 1. Remove template syntax from HTML (models sometimes mix Handlebars/Mustache with vanilla JS)
      html = html.gsub(/\{\{[#\/]?[^}]*\}\}/, '') # Remove {{...}}, {{#...}}, {{/...}}
      
      # 2. Extract any <script> tags from HTML and merge into javascript param
      script_content = []
      html = html.gsub(/<script[^>]*>(.*?)<\/script>/mi) do |match|
        script_content << $1.strip if $1.present?
        '' # Remove from HTML
      end
      if script_content.any?
        javascript = [javascript, *script_content].compact.join("\n\n")
      end
      
      # 3. Fix common JavaScript syntax issues
      javascript = repair_javascript(javascript) if javascript.present?
      
      # 4. Fix common CSS issues (like padding,: 16px instead of padding: 16px)
      css = css.gsub(/(\w+),:\s*/, '\1: ') if css.present?
      # Fix rgba with quotes: rgba(0",0",0",0,.1) -> rgba(0,0,0,0.1)
      css = css.gsub(/rgba\(([^)]*)"([^)]*)\)/) { "rgba(#{$1}#{$2})".gsub('"', '') } if css.present?
      
      Rails.logger.info "[FreeformCanvas] Content cleaned - HTML: #{html.length} chars, JS: #{javascript.length} chars, CSS: #{css.length} chars"
      
      [html, javascript, css]
    end
    
    def repair_javascript(js)
      return js if js.blank?
      
      # Count braces and parentheses
      open_braces = js.count('{')
      close_braces = js.count('}')
      open_parens = js.count('(')
      close_parens = js.count(')')
      
      # Add missing closing braces
      if close_braces < open_braces
        missing = open_braces - close_braces
        Rails.logger.warn "[FreeformCanvas] Adding #{missing} missing closing braces"
        js += "\n" + ("}" * missing)
      end
      
      # Add missing closing parentheses (common with forEach callbacks)
      if close_parens < open_parens
        missing = open_parens - close_parens
        Rails.logger.warn "[FreeformCanvas] Adding #{missing} missing closing parentheses"
        js += ")" * missing
      end
      
      # Common pattern fix: forEach callback missing );
      # Look for pattern like "});  " without proper closure
      js = js.gsub(/\}\s*\n\s*<\/script>/, "});\n</script>")
      
      js
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
