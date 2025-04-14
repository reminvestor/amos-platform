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
    update_attrs = {
      title: new_landing_page.title,
      headline: new_landing_page.headline,
      subheadline: new_landing_page.subheadline,
      content: new_landing_page.content,
      primary_color: new_landing_page.primary_color,
      secondary_color: new_landing_page.secondary_color,
      font_family: new_landing_page.font_family,
      meta_description: new_landing_page.meta_description,
      meta_keywords: new_landing_page.meta_keywords,
      cta_text: new_landing_page.cta_text,
      cta_url: new_landing_page.cta_url,
      ai_settings: {
        generated_at: Time.current,
        generation_time: (Time.current - job_start_time).to_i,
        model: "multi-agent-system",
        topic: topic,
        job_id: job_id,
        original_plan: new_landing_page.ai_settings&.dig('original_plan')
      },
      image_prompts: new_landing_page.image_prompts
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
    
    # If image prompts were generated, trigger image generation
    if new_landing_page.image_prompts.present? && new_landing_page.image_prompts['hero_image'].present?
      log_with_context("Queuing image generation for hero image")
      log_with_context("Hero image prompt: #{new_landing_page.image_prompts['hero_image'].truncate(100)}")
      
      GenerateLandingPageImageJob.perform_later(
        landing_page.id,
        new_landing_page.image_prompts['hero_image'],
        'hero',
        job_id  # Pass the job_id for correlation
      )
      
      log_with_context("Hero image generation job enqueued")
      
      # Feature images
      if new_landing_page.image_prompts['feature_images'].present?
        log_with_context("Queuing image generation for #{new_landing_page.image_prompts['feature_images'].size} feature images")
        
        new_landing_page.image_prompts['feature_images'].each_with_index do |prompt, index|
          GenerateLandingPageImageJob.perform_later(
            landing_page.id,
            prompt,
            "feature_#{index}",
            job_id  # Pass the job_id for correlation
          )
          log_with_context("Feature image #{index} generation job enqueued")
        end
      end
    else
      log_with_context("No image prompts generated, skipping image generation")
    end
    
    job_duration = Time.current - job_start_time
    log_with_context("="*80)
    log_with_context("JOB COMPLETED SUCCESSFULLY in #{job_duration.round(2)} seconds")
    log_with_context("Generated landing page for topic: #{topic}")
    log_with_context("="*80)
  end
  
  private
  
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