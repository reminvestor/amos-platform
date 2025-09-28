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
              description: 'Title for the landing page'
            },
            description: {
              type: 'string',
              description: 'Description of what the landing page is for'
            },
            page_type: {
              type: 'string',
              enum: ['lead_generation', 'product_launch', 'event_registration', 
                     'newsletter_signup', 'free_trial', 'demo_request', 'general'],
              description: 'Type of landing page to create'
            }
          },
          required: ['title', 'description']
        }
      }
    end
    
    def execute(args)
      log_execution(args)
      
      title = get_arg(args, :title)
      description = get_arg(args, :description)
      page_type = get_arg(args, :page_type, 'lead_generation')
      
      # Validate required args
      if error = validate_required_args(args, [:title, :description])
        return error
      end
      
      begin
        # Create the landing page record
        landing_page = LandingPage.create!(
          user: user,
          entity: entity,
          title: title,
          internal_name: title,
          slug: generate_unique_slug(title),
          page_type: page_type,
          status: 'draft',
          ai_generated: true,
          metadata: {
            description: description,
            generated_at: Time.current
          }
        )
        
        # Create generation job with high priority
        job = SimpleAiLandingPageJob.set(priority: 10).perform_later(
          landing_page_id: landing_page.id,
          description: description,
          page_type: page_type,
          user_id: user.id
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
