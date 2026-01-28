# frozen_string_literal: true

module Tools
  # PlanDesignTool creates a visual plan/blueprint for a landing page or website
  # before the actual build. This follows the "Plan → Build" pattern.
  #
  # Flow:
  # 1. User describes what they want in natural language
  # 2. AI generates a structured plan (sections, colors, content ideas)
  # 3. Plan is shown visually in the App Designer canvas
  # 4. User can refine the plan (add/remove sections, change text, add pages for websites)
  # 5. "Build" generates the actual HTML
  #
  # For WEBSITES: Plan includes multiple pages, each with its own sections
  # User can add/remove pages, configure navigation
  #
  class PlanDesignTool < BaseTool
    def self.metadata
      {
        name: 'plan_design',
        description: <<~DESC.strip,
          Create a visual plan/blueprint for landing pages, websites, apps, or canvases before building.
          
          USE THIS when user wants to create any visual interface. Shows a rich visual
          preview with sections, colors, CTA text that user can review and refine.
          
          Design Types:
          - LANDING PAGE: Single page with sections (hero, features, testimonials, etc.)
          - WEBSITE: Multiple pages with navigation, each page has sections
          - APP: Website + data sources for dynamic content (external facing)
          - CANVAS: Internal dashboard/tool with data sources (for Amos users)
          
          Apps and Canvases can bind to Data Sources (workflow outputs) for live data.
          
          Actions:
          - create: Generate new plan from description
          - refine: Modify sections, colors, text, add/remove pages, add data sources
          - build: Generate actual output from plan
          - list: Show all draft design plans for the user
          - load: Load an existing plan into the design studio canvas
          - add_data_source: Connect a workflow output to a named data source
          - remove_data_source: Remove a data source binding
        DESC
        category: 'design',
        input_schema: {
          type: 'object',
          properties: {
            description: {
              type: 'string',
              description: 'What the user wants to build. Be specific about business type, target audience, goals.'
            },
            design_type: {
              type: 'string',
              enum: %w[landing_page website app canvas],
              description: 'landing_page = single page, website = multi-page, app = website with data sources (external), canvas = internal dashboard/tool with data sources'
            },
            action: {
              type: 'string',
              enum: %w[create refine build add_page remove_page list load add_data_source remove_data_source],
              description: "Action to perform on the plan"
            },
            plan_id: {
              type: 'integer',
              description: 'ID of existing plan (required for refine/build/add_page/remove_page)'
            },
            # For refinements
            refinements: {
              type: 'object',
              description: 'Changes to make to the plan (for action: refine)',
              properties: {
                add_section: { type: 'string', description: 'Section type to add (hero, features, pricing, testimonials, cta, faq, gallery, contact)' },
                remove_section: { type: 'string', description: 'Section name to remove' },
                update_colors: { 
                  type: 'object', 
                  description: 'Color scheme changes. E.g. { primary: "#0A2647", accent: "#E63946" }' 
                },
                update_typography: {
                  type: 'object',
                  description: 'Font changes. E.g. { headings: "Montserrat", body: "Open Sans" }'
                },
                update_style: {
                  type: 'string',
                  description: 'Design style: modern, corporate, minimal, bold, elegant, playful, tech'
                },
                design_reference_url: {
                  type: 'string',
                  description: 'URL to a screenshot image to use as design inspiration'
                },
                update_section: { 
                  type: 'object', 
                  description: <<~DESC.strip
                    Update a specific section. Structure:
                    {
                      name: "cta" (or "hero", "features", etc.),
                      content: { headline: "New Headline", subheadline: "...", cta_text: "..." },
                      layout: "centered" (or "split", "3-column", "carousel"),
                      background: "dark" (or "light", "gradient"),
                      visual_description: "How the section should look - colors, animations, layout details",
                      content_guidance: "What content to focus on - tone, messaging, key points",
                      image_style: "photorealistic" | "illustration" | "abstract" | "3d-render" | "minimal" | "none"
                    }
                    
                    Use visual_description and content_guidance to capture user's detailed vision for each section.
                    These guide the AI during the build phase.
                  DESC
                }
              }
            },
            # For website pages
            page_name: {
              type: 'string',
              description: 'Name of page to add/remove/update'
            },
            page_sections: {
              type: 'array',
              description: 'Sections for the new page',
              items: { type: 'string' }
            },
            # Optional hints from user
            color_preference: {
              type: 'string',
              description: 'Preferred color scheme (e.g., "dark and professional", "bright and modern")'
            },
            style_preference: {
              type: 'string',
              description: 'Preferred style (e.g., "minimalist", "bold", "corporate")'
            },
            business_info: {
              type: 'object',
              description: 'Business details to include',
              properties: {
                name: { type: 'string' },
                tagline: { type: 'string' },
                value_proposition: { type: 'string' },
                target_audience: { type: 'string' },
                cta_text: { type: 'string', description: 'Call-to-action button text' },
                offer: { type: 'string', description: 'What you are offering' },
                price: { type: 'string' }
              }
            },
            # Data source configuration (for apps and canvases)
            data_source: {
              type: 'object',
              description: 'Data source configuration for apps/canvases',
              properties: {
                name: { type: 'string', description: 'Unique name for this data source (e.g., "revenue_data")' },
                type: { type: 'string', enum: %w[workflow integration model], description: 'Source type' },
                source_id: { type: 'integer', description: 'ID of the workflow, integration action, or model' },
                output_path: { type: 'string', description: 'JSONPath to data within the output (e.g., "data.results")' },
                refresh_interval: { type: 'integer', description: 'Auto-refresh interval in seconds (0 = manual only)' }
              }
            },
            data_source_name: {
              type: 'string',
              description: 'Name of data source to remove (for remove_data_source action)'
            }
          },
          required: ['description']
        }
      }
    end

    def execute(args)
      log_execution(args)

      action = get_arg(args, :action) || 'create'

      case action
      when 'create'
        create_plan(args)
      when 'refine'
        refine_plan(args)
      when 'build'
        build_from_plan(args)
      when 'add_page'
        add_page_to_plan(args)
      when 'remove_page'
        remove_page_from_plan(args)
      when 'list'
        list_plans(args)
      when 'load'
        load_plan(args)
      when 'add_data_source'
        add_data_source(args)
      when 'remove_data_source'
        remove_data_source(args)
      else
        error_response("Unknown action: #{action}")
      end
    end

    private

    # Set explicit session focus when working on a plan
    def set_session_focus(design_plan)
      return unless @context&.dig(:session_id)
      
      begin
        focus = Amos::SessionFocus.new(
          session_id: @context[:session_id],
          user: user,
          entity: entity
        )
        focus.focus_on_design_plan(design_plan)
      rescue => e
        Rails.logger.warn "[PlanDesignTool] Could not set session focus: #{e.message}"
      end
    end

    # ============================================
    # CREATE PLAN
    # ============================================

    def create_plan(args)
      description = get_arg(args, :description)
      design_type = get_arg(args, :design_type) || 'landing_page'
      color_preference = get_arg(args, :color_preference)
      style_preference = get_arg(args, :style_preference)
      business_info = get_arg(args, :business_info) || {}

      unless description.present?
        return error_response("Please describe what you want to build")
      end

      # Stream progress to user
      stream_progress("📋 Creating your design plan...", percentage: 10)

      # Gather business profile context for personalization
      business_profile = gather_business_context
      stream_progress("🏢 Loaded your business profile...", percentage: 20)

      # Merge user-provided business_info with profile data
      enriched_business_info = business_profile.merge(business_info.stringify_keys)
      
      # Use profile colors if no preference specified
      color_preference ||= enriched_business_info['brand_colors'] || enriched_business_info['primary_color']

      stream_progress("🎨 Generating visual plan with AI...", percentage: 40)

      # Generate the plan using AI
      ai_service = BedrockService.new
      plan_data = generate_plan_with_ai(
        ai_service,
        description: description,
        design_type: design_type,
        color_preference: color_preference,
        style_preference: style_preference,
        business_info: enriched_business_info
      )
      
      stream_progress("✨ Plan ready! Loading canvas...", percentage: 90)

      # Create a DesignPlan record to track this
      design_plan = DesignPlan.create!(
        entity: entity,
        user: user,
        name: plan_data['name'] || "New #{design_type.titleize}",
        design_type: design_type,
        description: description,
        plan_data: plan_data,
        status: 'draft'
      )

      # Set explicit session focus on this plan
      set_session_focus(design_plan)

      # Broadcast to canvas
      broadcast_plan_to_canvas(design_plan)

      # Customize message based on type
      type_label = design_type == 'website' ? 'website' : 'landing page'
      page_count = plan_data['pages']&.length || 1
      section_count = if design_type == 'website'
        plan_data['pages']&.sum { |p| p['sections']&.length || 0 } || 0
      else
        plan_data['sections']&.length || 0
      end

      success_response(
        plan_id: design_plan.id,
        name: design_plan.name,
        design_type: design_type,
        plan: plan_data,
        status: 'draft',
        message: "📋 Here's your #{type_label} plan with #{section_count} sections#{page_count > 1 ? " across #{page_count} pages" : ''}!",
        canvas_type: 'design_studio',
        canvas_data: {
          plan_id: design_plan.id,
          plan: plan_data,
          status: 'draft',
          design_type: design_type
        },
        next_steps: design_type == 'website' ? [
          "Review the pages and sections",
          "Say 'add a page for [topic]' to add more pages",
          "Say 'change the hero headline to...' to update content",
          "Say 'build it' when ready"
        ] : [
          "Review the sections and content",
          "Tell me to add, remove, or change any sections",
          "Update the headline, CTA, or colors",
          "Say 'build it' when you're ready"
        ]
      )
    rescue => e
      Rails.logger.error "PlanDesignTool error: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
      error_response("Failed to create plan: #{e.message}")
    end

    # ============================================
    # REFINE PLAN
    # ============================================

    def refine_plan(args)
      plan_id = get_arg(args, :plan_id)
      refinements = get_arg(args, :refinements) || {}

      design_plan = find_plan(plan_id)
      return design_plan if design_plan.is_a?(Hash) # Error response

      unless design_plan.status == 'draft'
        return error_response("This plan has already been built and cannot be modified")
      end

      # Apply refinements
      plan_data = design_plan.plan_data.deep_dup

      if refinements[:add_section].present?
        section = generate_section(refinements[:add_section])
        plan_data['sections'] ||= []
        plan_data['sections'] << section
      end

      if refinements[:remove_section].present?
        plan_data['sections']&.reject! { |s| s['name'] == refinements[:remove_section] }
      end

      if refinements[:update_colors].present?
        plan_data['color_scheme'] ||= {}
        plan_data['color_scheme'] = plan_data['color_scheme'].merge(refinements[:update_colors])
      end
      
      if refinements[:update_typography].present?
        plan_data['typography'] ||= {}
        plan_data['typography'] = plan_data['typography'].merge(refinements[:update_typography])
      end
      
      if refinements[:update_style].present?
        plan_data['style'] = refinements[:update_style]
      end
      
      if refinements[:design_reference_url].present?
        plan_data['design_reference_url'] = refinements[:design_reference_url]
      end

      if refinements[:update_section].present?
        update_data = refinements[:update_section].with_indifferent_access
        section_name = update_data[:name] || update_data[:section_name]
        
        section = plan_data['sections']&.find { |s| s['name'] == section_name || s['type'] == section_name }
        if section
          # Deep merge content updates
          if update_data[:content].present?
            section['content'] ||= {}
            section['content'] = section['content'].deep_merge(update_data[:content].stringify_keys)
          end
          # Update layout if specified
          section['layout_hint'] = update_data[:layout] if update_data[:layout].present?
          section['background'] = update_data[:background] if update_data[:background].present?
          
          # Advanced section options - AI fills these based on user's description
          section['visual_description'] = update_data[:visual_description] if update_data[:visual_description].present?
          section['content_guidance'] = update_data[:content_guidance] if update_data[:content_guidance].present?
          section['image_style'] = update_data[:image_style] if update_data[:image_style].present?
          
          # Merge any other top-level updates
          other_updates = update_data.except(:name, :section_name, :content, :layout, :background, 
                                              :visual_description, :content_guidance, :image_style)
          section.merge!(other_updates.stringify_keys) if other_updates.any?
        end
      end

      design_plan.update!(plan_data: plan_data)

      # Broadcast updated plan
      broadcast_plan_to_canvas(design_plan)

      success_response(
        plan_id: design_plan.id,
        name: design_plan.name,
        plan: plan_data,
        status: design_plan.status,
        message: "✏️ Plan updated!",
        canvas_loaded: true
      )
    end

    # ============================================
    # BUILD FROM PLAN
    # ============================================

    def build_from_plan(args)
      # Delegate to the dedicated BuildDesignTool for separation of concerns
      build_tool = Tools::BuildDesignTool.new(
        user: user,
        entity: entity,
        context: @context,
        progress_callback: @progress_callback
      )
      build_tool.execute(args)
    end

    # ============================================
    # AI PLAN GENERATION
    # ============================================

    def generate_plan_with_ai(ai_service, description:, design_type:, color_preference:, style_preference:, business_info:)
      is_website = design_type == 'website'
      
      system_prompt = <<~SYSTEM
        You are a web design architect. Given a description, create a detailed plan/blueprint 
        for a #{is_website ? 'multi-page website' : 'single landing page'}.
        
        #{is_website ? website_schema_prompt : landing_page_schema_prompt}
        
        IMPORTANT:
        - Generate ACTUAL suggested content, not just "content ideas"
        - Include specific headlines, subheadlines, CTA button text
        - Make the content compelling and conversion-focused
        - Consider the target audience and purpose
        - Use modern design best practices
        
        #{color_preference.present? ? "Color preference: #{color_preference}" : ""}
        #{style_preference.present? ? "Style preference: #{style_preference}" : ""}
        #{business_info.present? ? "Business info: #{business_info.to_json}" : ""}
        
        Return ONLY valid JSON, no markdown or explanation.
      SYSTEM

      user_message = "Create a design plan for: #{description}"

      messages = [{ role: 'user', content: user_message }]
      response = ai_service.send_message(system_prompt, messages, model: 'qwen3-next-80b', max_tokens: 6000, json_mode: true)

      # Parse JSON response
      json_str = response.to_s.strip
      json_str = json_str.gsub(/```json\n?/, '').gsub(/```\n?/, '') # Strip markdown
      
      JSON.parse(json_str)
    rescue JSON::ParserError => e
      Rails.logger.warn "Failed to parse plan JSON: #{e.message}"
      is_website ? default_website_plan : default_landing_page_plan
    end
    
    def landing_page_schema_prompt
      <<~SCHEMA
        Return a JSON object with this exact structure:
        {
          "name": "Short name for this design",
          "style": "Overall style (modern, minimal, bold, corporate, etc.)",
          "layout": "single-column",
          "color_scheme": {
            "primary": "#hex color",
            "secondary": "#hex color",
            "accent": "#hex color (for CTAs)",
            "background": "#hex color",
            "text": "#hex color"
          },
          "typography": {
            "headings": "Font family name",
            "body": "Font family name"
          },
          "sections": [
            {
              "name": "hero",
              "type": "hero",
              "position": 1,
              "content": {
                "headline": "Actual compelling headline text",
                "subheadline": "Supporting text that explains value",
                "cta_text": "Button text",
                "cta_secondary": "Optional secondary button text"
              },
              "layout_hint": "centered | split | video-background",
              "background": "gradient | dark | light | image",
              "visual_description": "Optional - detailed visual style (e.g., 'dark gradient with floating particles, glassmorphism card, subtle animations')",
              "content_guidance": "Optional - what content should convey (e.g., 'focus on ROI, use statistics, professional tone')",
              "image_style": "photorealistic | illustration | abstract | 3d-render | minimal | none"
            },
            {
              "name": "features",
              "type": "features",
              "position": 2,
              "content": {
                "section_title": "Section heading",
                "items": [
                  {"title": "Feature 1", "description": "Brief description"},
                  {"title": "Feature 2", "description": "Brief description"},
                  {"title": "Feature 3", "description": "Brief description"}
                ]
              },
              "layout_hint": "3-column | 2-column | icon-grid",
              "background": "light | dark",
              "visual_description": "Optional - detailed visual style",
              "content_guidance": "Optional - content focus",
              "image_style": "photorealistic | illustration | etc."
            }
          ],
          "special_elements": ["video", "testimonials-carousel", "countdown", "animation"],
          "tone": "Professional, authoritative, friendly, etc."
        }
        
        Include 4-6 sections typically: hero, features/benefits, social proof, pricing or CTA, contact/footer.
        
        IMPORTANT: When user describes specific visual effects, layouts, or content focus for sections,
        capture that in visual_description and content_guidance fields. These guide the AI during build.
      SCHEMA
    end
    
    def website_schema_prompt
      <<~SCHEMA
        Return a JSON object with this exact structure:
        {
          "name": "Short name for this website",
          "style": "Overall style (modern, minimal, bold, corporate, etc.)",
          "navigation": {
            "style": "fixed-top | sticky | sidebar",
            "items": ["Home", "About", "Services", "Contact"]
          },
          "color_scheme": {
            "primary": "#hex color",
            "secondary": "#hex color", 
            "accent": "#hex color",
            "background": "#hex color",
            "text": "#hex color"
          },
          "typography": {
            "headings": "Font family name",
            "body": "Font family name"
          },
          "pages": [
            {
              "name": "Home",
              "slug": "index",
              "description": "Homepage with main value proposition",
              "sections": [
                {
                  "name": "hero",
                  "type": "hero",
                  "content": {
                    "headline": "Actual headline",
                    "subheadline": "Supporting text",
                    "cta_text": "Get Started",
                    "cta_link": "/contact"
                  },
                  "layout_hint": "centered | split | video-background",
                  "background": "gradient | dark | light",
                  "visual_description": "Optional - detailed visual style",
                  "content_guidance": "Optional - content focus",
                  "image_style": "photorealistic | illustration | etc."
                },
                {
                  "name": "features",
                  "type": "features",
                  "content": {
                    "section_title": "Why Choose Us",
                    "items": [...]
                  }
                }
              ]
            },
            {
              "name": "About",
              "slug": "about",
              "description": "Company story and team",
              "sections": [...]
            }
          ],
          "global_elements": {
            "header": { "logo": true, "cta_button": "Contact" },
            "footer": { "columns": 4, "newsletter": true, "social_links": true }
          },
          "tone": "Professional, authoritative, friendly, etc."
        }
        
        Include 3-6 pages typically: Home, About, Services/Products, Testimonials/Case Studies, Contact.
        
        IMPORTANT: When user describes specific visual effects or content focus for sections,
        capture that in visual_description and content_guidance fields.
      SCHEMA
    end
    
    def default_landing_page_plan
      {
        'name' => 'New Landing Page',
        'style' => 'Modern and Professional',
        'layout' => 'single-column',
        'color_scheme' => {
          'primary' => '#6366f1',
          'secondary' => '#818cf8',
          'accent' => '#f59e0b',
          'background' => '#ffffff',
          'text' => '#1f2937'
        },
        'typography' => { 'headings' => 'Inter', 'body' => 'Inter' },
        'sections' => [
          { 'name' => 'hero', 'type' => 'hero', 'position' => 1, 
            'content' => { 'headline' => 'Your Compelling Headline', 'subheadline' => 'Supporting value proposition', 'cta_text' => 'Get Started' },
            'background' => 'gradient' },
          { 'name' => 'features', 'type' => 'features', 'position' => 2, 
            'content' => { 'section_title' => 'Key Features', 'items' => [{ 'title' => 'Feature 1', 'description' => 'Description' }] },
            'background' => 'light' },
          { 'name' => 'cta', 'type' => 'cta', 'position' => 3, 
            'content' => { 'headline' => 'Ready to Get Started?', 'cta_text' => 'Sign Up Now' },
            'background' => 'dark' }
        ],
        'special_elements' => [],
        'tone' => 'Professional'
      }
    end
    
    def default_website_plan
      {
        'name' => 'New Website',
        'style' => 'Modern and Professional',
        'navigation' => { 'style' => 'fixed-top', 'items' => ['Home', 'About', 'Services', 'Contact'] },
        'color_scheme' => {
          'primary' => '#6366f1',
          'secondary' => '#818cf8',
          'accent' => '#f59e0b',
          'background' => '#ffffff',
          'text' => '#1f2937'
        },
        'typography' => { 'headings' => 'Inter', 'body' => 'Inter' },
        'pages' => [
          { 'name' => 'Home', 'slug' => 'index', 'sections' => [
            { 'name' => 'hero', 'type' => 'hero', 'content' => { 'headline' => 'Welcome', 'cta_text' => 'Learn More' } }
          ]},
          { 'name' => 'About', 'slug' => 'about', 'sections' => [
            { 'name' => 'about', 'type' => 'about', 'content' => { 'headline' => 'About Us' } }
          ]},
          { 'name' => 'Contact', 'slug' => 'contact', 'sections' => [
            { 'name' => 'contact', 'type' => 'contact', 'content' => { 'headline' => 'Get in Touch' } }
          ]}
        ],
        'tone' => 'Professional'
      }
    end

    # ============================================
    # ADD/REMOVE PAGES (for websites)
    # ============================================
    
    def add_page_to_plan(args)
      plan_id = get_arg(args, :plan_id)
      page_name = get_arg(args, :page_name)
      page_sections = get_arg(args, :page_sections) || ['hero', 'content']
      
      design_plan = find_plan(plan_id)
      return design_plan if design_plan.is_a?(Hash)
      
      unless design_plan.design_type == 'website'
        return error_response("Only websites support multiple pages")
      end
      
      plan_data = design_plan.plan_data.deep_dup
      plan_data['pages'] ||= []
      
      # Generate page slug
      slug = page_name.to_s.parameterize
      
      # Check for duplicate
      if plan_data['pages'].any? { |p| p['slug'] == slug }
        return error_response("A page with slug '#{slug}' already exists")
      end
      
      # Add new page
      new_page = {
        'name' => page_name,
        'slug' => slug,
        'description' => "New page: #{page_name}",
        'sections' => page_sections.map { |s| generate_section(s) }
      }
      
      plan_data['pages'] << new_page
      
      # Update navigation
      plan_data['navigation'] ||= { 'items' => [] }
      plan_data['navigation']['items'] << page_name unless plan_data['navigation']['items'].include?(page_name)
      
      design_plan.update!(plan_data: plan_data)
      broadcast_plan_to_canvas(design_plan)
      
      success_response(
        plan_id: design_plan.id,
        message: "➕ Added page '#{page_name}' with #{page_sections.length} sections",
        page: new_page,
        total_pages: plan_data['pages'].length,
        canvas_type: 'design_studio',
        canvas_data: { plan_id: design_plan.id, plan: plan_data, status: 'draft' }
      )
    end
    
    def remove_page_from_plan(args)
      plan_id = get_arg(args, :plan_id)
      page_name = get_arg(args, :page_name)
      
      design_plan = find_plan(plan_id)
      return design_plan if design_plan.is_a?(Hash)
      
      plan_data = design_plan.plan_data.deep_dup
      
      # Remove page
      removed = plan_data['pages']&.reject! { |p| p['name'].downcase == page_name.downcase }
      
      unless removed
        return error_response("Page '#{page_name}' not found in plan")
      end
      
      # Update navigation
      plan_data['navigation']['items']&.reject! { |i| i.downcase == page_name.downcase }
      
      design_plan.update!(plan_data: plan_data)
      broadcast_plan_to_canvas(design_plan)
      
      success_response(
        plan_id: design_plan.id,
        message: "➖ Removed page '#{page_name}'",
        remaining_pages: plan_data['pages']&.map { |p| p['name'] },
        canvas_type: 'design_studio',
        canvas_data: { plan_id: design_plan.id, plan: plan_data, status: 'draft' }
      )
    end

    # ============================================
    # DATA SOURCE MANAGEMENT
    # ============================================

    def add_data_source(args)
      plan_id = get_arg(args, :plan_id)
      data_source = get_arg(args, :data_source)
      
      unless plan_id
        return error_response("plan_id is required to add a data source")
      end
      
      unless data_source && data_source[:name] && data_source[:type]
        return error_response("data_source must include at least 'name' and 'type'")
      end
      
      design_plan = find_plan(plan_id)
      return design_plan if design_plan.is_a?(Hash)
      
      # Validate design type supports data sources
      unless design_plan.dynamic? || %w[app canvas].include?(design_plan.design_type)
        return error_response("Data sources can only be added to apps and canvases. This is a #{design_plan.design_type}.")
      end
      
      # Build data source config
      source_config = {
        name: data_source[:name],
        type: data_source[:type],
        source_id: data_source[:source_id],
        output_path: data_source[:output_path] || 'data',
        refresh_interval: data_source[:refresh_interval] || 0,
        created_at: Time.current.iso8601
      }
      
      # Check for duplicate name
      if design_plan.find_data_source(source_config[:name])
        return error_response("A data source named '#{source_config[:name]}' already exists. Use a different name or remove the existing one first.")
      end
      
      design_plan.add_data_source!(source_config)
      broadcast_plan_to_canvas(design_plan)
      
      success_response(
        plan_id: design_plan.id,
        message: "📊 Added data source '#{source_config[:name]}' (#{source_config[:type]})",
        data_sources: design_plan.data_sources,
        canvas_type: 'design_studio',
        canvas_data: { plan_id: design_plan.id, plan: design_plan.plan_data, data_sources: design_plan.data_sources, status: 'draft' }
      )
    end

    def remove_data_source(args)
      plan_id = get_arg(args, :plan_id)
      data_source_name = get_arg(args, :data_source_name)
      
      unless plan_id
        return error_response("plan_id is required to remove a data source")
      end
      
      unless data_source_name
        return error_response("data_source_name is required")
      end
      
      design_plan = find_plan(plan_id)
      return design_plan if design_plan.is_a?(Hash)
      
      unless design_plan.find_data_source(data_source_name)
        return error_response("Data source '#{data_source_name}' not found in this plan")
      end
      
      design_plan.remove_data_source!(data_source_name)
      broadcast_plan_to_canvas(design_plan)
      
      success_response(
        plan_id: design_plan.id,
        message: "🗑️ Removed data source '#{data_source_name}'",
        data_sources: design_plan.data_sources,
        canvas_type: 'design_studio',
        canvas_data: { plan_id: design_plan.id, plan: design_plan.plan_data, data_sources: design_plan.data_sources, status: 'draft' }
      )
    end

    # ============================================
    # LIST PLANS
    # ============================================

    def list_plans(args)
      design_type = get_arg(args, :design_type) # Optional filter
      
      # Scope by both entity AND user for proper isolation
      plans_query = DesignPlan.where(entity: @entity, user: @user)
      plans_query = plans_query.where(design_type: design_type) if design_type.present?
      plans = plans_query.order(updated_at: :desc).limit(20)
      
      if plans.empty?
        return success_response(
          message: "📋 You don't have any design plans yet. Say 'create a landing page for...' to get started!",
          plans: []
        )
      end
      
      plans_list = plans.map do |plan|
        plan_data = plan.plan_data || {}
        sections_count = (plan_data['sections'] || []).length
        pages_count = (plan_data['pages'] || []).length
        
        {
          id: plan.id,
          title: plan_data['title'] || plan_data.dig('content', 'headline') || "Untitled #{plan.design_type.titleize}",
          design_type: plan.design_type,
          status: plan.status,
          sections_count: sections_count,
          pages_count: pages_count,
          created_at: plan.created_at.strftime('%b %d, %Y'),
          updated_at: plan.updated_at.strftime('%b %d at %I:%M %p'),
          built: plan.status == 'built',
          landing_page_id: plan.landing_page_id,
          website_id: plan.website_id
        }
      end
      
      # Format a nice summary
      draft_count = plans_list.count { |p| p[:status] == 'draft' }
      built_count = plans_list.count { |p| p[:status] == 'built' }
      
      message = "📋 **Your Design Plans** (#{plans_list.length} total)\n\n"
      message += "**Drafts:** #{draft_count} | **Built:** #{built_count}\n\n"
      
      plans_list.first(10).each do |plan|
        status_icon = plan[:status] == 'draft' ? '📝' : '✅'
        type_icon = plan[:design_type] == 'website' ? '🌐' : '📄'
        message += "#{status_icon} #{type_icon} **#{plan[:title]}** (ID: #{plan[:id]})\n"
        message += "   #{plan[:sections_count]} sections • Updated #{plan[:updated_at]}\n\n"
      end
      
      message += "\n💡 Say 'open plan [ID]' or 'continue working on [title]' to load a plan."
      
      success_response(
        message: message,
        plans: plans_list,
        draft_count: draft_count,
        built_count: built_count
      )
    end

    # ============================================
    # LOAD PLAN
    # ============================================

    def load_plan(args)
      plan_id = get_arg(args, :plan_id)
      
      unless plan_id.present?
        return error_response("Please specify which plan to load (plan_id required)")
      end
      
      design_plan = find_plan(plan_id)
      return design_plan if design_plan.is_a?(Hash) # Error response
      
      plan_data = design_plan.plan_data || {}
      
      # Broadcast to open the design studio with this plan
      broadcast_plan_to_canvas(design_plan)
      
      sections = plan_data['sections'] || []
      pages = plan_data['pages'] || []
      title = plan_data['title'] || plan_data.dig('content', 'headline') || 'Design Plan'
      
      status_msg = design_plan.status == 'draft' ? 
        "This is a **draft** - you can continue editing or build it when ready." :
        "This plan has been **built** into a #{design_plan.design_type.gsub('_', ' ')}."
      
      success_response(
        plan_id: design_plan.id,
        title: title,
        design_type: design_plan.design_type,
        status: design_plan.status,
        sections_count: sections.length,
        pages_count: pages.length,
        message: "📋 Loaded **#{title}**\n\n#{status_msg}",
        canvas_type: 'design_studio',
        canvas_data: { 
          plan_id: design_plan.id, 
          plan: plan_data, 
          status: design_plan.status,
          landing_page_id: design_plan.landing_page_id,
          website_id: design_plan.website_id
        }
      )
    end

    def generate_section(section_type)
      section_type = section_type.to_s
      {
        'name' => section_type,
        'type' => section_type,
        'position' => 99,
        'content' => default_section_content(section_type),
        'background' => section_type == 'hero' ? 'gradient' : 'light'
      }
    end
    
    def default_section_content(section_type)
      case section_type
      when 'hero'
        { 'headline' => 'Your Headline Here', 'subheadline' => 'Supporting text', 'cta_text' => 'Get Started' }
      when 'features'
        { 'section_title' => 'Key Features', 'items' => [{ 'title' => 'Feature', 'description' => 'Description' }] }
      when 'about'
        { 'headline' => 'About Us', 'content' => 'Your story here' }
      when 'contact'
        { 'headline' => 'Get in Touch', 'form_fields' => ['name', 'email', 'message'] }
      when 'testimonials'
        { 'section_title' => 'What People Say', 'items' => [] }
      when 'pricing'
        { 'section_title' => 'Pricing', 'items' => [] }
      when 'cta'
        { 'headline' => 'Ready to Start?', 'cta_text' => 'Sign Up' }
      else
        { 'headline' => section_type.titleize }
      end
    end

    def format_color_scheme(color_scheme)
      return nil unless color_scheme
      
      parts = []
      parts << "Primary: #{color_scheme['primary']}" if color_scheme['primary']
      parts << "Secondary: #{color_scheme['secondary']}" if color_scheme['secondary']
      parts << "Accent: #{color_scheme['accent']}" if color_scheme['accent']
      parts << "Background: #{color_scheme['background']}" if color_scheme['background']
      parts.join(', ')
    end

    # ============================================
    # HELPERS
    # ============================================

    def find_plan(plan_id)
      if plan_id.present?
        # Scope by both entity AND user for security
        plan = DesignPlan.find_by(id: plan_id, entity_id: entity.id, user_id: user.id)
        return error_response("Plan not found or you don't have access to it") unless plan
        plan
      else
        # Find most recent draft plan for this user
        plan = DesignPlan.where(entity_id: entity.id, user_id: user.id, status: 'draft')
                        .order(created_at: :desc)
                        .first
        return error_response("No active plan found. Describe what you want to build.") unless plan
        plan
      end
    end

    # Gather business context from user's profile for personalization
    def gather_business_context
      context = {}
      
      # Get business profile
      profile = user&.business_profile
      if profile
        context['company_name'] = profile.company_name if profile.respond_to?(:company_name) && profile.company_name.present?
        context['tagline'] = profile.tagline if profile.respond_to?(:tagline) && profile.tagline.present?
        context['industry'] = profile.industry if profile.respond_to?(:industry) && profile.industry.present?
        context['target_audience'] = profile.target_audience if profile.respond_to?(:target_audience) && profile.target_audience.present?
        context['brand_colors'] = profile.brand_colors if profile.respond_to?(:brand_colors) && profile.brand_colors.present?
        context['tone'] = profile.voice_tone if profile.respond_to?(:voice_tone) && profile.voice_tone.present?
        context['value_proposition'] = profile.value_proposition if profile.respond_to?(:value_proposition) && profile.value_proposition.present?
      end
      
      # Get entity info
      if entity
        context['company_name'] ||= entity.name
        context['website'] = entity.website if entity.respond_to?(:website) && entity.website.present?
      end
      
      Rails.logger.info "📋 PlanDesign gathered business context: #{context.keys.join(', ')}"
      context
    end

    def broadcast_plan_to_canvas(design_plan)
      session_id = @context[:session_id] if @context
      return unless session_id

      ActionCable.server.broadcast(
        "scout_channel_#{session_id}",
        {
          type: 'canvas_load',
          canvas_type: 'design_studio',
          canvas_title: "Design: #{design_plan.name}",
          canvas_data: {
            plan_id: design_plan.id,
            plan: design_plan.plan_data,
            status: design_plan.status
          }
        }
      )
    end
  end
end
