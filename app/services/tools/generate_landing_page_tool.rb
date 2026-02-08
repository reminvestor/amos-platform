module Tools
  class GenerateLandingPageTool < BaseTool
    def self.metadata
      {
        name: "generate_ai_landing_page",
        description: <<~DESC.strip,
          AI landing page generator. Creates a complete HTML page with professional design,
          AI-generated images, responsive layout, and lead capture forms.
          
          Called internally by platform_create(type: "landing_page").
          Accepts: title, description, page_type, design_style, business_name,
          key_details, business_info, design_preferences, form_fields, and more.
        DESC
        category: "landing_page",
        input_schema: {
          type: "object",
          properties: {
            title: {
              type: "string",
              description: "Title for the landing page (optional if program_name or business_name provided)"
            },
            description: {
              type: "string",
              description: "Description of what the landing page is for (optional if content_focus or key_details provided)"
            },
            program_name: {
              type: "string",
              description: "Name of the program/offering (can be used as title)"
            },
            business_name: {
              type: "string",
              description: "Business or company name"
            },
            content_focus: {
              type: "string",
              description: "What the content should focus on"
            },
            key_details: {
              type: "object",
              description: "Key details about the offering (pricing, target_audience, goals, etc.)"
            },
            design_style: {
              type: "string",
              description: "Design style and aesthetic preferences"
            },
            page_type: {
              type: "string",
              enum: [ "lead_generation", "product_launch", "event_registration",
                     "newsletter_signup", "free_trial", "demo_request", "general" ],
              description: "Type of landing page to create"
            },
            form_fields: {
              type: "array",
              description: "Custom form fields for lead capture"
            },
            business_info: {
              type: "object",
              description: "Business information (offer, price, value_proposition, etc.)"
            },
            design_preferences: {
              type: "object",
              description: "Design preferences (style, cta, hero_image, etc.)"
            },
            generate_images: {
              type: "boolean",
              description: "Auto-generate AI images for the landing page (hero, features, backgrounds) using Gemini. Defaults to true."
            },
            image_style: {
              type: "string",
              description: "Style for generated images (e.g., 'photorealistic', 'illustration', 'abstract', '3D render'). Defaults to 'professional photography'."
            },
            image_quality: {
              type: "string",
              enum: ["standard", "pro", "hd", "high"],
              description: "Image quality level: 'standard' (fast, default) or 'pro'/'hd'/'high' (high-fidelity, better text rendering). Use pro when user asks for 'high quality', 'pro', 'hd', or 'premium' images."
            }
          },
          required: []  # No strict requirements - tool will intelligently extract what it needs
        }
      }
    end

    def execute(args)
      log_execution(args)

      # DEBUG: Log received arguments
      Rails.logger.info "🔍 DEBUG generate_landing_page received args: #{args.inspect}"
      Rails.logger.info "🔍 DEBUG key_details: #{get_arg(args, :key_details).inspect}"
      Rails.logger.info "🔍 DEBUG business_info: #{get_arg(args, :business_info).inspect}"

      # Intelligently extract title from various sources
      title = get_arg(args, :title) ||
              get_arg(args, :program_name) ||
              get_arg(args, :business_name) ||
              "Landing Page"

      # Intelligently extract description from various sources
      description = get_arg(args, :description) ||
                   get_arg(args, :content_focus) ||
                   get_arg(args, :program_name) ||
                   extract_description_from_details(args) ||
                   "AI-Generated Landing Page"

      page_type = get_arg(args, :page_type, "lead_generation")

      Rails.logger.info "📄 Generating landing page: #{title}"
      Rails.logger.info "📝 Description: #{description[0..100]}..."

      # Stream progress: Starting
      stream_progress("🚀 Starting landing page generation...", percentage: 0)

      begin
        # Stream progress: Analyzing requirements
        stream_progress("📋 Analyzing your requirements and gathering context...", percentage: 10)

        # Gather rich context from business profile
        business_profile = gather_business_profile_context
        
        # Get conversation history if available (for personalization)
        conversation_context = gather_conversation_context
        
          # Get any reference materials (screenshots, URLs analyzed)
        reference_materials = get_arg(args, :reference_materials) || get_arg(args, :reference_analysis)
        
        # NEW: Get screenshot analysis if available (from analyze_screenshot_for_design tool)
        screenshot_analysis = get_arg(args, :screenshot_analysis)

        # Extract all available context for rich page generation
        generation_context = {
          description: description,
          page_type: page_type,
          
          # Nested structured data
          key_details: get_arg(args, :key_details) || {},
          business_info: get_arg(args, :business_info) || {},
          design_preferences: get_arg(args, :design_preferences) || {},
          
          # Basic settings
          design_style: get_arg(args, :design_style),
          form_fields: get_arg(args, :form_fields) || [],
          business_name: get_arg(args, :business_name),
          program_name: get_arg(args, :program_name),
          content_focus: get_arg(args, :content_focus),
          
          # Image and style data
          uploaded_images: get_arg(args, :uploaded_images) || [],
          image_urls: get_arg(args, :image_urls) || [],
          brand_colors: get_arg(args, :brand_colors) || get_arg(args, :colors),
          style_guidelines: get_arg(args, :style_guidelines),
          layout_inspiration: get_arg(args, :layout_notes),
          
          # NEW: Explicit design inputs from agent contract
          color_scheme: get_arg(args, :color_scheme),
          aesthetic_style: get_arg(args, :aesthetic_style),
          layout_preference: get_arg(args, :layout_preference),
          special_elements: get_arg(args, :special_elements) || [],
          
          # NEW: Explicit content inputs from agent contract
          headline: get_arg(args, :headline),
          offer_details: get_arg(args, :offer_details),
          key_benefits: get_arg(args, :key_benefits) || [],
          unique_selling_points: get_arg(args, :unique_selling_points) || [],
          social_proof: get_arg(args, :social_proof),
          cta_text: get_arg(args, :cta_text),
          tone_of_voice: get_arg(args, :tone_of_voice),
          
          # Rich personalization context
          business_profile: business_profile,
          conversation_context: conversation_context,
          reference_materials: reference_materials,
          screenshot_analysis: screenshot_analysis,  # NEW: Structured design spec from screenshot
          design_reference_url: get_arg(args, :design_reference_url),  # User-uploaded design reference image
          
          # Raw args for any additional context the agent provided
          raw_agent_context: args.except(:title, :description)
        }
        
        # Log the rich context being used
        Rails.logger.info "🎨 Generation context keys: #{generation_context.keys.select { |k| generation_context[k].present? }}"

        # Stream progress: Creating record
        stream_progress("💾 Creating landing page record...", percentage: 20)

        # Create the landing page record (without page_type field)
        landing_page = LandingPage.create!(
          user: user,
          entity: entity,
          title: title,
          slug: generate_unique_slug(title),
          status: "draft",
          metadata: {
            ai_generated: true,  # Store in metadata instead
            description: description,
            page_type: page_type,  # Store in metadata instead
            generated_at: Time.current,
            generation_context: generation_context,
            generated_from: "workflow"
          }
        )

        # Auto-generate AI images using Gemini (enabled by default)
        generate_images = get_arg(args, :generate_images, true)
        image_style = get_arg(args, :image_style, "professional photography")
        image_quality = get_arg(args, :image_quality, "standard")&.downcase

        if generate_images
          # Determine provider based on quality
          provider = quality_to_provider(image_quality)
          provider_name = provider == :gemini_pro ? "Gemini Nano Banana Pro" : "Gemini Nano Banana"
          stream_progress("🖼️ Generating AI images with #{provider_name}...", percentage: 25)
          generated_image_urls = generate_landing_page_images(
            title: title,
            description: description,
            context: generation_context,
            style: image_style,
            quality: image_quality,
            landing_page: landing_page
          )

          # Add generated images to the context for HTML generation
          generation_context[:image_urls] = (generation_context[:image_urls] || []) + generated_image_urls
          generation_context[:ai_generated_images] = true
        end

        # Stream progress: Generating HTML with AI
        stream_progress("🎨 Generating page content with AI (this may take 2-3 minutes)...", percentage: 30)

        # Use AI to generate professional HTML
        html_content = generate_ai_html(title, description, generation_context)

        # Stream progress: Compiling
        stream_progress("🔨 Compiling final landing page...", percentage: 90)

        landing_page.update!(html_content: html_content)

        Rails.logger.info "✅ Landing page created with HTML: #{landing_page.id}"

        # Stream progress: Complete!
        stream_progress("✅ Done! Loading your new landing page...", percentage: 100)

        success_response(
          id: landing_page.id,
          landing_page_id: landing_page.id,  # Include for workflow context
          title: landing_page.title,
          slug: landing_page.slug,
          subdomain: landing_page.subdomain,
          subdomain_url: landing_page.subdomain_url,  # Direct URL via subdomain (e.g., mypage.lp.amoslabs.com)
          status: "draft",
          message: "Your landing page '#{landing_page.title}' is ready! Opening the editor now.",
          preview_url: "/landing_pages/#{landing_page.slug}/preview",
          public_url: landing_page.subdomain_url || "/landing/#{landing_page.slug}",
          # Auto-open the landing page editor canvas
          canvas_type: 'landing_page_editor',
          canvas_data: { landing_page_id: landing_page.id }
        )
      rescue => e
        Rails.logger.error "Landing page generation failed: #{e.message}"
        error_response("Failed to create landing page: #{e.message}")
      end
    end

    private

    def quality_to_provider(quality)
      case quality.to_s.downcase
      when "pro", "hd", "high", "high_quality", "premium"
        :gemini_pro
      else
        :gemini
      end
    end

    def extract_description_from_details(args)
      # Try to build a description from key_details or business_info
      key_details = get_arg(args, :key_details)
      business_info = get_arg(args, :business_info)

      if key_details.is_a?(Hash)
        parts = []
        parts << key_details["main_goal"] || key_details[:main_goal] if key_details["main_goal"] || key_details[:main_goal]
        parts << "for #{key_details['target_audience'] || key_details[:target_audience]}" if key_details["target_audience"] || key_details[:target_audience]
        parts << "at #{key_details['pricing'] || key_details[:pricing]}" if key_details["pricing"] || key_details[:pricing]
        return parts.join(" ") if parts.any?
      end

      if business_info.is_a?(Hash)
        parts = []
        parts << business_info["offer"] || business_info[:offer] if business_info["offer"] || business_info[:offer]
        parts << business_info["value_proposition"] || business_info[:value_proposition] if business_info["value_proposition"] || business_info[:value_proposition]
        return parts.join(" - ") if parts.any?
      end

      nil
    end

    def generate_unique_slug(title)
      base_slug = title.parameterize
      slug = base_slug
      counter = 1

      while LandingPage.exists?(slug: slug, entity: entity)
        slug = "#{base_slug}-#{counter}"
        counter += 1
      end

      slug
    end

    def generate_ai_html(title, description, context)
      # Use AI to generate professional landing page HTML
      # Extract values from nested structures
      key_details = context[:key_details] || {}
      business_info = context[:business_info] || {}
      design_prefs = context[:design_preferences] || {}

      # Get actual values with intelligent fallbacks
      business_name = context[:business_name] ||
                     key_details[:company_name] ||
                     key_details["company_name"] ||
                     title

      value_prop = business_info[:value_proposition] ||
                  business_info["value_proposition"] ||
                  key_details[:value_proposition] ||
                  key_details["value_proposition"] ||
                  description

      target_audience = business_info[:target_audience] ||
                       business_info["target_audience"] ||
                       key_details[:target_audience] ||
                       key_details["target_audience"] ||
                       "businesses"

      cta_text = context[:cta_text] ||
                design_prefs[:cta] ||
                design_prefs["cta"] ||
                key_details[:call_to_action] ||
                key_details["call_to_action"] ||
                "Get Started"

      design_style = context[:design_style] ||
                    design_prefs[:style] ||
                    design_prefs["style"] ||
                    key_details[:design_style] ||
                    "modern and professional"

      # Extract rich design preferences (check explicit inputs first, then nested)
      color_scheme = context[:color_scheme] || design_prefs[:color_scheme] || design_prefs["color_scheme"]
      aesthetic = context[:aesthetic_style] || design_prefs[:aesthetic] || design_prefs["aesthetic"]
      layout = context[:layout_preference] || design_prefs[:layout] || design_prefs["layout"]
      typography = design_prefs[:typography] || design_prefs["typography"]
      special_elements = context[:special_elements].presence || design_prefs[:special_elements] || design_prefs["special_elements"]
      imagery = design_prefs[:imagery] || design_prefs["imagery"]
      tone_of_voice = context[:tone_of_voice] || design_prefs[:tone_of_voice] || design_prefs["tone_of_voice"]

      # Extract rich business info (check explicit inputs first, then nested)
      offer = context[:offer_details] || business_info[:offer] || business_info["offer"]
      price = business_info[:price] || business_info["price"]
      key_benefits = context[:key_benefits].presence || business_info[:key_benefits] || business_info["key_benefits"] || []
      course_examples = business_info[:course_examples] || business_info["course_examples"] || []
      
      # Explicit headline override
      headline = context[:headline]
      
      # Social proof from explicit input
      explicit_social_proof = context[:social_proof]

      # Extract key details (check explicit inputs first)
      pricing = key_details[:pricing] || key_details["pricing"]
      brand_voice = tone_of_voice || key_details[:brand_voice] || key_details["brand_voice"]
      unique_selling_points = context[:unique_selling_points].presence || key_details[:unique_selling_points] || key_details["unique_selling_points"] || []
      social_proof = explicit_social_proof || key_details[:social_proof_angle] || key_details["social_proof_angle"]
      urgency = key_details[:urgency_factor] || key_details["urgency_factor"]

      # Get style data from context
      brand_colors = context[:brand_colors] || []
      style_guidelines = context[:style_guidelines] || {}
      layout_inspiration = context[:layout_inspiration]
      uploaded_images = context[:uploaded_images] || []
      image_urls = context[:image_urls] || []

      Rails.logger.info "🎨 Generating HTML with: business=#{business_name}, colors=#{color_scheme || brand_colors.inspect}, design_prefs=#{design_prefs.keys.inspect}"

      # Build comprehensive design section
      design_section = <<~DESIGN

        DESIGN SPECIFICATIONS (FOLLOW THESE EXACTLY):
        #{color_scheme.present? ? "- Color Scheme: #{color_scheme}" : ""}
        #{aesthetic.present? ? "- Aesthetic: #{aesthetic}" : ""}
        #{layout.present? ? "- Layout: #{layout}" : ""}
        #{typography.present? ? "- Typography: #{typography}" : ""}
        #{special_elements.present? ? "- Special Elements to Include: #{special_elements}" : ""}
        #{imagery.present? ? "- Imagery Style: #{imagery}" : ""}
        #{brand_voice.present? ? "- Brand Voice/Tone: #{brand_voice}" : ""}
      DESIGN

      # Build business content section
      content_section = <<~CONTENT

        CONTENT TO INCLUDE:
        #{offer.present? ? "- Main Offer: #{offer}" : ""}
        #{price.present? ? "- Pricing: #{price}" : ""}
        #{pricing.present? ? "- Pricing Details: #{pricing}" : ""}
        #{key_benefits.any? ? "- Key Benefits to Highlight:\n  #{key_benefits.map { |b| "• #{b}" }.join("\n  ")}" : ""}
        #{course_examples.any? ? "- Example Services/Products:\n  #{course_examples.map { |c| "• #{c}" }.join("\n  ")}" : ""}
        #{unique_selling_points.any? ? "- Unique Selling Points:\n  #{unique_selling_points.map { |u| "• #{u}" }.join("\n  ")}" : ""}
        #{social_proof.present? ? "- Social Proof Angle: #{social_proof}" : ""}
        #{urgency.present? ? "- Urgency/CTA Message: #{urgency}" : ""}
      CONTENT

      # Build enhanced prompt with style data (legacy support)
      style_section = if brand_colors.any? || style_guidelines.present?
        <<~STYLE

          BRAND STYLE GUIDELINES:
          #{brand_colors.any? ? "- Brand Colors: #{brand_colors.join(', ')}" : ""}
          #{style_guidelines['typography'] ? "- Typography: #{style_guidelines['typography']}" : ""}
          #{style_guidelines['aesthetic'] ? "- Aesthetic: #{style_guidelines['aesthetic']}" : ""}
          #{layout_inspiration ? "- Layout Inspiration: #{layout_inspiration}" : ""}

          CRITICAL: Use these brand colors in the design!
        STYLE
      else
        ""
      end

      image_section = if uploaded_images.any? || image_urls.any?
        image_list = (uploaded_images + image_urls).first(4)
        hero_image = image_list[0]
        feature_images = image_list[1..3] || []
        
        <<~IMAGES

          === AI-GENERATED IMAGES (USE THESE EXACT URLs!) ===
          
          🚨 CRITICAL: You MUST use these EXACT image URLs in your HTML. Do NOT create placeholder URLs.
          
          HERO IMAGE (use in hero section):
          <img src="#{hero_image}" alt="Hero image for landing page" class="img-fluid">
          
          #{feature_images.any? ? "FEATURE IMAGES (use in features/benefits sections):\n" + feature_images.each_with_index.map { |img, i| "<img src=\"#{img}\" alt=\"Feature image #{i+1}\" class=\"img-fluid\">" }.join("\n") : ""}
          
          RULES FOR IMAGES:
          - Copy the src URL EXACTLY as shown above - these are real, working URLs
          - Use the hero image in the hero/banner section
          - Use feature images in cards/features section
          - Add appropriate alt text for accessibility
          - Do NOT use placeholder URLs like "https://via.placeholder.com" or "image1.jpg"
          - Do NOT make up URLs - use ONLY the URLs provided above
        IMAGES
      else
        ""
      end

      # Build business profile section for deep personalization
      business_profile = context[:business_profile] || {}
      profile_section = if business_profile.any?
        <<~PROFILE

          === BUSINESS PROFILE (Use for authentic, personalized copy) ===
          #{business_profile[:company_name].present? ? "Company: #{business_profile[:company_name]}" : ""}
          #{business_profile[:industry].present? ? "Industry: #{business_profile[:industry]}" : ""}
          #{business_profile[:description].present? ? "About: #{business_profile[:description]}" : ""}
          #{business_profile[:target_audience].present? ? "Primary Audience: #{business_profile[:target_audience]}" : ""}
          #{business_profile[:value_proposition].present? ? "Core Value Prop: #{business_profile[:value_proposition]}" : ""}
          #{business_profile[:tone_of_voice].present? ? "Brand Voice: #{business_profile[:tone_of_voice]}" : ""}
          #{business_profile[:key_differentiators].present? ? "Differentiators: #{business_profile[:key_differentiators]}" : ""}
          #{business_profile[:services].present? ? "Services: #{business_profile[:services]}" : ""}
          #{business_profile[:products].present? ? "Products: #{business_profile[:products]}" : ""}
          #{business_profile[:tagline].present? ? "Tagline: #{business_profile[:tagline]}" : ""}
          #{business_profile[:mission].present? ? "Mission: #{business_profile[:mission]}" : ""}
          #{business_profile[:brand_colors].present? ? "Brand Colors: #{business_profile[:brand_colors]}" : ""}
        PROFILE
      else
        ""
      end

      # NEW: Build screenshot analysis section (HIGHEST PRIORITY for design accuracy!)
      screenshot_analysis = context[:screenshot_analysis]
      screenshot_section = if screenshot_analysis.present?
        design_spec = screenshot_analysis[:design_specification] || screenshot_analysis["design_specification"]
        analysis_mode = screenshot_analysis[:analysis_quality] || screenshot_analysis["analysis_quality"] || "standard"
        
        spec_formatted = if design_spec.is_a?(Hash)
          JSON.pretty_generate(design_spec)
        else
          design_spec.to_s
        end
        
        <<~SCREENSHOT
          
          ═══════════════════════════════════════════════════════════════
          🎨 SCREENSHOT DESIGN SPECIFICATION (#{analysis_mode.upcase} MODE)
          ═══════════════════════════════════════════════════════════════
          
          ⚠️  CRITICAL: This is a #{analysis_mode} analysis of the user's provided screenshot.
          Follow this design specification EXACTLY to match their desired design!
          
          #{spec_formatted}
          
          DESIGN REQUIREMENTS:
          1. **Layout**: Follow the section structure and layout type specified above
          2. **Colors**: Use the EXACT hex codes provided (primary, secondary, accent, background, text)
          3. **Typography**: Match the font styles, sizes, weights, and spacing specified
          4. **Spacing**: Follow the padding, margins, and density measurements
          #{analysis_mode == "high_fidelity" ? "5. **Content**: If extracted_content is provided, use that actual text from the screenshot" : ""}
          
          This design spec is the PRIMARY source of truth for visual design!
          ═══════════════════════════════════════════════════════════════
        SCREENSHOT
      else
        ""
      end
      
      # Build reference materials section (screenshots, URL analysis) - LEGACY support
      reference_materials = context[:reference_materials]
      reference_section = if reference_materials.present? && screenshot_analysis.blank?
        <<~REFERENCE

          === DESIGN REFERENCE ANALYSIS ===
          The user provided reference materials. Here's what was analyzed:
          #{reference_materials}
          
          IMPORTANT: Incorporate the design patterns, layout styles, and visual elements described above!
        REFERENCE
      else
        ""
      end

      # Build conversation context for personalization
      conversation_context = context[:conversation_context] || {}
      conversation_section = if conversation_context[:recent_conversation].present? || conversation_context[:user_inputs].present?
        user_inputs = conversation_context[:user_inputs] || {}
        recent = conversation_context[:recent_conversation] || []
        
        <<~CONVERSATION

          === USER CONVERSATION CONTEXT ===
          #{user_inputs.any? ? "User's specific requests:\n#{user_inputs.map { |k, v| "- #{k}: #{v}" }.join("\n")}" : ""}
          #{recent.any? ? "\nRecent conversation highlights:\n#{recent.last(5).map { |msg| "#{msg[:role]}: #{msg[:content]}" }.join("\n")}" : ""}
          
          Use this context to make the landing page feel personalized to what the user asked for!
        CONVERSATION
      else
        ""
      end

      # Build raw context section for any additional agent-provided info
      raw_context = context[:raw_agent_context] || {}
      additional_context = raw_context.except(:key_details, :business_info, :design_preferences).compact
      additional_section = if additional_context.any?
        <<~ADDITIONAL

          === ADDITIONAL CONTEXT FROM AGENT ===
          #{additional_context.map { |k, v| "#{k}: #{v.is_a?(Hash) || v.is_a?(Array) ? v.to_json : v}" }.join("\n")}
        ADDITIONAL
      else
        ""
      end

      # Build planned sections from design plan (if provided)
      section_content = key_details[:section_content] || key_details["section_content"] || []
      planned_sections = key_details[:sections] || key_details["sections"] || []
      plan_section = if section_content.any?
        sections_formatted = section_content.map do |s|
          content_data = s[:content] || s["content"] || {}
          content_data = content_data.with_indifferent_access if content_data.is_a?(Hash)
          
          # Format content based on section type
          content_lines = []
          
          if content_data.is_a?(Hash)
            # Hero section
            if content_data[:headline].present?
              content_lines << "    ★ HEADLINE (use this exact text): \"#{content_data[:headline]}\""
            end
            if content_data[:subheadline].present?
              content_lines << "    ★ SUBHEADLINE (use this exact text): \"#{content_data[:subheadline]}\""
            end
            if content_data[:cta_text].present?
              content_lines << "    ★ CTA BUTTON TEXT: \"#{content_data[:cta_text]}\""
            end
            if content_data[:cta_secondary].present?
              content_lines << "    ★ SECONDARY CTA: \"#{content_data[:cta_secondary]}\""
            end
            
            # Section title (for features, testimonials, etc)
            if content_data[:section_title].present?
              content_lines << "    ★ SECTION TITLE: \"#{content_data[:section_title]}\""
            end
            
            # Features items
            if content_data[:items].present? && content_data[:items].is_a?(Array)
              content_lines << "    ★ FEATURE ITEMS (use these exact titles and descriptions):"
              content_data[:items].each_with_index do |item, idx|
                item = item.with_indifferent_access if item.is_a?(Hash)
                content_lines << "      #{idx + 1}. Title: \"#{item[:title] || item['title']}\""
                if item[:description] || item['description']
                  content_lines << "         Description: \"#{item[:description] || item['description']}\""
                end
              end
            end
            
            # Testimonials
            if content_data[:testimonials].present? && content_data[:testimonials].is_a?(Array)
              content_lines << "    ★ TESTIMONIALS (use these exact quotes and authors):"
              content_data[:testimonials].each_with_index do |t, idx|
                t = t.with_indifferent_access if t.is_a?(Hash)
                content_lines << "      #{idx + 1}. Quote: \"#{t[:quote] || t['quote']}\""
                content_lines << "         Author: #{t[:author] || t['author']}"
                content_lines << "         Company/Agency: #{t[:agency] || t['agency'] || t[:company] || t['company']}" if (t[:agency] || t['agency'] || t[:company] || t['company']).present?
              end
            end
            
            # Pricing plans
            if content_data[:plans].present? && content_data[:plans].is_a?(Array)
              content_lines << "    ★ PRICING TIERS:"
              content_data[:plans].each do |plan|
                plan = plan.with_indifferent_access if plan.is_a?(Hash)
                content_lines << "      - #{plan[:name]}: #{plan[:price]} #{plan[:best_value] ? '(HIGHLIGHT THIS)' : ''}"
              end
            end
          elsif content_data.is_a?(String)
            content_lines << "    Content: #{content_data}"
          end
          
          section_name = s[:name] || s["name"]
          section_type = s[:type] || s["type"]
          background = s[:background] || s["background"] || "default"
          layout_hint = s[:layout_hint] || s["layout_hint"]
          
          # Advanced options from user
          visual_description = s[:visual_description] || s["visual_description"]
          content_guidance = s[:content_guidance] || s["content_guidance"]
          image_style = s[:image_style] || s["image_style"]
          
          # Build layout instructions based on section type
          layout_instruction = case layout_hint
          when 'centered'
            "⚙️ LAYOUT: CENTERED - Text centered, full width, NO side images"
          when 'split', 'split-image', 'split-left'
            "⚙️ LAYOUT: SPLIT - Text on left (col-lg-6), image on right (col-lg-6)"
          when 'split-right'
            "⚙️ LAYOUT: SPLIT - Image on left (col-lg-6), text on right (col-lg-6)"
          when 'split-video'
            "⚙️ LAYOUT: SPLIT WITH VIDEO - Text on left, video embed on right"
          when 'split-form'
            "⚙️ LAYOUT: SPLIT WITH FORM - Text on left, signup form on right"
          when 'video-background'
            "⚙️ LAYOUT: VIDEO BACKGROUND - Full-width with video as background"
          when '3-column'
            "⚙️ LAYOUT: 3-COLUMN GRID - Three equal columns (col-lg-4)"
          when '2-column'
            "⚙️ LAYOUT: 2-COLUMN GRID - Two equal columns (col-lg-6)"
          when 'icon-grid'
            "⚙️ LAYOUT: ICON GRID - Grid of icon + text pairs"
          when 'carousel'
            "⚙️ LAYOUT: CAROUSEL - Bootstrap carousel for multiple items"
          when 'cards'
            "⚙️ LAYOUT: CARDS - Card-style boxes for each item"
          else
            layout_hint.present? ? "⚙️ LAYOUT: #{layout_hint.upcase}" : ""
          end
          
          section_block = <<~SECTION_ITEM
            
            ▸ SECTION: #{section_name.to_s.titleize} (type: #{section_type})
              Background Style: #{background.upcase}
              #{layout_instruction}
          #{content_lines.join("\n")}
          #{visual_description.present? ? "\n    🎨 VISUAL STYLE (user-specified): #{visual_description}" : ""}
          #{content_guidance.present? ? "\n    📝 CONTENT GUIDANCE (user-specified): #{content_guidance}" : ""}
          #{image_style.present? && image_style != 'none' ? "\n    🖼️ IMAGE STYLE: #{image_style}" : ""}
          SECTION_ITEM
          
          section_block
        end.join("\n")
        
        <<~PLAN
          
          ╔═══════════════════════════════════════════════════════════════════╗
          ║  🎯 APPROVED DESIGN PLAN - YOU MUST USE THIS CONTENT EXACTLY!     ║
          ╚═══════════════════════════════════════════════════════════════════╝
          
          The user REVIEWED and APPROVED this plan. Each section below contains
          the EXACT text to use. DO NOT substitute with generic placeholder text.
          DO NOT invent new headlines or content. USE WHAT IS PROVIDED.
          
          #{sections_formatted}
          
          ╔═══════════════════════════════════════════════════════════════════╗
          ║  ⚠️  TEXT MARKED WITH ★ MUST APPEAR VERBATIM IN THE HTML!        ║
          ║  The user already approved these exact words. Do not change them. ║
          ╚═══════════════════════════════════════════════════════════════════╝
        PLAN
      elsif planned_sections.any?
        # Fallback: just section names without detailed content
        <<~PLAN
          
          === PLANNED SECTIONS ===
          Include these sections in order: #{planned_sections.join(', ')}
        PLAN
      else
        ""
      end

      # NEW: Design Reference Image section
      design_reference_url = context[:design_reference_url]
      design_reference_section = if design_reference_url.present?
        <<~REFERENCE
          
          ═══════════════════════════════════════════════════════════════
          🖼️ DESIGN REFERENCE IMAGE
          ═══════════════════════════════════════════════════════════════
          
          The user uploaded a screenshot as design inspiration: #{design_reference_url}
          
          Please take visual cues from this reference image:
          - Overall layout structure and section arrangement
          - Color palette (if visible)
          - Typography style and sizing
          - Spacing and visual density
          - Call-to-action button styles
          - Hero section treatment
          
          Incorporate these design elements while still creating an original page
          that matches the user's business and content requirements.
          ═══════════════════════════════════════════════════════════════
        REFERENCE
      else
        ""
      end

      prompt = <<~PROMPT
        Generate a complete, highly personalized landing page HTML for this specific business:
        #{screenshot_section}#{design_reference_section}#{plan_section}#{profile_section}
        === PRIMARY REQUIREMENTS ===
        Company Name: #{business_name}
        #{headline.present? ? "EXACT Headline to Use: #{headline}" : "Value Proposition (base headline on this): #{value_prop}"}
        Target Audience: #{target_audience}
        Call to Action Button Text: "#{cta_text}"
        Design Style: #{design_style}
        #{tone_of_voice.present? ? "Writing Tone/Voice: #{tone_of_voice}" : ""}
        #{explicit_social_proof.present? ? "Social Proof to Include: #{explicit_social_proof}" : ""}
        #{design_section}#{content_section}#{style_section}#{image_section}#{reference_section}#{conversation_section}#{additional_section}
        === TECHNICAL REQUIREMENTS ===
        - Use Bootstrap 5 for responsive design
        - Include hero section with compelling headline and CTA
        - Add sections for features/benefits (use the key benefits provided!)
        - Mobile-responsive with smooth scrolling
        - Professional styling with custom CSS
        - Use Font Awesome or similar for icons
        #{color_scheme.present? ? "- IMPORTANT: Use this color scheme: #{color_scheme}" : ""}
        #{special_elements.present? ? "- IMPORTANT: Include these design elements: #{special_elements}" : ""}
        #{layout.present? ? "- IMPORTANT: Follow this layout style: #{layout}" : ""}
        #{brand_colors.any? ? "- Use brand colors: #{brand_colors.join(', ')}" : ""}
        #{uploaded_images.any? ? "- Include uploaded images in appropriate sections" : ""}

        === FORM REQUIREMENTS (CRITICAL - Follow EXACTLY) ===
        Include a signup/contact form with fields: #{context[:form_fields]&.join(', ') || 'name, email, phone'}
        
        FORM STRUCTURE - Use this EXACT pattern:
        <form class="contact-form">
          <div class="mb-3">
            <input type="text" name="name" class="form-control" placeholder="Your Name" required>
          </div>
          <div class="mb-3">
            <input type="email" name="email" class="form-control" placeholder="Your Email" required>
          </div>
          <div class="mb-3">
            <input type="tel" name="phone" class="form-control" placeholder="Your Phone">
          </div>
          <button type="submit" class="btn btn-primary w-100">#{cta_text}</button>
        </form>
        
        FORM RULES:
        - NO inline JavaScript (no onclick, onsubmit, etc.)
        - NO action attribute (leave it off or use action="#")
        - NO complex nested elements inside form
        - Use simple Bootstrap form classes
        - Each input should have a unique name attribute
        
        JAVASCRIPT RULES (if including any scripts):
        - Use single quotes for strings containing HTML attributes
        - CORRECT: element.innerHTML = '<div style="padding:20px;">...</div>';
        - WRONG: element.innerHTML = "<div style="padding:20px;">...</div>";
        - Always escape quotes properly to avoid syntax errors

        === PERSONALIZATION (CRITICAL - Make this feel custom, not generic!) ===
        - Company name in logo/header: "#{business_name}" (NOT generic placeholders)
        #{headline.present? ? "- EXACT Hero headline to use: \"#{headline}\"" : "- Hero headline should incorporate: \"#{value_prop}\""}
        - CTA buttons should say: "#{cta_text}"
        - Content should speak directly to: "#{target_audience}"
        - Use industry-specific language and terminology
        #{key_benefits.any? ? "- Feature section MUST include these exact benefits:\n  #{key_benefits.first(6).map { |b| "• #{b}" }.join("\n  ")}" : ""}
        #{unique_selling_points.any? ? "- Unique selling points to highlight:\n  #{unique_selling_points.first(5).map { |u| "• #{u}" }.join("\n  ")}" : ""}
        #{color_scheme.present? ? "- Use this EXACT color palette throughout: #{color_scheme}" : ""}
        #{aesthetic.present? ? "- Match this aesthetic style: #{aesthetic}" : ""}
        #{layout.present? ? "- Follow this layout pattern: #{layout}" : ""}
        #{brand_voice.present? ? "- Write all copy in this voice/tone: #{brand_voice}" : ""}
        #{business_profile[:tagline].present? ? "- Include the tagline: \"#{business_profile[:tagline]}\"" : ""}
        #{social_proof.present? ? "- Include this social proof: #{social_proof}" : ""}
        #{offer.present? ? "- Feature this offer prominently: #{offer}" : ""}
        
        ⚠️⚠️⚠️ IF A DESIGN PLAN WAS PROVIDED ABOVE (marked with ★), YOU MUST:
        - Use the EXACT headlines from the plan
        - Use the EXACT feature titles and descriptions from the plan
        - Use the EXACT testimonial quotes and authors from the plan
        - Use the EXACT CTA text from the plan
        - Do NOT substitute with generic "Transform Your Business" or similar
        - The user APPROVED that specific content - changing it is a failure!

        Return ONLY the complete HTML (from <!DOCTYPE html> to </html>).
        Make it conversion-optimized, visually unique, and feel CUSTOM-MADE for this specific business.
        
        DO NOT use generic placeholder text like "Lorem ipsum" or "[Company Name]" - use the ACTUAL data provided above!
        
        EFFICIENCY REQUIREMENTS (to ensure complete output):
        - Use Bootstrap 5 utility classes instead of custom CSS when possible
        - Keep custom CSS minimal - only for brand colors and unique design elements
        - Include: Hero, Features (3-4), Benefits, Form, Testimonials (2-3), CTA, Footer
        - MUST complete all form fields with proper closing tags and submit button
        - MUST include </body></html> at the end - incomplete HTML is unusable!
        
        TEXT CONTRAST (CRITICAL - Never create unreadable text!):
        - EVERY piece of text must be clearly readable against its background
        - Dark text (#1a1a2e, #333, #1e293b) on light/white backgrounds
        - Light/white text (#fff, #f8fafc) ONLY on dark or colored backgrounds
        - NEVER use light/gray text on white or light backgrounds
        - NEVER use white text on light-colored sections (light pink, light blue, etc.)
        - Test mentally: "Can I read this text?" If not, fix the contrast
        - Headings should ALWAYS be high-contrast (dark on light, or white on dark)
        - Body text should be at least #555 on white backgrounds
        - If using a gradient background, ensure text color contrasts with ALL parts of the gradient

        FOOTER STYLING (CRITICAL):
        - Footer should have a DARK background (e.g., bg-dark, #1e293b, #0f172a)
        - Footer TEXT must be LIGHT/WHITE (text-light, text-white, #e2e8f0, #f8fafc)
        - Links in footer should be light colored with hover states
        - Use classes like: footer { background: #1e293b; color: #e2e8f0; }
      PROMPT

      begin
        ai_service = BedrockService.new(user: user, entity: entity)

        messages = [
          { role: "user", content: prompt }
        ]

        # Use Qwen 3 Coder for HTML generation - specialized for code/markup tasks
        # Using Qwen3-Next-80B - our best performing model (9.2/10 benchmarks, 131K context)
        # Switched from qwen-3-coder-30b which was returning empty responses
        Rails.logger.info "🚀 Using Qwen3-Next-80B for landing page generation"
        response = ai_service.complete(
          messages: messages,
          max_tokens: 8192,
          temperature: 0.7,
          model: 'qwen3-next-80b'
        )

        # Strip markdown code blocks if AI wrapped the HTML
        cleaned_response = strip_markdown_wrapper(response)
        
        # Check for truncated HTML (common signs of incomplete output)
        is_truncated = !cleaned_response.include?("</html>") || 
                       !cleaned_response.include?("</body>") ||
                       !cleaned_response.include?("</form>") ||
                       cleaned_response.scan(/<form/).count > cleaned_response.scan(/<\/form>/).count
        
        if is_truncated
          Rails.logger.warn "⚠️ AI response appears truncated - HTML incomplete"
          Rails.logger.warn "⚠️ Response length: #{cleaned_response.length} chars"
          Rails.logger.warn "⚠️ Has </html>: #{cleaned_response.include?('</html>')}"
          Rails.logger.warn "⚠️ Has </body>: #{cleaned_response.include?('</body>')}"
          Rails.logger.warn "⚠️ Forms: #{cleaned_response.scan(/<form/).count} opens, #{cleaned_response.scan(/<\/form>/).count} closes"
        end

        # Sanitize any corrupted forms
        cleaned_response = sanitize_forms(cleaned_response)

        # Extract HTML from response
        html = if cleaned_response.include?("<!DOCTYPE html>")
          cleaned_response
        else
          # Fallback if AI didn't return HTML
          Rails.logger.warn "⚠️ Using fallback HTML - AI response didn't contain valid HTML"
          generate_fallback_html(title, description, business_name, value_prop, cta_text)
        end
        
        # Ensure HTML has proper structure (closing tags)
        html = ensure_html_structure(html)
        
        # CRITICAL: Ensure a contact form exists - inject if missing
        html = ensure_form_exists(html, cta_text, business_name)

        # Inject form submission JavaScript (AI-generated forms won't have this!)
        inject_form_handling_script(html)
      rescue => e
        Rails.logger.error "AI HTML generation failed: #{e.message}"
        html = generate_fallback_html(title, description, business_name, value_prop, cta_text)
        inject_form_handling_script(html)
      end
    end

    def inject_form_handling_script(html)
      # Generate the submission URL based on the landing page slug
      # The slug will be extracted from the saved landing page
      form_script = <<~JAVASCRIPT
        <script>
        document.addEventListener('DOMContentLoaded', function() {
          // Handle ALL forms on this landing page
          const forms = document.querySelectorAll('form');
          
          // Detect if we're in preview mode
          const isPreviewMode = window.location.pathname.includes('/preview') || 
                                window.location.pathname.includes('/landing_pages/') ||
                                (window.parent !== window && window.parent.location.pathname.includes('/landing_pages/'));
          
          console.log('[Landing Page] Form handler initialized. Found ' + forms.length + ' forms. Preview mode: ' + isPreviewMode);
          
          forms.forEach(function(form, index) {
            // Skip forms that already have a valid external action (starts with http)
            const action = form.getAttribute('action');
            if (action && action.startsWith('http')) {
              console.log('[Landing Page] Skipping form ' + index + ' - has external action: ' + action);
              return;
            }
            
            console.log('[Landing Page] Attaching submit handler to form ' + index);
            
            // CRITICAL: Remove any action/method attributes that could cause regular submission
            form.removeAttribute('action');
            form.removeAttribute('method');
            form.setAttribute('data-handled', 'true');
            
            form.addEventListener('submit', function(e) {
              e.preventDefault();
              e.stopPropagation();
              
              console.log('[Landing Page] Form submitted');
              
              const formData = new FormData(form);
              const submitButton = form.querySelector('button[type="submit"], input[type="submit"], button:not([type])');
              const originalText = submitButton ? submitButton.textContent || submitButton.value : '';
              
              // Show loading state
              if (submitButton) {
                submitButton.disabled = true;
                if (submitButton.tagName === 'BUTTON') {
                  submitButton.textContent = 'Sending...';
                } else {
                  submitButton.value = 'Sending...';
                }
              }
              
              // Build submission URL - extract slug from current URL
              let submissionUrl = '/api/v1/landing_page_submissions';
              
              // Try multiple URL patterns
              // Pattern 1: /landing/slug (public URL)
              // Pattern 2: /landing_pages/slug/preview (preview URL)
              // Pattern 3: /landing_pages/slug (editor URL)
              let slug = null;
              
              const publicMatch = window.location.pathname.match(/\\/landing\\/([^\\/]+)/);
              const previewMatch = window.location.pathname.match(/\\/landing_pages\\/([^\\/]+)\\/preview/);
              const editorMatch = window.location.pathname.match(/\\/landing_pages\\/([^\\/]+)$/);
              
              if (publicMatch) {
                slug = publicMatch[1];
              } else if (previewMatch) {
                slug = previewMatch[1];
              } else if (editorMatch && editorMatch[1] !== 'new') {
                slug = editorMatch[1];
              }
              
              if (slug) {
                submissionUrl = '/api/v1/landing_pages/' + slug + '/submit';
              }
              
              // Add preview flag if in preview mode
              if (isPreviewMode) {
                submissionUrl += (submissionUrl.includes('?') ? '&' : '?') + 'preview=true';
              }
              
              console.log('[Landing Page] Detected slug: ' + slug + ', URL: ' + submissionUrl);
              
              console.log('[Landing Page] Submitting to: ' + submissionUrl);
              
              fetch(submissionUrl, {
                method: 'POST',
                body: formData,
                headers: {
                  'X-Requested-With': 'XMLHttpRequest'
                }
              })
              .then(response => response.json())
              .then(data => {
                console.log('[Landing Page] Response:', data);
                if (data.success) {
                  form.innerHTML = '<div class="alert alert-success" style="padding: 20px; background: #d4edda; border: 1px solid #c3e6cb; border-radius: 8px; color: #155724;"><h4 style="margin: 0 0 10px 0;">Thank you!</h4><p style="margin: 0;">' + data.message + '</p></div>';
                } else {
                  showFormError(form, data.message || 'There was an error submitting your form.');
                  if (submitButton) {
                    submitButton.disabled = false;
                    if (submitButton.tagName === 'BUTTON') {
                      submitButton.textContent = originalText;
                    } else {
                      submitButton.value = originalText;
                    }
                  }
                }
              })
              .catch(error => {
                console.error('[Landing Page] Error:', error);
                showFormError(form, 'There was an error submitting your form. Please try again.');
                if (submitButton) {
                  submitButton.disabled = false;
                  if (submitButton.tagName === 'BUTTON') {
                    submitButton.textContent = originalText;
                  } else {
                    submitButton.value = originalText;
                  }
                }
              });
            });
          });
          
          function showFormError(form, message) {
            let errorDiv = form.querySelector('.form-error');
            if (!errorDiv) {
              errorDiv = document.createElement('div');
              errorDiv.className = 'alert alert-danger form-error';
              errorDiv.style.cssText = 'padding: 15px; background: #f8d7da; border: 1px solid #f5c6cb; border-radius: 8px; color: #721c24; margin-bottom: 15px;';
              form.insertBefore(errorDiv, form.firstChild);
            }
            errorDiv.textContent = message;
          }
        });
        </script>
      JAVASCRIPT

      # Inject the script before </body>
      # Be robust about finding the right place to inject
      if html.include?("</body>")
        html.sub("</body>", "#{form_script}\n</body>")
      elsif html.include?("</html>")
        # No </body> but has </html> - inject before </html>
        html.sub("</html>", "#{form_script}\n</body>\n</html>")
      else
        # Malformed HTML - wrap properly
        Rails.logger.warn "⚠️ Landing page HTML missing </body> and </html> tags - fixing structure"
        # Ensure we have proper closing tags
        "#{html}\n#{form_script}\n</body>\n</html>"
      end
    end
    
    # Ensure HTML has proper structure before processing
    def ensure_html_structure(html)
      return html unless html.present?
      
      result = html.dup
      
      # Check for and fix missing closing tags
      has_body_close = result.include?("</body>")
      has_html_close = result.include?("</html>")
      
      unless has_body_close
        if has_html_close
          result = result.sub("</html>", "</body>\n</html>")
        else
          result = "#{result}\n</body>\n</html>"
        end
        Rails.logger.warn "⚠️ Added missing </body> tag to landing page HTML"
      end
      
      unless has_html_close
        result = "#{result}\n</html>"
        Rails.logger.warn "⚠️ Added missing </html> tag to landing page HTML"
      end
      
      result
    end

    def strip_markdown_wrapper(html)
      # Remove markdown code block wrappers: ```html ... ``` or ``` ... ```
      cleaned = html.to_s.strip

      # Remove starting code block (case insensitive)
      cleaned = cleaned.sub(/\A```html\s*\n?/i, "")
      cleaned = cleaned.sub(/\A```\s*\n?/, "")

      # Remove ending code block
      cleaned = cleaned.sub(/\n?```\s*\z/, "")

      cleaned.strip
    end

    # Ensure a contact form exists in the landing page
    def ensure_form_exists(html, cta_text = "Get Started", business_name = "us")
      return html unless html.present?
      
      # Check if form already exists
      if html.include?('<form') && html.include?('</form>')
        Rails.logger.info "✅ Form found in landing page HTML"
        return html
      end
      
      Rails.logger.warn "⚠️ No form found in landing page - injecting default form"
      
      # Create a form section to inject
      form_section = <<~FORM
        <!-- Contact Form Section (Auto-injected) -->
        <section class="py-5 bg-light" id="contact">
          <div class="container">
            <div class="row justify-content-center">
              <div class="col-lg-6">
                <div class="card shadow">
                  <div class="card-body p-4">
                    <h3 class="text-center mb-4">Get In Touch</h3>
                    <p class="text-center text-muted mb-4">Ready to get started? Fill out the form below and we'll be in touch!</p>
                    <form class="contact-form">
                      <div class="mb-3">
                        <input type="text" name="name" class="form-control" placeholder="Your Name" required>
                      </div>
                      <div class="mb-3">
                        <input type="email" name="email" class="form-control" placeholder="Your Email" required>
                      </div>
                      <div class="mb-3">
                        <input type="tel" name="phone" class="form-control" placeholder="Your Phone">
                      </div>
                      <div class="mb-3">
                        <textarea name="message" class="form-control" rows="3" placeholder="How can we help?"></textarea>
                      </div>
                      <button type="submit" class="btn btn-primary w-100">#{cta_text}</button>
                    </form>
                  </div>
                </div>
              </div>
            </div>
          </div>
        </section>
      FORM
      
      # Inject before </body> or footer
      if html.include?('</footer>')
        html.sub('</footer>', "</footer>\n#{form_section}")
      elsif html.include?('</main>')
        html.sub('</main>', "#{form_section}\n</main>")
      elsif html.include?('</body>')
        html.sub('</body>', "#{form_section}\n</body>")
      else
        # Append if no clear injection point
        html + form_section
      end
    end

    # Sanitize forms to remove problematic attributes and ensure proper submission
    def sanitize_forms(html)
      return html unless html.present?
      
      cleaned = html.dup
      
      # Remove inline event handlers from forms and form elements
      # These patterns catch onclick, onsubmit, onchange, etc.
      cleaned = cleaned.gsub(/\s+on\w+\s*=\s*["'][^"']*["']/i, '')
      cleaned = cleaned.gsub(/\s+on\w+\s*=\s*[^\s>]+/i, '')
      
      # Remove ALL action attributes from forms - we handle submission via JS
      # This prevents forms from submitting to random URLs
      cleaned = cleaned.gsub(/<form([^>]*)\s+action\s*=\s*["'][^"']*["']([^>]*)>/i, '<form\1\2>')
      
      # Remove method="get" - our JS uses POST
      cleaned = cleaned.gsub(/<form([^>]*)\s+method\s*=\s*["']get["']([^>]*)>/i, '<form\1\2>')
      
      # Remove JavaScript pseudo-URLs from any remaining actions
      cleaned = cleaned.gsub(/action\s*=\s*["']javascript:[^"']*["']/i, '')
      
      # Remove data-* attributes that might contain JavaScript
      cleaned = cleaned.gsub(/\s+data-[a-z-]+\s*=\s*["']javascript:[^"']*["']/i, '')
      
      # Fix common malformed form patterns
      # Remove any script tags inside forms (shouldn't be there)
      cleaned = cleaned.gsub(/<form[^>]*>.*?<script.*?<\/script>.*?<\/form>/mi) do |match|
        match.gsub(/<script.*?<\/script>/mi, '')
      end
      
      # Ensure form has proper structure - fix unclosed form tags
      form_count = cleaned.scan(/<form[^>]*>/i).length
      close_form_count = cleaned.scan(/<\/form>/i).length
      
      if form_count > close_form_count
        Rails.logger.warn "⚠️ Found #{form_count} form opens but only #{close_form_count} closes - adding missing close tags"
        # Add missing close tags before </body> or at end
        missing = form_count - close_form_count
        missing.times do
          if cleaned.include?('</body>')
            cleaned = cleaned.sub('</body>', "</form>\n</body>")
          else
            cleaned += "\n</form>"
          end
        end
      end
      
      Rails.logger.info "✅ Form sanitization complete"
      cleaned
    rescue => e
      Rails.logger.warn "Form sanitization failed: #{e.message}"
      html # Return original if sanitization fails
    end

    # Gather business profile data for personalization
    def gather_business_profile_context
      return {} unless entity
      
      profile = entity.business_profiles.first rescue nil
      return {} unless profile
      
      {
        company_name: profile.company_name,
        industry: profile.industry,
        description: profile.description,
        target_audience: profile.target_audience,
        value_proposition: profile.value_proposition,
        tone_of_voice: profile.tone_of_voice,
        key_differentiators: profile.key_differentiators,
        services: profile.services,
        products: profile.products,
        website: profile.website,
        tagline: profile.tagline,
        mission: profile.mission,
        # Brand settings if available
        brand_colors: entity.brand_settings&.dig('colors'),
        brand_fonts: entity.brand_settings&.dig('fonts'),
        logo_url: entity.logo_url
      }.compact
    rescue => e
      Rails.logger.warn "Could not gather business profile: #{e.message}"
      {}
    end
    
    # Gather relevant conversation context
    def gather_conversation_context
      return {} unless @context
      
      # Get session ID and recent conversation if available
      session_id = @context[:session_id]
      return {} unless session_id
      
      # Try to get recent conversation history
      recent_messages = ScoutConversation.where(session_id: session_id)
                                          .order(created_at: :desc)
                                          .limit(10)
                                          .pluck(:role, :content) rescue []
      
      # Also check for any user inputs from agent interactions
      user_inputs = @context[:user_inputs] || {}
      
      {
        recent_conversation: recent_messages.reverse.map { |role, content| 
          { role: role, content: content&.truncate(500) }
        },
        user_inputs: user_inputs,
        session_context: @context[:metadata] || {}
      }.compact
    rescue => e
      Rails.logger.warn "Could not gather conversation context: #{e.message}"
      {}
    end

    # Generate AI images for the landing page using Gemini
    def generate_landing_page_images(title:, description:, context:, style:, landing_page:, quality: "standard")
      generated_urls = []

      begin
        # Check if Gemini is configured
        unless ENV["GEMINI_API_KEY"].present?
          Rails.logger.warn "[GenerateLandingPageTool] Gemini API key not configured, skipping image generation"
          return []
        end

        # Determine provider based on quality
        provider = quality_to_provider(quality)
        provider_name = provider == :gemini_pro ? "Gemini Nano Banana Pro" : "Gemini Nano Banana"
        Rails.logger.info "[GenerateLandingPageTool] Using #{provider_name} for image generation (quality=#{quality})"

        service = ImageGenerationService.new(provider: provider)
        # Use Rails default URL options for proper host in production
        # Production default is 'app.amoslabs.com', development is 'localhost:3000'
        host = Rails.application.routes.default_url_options[:host] || 
               ENV["APP_HOST"] || 
               (Rails.env.production? ? "app.amoslabs.com" : "localhost:3000")

        # Extract context for prompts
        business_name = context[:business_name] || title
        page_type = context[:page_type] || "lead_generation"
        key_benefits = context[:key_benefits] || []
        industry = context.dig(:business_profile, :industry)

        # 1. Generate hero image (landscape)
        hero_prompt = build_hero_image_prompt(
          business_name: business_name,
          description: description,
          style: style,
          industry: industry
        )

        Rails.logger.info "[GenerateLandingPageTool] Generating hero image: #{hero_prompt.truncate(100)}"

        hero_asset = service.generate_and_store!(
          user: user,
          entity: entity,
          title: "#{title} - Hero Image",
          description: hero_prompt,
          size: "1536x1024",  # Landscape for hero
          tags: ["ai-generated", "landing-page", "hero", "landing-page-#{landing_page.id}", provider.to_s, "quality-#{quality}"]
        )

        if hero_asset&.file&.attached?
          hero_url = Rails.application.routes.url_helpers.rails_blob_url(hero_asset.file, host: host)
          generated_urls << hero_url
          Rails.logger.info "[GenerateLandingPageTool] Hero image generated: #{hero_asset.id}"
        end

        # 2. Generate feature images (3 square images for features section)
        feature_prompts = build_feature_image_prompts(
          key_benefits: key_benefits,
          business_name: business_name,
          style: style,
          description: description
        )

        feature_prompts.each_with_index do |prompt, index|
          Rails.logger.info "[GenerateLandingPageTool] Generating feature image #{index + 1}: #{prompt.truncate(80)}"

          feature_asset = service.generate_and_store!(
            user: user,
            entity: entity,
            title: "#{title} - Feature #{index + 1}",
            description: prompt,
            size: "1024x1024",  # Square for features
            tags: ["ai-generated", "landing-page", "feature", "landing-page-#{landing_page.id}", provider.to_s, "quality-#{quality}"]
          )

          if feature_asset&.file&.attached?
            feature_url = Rails.application.routes.url_helpers.rails_blob_url(feature_asset.file, host: host)
            generated_urls << feature_url
          end
        end

        # Store generated image IDs in landing page metadata
        landing_page.update!(
          metadata: landing_page.metadata.merge(
            "generated_images" => generated_urls,
            "image_generation_style" => style
          )
        )

        Rails.logger.info "[GenerateLandingPageTool] Generated #{generated_urls.count} images for landing page #{landing_page.id}"
        generated_urls
      rescue => e
        Rails.logger.error "[GenerateLandingPageTool] Image generation failed: #{e.message}"
        []  # Return empty array on failure, page will still generate without images
      end
    end

    def build_hero_image_prompt(business_name:, description:, style:, industry: nil)
      base_prompt = "Professional #{style} for a business landing page hero section. "

      if industry.present?
        base_prompt += "#{industry} industry theme. "
      end

      base_prompt += "Visual concept representing: #{description.truncate(200)}. "
      base_prompt += "Modern, clean, high-quality, suitable for a professional website header. "
      base_prompt += "Wide composition with space for text overlay. No text in image."

      base_prompt
    end

    def build_feature_image_prompts(key_benefits:, business_name:, style:, description:)
      # Generate 3 feature images
      prompts = []

      # If we have key benefits, generate images for those
      if key_benefits.is_a?(Array) && key_benefits.any?
        key_benefits.first(3).each do |benefit|
          prompts << "Professional #{style} icon/illustration representing: #{benefit}. Clean, modern design suitable for a website features section. Minimalist, professional style. No text."
        end
      end

      # Fill remaining slots with generic feature images
      default_concepts = [
        "Professional teamwork and collaboration",
        "Innovation and growth concept",
        "Customer success and satisfaction"
      ]

      while prompts.count < 3
        concept = default_concepts[prompts.count]
        prompts << "Professional #{style} representing #{concept}. Modern, clean design for a business website. Square format, suitable for features section. No text in image."
      end

      prompts.first(3)
    end

    def generate_fallback_html(title, description, business_name, value_prop = nil, cta_text = nil)
      # Simple fallback template
      <<~HTML
        <!DOCTYPE html>
        <html lang="en">
        <head>
          <meta charset="UTF-8">
          <meta name="viewport" content="width=device-width, initial-scale=1.0">
          <title>#{title}</title>
          <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/css/bootstrap.min.css" rel="stylesheet">
          <style>
            .hero { min-height: 60vh; background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); color: white; }
          </style>
        </head>
        <body>
          <section class="hero d-flex align-items-center">
            <div class="container text-center">
              <h1 class="display-3 fw-bold mb-4">#{business_name}</h1>
              <p class="lead mb-4">#{value_prop || description}</p>
              <a href="#contact" class="btn btn-light btn-lg">#{cta_text || 'Get Started'}</a>
            </div>
          </section>
        #{'  '}
          <section id="contact" class="py-5">
            <div class="container">
              <div class="col-lg-6 mx-auto">
                <h2 class="text-center mb-4">Get in Touch</h2>
                <form class="card p-4">
                  <div class="mb-3">
                    <input type="text" class="form-control" placeholder="Name" required>
                  </div>
                  <div class="mb-3">
                    <input type="email" class="form-control" placeholder="Email" required>
                  </div>
                  <button type="submit" class="btn btn-primary w-100">Submit</button>
                </form>
              </div>
            </div>
          </section>
        #{'  '}
          <script src="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/js/bootstrap.bundle.min.js"></script>
        </body>
        </html>
      HTML
    end
  end
end
