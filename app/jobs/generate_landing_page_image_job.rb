require 'down'
require 'open-uri'

class GenerateLandingPageImageJob < ApplicationJob
  include JobErrorHandling
  
  queue_as :default
  
  def perform(landing_page_id, description, section_key, correlation_id = nil)
    @correlation_id = correlation_id || SecureRandom.uuid
    log_with_context("Starting image generation job for landing page #{landing_page_id}, section: #{section_key}")

    begin
      # Find the landing page
      landing_page = LandingPage.find_by(id: landing_page_id)
      
      if landing_page.nil?
        raise ArgumentError, "Landing page with ID #{landing_page_id} not found"
      end
      
      log_with_context("Found landing page: #{landing_page.id} (#{landing_page.title})")
      
      # Optimize the prompt for DALL-E
      log_with_context("Optimizing prompt for DALL-E")
      optimized_prompt = optimize_prompt_for_dalle(description)
      
      # Generate the image using DALL-E
      log_with_context("Generating image with DALL-E: '#{optimized_prompt.truncate(100)}'")
      
      begin
        dalle_response = call_dalle_api(optimized_prompt)
        
        if dalle_response.nil? || !dalle_response['data'] || dalle_response['data'].empty?
          raise StandardError, "DALL-E API returned invalid response"
        end
        
        # Get the image URL from the response
        image_url = dalle_response['data'][0]['url']
        log_with_context("Image generated successfully at URL: #{image_url}")
        
        # Download the image and upload to S3 or ActiveStorage
        permanent_url = download_and_store_image(image_url, section_key, landing_page.id)
        log_with_context("Image stored permanently at: #{permanent_url}")
        
        # Update the landing page content to include the new image
        update_landing_page_with_image(landing_page, section_key, permanent_url)
        
        log_with_context("Landing page updated successfully with new image for #{section_key}")
      rescue OpenAI::Error => e
        log_with_context("OpenAI API error: #{e.message}", :error)
        
        # Handle rate limiting specifically
        if e.message.include?("rate_limit_exceeded")
          log_with_context("Rate limit exceeded - retrying in 60 seconds", :warn)
          retry_job(wait: 60.seconds)
          return
        end
        
        # For other OpenAI errors, set a fallback image and continue
        fallback_image_url = "https://placehold.co/600x400/EAEAEA/999999?text=Image+Generation+Failed"
        log_with_context("Using fallback image: #{fallback_image_url}", :warn)
        update_landing_page_with_image(landing_page, section_key, fallback_image_url)
        raise
      end
    rescue ArgumentError => e
      log_with_context("Invalid argument error: #{e.message}", :error)
      raise
    rescue StandardError => e
      log_with_context("Error generating image: #{e.message}", :error)
      log_with_context(e.backtrace.join("\n"), :error)
      raise
    end
  end
  
  private
  
  def log_with_context(message, level = :info)
    prefix = "[ImageGenJob LP##{instance_variable_defined?('@landing_page_id') ? @landing_page_id : '?'} #{instance_variable_defined?('@section_key') ? @section_key : '?'}]"
    
    case level
    when :error
      Rails.logger.error "#{prefix} #{message}"
    when :warn
      Rails.logger.warn "#{prefix} #{message}"
    else
      Rails.logger.info "#{prefix} #{message}"
    end
  end
  
  def optimize_prompt_for_dalle(description)
    # Make sure the description is not too long for DALL-E
    max_length = 1000
    description = description.truncate(max_length) if description.length > max_length
    
    # Add qualifiers to improve image quality
    qualifiers = [
      "Professional high-quality",
      "High resolution",
      "Marketing image",
      "Clean background",
      "Modern style"
    ]
    
    # Add style hints based on the content
    style_hints = []
    
    if description.downcase.include?("logo")
      style_hints << "minimalist design"
      style_hints << "scalable vector style"
    elsif description.downcase.include?("product")
      style_hints << "product photography style"
      style_hints << "white background"
    elsif description.downcase.include?("team") || description.downcase.include?("people")
      style_hints << "professional business setting"
      style_hints << "diverse team members"
    else
      style_hints << "suitable for website header"
      style_hints << "appropriate for marketing materials"
    end
    
    # Combine everything into a well-formatted prompt
    optimized_prompt = "#{qualifiers.sample(2).join(', ')} image: #{description}. #{style_hints.sample(2).join(', ')}."
    
    log_with_context("Original prompt: '#{description}'")
    log_with_context("Optimized prompt: '#{optimized_prompt}'")
    
    optimized_prompt
  end
  
  def call_dalle_api(prompt)
    log_with_context("Calling DALL-E API")
    
    client = OpenAI::Client.new(
      access_token: ENV['OPENAI_API_KEY'],
      organization_id: ENV['OPENAI_ORG_ID']
    )
    
    response = client.images.generate(
      parameters: {
        model: "dall-e-3",
        prompt: prompt,
        size: "1024x1024",
        quality: "standard",
        n: 1
      }
    )
    
    log_with_context("DALL-E API call completed")
    response
  end
  
  def download_and_store_image(image_url, section_key, landing_page_id)
    log_with_context("Downloading image from #{image_url}")
    
    begin
      # Try to use Down gem first, fall back to open-uri if Down is not available
      temp_file = nil
      begin
        temp_file = Down.download(image_url)
        log_with_context("Image downloaded to temp file using Down gem: #{temp_file.path}")
      rescue NameError => e
        log_with_context("Down gem not available, falling back to open-uri", :warn)
        
        uri = URI.parse(image_url)
        temp_file = Tempfile.new(['image_download', '.png'])
        temp_file.binmode
        temp_file.write(URI.open(uri).read)
        temp_file.rewind
        log_with_context("Image downloaded to temp file using open-uri: #{temp_file.path}")
      end
      
      # Generate a filename for the image
      filename = "landing_page_#{landing_page_id}_#{section_key}_#{Time.now.to_i}.png"
      
      # Upload to ActiveStorage or S3
      if defined?(ActiveStorage)
        log_with_context("Uploading image to ActiveStorage")
        blob = ActiveStorage::Blob.create_and_upload!(
          io: File.open(temp_file),
          filename: filename,
          content_type: 'image/png'
        )
        url = Rails.application.routes.url_helpers.url_for(blob)
        log_with_context("Image uploaded to ActiveStorage with URL: #{url}")
      else
        # Fall back to S3 direct upload if ActiveStorage is not available
        log_with_context("Uploading image to S3")
        s3_client = Aws::S3::Client.new(
          region: ENV['AWS_REGION'],
          access_key_id: ENV['AWS_ACCESS_KEY_ID'],
          secret_access_key: ENV['AWS_SECRET_ACCESS_KEY']
        )
        
        bucket_name = ENV['AWS_S3_BUCKET']
        key = "landing_page_images/#{filename}"
        
        s3_client.put_object(
          bucket: bucket_name,
          key: key,
          body: File.open(temp_file)
        )
        
        url = "https://#{bucket_name}.s3.amazonaws.com/#{key}"
        log_with_context("Image uploaded to S3 with URL: #{url}")
      end
      
      # Clean up temp file
      temp_file.close
      temp_file.unlink
      
      return url
    rescue => e
      log_with_context("Error downloading or storing image: #{e.message}", :error)
      log_with_context(e.backtrace.join("\n"), :error)
      
      # Return the original URL as fallback
      return image_url
    end
  end
  
  def update_landing_page_with_image(landing_page, section_key, image_url)
    log_with_context("Updating landing page with image URL: #{image_url}")
    
    begin
      # Parse the current content
      content_json = 
        if landing_page.content.is_a?(Hash) || landing_page.content.is_a?(Array)
          # Content is already a parsed object
          log_with_context("Content is already a parsed object, no JSON parsing needed")
          landing_page.content
        else
          # Parse it as a JSON string
          JSON.parse(landing_page.content)
        end
      
      # Handle hero section differently
      if section_key == 'hero'
        if content_json['hero'].present?
          content_json['hero']['image_url'] = image_url
          log_with_context("Updated hero section image_url")
        else
          content_json['hero'] = { 'image_url' => image_url, 'type' => 'hero' }
          log_with_context("Created hero section with image_url")
        end
      else
        # Parse section key safely
        parts = section_key.to_s.split('_')
        log_with_context("Parsing section key: #{section_key} into parts: #{parts.inspect}")
        
        # Handle different formats of section keys
        if parts.length >= 3 && parts[0] == 'section'
          section_index = parts[1].to_i rescue 0
          img_index = parts.last.to_i rescue 1
          
          log_with_context("Extracted section_index: #{section_index}, img_index: #{img_index}")
          
          # Get the correct section - handle both hash and array content formats
          section = nil
          section_key_in_content = "section_#{section_index}"
          
          if content_json.is_a?(Array)
            # Array-based content
            section = content_json[section_index] if section_index < content_json.length
            log_with_context("Using array-based content access for section #{section_index}")
          else
            # Hash-based content (traditional)
            section = content_json[section_key_in_content]
            log_with_context("Using hash-based content access for section key #{section_key_in_content}")
          end
          
          if section.present? && section['content'].present?
            # Update image in HTML content
            content = section['content']
            
            # Find the nth image tag and replace its src
            img_count = 0
            updated_content = content.gsub(/<img[^>]*>/) do |img|
              img_count += 1
              if img_count == img_index
                # Replace or add src attribute
                if img =~ /src=["'][^"']*["']/
                  img.gsub(/src=["'][^"']*["']/, "src=\"#{image_url}\"")
                else
                  img.gsub(/<img/, "<img src=\"#{image_url}\"")
                end
              else
                img
              end
            end
            
            # Update the section content
            section['content'] = updated_content
            log_with_context("Updated image #{img_index} in section #{section_index}")
          else
            log_with_context("Section not found or no content present", :warn)
          end
        else
          # Handle non-standard section key format
          log_with_context("Non-standard section key format: #{section_key}, treating as direct key", :warn)
          
          if content_json[section_key].present?
            content_json[section_key]['image_url'] = image_url
            log_with_context("Updated image_url for custom section key: #{section_key}")
          else
            log_with_context("Section not found for key: #{section_key}", :warn)
          end
        end
      end
      
      # Save the updated content
      if landing_page.update(content: content_json.to_json)
        log_with_context("Landing page content updated successfully")
      else
        log_with_context("Failed to update landing page: #{landing_page.errors.full_messages.join(', ')}", :error)
        raise StandardError, "Failed to update landing page content"
      end
    rescue JSON::ParserError => e
      log_with_context("Failed to parse landing page content as JSON: #{e.message}", :error)
      raise
    rescue StandardError => e
      log_with_context("Error updating landing page with image: #{e.message}", :error)
      log_with_context(e.backtrace.join("\n"), :error)
      raise
    end
  end
end 