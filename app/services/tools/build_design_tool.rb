# frozen_string_literal: true

module Tools
  # BuildDesignTool builds the actual output from a DesignPlan.
  # This is the "Build" step in the "Plan → Build" workflow.
  #
  # Supports building:
  # - Landing pages (single HTML page)
  # - Websites (multiple HTML pages)
  # - Apps (website + data sources)
  # - Canvases (internal dashboards with data sources)
  #
  class BuildDesignTool < BaseTool
    def self.metadata
      {
        name: 'build_design',
        description: <<~DESC.strip,
          Build the actual output from a design plan.
          
          USE THIS when user says "build it", "looks good", "create it", "go ahead" after
          reviewing a design plan in the Design Studio.
          
          This takes the visual plan and generates:
          - LANDING PAGE: HTML page with sections
          - WEBSITE: Multiple HTML pages with navigation
          - APP: Website + data source bindings for live data (external)
          - CANVAS: Internal dashboard with data source bindings
          
          Requires a plan_id from an existing DesignPlan in 'draft' status.
        DESC
        category: 'design',
        input_schema: {
          type: 'object',
          properties: {
            plan_id: {
              type: 'integer',
              description: 'ID of the DesignPlan to build from'
            },
            confirm: {
              type: 'boolean',
              description: 'Confirm the build (should be true when user approves)'
            }
          },
          required: ['plan_id']
        }
      }
    end

    def execute(args)
      log_execution(args)

      plan_id = get_arg(args, :plan_id)
      confirm = get_arg(args, :confirm) != false

      unless plan_id
        return error_response("plan_id is required to build")
      end

      design_plan = DesignPlan.find_by(id: plan_id, entity_id: entity.id, user_id: user.id)
      unless design_plan
        return error_response("Design plan not found: #{plan_id}")
      end

      unless design_plan.status == 'draft'
        return error_response("Plan must be in 'draft' status to build. Current: #{design_plan.status}")
      end

      # Mark as building
      design_plan.update!(status: 'building')

      case design_plan.design_type
      when 'website', 'app'
        build_website(design_plan)
      when 'canvas'
        build_canvas(design_plan)
      else # landing_page, single_page, portfolio
        build_landing_page(design_plan)
      end
    rescue => e
      Rails.logger.error "BuildDesignTool error: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
      design_plan&.update!(status: 'failed', error_message: e.message) if design_plan
      error_response("Build failed: #{e.message}")
    end

    private

    # Set explicit session focus when building something
    def set_session_focus(type, id, name = nil)
      return unless @context&.dig(:session_id)
      
      begin
        focus = Amos::SessionFocus.new(
          session_id: @context[:session_id],
          user: user,
          entity: entity
        )
        focus.set_focus(type: type, id: id, name: name)
      rescue => e
        Rails.logger.warn "[BuildDesignTool] Could not set session focus: #{e.message}"
      end
    end

    # ============================================
    # BUILD LANDING PAGE
    # ============================================

    def build_landing_page(design_plan)
      stream_progress("🏗️ Building landing page from your approved plan...", percentage: 10)

      # Use the existing GenerateLandingPageTool
      generate_tool = Tools::GenerateLandingPageTool.new(
        user: user,
        entity: entity,
        context: @context,
        progress_callback: @progress_callback
      )

      stream_progress("🎨 Preparing design with #{design_plan.plan_data['sections']&.length || 0} sections...", percentage: 20)

      # Convert plan to generation args
      plan_data = design_plan.plan_data
      design_reference_url = plan_data['design_reference_url'] || plan_data['reference_image_url']

      generation_args = {
        title: plan_data['name'],
        description: design_plan.description,
        design_style: plan_data['style'],
        color_scheme: format_color_scheme(plan_data['color_scheme']),
        key_details: {
          sections: plan_data['sections']&.map { |s| s['name'] },
          layout: plan_data['layout'],
          # Pass full section data including advanced options
          section_content: plan_data['sections']&.map do |s|
            {
              name: s['name'],
              type: s['type'],
              content: s['content'],
              background: s['background'],
              layout_hint: s['layout_hint'],
              # Advanced options for AI
              visual_description: s['visual_description'],
              content_guidance: s['content_guidance'],
              image_style: s['image_style']
            }
          end,
          typography: plan_data['typography'],
          tone: plan_data['tone']
        },
        design_preferences: {
          colors: plan_data['color_scheme'],
          typography: plan_data['typography'],
          style: plan_data['style']
        },
        design_reference_url: design_reference_url,
        # Pass advanced section descriptions for AI generation
        section_details: plan_data['sections']&.map do |s|
          next unless s['visual_description'].present? || s['content_guidance'].present?
          {
            name: s['name'],
            visual_description: s['visual_description'],
            content_guidance: s['content_guidance'],
            image_style: s['image_style']
          }
        end&.compact
      }

      result = generate_tool.execute(generation_args)

      if result[:success]
        design_plan.update!(
          status: 'completed',
          landing_page_id: result[:id]
        )

        # Update session focus to the built landing page
        set_session_focus(:landing_page, result[:id], design_plan.name)

        success_response(
          plan_id: design_plan.id,
          landing_page_id: result[:id],
          message: "🎉 Your landing page has been built! Opening editor...",
          canvas_type: 'landing_page_editor',
          canvas_data: { landing_page_id: result[:id] }
        )
      else
        design_plan.update!(status: 'failed', error_message: result[:error])
        error_response("Build failed: #{result[:error]}")
      end
    end

    # ============================================
    # BUILD WEBSITE / APP
    # ============================================

    def build_website(design_plan)
      stream_progress("🏗️ Building website from your approved plan...", percentage: 10)

      plan_data = design_plan.plan_data

      # Create the Website (store design details in theme_config JSONB)
      website = Website.create!(
        entity: entity,
        created_by: user,
        name: plan_data['name'] || design_plan.name,
        slug: (plan_data['name'] || design_plan.name).to_s.parameterize,
        description: design_plan.description,
        theme: plan_data['style']&.parameterize || 'modern',
        theme_config: {
          color_scheme: plan_data['color_scheme'],
          typography: plan_data['typography'],
          navigation: plan_data['navigation'],
          data_sources: design_plan.data_sources
        },
        status: 'draft'
      )

      # Create each page
      pages = plan_data['pages'] || []
      pages.each_with_index do |page_plan, index|
        stream_progress("📄 Building page #{index + 1}/#{pages.length}: #{page_plan['name']}...", percentage: 20 + (60 * index / pages.length))

        page_html = generate_page_html(page_plan, plan_data)

        # Convert sections to content_blocks format (WebsitePage uses content_blocks, not sections)
        content_blocks = (page_plan['sections'] || []).map do |section|
          {
            'id' => SecureRandom.uuid,
            'type' => section['type'] || section['name'],
            'data' => section['content'] || {},
            'background' => section['background'],
            'layout_hint' => section['layout_hint'],
            'visual_description' => section['visual_description'],
            'content_guidance' => section['content_guidance'],
            'image_style' => section['image_style']
          }.compact
        end

        website.website_pages.create!(
          entity: entity,
          name: page_plan['name'],
          slug: page_plan['slug'] || page_plan['name'].parameterize,
          template: determine_template(page_plan),
          html_content: page_html,
          content_blocks: content_blocks,
          show_in_nav: true,
          nav_order: index,
          status: 'draft',
          is_homepage: index == 0
        )
      end

      design_plan.update!(
        status: 'completed',
        website_id: website.id
      )

      stream_progress("✅ Website built successfully!", percentage: 100)

      success_response(
        plan_id: design_plan.id,
        website_id: website.id,
        page_count: pages.length,
        message: "🎉 Your #{design_plan.app? ? 'app' : 'website'} with #{pages.length} pages has been built!",
        canvas_type: 'website_editor',
        canvas_data: { website_id: website.id }
      )
    end

    # ============================================
    # BUILD CANVAS (INTERNAL DASHBOARD)
    # ============================================

    def build_canvas(design_plan)
      stream_progress("🏗️ Building canvas from your approved plan...", percentage: 10)

      plan_data = design_plan.plan_data

      # Create or find the app module for this canvas
      app_module = find_or_create_canvas_module

      # Create the ModuleCanvas
      canvas = ModuleCanvas.create!(
        app_module: app_module,
        entity: entity,
        name: plan_data['name'] || design_plan.name,
        slug: (plan_data['name'] || design_plan.name).parameterize,
        canvas_type: 'dashboard',
        ui_mode: 'simple',
        html_content: generate_canvas_html(plan_data),
        data_sources: design_plan.data_sources || [],
        layout_config: {
          sections: plan_data['sections'],
          style: plan_data['style'],
          colors: plan_data['color_scheme']
        }
      )

      design_plan.update!(
        status: 'completed',
        module_canvas_id: canvas.id
      )

      stream_progress("✅ Canvas built successfully!", percentage: 100)

      success_response(
        plan_id: design_plan.id,
        canvas_id: canvas.id,
        data_source_count: (design_plan.data_sources || []).count,
        message: "🎉 Your canvas has been built!",
        canvas_type: 'module_canvas',
        canvas_data: { canvas_id: canvas.id }
      )
    end

    # ============================================
    # HTML GENERATION HELPERS
    # ============================================

    def generate_page_html(page_plan, global_plan)
      ai_service = BedrockService.new

      system_prompt = <<~SYSTEM
        Generate responsive HTML for a website page. Use Bootstrap 5 for layout.
        The page should match this design specification and be part of a cohesive website.
        
        Color scheme: #{global_plan['color_scheme'].to_json}
        Typography: #{global_plan['typography'].to_json}
        Navigation: #{global_plan['navigation'].to_json}
        Style: #{global_plan['style']}
        
        Return ONLY the HTML content (the <body> inner content), no doctype or html tags.
        Include proper Bootstrap classes for responsiveness.
        Use inline styles for colors matching the color scheme.
      SYSTEM

      user_prompt = "Generate HTML for the '#{page_plan['name']}' page with these sections: #{page_plan['sections'].to_json}"

      messages = [{ role: 'user', content: user_prompt }]
      response = ai_service.send_message(system_prompt, messages, model: 'qwen3-next-80b', max_tokens: 8000)

      # Clean response
      html = response.to_s.strip
      html = html.gsub(/```html\n?/, '').gsub(/```\n?/, '')
      html
    end

    def generate_canvas_html(plan_data)
      # For canvases, generate a dashboard-style layout with data placeholders
      sections = plan_data['sections'] || []

      html_parts = ['<div class="dashboard-container p-4">']

      sections.each do |section|
        section_type = section['type'] || 'content'
        section_name = section['name'] || 'Section'

        case section_type
        when 'kpi', 'metric'
          html_parts << generate_kpi_section(section)
        when 'chart', 'graph'
          html_parts << generate_chart_section(section)
        when 'table', 'data_table'
          html_parts << generate_table_section(section)
        else
          html_parts << generate_content_section(section)
        end
      end

      html_parts << '</div>'
      html_parts.join("\n")
    end

    def generate_kpi_section(section)
      <<~HTML
        <div class="card mb-4">
          <div class="card-body">
            <h6 class="text-muted">#{section['name']}</h6>
            <h2 class="display-4" data-binding="#{section['data_source']}">--</h2>
            <small class="text-muted">#{section['description'] || ''}</small>
          </div>
        </div>
      HTML
    end

    def generate_chart_section(section)
      <<~HTML
        <div class="card mb-4">
          <div class="card-header">#{section['name']}</div>
          <div class="card-body">
            <div class="chart-container" data-binding="#{section['data_source']}" data-chart-type="#{section['chart_type'] || 'line'}" style="height: 300px;">
              <canvas></canvas>
            </div>
          </div>
        </div>
      HTML
    end

    def generate_table_section(section)
      <<~HTML
        <div class="card mb-4">
          <div class="card-header">#{section['name']}</div>
          <div class="card-body">
            <div class="table-responsive" data-binding="#{section['data_source']}">
              <table class="table table-striped">
                <thead><tr><th>Loading...</th></tr></thead>
                <tbody></tbody>
              </table>
            </div>
          </div>
        </div>
      HTML
    end

    def generate_content_section(section)
      <<~HTML
        <div class="card mb-4">
          <div class="card-header">#{section['name']}</div>
          <div class="card-body">
            #{section['content'] || '<p>Content will be displayed here.</p>'}
          </div>
        </div>
      HTML
    end

    # ============================================
    # HELPERS
    # ============================================

    def determine_template(page_plan)
      sections = page_plan['sections']&.map { |s| s['type'] } || []

      if sections.include?('hero') && sections.include?('cta')
        'landing'
      elsif sections.include?('contact')
        'form'
      elsif sections.include?('gallery') || sections.include?('portfolio')
        'list'
      elsif page_plan['slug'] == 'index'
        'homepage'
      else
        'content'
      end
    end

    def format_color_scheme(scheme)
      return nil unless scheme.is_a?(Hash)

      scheme.map { |k, v| "#{k}: #{v}" }.join(', ')
    end

    def find_or_create_canvas_module
      # Find or create a general "Dashboards" module for user-created canvases
      app_module = AppModule.find_by(entity: entity, slug: 'user-dashboards')

      unless app_module
        app_module = AppModule.create!(
          entity: entity,
          name: 'User Dashboards',
          slug: 'user-dashboards',
          description: 'Custom dashboards and canvases created by users',
          status: 'active'
        )
      end

      app_module
    end
  end
end
