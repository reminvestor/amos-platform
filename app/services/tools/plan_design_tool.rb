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
          Create a visual plan/blueprint for a landing page or website before building.
          
          USE THIS when user wants to create a landing page or website. Shows a rich visual
          preview with sections, colors, CTA text that user can review and refine.
          
          For LANDING PAGES: Single page with sections (hero, features, testimonials, etc.)
          For WEBSITES: Multiple pages with navigation, each page has sections
          
          Actions:
          - create: Generate new plan from description
          - refine: Modify sections, colors, text, add/remove pages
          - build: Generate actual HTML from plan
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
              enum: %w[landing_page website],
              description: 'landing_page = single page, website = multi-page with navigation'
            },
            action: {
              type: 'string',
              enum: %w[create refine build add_page remove_page],
              description: "Action to perform on the plan"
            },
            plan_id: {
              type: 'integer',
              description: 'ID of existing plan (required for refine/build/add_page/remove_page)'
            },
            # For refinements
            refinements: {
              type: 'object',
              description: 'Changes to make to the plan',
              properties: {
                add_section: { type: 'string', description: 'Section type to add (hero, features, pricing, etc.)' },
                remove_section: { type: 'string', description: 'Section name to remove' },
                update_colors: { type: 'object', description: 'Color scheme changes' },
                update_section: { type: 'object', description: 'Changes to a specific section' },
                update_text: { type: 'object', description: 'Update text in sections (headline, subhead, cta_text)' }
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
      else
        error_response("Unknown action: #{action}")
      end
    end

    private

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
        canvas_type: 'app_designer',
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
        plan_data['color_scheme'] = plan_data['color_scheme'].merge(refinements[:update_colors])
      end

      if refinements[:update_section].present?
        section_name = refinements[:update_section][:name]
        updates = refinements[:update_section].except(:name)
        section = plan_data['sections']&.find { |s| s['name'] == section_name }
        section&.merge!(updates.stringify_keys) if section
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
      plan_id = get_arg(args, :plan_id)

      design_plan = find_plan(plan_id)
      return design_plan if design_plan.is_a?(Hash) # Error response

      # Mark as building
      design_plan.update!(status: 'building')

      if design_plan.design_type == 'website'
        build_website_from_plan(design_plan)
      else
        build_landing_page_from_plan(design_plan)
      end
    end
    
    def build_landing_page_from_plan(design_plan)
      stream_progress("🏗️ Building landing page from your approved plan...", percentage: 10)
      
      # Generate the actual landing page using the existing tool
      generate_tool = Tools::GenerateLandingPageTool.new(
        user: user,
        entity: entity,
        context: @context,
        progress_callback: @progress_callback  # Pass progress callback to child tool
      )

      stream_progress("🎨 Preparing design with #{design_plan.plan_data['sections']&.length || 0} sections...", percentage: 20)

      # Convert plan to generation args with actual content
      plan_data = design_plan.plan_data
      generation_args = {
        title: plan_data['name'],
        description: design_plan.description,
        design_style: plan_data['style'],
        color_scheme: format_color_scheme(plan_data['color_scheme']),
        # Pass section structure with actual content
        key_details: {
          sections: plan_data['sections']&.map { |s| s['name'] },
          layout: plan_data['layout'],
          section_content: plan_data['sections']&.map { |s| 
            { 
              name: s['name'], 
              type: s['type'],
              content: s['content'],  # Actual content from plan
              background: s['background']
            } 
          },
          typography: plan_data['typography'],
          tone: plan_data['tone']
        },
        design_preferences: {
          colors: plan_data['color_scheme'],
          typography: plan_data['typography'],
          style: plan_data['style']
        }
      }

      result = generate_tool.execute(generation_args)

      if result[:success]
        design_plan.update!(
          status: 'completed',
          landing_page_id: result[:id]
        )

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
    
    def build_website_from_plan(design_plan)
      plan_data = design_plan.plan_data
      
      # Create the Website
      website = Website.create!(
        entity: entity,
        created_by: user,
        name: plan_data['name'],
        slug: plan_data['name'].to_s.parameterize,
        description: design_plan.description,
        theme: plan_data['style']&.parameterize || 'modern',
        color_scheme: plan_data['color_scheme'],
        typography: plan_data['typography'],
        navigation: plan_data['navigation'],
        status: 'draft'
      )
      
      # Create each page
      pages = plan_data['pages'] || []
      pages.each_with_index do |page_plan, index|
        # Generate HTML for this page
        page_html = generate_website_page_html(page_plan, plan_data)
        
        website.website_pages.create!(
          entity: entity,
          name: page_plan['name'],
          slug: page_plan['slug'] || page_plan['name'].parameterize,
          template: determine_template(page_plan),
          html_content: page_html,
          sections: page_plan['sections'],
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
      
      success_response(
        plan_id: design_plan.id,
        website_id: website.id,
        page_count: pages.length,
        message: "🎉 Your website with #{pages.length} pages has been built!",
        canvas_type: 'website_editor',
        canvas_data: { website_id: website.id }
      )
    rescue => e
      Rails.logger.error "Build website failed: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
      design_plan.update!(status: 'failed', error_message: e.message)
      error_response("Build failed: #{e.message}")
    end
    
    def generate_website_page_html(page_plan, global_plan)
      # Use the GenerateLandingPageTool's AI to generate HTML for this page
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
              "background": "gradient | dark | light | image"
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
              "background": "light | dark"
            }
          ],
          "special_elements": ["video", "testimonials-carousel", "countdown", "animation"],
          "tone": "Professional, authoritative, friendly, etc."
        }
        
        Include 4-6 sections typically: hero, features/benefits, social proof, pricing or CTA, contact/footer.
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
                  }
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
        canvas_type: 'app_designer',
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
        canvas_type: 'app_designer',
        canvas_data: { plan_id: design_plan.id, plan: plan_data, status: 'draft' }
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
        plan = DesignPlan.find_by(id: plan_id, entity_id: entity.id)
        return error_response("Plan not found") unless plan
        plan
      else
        # Find most recent draft plan
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
          canvas_type: 'app_designer',
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
