class ApplyLandingPageChangeJob < ApplicationJob
  include JobErrorHandling
  queue_as :default

  def perform(landing_page_id, previous_content, section_index = nil, section_type = nil, correlation_id = nil)
    @correlation_id = correlation_id || SecureRandom.uuid
    log_with_context("Starting ApplyLandingPageChangeJob for landing page #{landing_page_id}, section: #{section_index || 'all'}")
    
    begin
      # Look up the landing page
      @landing_page = LandingPage.find_by(id: landing_page_id)
      
      if @landing_page.nil?
        raise ArgumentError, "Landing page with ID #{landing_page_id} not found"
      end
      
      log_with_context("Found landing page: #{@landing_page.id} (#{@landing_page.title})")
      
      # Parse the landing page content JSON
      current_content = parse_landing_page_content
      
      # Store the original content for comparison
      original_content = current_content.deep_dup
      
      # Check if previous_content is likely a plain text instruction rather than JSON
      is_plain_text = false
      begin
        # Try to parse it as JSON to see if it's valid
        JSON.parse(previous_content)
      rescue JSON::ParserError
        # If we get here, it's not valid JSON
        log_with_context("previous_content appears to be plain text, not JSON")
        is_plain_text = true
      end
      
      # Process the changes
      if section_index.present?
        # Convert section_index to integer if it's not already
        section_index = section_index.to_i if section_index.is_a?(String)
        
        log_with_context("Applying changes to section #{section_index} (#{section_type})")
        
        # Handle array vs hash content storage
        is_array_content = current_content.is_a?(Array)
        log_with_context("Content is an #{is_array_content ? 'array' : 'hash'}")
        
        if is_array_content
          # For array content, use direct numeric index
          if section_index < 0 || section_index >= current_content.length
            log_with_context("Section index #{section_index} is out of bounds, creating a new section")
            if section_index < 0
              section_index = 0
            end
            # Extend the array if needed
            while current_content.length <= section_index
              current_content << {}
            end
          end
          
          # Make sure the section is a hash
          if !current_content[section_index].is_a?(Hash)
            log_with_context("Converting section #{section_index} from #{current_content[section_index].class} to Hash")
            current_content[section_index] = {
              'type' => section_type || 'text_block',
              'content' => current_content[section_index].to_s
            }
          end
          
          if is_plain_text
            # Handle plain text instruction directly
            current_content[section_index]['ai_instruction'] = previous_content
            log_with_context("Stored plain text instruction in array section: #{previous_content.truncate(50)}")
            updated_content = current_content
          else
            # For JSON processing, convert array to hash temporarily
            temp_hash = {}
            current_content.each_with_index do |item, idx|
              temp_hash[idx == 0 ? 'hero' : "section_#{idx}"] = item
            end
            section_key = section_index == 0 ? 'hero' : "section_#{section_index}"
            temp_result = apply_changes_to_section(temp_hash, section_key, previous_content, section_type)
            
            # Update only the specific section in the array
            current_content[section_index] = temp_result[section_key]
            updated_content = current_content
          end
        else
          # For hash content, use string key
          section_key = section_index == 0 ? 'hero' : "section_#{section_index}"
          
          if is_plain_text
            # Handle plain text instruction directly
            if !current_content[section_key].is_a?(Hash)
              current_content[section_key] = {
                'type' => section_type || 'text_block',
                'content' => ''
              }
            end
            
            # Update the content directly with AI instructions
            current_content[section_key]['ai_instruction'] = previous_content
            log_with_context("Stored plain text instruction in hash section: #{previous_content.truncate(50)}")
            
            updated_content = current_content
          else
            # Normal JSON processing
            updated_content = apply_changes_to_section(current_content, section_key, previous_content, section_type)
          end
        end
      else
        # Apply changes to the entire content
        log_with_context("Applying changes to entire content")
        if is_plain_text
          # Handle plain text instruction at content level
          log_with_context("Storing plain text instruction at content level")
          
          # For arrays, store at a special meta key
          if current_content.is_a?(Array)
            # Convert to hash with special key
            temp_hash = {
              'content_array' => current_content,
              'ai_instruction' => previous_content
            }
            updated_content = temp_hash
          else
            current_content['ai_instruction'] = previous_content
            updated_content = current_content
          end
        else
          begin
            updated_content = JSON.parse(previous_content)
          rescue JSON::ParserError => e
            log_with_context("Failed to parse previous_content as JSON: #{e.message}", :error)
            raise ArgumentError, "Invalid JSON format in previous_content: #{e.message}"
          end
        end
      end
      
      # Update landing page with the modified content
      if @landing_page.update(content: updated_content.to_json)
        log_with_context("Landing page content updated successfully")
      else
        log_with_context("Failed to update landing page content: #{@landing_page.errors.full_messages.join(', ')}", :error)
        raise StandardError, "Failed to update landing page content"
      end
      
      # Process images ONLY in the section that was updated
      process_images_in_content(updated_content, section_index)
      
      # Special case: if we have a plain text instruction that mentions images
      # but no image tags were found, generate an image from the instruction
      if is_plain_text && previous_content.downcase.include?('image') && 
         !previous_content.include?('<img') && section_index.present?
        
        log_with_context("Plain text instruction mentions images but no image tags found. Generating image from instruction.")
        
        # Create a section key
        section_key = section_index == 0 ? 'hero' : "section_#{section_index}"
        
        # Get existing image prompts or create new hash
        image_prompts = @landing_page.image_prompts || {}
        
        # Create a prompt from the instruction
        description = "AI marketing image based on instruction: #{previous_content.truncate(100)}"
        
        # Store the image prompt
        img_key = "#{section_key}_auto_img"
        image_prompts[img_key] = {
          "description" => description,
          "created_at" => Time.now.iso8601,
          "auto_generated" => true
        }
        
        # Save the updated prompts
        @landing_page.update(image_prompts: image_prompts)
        
        # Schedule image generation
        begin
          log_with_context("Scheduling auto-image generation for #{section_key} from plain text instruction")
          
          # Create a detailed prompt
          detailed_prompt = "Professional high-quality marketing image for website: #{description}. " +
                            "Modern design, vibrant colors, clear focal point. Suitable for marketing content."
          
          job = GenerateLandingPageImageJob.set(priority: 10).perform_later(
            @landing_page.id,
            detailed_prompt,
            img_key,
            @correlation_id
          )
          
          log_with_context("Auto-image job scheduled with ID: #{job.job_id}")
        rescue => e
          log_with_context("Failed to schedule auto-image job: #{e.message}", :error)
        end
      end
      
      # Log a summary of what was changed
      log_changes(original_content, updated_content)
      
      # Update timestamp
      @landing_page.touch
      
      log_with_context("ApplyLandingPageChangeJob completed successfully")
    rescue ArgumentError => e
      log_with_context("Invalid argument error: #{e.message}", :error)
      raise
    rescue StandardError => e
      log_with_context("ERROR in ApplyLandingPageChangeJob: #{e.message}", :error)
      log_with_context(e.backtrace.join("\n"), :error)
      raise
    end
  end
  
  private
  
  def log_with_context(message, level = :info)
    prefix = "[#{@correlation_id}]"
    case level
    when :error
      Rails.logger.error "#{prefix} #{message}"
    when :warn
      Rails.logger.warn "#{prefix} #{message}"
    else
      Rails.logger.info "#{prefix} #{message}"
    end
  end
  
  def parse_landing_page_content
    begin
      # Check if content is already a Hash or Array (already parsed)
      content = @landing_page.content
      if content.is_a?(Hash) || content.is_a?(Array)
        log_with_context("Content is already a parsed object, no JSON parsing needed")
        return content
      end
      
      # Otherwise parse it as a JSON string
      JSON.parse(content.presence || '{}')
    rescue JSON::ParserError => e
      log_with_context("Failed to parse landing page content as JSON: #{e.message}", :error)
      {}  # Return empty hash if parsing fails
    end
  end
  
  def process_images_in_content(content_json, target_section_index)
    log_with_context("Looking for images in content sections")
    
    # Safety check - skip image processing if null content 
    if content_json.nil?
      log_with_context("Content is nil, skipping image processing", :warn)
      return
    end
    
    image_prompts = @landing_page.image_prompts || {}
    sections_to_process = []
    
    # Convert target_section_index to integer if it's a string
    target_section_index = target_section_index.to_i if target_section_index.is_a?(String)
    
    # Check if content is an array or hash
    is_array_content = content_json.is_a?(Array)
    log_with_context("Content structure is #{is_array_content ? 'array' : 'hash'}")
    
    # If target_section_index is specified, only process that section
    if target_section_index.present?
      if is_array_content
        # For array content structure
        if target_section_index >= 0 && target_section_index < content_json.length
          section = content_json[target_section_index]
          sections_to_process << [target_section_index, section]
          log_with_context("Processing only array section at index #{target_section_index}")
        else
          log_with_context("Target section index #{target_section_index} is out of bounds", :warn)
        end
      else
        # For hash content structure (original behavior)
        if target_section_index == 0
          sections_to_process << ['hero', content_json['hero']]
          log_with_context("Processing only hero section for images")
        else
          key = "section_#{target_section_index}"
          if content_json[key].present?
            sections_to_process << [key, content_json[key]]
            log_with_context("Processing only section #{target_section_index} for images")
          else
            log_with_context("Target section #{key} not found in content", :warn)
          end
        end
      end
    else
      # Process all sections if no target section was specified
      log_with_context("Processing all sections for images")
      
      if is_array_content
        # For array content
        content_json.each_with_index do |section, index|
          sections_to_process << [index, section]
        end
      else
        # For hash content (original behavior)
        content_json.each do |key, value|
          next unless key.match?(/^(hero|section_\d+)$/)
          sections_to_process << [key, value]
        end
      end
    end
    
    log_with_context("Checking for images in #{sections_to_process.size} sections")
    
    # Process each section
    sections_to_process.each do |key_or_index, section|
      # Skip if section is nil or doesn't have content
      next unless section.is_a?(Hash) && section['content'].present?
      
      # Extract section index from key
      section_index = 
        if is_array_content
          # For array, the key is already the numeric index
          key_or_index
        else
          # For hash, extract from string key
          key_or_index == 'hero' ? 0 : key_or_index.split('_').last.to_i
        end
      
      section_type = 
        if is_array_content
          section['type'] || 'unknown'
        else
          key_or_index == 'hero' ? 'hero' : (section['type'] || 'unknown')
        end
      
      log_with_context("Checking section #{section_index} of type #{section_type} for images")
      
      # Check for img tags in content
      content = section['content'].to_s
      images = content.scan(/<img[^>]*>/)
      
      log_with_context("Found #{images.size} potential images in section #{section_index}")
      
      # Process each image
      images.each_with_index do |img, img_index|
        # Log the full image tag for debugging
        log_with_context("Processing image tag: #{img}")
        
        # Extract image description from alt text
        description = nil
        if img =~ /alt=["']([^"']+)["']/
          description = $1.strip
          log_with_context("Found alt text: #{description}")
        else
          # If no alt text, generate a generic description based on section type
          log_with_context("No alt text found in image tag, using generic description")
          description = "AI marketing image for #{section_type} section"
        end
          
        # Generate a unique key for this image
        img_key = 
          if is_array_content
            "section_#{section_index}_img_#{img_index + 1}"
          else
            key_or_index == 'hero' ? 'hero' : "section_#{section_index}_img_#{img_index + 1}"
          end
        
        log_with_context("Image found: section=#{section_index}, description='#{description.truncate(50)}', key=#{img_key}")
        
        # Store the image prompt
        image_prompts[img_key] = {
          "description" => description,
          "created_at" => Time.now.iso8601
        }
        
        # Schedule image generation with improved description
        begin
          log_with_context("Scheduling GenerateLandingPageImageJob for #{img_key}")
          
          # Create a more detailed prompt for better image quality
          detailed_prompt = "Professional high-quality marketing image for website: #{description}. " +
                            "Modern design, vibrant colors, clear focal point. Suitable for #{section_type} section."
          
          job = GenerateLandingPageImageJob.set(priority: 10).perform_later(
            @landing_page.id,
            detailed_prompt,
            img_key,
            @correlation_id
          )
          
          log_with_context("Job scheduled with ID: #{job.job_id}")
        rescue => e
          log_with_context("Failed to schedule image job: #{e.message}", :error)
        end
      end
    end
    
    # Update image_prompts in landing page if any were found
    if image_prompts.present? && image_prompts != @landing_page.image_prompts
      log_with_context("Updating landing page with #{image_prompts.size} image prompts")
      
      if @landing_page.update(image_prompts: image_prompts)
        log_with_context("Successfully saved image prompts to landing page")
      else
        log_with_context("Failed to save image prompts: #{@landing_page.errors.full_messages.join(', ')}", :warn)
      end
    end
  end
  
  def apply_changes_to_section(content_json, key, previous_content, section_type)
    # Parse the new section content from previous_content
    begin
      new_section_content = JSON.parse(previous_content)
      
      # Ensure content_json is a hash, not an array
      if content_json.is_a?(Array)
        log_with_context("Converting content_json from Array to Hash")
        temp_hash = {}
        content_json.each_with_index do |item, idx|
          temp_hash["section_#{idx}"] = item
        end
        content_json = temp_hash
      end
      
      # Ensure content_json is a hash
      unless content_json.is_a?(Hash)
        log_with_context("Converting content_json from #{content_json.class} to Hash for top level")
        temp_hash = {}
        temp_hash["content"] = content_json.to_s
        content_json = temp_hash
      end
      
      # Check if key is valid for content_json
      if content_json.has_key?(key)
        log_with_context("Key '#{key}' exists in content_json")
      else
        log_with_context("Key '#{key}' does not exist in content_json, creating it")
        content_json[key] = {}
      end
      
      # Update the section in the content_json
      if key == 'hero'
        # For hero section, merge the changes
        if content_json[key].present?
          # Ensure the section is a hash
          if !content_json[key].is_a?(Hash)
            log_with_context("Converting hero section from #{content_json[key].class} to Hash")
            content_json[key] = {'content' => content_json[key].to_s, 'type' => 'hero'}
          end
          
          # Filter out 'new_section' key if present to avoid UnknownAttributeError
          filtered_content = new_section_content.except('new_section')
          log_with_context("Merging filtered content into hero section")
          content_json[key].merge!(filtered_content)
          log_with_context("Updated hero section with new content")
        else
          # Filter out 'new_section' key if present
          log_with_context("Creating new hero section")
          content_json[key] = new_section_content.except('new_section')
          log_with_context("Created new hero section")
        end
      else
        # Handle the case when the section doesn't exist yet
        if !content_json[key].present?
          log_with_context("Section #{key} doesn't exist, creating it")
          content_json[key] = { 'type' => section_type, 'content' => '' }
          log_with_context("Created new section #{key} with type #{section_type}")
        elsif !content_json[key].is_a?(Hash)
          # If it exists but is not a hash, convert it
          log_with_context("Converting section #{key} from #{content_json[key].class} to Hash")
          content_json[key] = {'content' => content_json[key].to_s, 'type' => section_type || 'text_block'}
        end
        
        # Ensure section is a hash before proceeding
        unless content_json[key].is_a?(Hash)
          log_with_context("Critical error: section #{key} is still not a hash after conversion", :error)
          content_json[key] = { 'type' => section_type || 'text_block', 'content' => content_json[key].to_s }
        end
        
        # For other sections, check if 'new_section' key is present
        if new_section_content.key?('new_section')
          log_with_context("Processing 'new_section' key in content")
          
          # Extract type and content from the new_section object
          new_type = new_section_content['type'] || section_type || 'text_block'
          new_content = new_section_content['content'] || ''
          
          # Create a clean section object without the 'new_section' key
          log_with_context("Creating clean section object")
          content_json[key] = {
            'type' => new_type,
            'content' => new_content
          }
          
          log_with_context("Created/updated section with type: #{new_type}")
        else
          # Update the specified section with attributes that exist in the section
          valid_attributes = ['type', 'content', 'title', 'subtitle', 'image_url']
          
          log_with_context("Updating section #{key} with valid attributes")
          valid_attributes.each do |attr|
            begin
              if new_section_content.key?(attr)
                content_json[key][attr] = new_section_content[attr]
                log_with_context("Updated #{key}.#{attr}")
              end
            rescue => e
              log_with_context("Error updating #{key}.#{attr}: #{e.message}", :error)
            end
          end
          
          # Handle any additional attributes specific to the section type
          # Filter out 'new_section' key to avoid UnknownAttributeError
          begin
            additional_attrs = new_section_content.except(*(valid_attributes + ['new_section']))
            if additional_attrs.any?
              log_with_context("Found additional attributes in section content")
              additional_attrs.each do |attr, value|
                begin
                  content_json[key][attr] = value
                  log_with_context("Updated #{key}.#{attr}")
                rescue => e
                  log_with_context("Error setting additional attribute #{key}.#{attr}: #{e.message}", :error)
                end
              end
            end
          rescue => e
            log_with_context("Error processing additional attributes: #{e.message}", :error)
          end
        end
      end
      
      return content_json
    rescue JSON::ParserError => e
      log_with_context("Failed to parse previous_content as JSON: #{e.message}", :error)
      
      # If parsing fails, treat it as plain text content
      if content_json[key].present?
        # Ensure the section is a hash
        if !content_json[key].is_a?(Hash)
          log_with_context("Converting section #{key} from #{content_json[key].class} to Hash for text content")
          content_json[key] = {'type' => section_type || 'text_block', 'content' => ''}
        end
        
        begin
          content_json[key]['content'] = previous_content
          log_with_context("Applied previous_content as plain text")
        rescue => e
          log_with_context("Error setting plain text content: #{e.message}", :error)
          # Last resort - completely rebuild the section
          content_json[key] = {
            'type' => section_type || 'text_block',
            'content' => previous_content
          }
        end
      else
        content_json[key] = {
          'type' => section_type || 'text_block',
          'content' => previous_content
        }
        log_with_context("Created new section with plain text content")
      end
      
      return content_json
    rescue StandardError => e
      log_with_context("Unexpected error in apply_changes_to_section: #{e.message}", :error)
      log_with_context(e.backtrace.join("\n"), :error)
      
      # Return the original content unchanged as a last resort
      return content_json
    end
  end
  
  def log_changes(original, updated)
    # Find differences between original and updated content
    differences = []
    
    # Convert arrays to hashes if needed
    original_hash = original.is_a?(Array) ? array_to_hash(original) : original
    updated_hash = updated.is_a?(Array) ? array_to_hash(updated) : updated
    
    # Ensure we're working with hashes
    original_hash = {} unless original_hash.is_a?(Hash)
    updated_hash = {} unless updated_hash.is_a?(Hash)
    
    # Compare the two hashes
    updated_hash.each do |key, value|
      if !original_hash[key] || original_hash[key] != value
        if !original_hash[key]
          differences << "#{key} (new)"
        else
          differences << key
        end
      end
    end
    
    if differences.any?
      log_with_context("Changed sections: #{differences.join(', ')}")
    else
      log_with_context("No sections were changed")
    end
  end
  
  # Helper method to convert an array to a hash with section_N keys
  def array_to_hash(array)
    return {} unless array.is_a?(Array)
    
    result = {}
    array.each_with_index do |item, idx|
      result["section_#{idx}"] = item
    end
    result
  end
end 