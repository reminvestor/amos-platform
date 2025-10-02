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
          ai_generated: true,
          metadata: {
            description: description,
            page_type: page_type,  # Store in metadata instead
            generated_at: Time.current,
            generation_context: generation_context,
            generated_from: 'workflow'
          }
        )
        
        # Create generation job with high priority and full context
        job = SimpleAiLandingPageJob.set(priority: 10).perform_later(
          landing_page_id: landing_page.id,
          description: description,
          page_type: page_type,
          user_id: user.id,
          generation_context: generation_context
        )
        
        Rails.logger.info "🚀 Queued AI landing page generation job: #{job.job_id}"
        
        success_response(
          id: landing_page.id,
          title: landing_page.title,
          slug: landing_page.slug,
          status: 'generating',
          job_id: job.job_id,
          message: "AI is creating your landing page. This usually takes 20-30 seconds.",
          preview_url: "/landing_pages/#{landing_page.slug}/preview"
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
  end
end
