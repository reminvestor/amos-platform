require_relative "../../models/landing_page_dsl"

module AiAgents
  class LandingPageDslAgent < BaseAgent
    def initialize
      super
      @ai_service = AiServiceHelper.get_service
    end

    def generate_dsl(business_name:, industry:, target_audience:, key_message:, theme: "professional", primary_color: nil, style_notes: nil, images: [], image_preferences: {}, raw_context: {})
      Rails.logger.info "LandingPageDslAgent: Generating DSL for #{business_name} (#{industry})"

      system_prompt = build_dsl_system_prompt
      user_prompt = build_dsl_user_prompt(
        business_name: business_name,
        industry: industry,
        target_audience: target_audience,
        key_message: key_message,
        theme: theme,
        primary_color: primary_color,
        style_notes: style_notes,
        images: images,
        image_preferences: image_preferences
      )

      # Generate DSL using AI
      Rails.logger.info "LandingPageDslAgent: SYSTEM PROMPT (first 200): #{system_prompt.first(200)}..."
      Rails.logger.info "LandingPageDslAgent: USER PROMPT (first 400): #{user_prompt.first(400)}..."
      response = @ai_service.send_message(
        system_prompt,
        user_prompt,
        model: "claude-sonnet-4-5",  # Sonnet for reliable code/build output
        max_tokens: 4000,
        temperature: 0.7
      )

      if response.blank?
        raise "AI service returned empty response"
      end

      # Parse JSON response (strip markdown code blocks if present)
      begin
        # Remove markdown code blocks if present
        cleaned_response = response.strip
        if cleaned_response.start_with?("```json") && cleaned_response.end_with?("```")
          cleaned_response = cleaned_response[7..-4] # Remove ```json and ```
        elsif cleaned_response.start_with?("```") && cleaned_response.end_with?("```")
          cleaned_response = cleaned_response[3..-4] # Remove ``` and ```
        end

        dsl_content = JSON.parse(cleaned_response)
      rescue JSON::ParserError => e
        Rails.logger.error "Failed to parse AI response as JSON: #{e.message}"
        Rails.logger.error "Original response: #{response}"
        Rails.logger.error "Cleaned response: #{cleaned_response}"
        raise "AI generated invalid JSON: #{e.message}"
      end

      # Validate the DSL structure
      validation = ::LandingPageDsl.validate(dsl_content)
      unless validation[:valid]
        Rails.logger.error "Generated DSL failed validation: #{validation[:errors].join(', ')}"

        # Try to fix common issues automatically
        dsl_content = fix_common_dsl_issues(dsl_content)

        # Validate again
        validation = ::LandingPageDsl.validate(dsl_content)
        unless validation[:valid]
          raise "Generated DSL failed validation even after fixes: #{validation[:errors].join(', ')}"
        end
      end

      Rails.logger.info "LandingPageDslAgent: Successfully generated and validated DSL"
      dsl_content
    end

    private

    def build_dsl_system_prompt
      <<~PROMPT
        You are an expert landing page designer and developer who creates structured landing page specifications using a Domain Specific Language (DSL).

        CRITICAL: You must respond with ONLY valid JSON that follows the exact DSL schema provided below.

        LANDING PAGE DSL SCHEMA:
        ```json
        {
          "page": {
            "theme": "clean|modern|bold|professional|creative",
            "title": "Page title for SEO (max 100 chars)",
            "description": "Meta description for SEO (max 200 chars)",
            "sections": [
              {
                "type": "hero",
                "headline": "Main headline (5-100 chars)",
                "subheadline": "Supporting text (max 200 chars)",
                "cta": {
                  "text": "Button text (2-30 chars)",
                  "action": "submit_form|external_link|scroll_to|download",
                  "target": "#contact|https://example.com|#section",
                  "style": "primary|secondary|outline"
                },
                "image": {
                  "src": "https://images.unsplash.com/...",
                  "alt": "Image description"
                },
                "background": {
                  "type": "color|gradient|image",
                  "value": "#ffffff|linear-gradient(...)|url(...)"
                }
              },
              {
                "type": "features",
                "title": "Section title",
                "subtitle": "Optional subtitle",
                "items": [
                  {
                    "title": "Feature name",
                    "description": "Feature description",
                    "icon": "bootstrap-icon-name"
                  }
                ]
              },
              {
                "type": "cta",
                "headline": "Call to action headline",
                "description": "Supporting text",
                "button": {
                  "text": "Button text",
                  "action": "submit_form",
                  "style": "primary"
                }
              },
              {
                "type": "testimonials",
                "title": "Section title",
                "items": [
                  {
                    "quote": "Customer testimonial",
                    "author": "Customer name",
                    "title": "Customer title/company"
                  }
                ]
              },
              {
                "type": "contact",
                "title": "Contact section title",
                "description": "Contact description",
                "fields": ["name", "email", "phone", "company", "message"]
              },
              {
                "type": "about",
                "title": "About section title",
                "content": "About content with paragraphs"
              }
            ]
          }
        }
        ```

        DESIGN PRINCIPLES:
        - Use professional, conversion-focused copy
        - Include clear value propositions
        - Add social proof when appropriate
        - Ensure mobile-responsive design
        - Include proper call-to-action placement
        - Use industry-appropriate language and tone

        THEME CHARACTERISTICS:
        - clean: Minimalist, lots of white space, simple typography
        - modern: Contemporary with gradients, rounded corners
        - bold: High contrast, vibrant colors, strong typography
        - professional: Corporate, trustworthy, conservative colors
        - creative: Playful, unique layouts, artistic elements

        BOOTSTRAP ICONS AVAILABLE:
        check-circle, star, shield, trophy, lightbulb, gear, graph-up, people,#{' '}
        chat, phone, envelope, calendar, clock, map, award, heart, thumbs-up

        UNSPLASH IMAGE GUIDELINES:
        - Use high-quality Unsplash URLs: https://images.unsplash.com/photo-[id]?w=800&h=600&fit=crop
        - Choose images that match the business industry and theme
        - Always include descriptive alt text
        - Prefer professional, business-appropriate images

        RESPONSE FORMAT:
        Respond with ONLY the JSON DSL structure. No additional text, explanations, or markdown formatting.
      PROMPT
    end

    def build_dsl_user_prompt(business_name:, industry:, target_audience:, key_message:, theme:, primary_color:, style_notes:, images:, image_preferences: {})
      prompt = <<~PROMPT
        Create a landing page DSL for the following business:

        BUSINESS INFORMATION:
        - Business Name: #{business_name}
        - Industry: #{industry}
        - Target Audience: #{target_audience}
        - Key Message: #{key_message}

        DESIGN PREFERENCES:
        - Theme: #{theme}
      PROMPT

      if primary_color.present?
        prompt += "- Primary Color: #{primary_color}\n"
      end

      if style_notes.present?
        prompt += "- Style Notes: #{style_notes}\n"
      end

      # Include any uploaded/library images as preferred assets
      if images.present?
        prompt += "\nPREFERRED IMAGES (use these URLs if they make sense; do NOT ignore them):\n"
        images.first(6).each_with_index do |img, idx|
          url = img[:url] || img["url"]
          title = img[:title] || img["title"]
          desc = img[:description] || img["description"]
          prompt += "- Image #{idx+1}: #{url} (#{title}) #{desc}\n"
        end
      end

      if image_preferences.present?
        prompt += "\nIMAGE PREFERENCES: #{image_preferences.to_json}\n"
      end

      prompt += <<~PROMPT

        REQUIREMENTS:
        1. Create a compelling hero section with the business name and key message
        2. Include a features section highlighting 3-4 key benefits/services
        3. Add a strong call-to-action section
        4. Include a contact form section with appropriate fields for the industry
        5. Use the specified theme consistently
        6. Write copy that resonates with the target audience
        7. If PREFERRED IMAGES are provided above, use them for hero/features instead of stock images.
           Only fall back to Unsplash if not enough preferred images are available.
        8. Use Bootstrap icons that match the business type

        INDUSTRY-SPECIFIC GUIDANCE:
      PROMPT

      case industry.downcase
      when "consulting"
        prompt += "- Focus on expertise, results, and trust-building\n- Use professional language and testimonials\n- Emphasize ROI and business outcomes\n"
      when "technology"
        prompt += "- Highlight innovation and cutting-edge solutions\n- Use modern, tech-savvy language\n- Focus on efficiency and scalability\n"
      when "healthcare"
        prompt += "- Emphasize care, trust, and expertise\n- Use reassuring, professional tone\n- Focus on patient outcomes and safety\n"
      when "finance"
        prompt += "- Build trust and credibility\n- Use conservative, professional language\n- Focus on security and results\n"
      when "retail"
        prompt += "- Highlight products and customer satisfaction\n- Use engaging, sales-focused copy\n- Include social proof and reviews\n"
      else
        prompt += "- Use professional, trustworthy language\n- Focus on value proposition and benefits\n- Include relevant social proof\n"
      end

      prompt += "\nGenerate the complete landing page DSL as valid JSON:"

      prompt
    end

    def fix_common_dsl_issues(dsl_content)
      # Common fixes for AI-generated DSL
      fixed_dsl = dsl_content.deep_dup

      # Ensure page wrapper exists
      unless fixed_dsl["page"]
        fixed_dsl = { "page" => fixed_dsl }
      end

      # Ensure theme is valid
      valid_themes = %w[clean modern bold professional creative]
      unless valid_themes.include?(fixed_dsl.dig("page", "theme"))
        fixed_dsl["page"]["theme"] = "professional"
      end

      # Ensure sections exist
      fixed_dsl["page"]["sections"] ||= []

      # Fix section types
      fixed_dsl["page"]["sections"].each do |section|
        # Ensure type is specified
        section["type"] ||= "hero" if section == fixed_dsl["page"]["sections"].first

        # Fix button actions
        if section["cta"] && section["cta"]["action"]
          valid_actions = %w[submit_form external_link scroll_to download]
          unless valid_actions.include?(section["cta"]["action"])
            section["cta"]["action"] = "submit_form"
          end
        end

        if section["button"] && section["button"]["action"]
          valid_actions = %w[submit_form external_link scroll_to download]
          unless valid_actions.include?(section["button"]["action"])
            section["button"]["action"] = "submit_form"
          end
        end
      end

      # Ensure at least one section exists
      if fixed_dsl["page"]["sections"].empty?
        fixed_dsl["page"]["sections"] = [
          {
            "type" => "hero",
            "headline" => "Welcome to Our Service",
            "subheadline" => "Professional services tailored to your needs"
          }
        ]
      end

      fixed_dsl
    end
  end
end
