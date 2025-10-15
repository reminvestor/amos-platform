module Tools
  class GenerateLandingPageTool < BaseTool
    def self.metadata
      {
        name: 'generate_ai_landing_page',
        description: 'Create sophisticated AI-powered landing pages',
        category: 'landing_page',
        input_schema: {
          type: 'object',
          properties: {
            title: {
              type: 'string',
              description: 'Title for the landing page (optional if program_name or business_name provided)'
            },
            description: {
              type: 'string',
              description: 'Description of what the landing page is for (optional if content_focus or key_details provided)'
            },
            program_name: {
              type: 'string',
              description: 'Name of the program/offering (can be used as title)'
            },
            business_name: {
              type: 'string',
              description: 'Business or company name'
            },
            content_focus: {
              type: 'string',
              description: 'What the content should focus on'
            },
            key_details: {
              type: 'object',
              description: 'Key details about the offering (pricing, target_audience, goals, etc.)'
            },
            design_style: {
              type: 'string',
              description: 'Design style and aesthetic preferences'
            },
            page_type: {
              type: 'string',
              enum: ['lead_generation', 'product_launch', 'event_registration', 
                     'newsletter_signup', 'free_trial', 'demo_request', 'general'],
              description: 'Type of landing page to create'
            },
            form_fields: {
              type: 'array',
              description: 'Custom form fields for lead capture'
            },
            business_info: {
              type: 'object',
              description: 'Business information (offer, price, value_proposition, etc.)'
            },
            design_preferences: {
              type: 'object',
              description: 'Design preferences (style, cta, hero_image, etc.)'
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
      
      page_type = get_arg(args, :page_type, 'lead_generation')
      
      Rails.logger.info "📄 Generating landing page: #{title}"
      Rails.logger.info "📝 Description: #{description[0..100]}..."
      
      begin
        # Extract all available context for rich page generation
        generation_context = {
          description: description,
          page_type: page_type,
          key_details: get_arg(args, :key_details) || {},
          business_info: get_arg(args, :business_info) || {},
          design_preferences: get_arg(args, :design_preferences) || {},
          design_style: get_arg(args, :design_style),
          form_fields: get_arg(args, :form_fields) || [],
          business_name: get_arg(args, :business_name),
          program_name: get_arg(args, :program_name),
          content_focus: get_arg(args, :content_focus)
        }
        
        # Create the landing page record (without page_type field)
        landing_page = LandingPage.create!(
          user: user,
          entity: entity,
          title: title,
          slug: generate_unique_slug(title),
          status: 'draft',
          metadata: {
            ai_generated: true,  # Store in metadata instead
            description: description,
            page_type: page_type,  # Store in metadata instead
            generated_at: Time.current,
            generation_context: generation_context,
            generated_from: 'workflow'
          }
        )
        
        # Use AI to generate professional HTML
        html_content = generate_ai_html(title, description, generation_context)
        
        landing_page.update!(html_content: html_content)
        
        Rails.logger.info "✅ Landing page created with HTML: #{landing_page.id}"
        
        success_response(
          id: landing_page.id,
          landing_page_id: landing_page.id,  # Include for workflow context
          title: landing_page.title,
          slug: landing_page.slug,
          status: 'draft',
          message: "Landing page created successfully!",
          preview_url: "/landing_pages/#{landing_page.slug}/preview",
          html_content: html_content,  # Include HTML for validation
          edit_url: "/landing_pages/#{landing_page.id}/edit",
          landing_page_url: "/landing_pages/#{landing_page.slug}/preview"
        )
      rescue => e
        Rails.logger.error "Landing page generation failed: #{e.message}"
        error_response("Failed to create landing page: #{e.message}")
      end
    end
    
    private
    
    def extract_description_from_details(args)
      # Try to build a description from key_details or business_info
      key_details = get_arg(args, :key_details)
      business_info = get_arg(args, :business_info)
      
      if key_details.is_a?(Hash)
        parts = []
        parts << key_details['main_goal'] || key_details[:main_goal] if key_details['main_goal'] || key_details[:main_goal]
        parts << "for #{key_details['target_audience'] || key_details[:target_audience]}" if key_details['target_audience'] || key_details[:target_audience]
        parts << "at #{key_details['pricing'] || key_details[:pricing]}" if key_details['pricing'] || key_details[:pricing]
        return parts.join(' ') if parts.any?
      end
      
      if business_info.is_a?(Hash)
        parts = []
        parts << business_info['offer'] || business_info[:offer] if business_info['offer'] || business_info[:offer]
        parts << business_info['value_proposition'] || business_info[:value_proposition] if business_info['value_proposition'] || business_info[:value_proposition]
        return parts.join(' - ') if parts.any?
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
                     key_details['company_name'] || 
                     title
                     
      value_prop = business_info[:value_proposition] || 
                  business_info['value_proposition'] ||
                  key_details[:value_proposition] ||
                  key_details['value_proposition'] ||
                  description
                  
      target_audience = business_info[:target_audience] ||
                       business_info['target_audience'] ||
                       key_details[:target_audience] ||
                       key_details['target_audience'] ||
                       "businesses"
                       
      cta_text = design_prefs[:cta] ||
                design_prefs['cta'] ||
                key_details[:call_to_action] ||
                key_details['call_to_action'] ||
                "Get Started"
                
      design_style = context[:design_style] || 
                    design_prefs[:style] ||
                    design_prefs['style'] ||
                    key_details[:design_style] ||
                    "modern and professional"
      
      Rails.logger.info "🎨 Generating HTML with: business=#{business_name}, value=#{value_prop}, audience=#{target_audience}, cta=#{cta_text}"
      
      prompt = <<~PROMPT
        Generate a complete, professional landing page HTML for:
        
        Company Name: #{business_name}
        Value Proposition: #{value_prop}
        Target Audience: #{target_audience} 
        Call to Action: #{cta_text}
        Design Style: #{design_style}
        
        Requirements:
        - Use Bootstrap 5 for responsive design
        - Include hero section with compelling headline and CTA
        - Add sections for features/benefits
        - Include signup/contact form
        - Mobile-responsive
        - Professional styling
        - Use the business information to create compelling copy
        
        CRITICAL: Use the EXACT values provided above:
        - Company name in logo/header: "#{business_name}" (NOT generic placeholders)
        - Hero headline should incorporate: "#{value_prop}"
        - CTA buttons should say: "#{cta_text}"
        - Content should speak to: "#{target_audience}"
        
        Return ONLY the complete HTML (from <!DOCTYPE html> to </html>).
        Make it conversion-optimized and visually appealing.
      PROMPT
      
      begin
        ai_service = BedrockService.new(user: user, entity: entity)
        
        messages = [
          { role: 'user', content: prompt }
        ]
        
        response = ai_service.complete(
          messages: messages,
          max_tokens: 8000,
          temperature: 0.7
        )
        
        # Strip markdown code blocks if AI wrapped the HTML
        cleaned_response = strip_markdown_wrapper(response)
        
        # Extract HTML from response
        if cleaned_response.include?('<!DOCTYPE html>')
          cleaned_response
        else
          # Fallback if AI didn't return HTML
          generate_fallback_html(title, description, business_name, value_prop, cta_text)
        end
      rescue => e
        Rails.logger.error "AI HTML generation failed: #{e.message}"
        generate_fallback_html(title, description, business_name, value_prop, cta_text)
      end
    end
    
    def strip_markdown_wrapper(html)
      # Remove markdown code block wrappers: ```html ... ``` or ``` ... ```
      cleaned = html.to_s.strip
      
      # Remove starting code block (case insensitive)
      cleaned = cleaned.sub(/\A```html\s*\n?/i, '')
      cleaned = cleaned.sub(/\A```\s*\n?/, '')
      
      # Remove ending code block
      cleaned = cleaned.sub(/\n?```\s*\z/, '')
      
      cleaned.strip
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
          
          <script src="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/js/bootstrap.bundle.min.js"></script>
        </body>
        </html>
      HTML
    end
  end
end
