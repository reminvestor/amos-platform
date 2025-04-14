class GenerateLandingPageImageJob < ApplicationJob
  include JobErrorHandling
  
  queue_as :ai_generation
  
  def perform(landing_page_id, image_description, section = 'hero', correlation_id = nil)
    log_with_context("Starting image generation job for landing page #{landing_page_id}, section: #{section}")
    log_with_context("Image description: #{image_description.truncate(100)}")
    
    landing_page = LandingPage.find_by(id: landing_page_id)
    
    if landing_page.nil?
      raise ArgumentError, "Landing page with ID #{landing_page_id} not found"
    end
    
    # Optimize the prompt for DALL-E
    log_with_context("Optimizing prompt for DALL-E")
    optimized_prompt = optimize_prompt_for_dalle(image_description)
    log_with_context("Optimized prompt generated (#{optimized_prompt.size} chars)")
    
    # Call DALL-E API to generate image
    log_with_context("Calling DALL-E API to generate image")
    image_url = generate_dalle_image(optimized_prompt)
    
    if image_url.blank?
      raise StandardError, "Failed to generate image from DALL-E API"
    end
    
    log_with_context("Successfully generated image URL: #{image_url.truncate(50)}")
    
    # Update landing page with the generated image URL
    log_with_context("Updating landing page with generated image")
    
    # Store the image in the appropriate field
    case section
    when 'hero'
      landing_page.update(image_url: image_url)
      log_with_context("Updated hero image URL")
    else
      # Store in content JSON for other sections
      content = landing_page.content || []
      content_section = content.find { |s| s['type'] == section }
      
      if content_section
        content_section['image_url'] = image_url
      else
        content << { 'type' => section, 'image_url' => image_url }
      end
      
      landing_page.update(content: content)
      log_with_context("Updated image URL in content section: #{section}")
    end
    
    # Store prompt in image_prompts JSON
    image_prompts = landing_page.image_prompts || {}
    image_prompts[section] = {
      original: image_description,
      optimized: optimized_prompt,
      generated_at: Time.current.to_s
    }
    
    if landing_page.update(image_prompts: image_prompts)
      log_with_context("Successfully updated landing page with image prompts")
    else
      error_message = landing_page.errors.full_messages.join(', ')
      log_with_context("Failed to update landing page image prompts: #{error_message}", :error)
      raise ActiveRecord::RecordInvalid, "Failed to update landing page image prompts: #{error_message}"
    end
    
    log_with_context("Image generation job completed successfully")
  end
  
  private
  
  # Helper method to handle logging with or without tagging
  def log_with_context(message, level = :info)
    job_context = "ImageGenJob LP##{arguments.first} #{arguments[2]}"
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
  
  def optimize_prompt_for_dalle(original_prompt)
    # First use GPT-4o to optimize the prompt for DALL-E
    prompt = <<~PROMPT
      I need to generate an image using DALL-E 3 for a marketing landing page.
      
      Original description: #{original_prompt}
      
      Please rewrite this description to create an optimal prompt for DALL-E 3 that will generate a high-quality, 
      professional marketing image. Follow these guidelines:
      
      1. Be specific about style (e.g., photorealistic, 3D render, flat illustration)
      2. Include details about lighting, composition, and perspective
      3. Specify the mood and atmosphere
      4. Keep it under 150 words
      5. Make it suitable for a professional marketing context
      6. Avoid mentioning text/words in the image as DALL-E struggles with text
      7. Focus on creating a visually compelling image that would work well as a hero banner
      
      Return only the optimized prompt, without any explanations or quotes.
    PROMPT
    
    response = call_openai_api(prompt)
    
    if response && response["choices"] && response["choices"].first
      optimized = response["choices"].first["message"]["content"].strip
      return optimized
    end
    
    # If optimization fails, use original prompt with some enhancements
    "Professional marketing landing page image: #{original_prompt}. High quality, modern design, well-lit, suitable for website hero section."
  end
  
  def generate_dalle_image(prompt)
    require 'net/http'
    require 'uri'
    require 'json'
    
    uri = URI.parse("https://api.openai.com/v1/images/generations")
    request = Net::HTTP::Post.new(uri)
    request.content_type = "application/json"
    request["Authorization"] = "Bearer #{ENV['OPENAI_API_KEY']}"
    
    request.body = JSON.dump({
      "model" => "dall-e-3",
      "prompt" => prompt,
      "n" => 1,
      "size" => "1024x1024",
      "quality" => "standard",
      "style" => "natural"
    })
    
    req_options = {
      use_ssl: uri.scheme == "https"
    }
    
    response = Net::HTTP.start(uri.hostname, uri.port, req_options) do |http|
      http.request(request)
    end
    
    if response.code == "200"
      result = JSON.parse(response.body)
      if result["data"] && result["data"].first && result["data"].first["url"]
        return result["data"].first["url"]
      end
    end
    
    log_with_context("Error generating DALL-E image: #{response.body}", :error)
    nil
  end
  
  def call_openai_api(prompt)
    require 'net/http'
    require 'uri'
    require 'json'
    
    uri = URI.parse("https://api.openai.com/v1/chat/completions")
    request = Net::HTTP::Post.new(uri)
    request.content_type = "application/json"
    request["Authorization"] = "Bearer #{ENV['OPENAI_API_KEY']}"
    
    request.body = JSON.dump({
      "model" => "gpt-4o",
      "messages" => [
        {
          "role" => "system", 
          "content" => "You are an expert at creating optimal prompts for DALL-E image generation. Your responses should only contain the optimized prompt, with no additional explanation."
        },
        {
          "role" => "user",
          "content" => prompt
        }
      ]
    })
    
    req_options = {
      use_ssl: uri.scheme == "https"
    }
    
    response = Net::HTTP.start(uri.hostname, uri.port, req_options) do |http|
      http.request(request)
    end
    
    return nil unless response.code == "200"
    JSON.parse(response.body)
  rescue => e
    log_with_context("Error calling OpenAI API: #{e.message}", :error)
    nil
  end
end 