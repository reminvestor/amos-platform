class SimpleAiLandingPageJob < ApplicationJob
  queue_as :ai_generation

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
    system_prompt = build_system_prompt
    user_prompt = build_user_prompt(
      title: title,
      description: description, 
      page_type: page_type,
      business_profile: business_profile,
      entity: entity
    )

    Rails.logger.info "Sending request to Claude for HTML generation"
    
    # Use Claude to generate complete HTML
    claude_service = ClaudeService.new
    response = claude_service.send_message(system_prompt, user_prompt)
    
    if response.blank?
      raise "Claude API returned empty response"
    end
    
    # Extract and clean HTML from response
    html_content = extract_html_from_response(response)
    
    if html_content.blank? || html_content.length < 100
      raise "Generated HTML content is too short or empty"
    end
    
    Rails.logger.info "Generated #{html_content.length} characters of HTML content"
    
    html_content
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

  def build_user_prompt(title:, description:, page_type:, business_profile:, entity:)
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

    <<~PROMPT
      Create a professional landing page with the following specifications:

      TITLE: #{title}
      DESCRIPTION: #{description}
      PAGE TYPE: #{page_type}

      #{business_context}

      #{page_type_guidance}

      SPECIFIC REQUIREMENTS:
      1. Create compelling headline and subheadline
      2. Include 3-4 benefit/feature sections
      3. Add testimonial or social proof section
      4. Include prominent call-to-action
      5. Add contact form in a visually appealing section
      6. Use professional imagery placeholders with proper alt text
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