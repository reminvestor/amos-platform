class GenerateFullLandingPageJob < ApplicationJob
  queue_as :default

  def perform(landing_page_id, description, clarification_answers, entity_id, business_profile_id = nil)
    landing_page = LandingPage.find(landing_page_id)
    entity = Entity.find(entity_id)
    business_profile = business_profile_id ? BusinessProfile.find(business_profile_id) : nil
    
    # Build context for AI
    context = {
      description: description,
      clarification_answers: clarification_answers,
      business_profile: business_profile,
      entity: entity,
      landing_page: landing_page
    }
    
    # Generate full landing page HTML using AI
    html_content = generate_landing_page_html(context)
    
    # Store the HTML content
    landing_page.update!(
      html_content: html_content,
      status: 'draft'
    )
    
    Rails.logger.info "Generated full landing page HTML for landing page #{landing_page_id}"
    
  rescue => e
    Rails.logger.error "Error generating full landing page for landing page #{landing_page_id}: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    
    # Store error message in html_content so user knows generation failed
    landing_page&.update(html_content: "<div class='alert alert-danger'>Error generating landing page. Please try again.</div>")
  end
  
  private
  
  def generate_landing_page_html(context)
    system_prompt = "You are an expert web developer and landing page designer who creates professional, responsive HTML landing pages."
    user_prompt = build_landing_page_prompt(context)
    
    # Use Claude to generate HTML
    response = ClaudeService.new.send_message(system_prompt, user_prompt)
    
    # Extract HTML from response
    extract_html_from_response(response)
  end
  
  def build_landing_page_prompt(context)
    business_context = ""
    if context[:business_profile]
      bp = context[:business_profile]
      business_context = "
Business Context:
- Company: #{bp.name}
- Industry: #{bp.industry}
- Description: #{bp.description}
- Target Audience: #{bp.target_audience}
- Brand Voice: #{bp.tone_of_voice}
"
    end
    
    answers_context = ""
    if context[:clarification_answers].present?
      answers_context = "
Clarification Answers:
#{context[:clarification_answers].map { |k, v| "- #{k}: #{v}" }.join("\n")}
"
    end
    
    "You are an expert web developer and landing page designer. Create a complete, professional landing page based on this information:

Original Description:
\"#{context[:description]}\"

#{business_context}
#{answers_context}

Create a complete HTML landing page that includes:
1. Modern, responsive design using Bootstrap 5
2. Professional styling with CSS
3. Clear headline and subheadline
4. Value proposition section
5. Call-to-action button(s)
6. Contact form or lead capture
7. Any additional sections based on the requirements

Requirements:
- Use Bootstrap 5 classes for styling
- Include custom CSS for professional appearance
- Make it mobile-responsive
- Use appropriate colors and typography
- Include placeholder images (use https://via.placeholder.com/ for images)
- Make sure all forms have proper validation
- Include Font Awesome icons where appropriate

Return ONLY the complete HTML code, starting with <!DOCTYPE html> and ending with </html>. Do not include any explanatory text before or after the HTML.

The HTML should be production-ready and can be displayed directly in a browser."
  end
  
  def extract_html_from_response(response)
    # Remove any markdown code blocks if present
    html = response.gsub(/```html\n?/, '').gsub(/```\n?/, '')
    
    # Ensure we start with DOCTYPE if not present
    unless html.strip.start_with?('<!DOCTYPE')
      html = "<!DOCTYPE html>\n" + html
    end
    
    html.strip
  end
end 