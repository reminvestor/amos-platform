class AgentGenerateLandingPageJob < ApplicationJob
  include JobErrorHandling
  
  queue_as :ai_generation
  
  def perform(landing_page_id, topic, entity_id, business_profile_id = nil, page_type = 'lead_generation')
    job_start_time = Time.current
    job_id = "lp-#{landing_page_id}-#{SecureRandom.hex(4)}"
    
    # Use tagged logging if available, otherwise just log with prefixes
    log_with_context("="*80)
    log_with_context("JOB STARTED at #{job_start_time}")
    log_with_context("Job ID: #{job_id}")
    log_with_context("Parameters:")
    log_with_context("  - landing_page_id: #{landing_page_id}")
    log_with_context("  - topic: #{topic}")
    log_with_context("  - entity_id: #{entity_id}")
    log_with_context("  - business_profile_id: #{business_profile_id}")
    log_with_context("  - page_type: #{page_type}")
    log_with_context("="*80)
    
    # Find the models
    landing_page = LandingPage.find_by(id: landing_page_id)
    entity = Entity.find_by(id: entity_id)
    business_profile = BusinessProfile.find_by(id: business_profile_id) if business_profile_id
    
    # Log model lookup results
    if landing_page.nil?
      raise ArgumentError, "Landing page with ID #{landing_page_id} not found"
    end
    
    if entity.nil?
      raise ArgumentError, "Entity with ID #{entity_id} not found"
    end
    
    if business_profile_id.present? && business_profile.nil?
      log_with_context("Business profile with ID #{business_profile_id} not found, proceeding without it", :warn)
    end
    
    log_with_context("Found landing page: #{landing_page.title} (ID: #{landing_page.id})")
    log_with_context("Found entity: #{entity.name} (ID: #{entity.id})")
    if business_profile
      log_with_context("Found business profile: #{business_profile.name} (ID: #{business_profile.id})")
    end
    
    log_with_context("Starting landing page generation for topic: #{topic}")
    
    # Create the orchestrator with job_id for correlation
    log_with_context("Creating orchestrator instance")
    orchestrator = AiAgents::Orchestrator.new({ job_id: job_id })
    
    # Generate the landing page
    log_with_context("Delegating to orchestrator.generate_landing_page")
    new_landing_page = orchestrator.generate_landing_page(topic, entity, business_profile, page_type)
    
    # Log orchestrator results in detail
    log_with_context("Orchestrator completed landing page generation")
    log_with_context("Orchestrator result details:")
    log_with_context("  - Title: #{new_landing_page.title}")
    log_with_context("  - Headline: #{new_landing_page.headline || 'None'}")
    log_with_context("  - Content sections: #{new_landing_page.content&.size || 0}")
    
    # Log each content section in detail
    if new_landing_page.content.present? && new_landing_page.content.is_a?(Array)
      new_landing_page.content.each_with_index do |section, i|
        log_with_context("Content section #{i+1} - #{section['title']} (#{section['type']})")
        log_with_context("Content section #{i+1} sample: #{section['content'].to_s.truncate(100)}")
      end
    else
      log_with_context("No content sections found or content is not an array", :warn)
      log_with_context("Content value: #{new_landing_page.content.inspect}", :warn)
    end
    
    # Update the existing landing page with the generated content
    log_with_context("Preparing to update existing landing page with generated content")
    
    # Generate complete HTML content from the orchestrator's output
    html_content = generate_html_from_orchestrator_output(new_landing_page)
    
    update_attrs = {
      title: new_landing_page.title,
      description: new_landing_page.description || landing_page.description,
      html_content: html_content,
      status: 'draft'  # Keep as draft until user reviews
    }
    
    # Log all update attributes for debugging
    log_with_context("DB update attributes prepared:")
    update_attrs.each do |key, value|
      if key == :content && value.is_a?(Array)
        log_with_context("  - content: Array with #{value.size} sections")
      elsif value.is_a?(Hash)
        log_with_context("  - #{key}: Hash with keys #{value.keys.join(', ')}")
      else
        truncated_value = value.to_s.truncate(100)
        log_with_context("  - #{key}: #{truncated_value}")
      end
    end
    
    # Log the actual SQL operation
    log_with_context("Performing database update operation")
    before_update = Time.current
    
    if landing_page.update(update_attrs)
      log_with_context("Successfully updated landing page (took #{(Time.current - before_update).round(2)}s)")
      log_with_context("Landing page updated with #{landing_page.content&.size || 0} content sections")
      
      # Verify the saved data
      reloaded_page = LandingPage.find(landing_page.id)
      log_with_context("Verified saved data - title: #{reloaded_page.title}")
      log_with_context("Verified saved data - sections: #{reloaded_page.content&.size || 0}")
    else
      error_message = landing_page.errors.full_messages.join(', ')
      log_with_context("Failed to update landing page: #{error_message}", :error)
      log_with_context("Database validation errors: #{landing_page.errors.messages}", :error)
      raise ActiveRecord::RecordInvalid, "Failed to update landing page: #{error_message}"
    end
    
    # Note: Image generation is skipped for now since we're using complete HTML content
    log_with_context("Landing page generation completed - images can be edited directly in HTML")
    
    job_duration = Time.current - job_start_time
    log_with_context("="*80)
    log_with_context("JOB COMPLETED SUCCESSFULLY in #{job_duration.round(2)} seconds")
    log_with_context("Generated landing page for topic: #{topic}")
    log_with_context("="*80)
  end
  
  private

  def generate_html_from_orchestrator_output(generated_page)
    # The orchestrator might return different formats, let's handle them
    if generated_page.respond_to?(:html_content) && generated_page.html_content.present?
      # If orchestrator already generated complete HTML
      return generated_page.html_content
    elsif generated_page.respond_to?(:content) && generated_page.content.present?
      # If we have structured content sections, convert to HTML
      return convert_sections_to_html(generated_page)
    else
      # Fallback: create a basic template
      return create_basic_html_template(generated_page)
    end
  end

  def convert_sections_to_html(generated_page)
    headline = generated_page.respond_to?(:headline) ? generated_page.headline : generated_page.title
    subheadline = generated_page.respond_to?(:subheadline) ? generated_page.subheadline : ""
    sections = generated_page.respond_to?(:content) ? generated_page.content : []
    
    html = <<~HTML
      <!DOCTYPE html>
      <html lang="en">
      <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>#{generated_page.title}</title>
        <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/css/bootstrap.min.css" rel="stylesheet">
        <style>
          .hero-section { background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); color: white; padding: 80px 0; }
          .feature-section { padding: 60px 0; }
          .cta-section { background: #f8f9fa; padding: 60px 0; }
        </style>
      </head>
      <body>
        <!-- Hero Section -->
        <section class="hero-section">
          <div class="container">
            <div class="row justify-content-center text-center">
              <div class="col-lg-8">
                <h1 class="display-4 fw-bold mb-4">#{headline}</h1>
                #{subheadline.present? ? "<p class='lead mb-4'>#{subheadline}</p>" : ""}
                <a href="#contact" class="btn btn-light btn-lg">Get Started</a>
              </div>
            </div>
          </div>
        </section>

    HTML

    # Add sections if they exist
    if sections.is_a?(Array) && sections.any?
      sections.each_with_index do |section, index|
        section_class = index % 2 == 0 ? "bg-white" : "bg-light"
        html += <<~HTML
          <section class="feature-section #{section_class}">
            <div class="container">
              <div class="row">
                <div class="col-lg-8 mx-auto text-center">
                  <h2 class="h3 mb-4">#{section['title'] || "Section #{index + 1}"}</h2>
                  <p>#{section['content'] || section['description'] || ""}</p>
                </div>
              </div>
            </div>
          </section>
        HTML
      end
    end

    # Add contact form
    html += <<~HTML
        <!-- Contact Section -->
        <section id="contact" class="cta-section">
          <div class="container">
            <div class="row justify-content-center">
              <div class="col-lg-6">
                <div class="card">
                  <div class="card-body">
                    <h3 class="card-title text-center mb-4">Get Started Today</h3>
                    <form action="/api/v1/contacts" method="POST">
                      <div class="mb-3">
                        <label for="first_name" class="form-label">First Name</label>
                        <input type="text" class="form-control" id="first_name" name="first_name" required>
                      </div>
                      <div class="mb-3">
                        <label for="last_name" class="form-label">Last Name</label>
                        <input type="text" class="form-control" id="last_name" name="last_name" required>
                      </div>
                      <div class="mb-3">
                        <label for="email" class="form-label">Email Address</label>
                        <input type="email" class="form-control" id="email" name="email" required>
                      </div>
                      <button type="submit" class="btn btn-primary w-100">Submit</button>
                    </form>
                  </div>
                </div>
              </div>
            </div>
          </div>
        </section>

        <script src="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/js/bootstrap.bundle.min.js"></script>
      </body>
      </html>
    HTML

    html
  end

  def create_basic_html_template(generated_page)
    title = generated_page.respond_to?(:title) ? generated_page.title : "Landing Page"
    
    <<~HTML
      <!DOCTYPE html>
      <html lang="en">
      <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>#{title}</title>
        <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/css/bootstrap.min.css" rel="stylesheet">
        <style>
          .hero-section { background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); color: white; padding: 80px 0; }
          .cta-section { background: #f8f9fa; padding: 60px 0; }
        </style>
      </head>
      <body>
        <!-- Hero Section -->
        <section class="hero-section">
          <div class="container">
            <div class="row justify-content-center text-center">
              <div class="col-lg-8">
                <h1 class="display-4 fw-bold mb-4">#{title}</h1>
                <p class="lead mb-4">AI-generated landing page content will appear here.</p>
                <a href="#contact" class="btn btn-light btn-lg">Get Started</a>
              </div>
            </div>
          </div>
        </section>

        <!-- Contact Section -->
        <section id="contact" class="cta-section">
          <div class="container">
            <div class="row justify-content-center">
              <div class="col-lg-6">
                <div class="card">
                  <div class="card-body">
                    <h3 class="card-title text-center mb-4">Contact Us</h3>
                    <form action="/api/v1/contacts" method="POST">
                      <div class="mb-3">
                        <label for="first_name" class="form-label">First Name</label>
                        <input type="text" class="form-control" id="first_name" name="first_name" required>
                      </div>
                      <div class="mb-3">
                        <label for="last_name" class="form-label">Last Name</label>
                        <input type="text" class="form-control" id="last_name" name="last_name" required>
                      </div>
                      <div class="mb-3">
                        <label for="email" class="form-label">Email Address</label>
                        <input type="email" class="form-control" id="email" name="email" required>
                      </div>
                      <button type="submit" class="btn btn-primary w-100">Submit</button>
                    </form>
                  </div>
                </div>
              </div>
            </div>
          </div>
        </section>

        <script src="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/js/bootstrap.bundle.min.js"></script>
      </body>
      </html>
    HTML
  end
  
  # Helper method to handle logging with or without tagging
  def log_with_context(message, level = :info)
    job_context = "AgentJob LP##{arguments.first}"
    formatted_message = "[#{job_context}] #{message}"
    
    case level
    when :error
      Rails.logger.error(formatted_message)
    when :warn
      Rails.logger.warn(formatted_message)
    else
      Rails.logger.info(formatted_message)
    end
  end
end 