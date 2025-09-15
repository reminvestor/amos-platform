class SimpleAiLandingPageJob < ApplicationJob
  queue_as :ai_generation
  
  # Retry the job if it fails, with exponential backoff
  retry_on Net::ReadTimeout, wait: :exponentially_longer, attempts: 3
  retry_on Aws::BedrockRuntime::Errors::ServiceError, wait: :exponentially_longer, attempts: 3

  def perform(landing_page_id, description, page_type, entity_id, business_profile_id = nil)
    landing_page = LandingPage.find(landing_page_id)
    entity = Entity.find(entity_id)
    business_profile = BusinessProfile.find_by(id: business_profile_id) if business_profile_id

    Rails.logger.info "SimpleAiLandingPageJob: Generating content for landing page #{landing_page_id}"
    Rails.logger.info "Description: #{description}"
    Rails.logger.info "Page type: #{page_type}"

    # Generate HTML content using Claude
    html_content = generate_landing_page_html(
      title: landing_page.title,
      description: description,
      page_type: page_type,
      business_profile: business_profile,
      entity: entity
    )

    # Update the landing page
    landing_page.update!(
      html_content: html_content,
      status: 'draft'
    )

    Rails.logger.info "SimpleAiLandingPageJob: Successfully generated content for landing page #{landing_page_id}"

  rescue => e
    Rails.logger.error "SimpleAiLandingPageJob failed for landing page #{landing_page_id}: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    
    # Store error message so user knows generation failed
    landing_page&.update(
      html_content: create_error_html(landing_page.title, e.message)
    )
    raise e
  end

  private

    def generate_landing_page_html(title:, description:, page_type:, business_profile:, entity:)
    # Extract any selected image hints and form selection embedded in the description
    selected_images = extract_selected_images_from_description(description)
    selected_form = extract_selected_form_from_description(description)
    sanitized_description = sanitize_description(description)
    
    # Analyze selected images to provide context to Claude
    image_descriptions = analyze_selected_images(selected_images)

    system_prompt = build_system_prompt
    user_prompt = build_user_prompt(
      title: title,
      description: sanitized_description,
      page_type: page_type,
      business_profile: business_profile,
      entity: entity,
      selected_images: selected_images,
      selected_form: selected_form,
      image_descriptions: image_descriptions
    )

    Rails.logger.info "Sending request to Claude for HTML generation"
    
    # Use configured AI service to generate complete HTML
    ai_service = AiServiceHelper.get_service
    # Use Claude Opus 4.1 specifically for landing page generation
    response = ai_service.send_message(system_prompt, user_prompt, model: 'claude-opus-4-1-20250805', max_tokens: 6000, temperature: 0.6)
    
    if response.blank?
      raise "Claude API returned empty response"
    end
    
    # Extract and clean HTML from response
    html_content = extract_html_from_response(response)
    
    if html_content.blank? || html_content.length < 100
      raise "Generated HTML content is too short or empty"
    end
    
    Rails.logger.info "Generated #{html_content.length} characters of HTML content"
    
    # If we have selected images from the wizard, apply them to the HTML deterministically
    html_with_images = apply_selected_images_to_html(html_content, selected_images)
    # If URLs are missing after model output, also replace common placeholder patterns
    html_with_images = replace_placeholder_images(html_with_images, selected_images)
    html_with_images
  end

  def build_system_prompt
    <<~PROMPT
      You are an expert web developer and landing page designer who creates professional, high-converting HTML landing pages.

      IMPORTANT REQUIREMENTS:
      1. Generate COMPLETE, self-contained HTML (including DOCTYPE, head, body)
      2. Use Bootstrap 5 for responsive design 
      3. Include professional styling and modern design
      4. Always include a contact form that submits to /api/v1/contacts
      5. Make it mobile-responsive and visually appealing
      6. Use proper semantic HTML
      7. Include compelling copy based on the business context

      FORM REQUIREMENTS:
      - Form action: "/api/v1/contacts"
      - Form method: "POST"
      - Required fields: email, first_name, last_name
      - Optional fields: phone, company, message
      - All form inputs must have proper name attributes matching the API

      DESIGN GUIDELINES:
      - Professional color scheme
      - Clear hierarchy and typography
      - Strategic use of white space
      - Call-to-action buttons that stand out
      - Social proof elements when appropriate
      - Fast loading (no heavy external dependencies beyond Bootstrap)

      Generate only the HTML code, no explanations or markdown formatting.
    PROMPT
  end

  def build_user_prompt(title:, description:, page_type:, business_profile:, entity:, selected_images: {}, selected_form: nil, image_descriptions: {})
    business_context = ""
    if business_profile
      business_context = <<~CONTEXT
        BUSINESS CONTEXT:
        - Company: #{business_profile.name}
        - Industry: #{business_profile.industry}
        - Description: #{business_profile.description}
        - Target Audience: #{business_profile.target_audience}
        - Brand Voice: #{business_profile.tone_of_voice}
      CONTEXT
    end

    page_type_guidance = get_page_type_guidance(page_type)

    images_section = ""
    if selected_images.present?
      # Build detailed image instructions with descriptions
      hero_desc = image_descriptions[:hero] || "Hero/banner image"
      feat1_desc = image_descriptions[:feature1] || "Feature image 1"
      feat2_desc = image_descriptions[:feature2] || "Feature image 2"
      
      images_section = <<~IMAGES
        MANDATORY IMAGES (YOU MUST USE THESE EXACT URLS - NO PLACEHOLDERS):
        
        1. HERO IMAGE:
           URL: #{selected_images[:hero]}
           Description: #{hero_desc}
           REQUIREMENTS: 
           - Use as the main hero/banner background (style="background-image:url(#{selected_images[:hero]})")
           - Also include as <img> tag for accessibility
           - Position prominently at the top of the page
        
        2. FEATURE IMAGE 1:
           URL: #{selected_images[:feature1]}
           Description: #{feat1_desc}
           REQUIREMENTS: Use in the first feature/benefit section
        
        3. FEATURE IMAGE 2:
           URL: #{selected_images[:feature2]}
           Description: #{feat2_desc}
           REQUIREMENTS: Use in the second feature/benefit section

        CRITICAL: 
        - You MUST use these exact URLs. Do NOT use any placeholder images.
        - These images have been specifically selected by the user.
        - Create alt text based on the descriptions provided above.
      IMAGES
    else
      images_section = <<~IMAGES
        NO IMAGES PROVIDED:
        Since no specific images were selected, you may use appropriate placeholder images (e.g., https://placehold.co/1200x600).
      IMAGES
    end
    form_section = ""
    if selected_form.present? && selected_form != 'none'
      if LandingPageFormTemplatesService.template_exists?(selected_form)
        template_html = LandingPageFormTemplatesService.get_template(selected_form)
        form_section = <<~FORM
          SELECTED FORM TEMPLATE: #{selected_form}
          CRITICAL: Use this exact form HTML somewhere appropriate on the page:
          ---FORM_START---
          #{template_html}
          ---FORM_END---
        FORM
      else
        form_section = "FORM TYPE REQUESTED: #{selected_form}. Use an appropriate form for this type."
      end
    elsif selected_form == 'none'
      form_section = "CRITICAL: Do NOT include any contact forms on this page."
    end

    <<~PROMPT
      Create a professional landing page with the following specifications:

      TITLE: #{title}
      DESCRIPTION: #{description}
      PAGE TYPE: #{page_type}

      #{business_context}

      #{page_type_guidance}

      #{images_section}
      #{form_section}

      SPECIFIC REQUIREMENTS:
      1. Create compelling headline and subheadline
      2. Include 3-4 benefit/feature sections
      3. Add testimonial or social proof section
      4. Include prominent call-to-action
      5. Add contact form in a visually appealing section
      6. If selected image URLs are provided, use them directly. Otherwise, use professional placeholders with proper alt text
      7. Ensure mobile responsiveness
      8. Include proper meta tags in head

      Generate the complete HTML code now:
    PROMPT
  end

  def get_page_type_guidance(page_type)
    case page_type
    when 'lead_generation'
      "Focus on capturing leads with a prominent form and clear value proposition. Emphasize benefits and urgency."
    when 'product_launch'
      "Highlight the new product features, benefits, and launch details. Include social proof and early bird offers."
    when 'event_registration'
      "Emphasize event details, speakers, agenda, and registration deadline. Include social proof from past events."
    when 'newsletter_signup'
      "Focus on the value of the newsletter content. Highlight what subscribers will receive and how often."
    when 'free_trial'
      "Emphasize the trial benefits, ease of getting started, and what happens after the trial. Remove friction from signup."
    when 'demo_request'
      "Focus on the value of the demo, what prospects will learn, and how it will solve their problems."
    else
      "Create a general purpose landing page that effectively communicates value and drives conversions."
    end
  end

  def extract_html_from_response(response)
    # Claude might wrap HTML in markdown code blocks or include explanations
    # Extract just the HTML content
    
    if response.include?('```html')
      # Extract from markdown code block
      html_match = response.match(/```html\s*(.*?)\s*```/m)
      return html_match[1] if html_match
    elsif response.include?('```')
      # Extract from generic code block
      html_match = response.match(/```\s*(.*?)\s*```/m)
      return html_match[1] if html_match
    end
    
    # If no code blocks, look for DOCTYPE or html tag
    if response.include?('<!DOCTYPE') || response.include?('<html')
      # Find the start and end of HTML content
      start_pos = [response.index('<!DOCTYPE'), response.index('<html')].compact.min
      if start_pos
        end_pos = response.rindex('</html>')
        if end_pos
          return response[start_pos..(end_pos + 6)] # +6 for '</html>'
        end
      end
    end
    
    # Fallback: return the whole response and hope for the best
    response
  end

  # --- Helper methods for images ---
  def extract_selected_images_from_description(description)
    h = {}
    text = description.to_s
    # Look for explicit JSON block after SELECTED_IMAGES_JSON:
    if (m = text.match(/SELECTED_IMAGES_JSON\s*:\s*(\{.*?\})/m))
      begin
        json = JSON.parse(m[1])
        h[:hero] = json['hero'] if json['hero'].present?
        h[:feature1] = json['feature1'] if json['feature1'].present?
        h[:feature2] = json['feature2'] if json['feature2'].present?
      rescue JSON::ParserError
        # ignore
      end
    end
    # Also parse simple hints like "Use this hero image URL: http..."
    if (m = text.match(/hero image url\s*:\s*(https?:[^\s]+)/i))
      h[:hero] ||= m[1]
    end
    if (m = text.match(/feature image url\s*1\s*:\s*(https?:[^\s]+)/i))
      h[:feature1] ||= m[1]
    end
    if (m = text.match(/feature image url\s*2\s*:\s*(https?:[^\s]+)/i))
      h[:feature2] ||= m[1]
    end
    h.compact
  end

  def sanitize_description(description)
    return '' if description.blank?
    # Remove embedded JSON hints so the model isn't distracted
    description.gsub(/SELECTED_IMAGES_JSON\s*:\s*\{.*?\}/m, '').strip
  end

  def apply_selected_images_to_html(html, images)
    return html if images.blank?
    updated = html.dup
    hero = images[:hero]
    f1 = images[:feature1]
    f2 = images[:feature2]

    if hero || f1 || f2
      img_index = 0
      updated = updated.gsub(/<img[^>]*>/) do |img|
        img_index += 1
        url = case img_index
              when 1 then hero
              when 2 then f1
              when 3 then f2
              else nil
              end
        if url
          if img =~ /src=["'][^"']*["']/
            img.gsub(/src=["'][^"']*["']/, "src=\"#{url}\"")
          else
            img.sub('<img', "<img src=\"#{url}\"")
          end
        else
          img
        end
      end
    end

    updated
  end

  # Replace standard placeholder URLs (placehold.co, 1200x600 etc.) with selected images when appropriate
  def replace_placeholder_images(html, images)
    return html if images.blank? || html.blank?
    updated = html.dup
    hero = images[:hero]
    f1 = images[:feature1]
    f2 = images[:feature2]

    # Common placeholder patterns
    placeholders = [
      %r{https?://placehold\.co/\d+x\d+[^"']*}i,
      %r{https?://via\.placeholder\.com/\d+x\d+[^"']*}i
    ]
    replacements = [hero, f1, f2].compact
    idx = 0
    placeholders.each do |pattern|
      updated = updated.gsub(pattern) do |_|
        url = replacements[idx]
        idx += 1
        url || _
      end
    end
    updated
  end

  def extract_selected_form_from_description(description)
    text = description.to_s
    # Look for explicit line like SELECTED_FORM: <key>
    if (m = text.match(/SELECTED_FORM\s*:\s*([a-z_]+)/i))
      return m[1].downcase
    end
    nil
  end

  def analyze_selected_images(images)
    return {} if images.blank?
    
    descriptions = {}
    ai_service = AiServiceHelper.get_service
    
    if images[:hero].present?
      begin
        descriptions[:hero] = ai_service.analyze_image(images[:hero], "Hero/banner image for a landing page")
        Rails.logger.info "Analyzed hero image: #{descriptions[:hero]}"
      rescue => e
        Rails.logger.error "Failed to analyze hero image: #{e.message}"
        descriptions[:hero] = "Hero/banner image"
      end
    end
    
    if images[:feature1].present?
      begin
        descriptions[:feature1] = ai_service.analyze_image(images[:feature1], "Feature section image for a landing page")
        Rails.logger.info "Analyzed feature1 image: #{descriptions[:feature1]}"
      rescue => e
        Rails.logger.error "Failed to analyze feature1 image: #{e.message}"
        descriptions[:feature1] = "Feature image"
      end
    end
    
    if images[:feature2].present?
      begin
        descriptions[:feature2] = ai_service.analyze_image(images[:feature2], "Secondary feature image for a landing page")
        Rails.logger.info "Analyzed feature2 image: #{descriptions[:feature2]}"
      rescue => e
        Rails.logger.error "Failed to analyze feature2 image: #{e.message}"
        descriptions[:feature2] = "Secondary feature image"
      end
    end
    
    descriptions
  end

  def create_error_html(title, error_message)
    <<~HTML
      <!DOCTYPE html>
      <html lang="en">
      <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>#{title}</title>
        <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/css/bootstrap.min.css" rel="stylesheet">
      </head>
      <body>
        <div class="container mt-5">
          <div class="row justify-content-center">
            <div class="col-md-8">
              <div class="alert alert-warning text-center">
                <h4>Content Generation In Progress</h4>
                <p>We're working on generating your landing page content. Please refresh the page in a few moments.</p>
                <p class="small text-muted">If this message persists, please contact support.</p>
              </div>
            </div>
          </div>
        </div>
      </body>
      </html>
    HTML
  end
end 