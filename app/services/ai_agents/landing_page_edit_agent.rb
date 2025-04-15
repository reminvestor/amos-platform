module AiAgents
  class LandingPageEditAgent < BaseAgent
    attr_reader :landing_page, :entity_id, :user_id, :instruction, :conversation_history, :section_index

    def initialize(landing_page:, entity_id:, user_id:, instruction:, conversation_history: [], section_index: nil)
      @landing_page = landing_page
      @entity_id = entity_id
      @user_id = user_id
      @instruction = instruction
      @conversation_history = conversation_history
      @section_index = section_index
      
      # Initialize the base agent with a context
      context = {
        landing_page_id: landing_page.id,
        instruction: instruction,
        entity_id: entity_id,
        user_id: user_id,
        section_index: section_index
      }
      
      super(context: context)
    end

    def execute
      Rails.logger.info("LandingPageEditAgent execution started for landing page: #{landing_page.id}")
      
      # Get business and campaign data for context
      entity = Entity.find_by(id: entity_id)
      business_profile = entity&.business_profiles&.first
      campaign = landing_page.campaign
      
      # Build the context for the AI request
      prompt = if section_index.nil?
        # If no section specified, this is a general edit (headline, CTA, etc.)
        build_general_prompt(business_profile, campaign)
      else
        # If section specified, focus only on that section
        build_section_prompt(business_profile, campaign, section_index)
      end
      
      # Log the entire prompt for debugging
      Rails.logger.info("LandingPageEditAgent prompt: #{prompt}")
      
      # Get the AI response
      response = call_openai_api(
        prompt,
        'gpt-4o',
        0.7,
        2048
      )
      
      # Log the AI response for debugging
      Rails.logger.info("LandingPageEditAgent response: #{response}")
      
      # Parse the response for content updates
      parsed_content_updates = if section_index.nil?
        parse_general_updates(response)
      else
        parse_section_updates(response, section_index)
      end
      
      # Parse the response for a user-friendly message
      ai_message = parse_ai_message(response)
      
      # Update context with the response
      update_context({
        ai_response: response,
        parsed_response: parsed_content_updates,
        ai_message: ai_message
      })
      
      Rails.logger.info("LandingPageEditAgent execution completed for landing page: #{landing_page.id}")
      
      # Return the result
      {
        success: true,
        updated_landing_page: parsed_content_updates,
        ai_response: response,
        ai_message: ai_message
      }
    rescue StandardError => e
      Rails.logger.error("Error in LandingPageEditAgent: #{e.message}")
      Rails.logger.error(e.backtrace.join("\n")) if e.backtrace
      
      # Return error information
      {
        success: false,
        error: e.message
      }
    end

    private

    def build_general_prompt(business_profile, campaign)
      # Start with the system prompt
      system_prompt_text = <<~PROMPT
        You are an expert web designer and copywriter specialized in creating high-converting landing pages.
        Your task is to modify a landing page according to the user's instructions.
        You will be provided with details about the current landing page and the change request.
        
        Follow these guidelines:
        1. Understand the current landing page structure
        2. Apply only the changes requested in the instruction
        3. Maintain the original style and tone where not explicitly changed
        4. Only return fields that need to be updated (headline, subheadline, cta_text, etc.)
        
        If you need to update a specific section on the page, use the section_update format:
        
        ```json
        {
          "section_update": {
            "type": "features", 
            "index": 0,
            "content": "The complete updated HTML content for this section"
          }
        }
        ```
        
        If you need to specifically update a features list, you can use this format instead:
        
        ```json
        {
          "features_section": {
            "features": ["Feature 1", "Feature 2", "Feature 3", "Feature 4"]
          }
        }
        ```
        
        For other general updates, use this format:
        
        ```json
        {
          "headline": "New Headline Text",
          "subheadline": "New subheadline text",
          "cta_text": "New CTA Button Text"
        }
        ```
        
        Your response should include two parts:
        1. A JSON object with ONLY the fields that need to be updated 
        2. A user-friendly message explaining what changes you made
      PROMPT
      
      # Add content sections information
      if landing_page.content.present?
        system_prompt_text += "\n\nHere are the content sections on this page:\n"
        landing_page.content.each_with_index do |section, index|
          system_prompt_text += "\n- Section #{index}: type '#{section['type']}', title '#{section['title']}'\n"
          if section['type'] == 'features'
            system_prompt_text += "  Features section content preview: #{section['content'].to_s.truncate(200)}\n"
          end
        end
      end
      
      # Construct landing page details (excluding content array)
      landing_page_json = {
        id: landing_page.id,
        title: landing_page.title,
        headline: landing_page.headline,
        subheadline: landing_page.subheadline,
        cta_text: landing_page.cta_text,
        cta_url: landing_page.cta_url
      }
      
      # Add business and campaign context
      build_context_prompt(system_prompt_text, landing_page_json, business_profile, campaign)
    end

    def build_section_prompt(business_profile, campaign, section_index)
      # Get the specific section to edit
      content = landing_page.content || []
      section = content[section_index] if section_index < content.size
      
      if section
        # System prompt focused on editing a specific section
        system_prompt_text = <<~PROMPT
          You are an expert web designer and copywriter specialized in creating high-converting landing pages.
          Your task is to modify a SPECIFIC SECTION of a landing page according to the user's instructions.
          
          Follow these guidelines:
          1. You'll be editing only ONE section, not the entire page
          2. Apply only the changes requested in the instruction
          3. Maintain the original style and tone where not explicitly changed
          4. Return the complete updated section
          
          Your response should include two parts:
          1. A JSON object with the updated section
          2. A user-friendly message explaining what changes you made
          
          Format your response like this:
          
          ```json
          {
            "title": "Updated Section Title",
            "content": "Updated section content with HTML formatting if needed",
            "type": "text_block"
          }
          ```
          
          And then your user-friendly message below the JSON.
        PROMPT
      else
        # System prompt focused on creating a new section
        system_prompt_text = <<~PROMPT
          You are an expert web designer and copywriter specialized in creating high-converting landing pages.
          Your task is to CREATE A NEW SECTION for a landing page according to the user's instructions.
          
          Follow these guidelines:
          1. You'll be creating a completely new section to be added to the page
          2. Create the section based on the user's instructions
          3. Match the style and tone of the existing page
          4. Include all required fields: title, content, and type
          
          Common section types include:
          - "text_block" - Standard text content with optional headline
          - "features" - Feature list, typically with icons
          - "testimonial" - Customer testimonial
          - "image_text" - Image alongside text
          - "cta" - Call to action section
          
          Your response should include two parts:
          1. A JSON object with the complete new section including title, content and type
          2. A user-friendly message explaining what you created
          
          Format your response like this:
          
          ```json
          {
            "title": "New Section Title",
            "content": "New section content with HTML formatting if needed",
            "type": "text_block"
          }
          ```
          
          And then your user-friendly message below the JSON.
        PROMPT
      end
      
      # Construct landing page overview for context
      landing_page_overview = {
        id: landing_page.id,
        title: landing_page.title,
        headline: landing_page.headline,
        subheadline: landing_page.subheadline
      }
      
      # Build the full prompt
      full_prompt = <<~PROMPT
        #{system_prompt_text}

        # Landing Page Overview
        ```json
        #{landing_page_overview.to_json}
        ```
        
      PROMPT
      
      # Only add section to edit if it exists
      if section
        full_prompt += <<~PROMPT
          # Section to Edit (Section #{section_index + 1})
          ```json
          #{section.to_json}
          ```
          
        PROMPT
      else
        full_prompt += <<~PROMPT
          # Creating New Section (Section #{section_index + 1})
          This will be a new section added to the landing page.
          
        PROMPT
      end
      
      full_prompt += <<~PROMPT
        #{build_business_campaign_context(business_profile, campaign)}
        
        #{build_conversation_context}
        
        # Current Instruction
        #{instruction}
        
        Based on the instruction, please provide the #{section ? 'updated' : 'new'} section and a user-friendly message explaining the changes you made.
      PROMPT
      
      full_prompt
    end
    
    def build_context_prompt(system_prompt, landing_page_json, business_profile, campaign)
      # Build the full prompt
      <<~PROMPT
        #{system_prompt}

        # Current Landing Page
        ```json
        #{landing_page_json.to_json}
        ```
        
        #{build_business_campaign_context(business_profile, campaign)}
        
        #{build_conversation_context}
        
        # Current Instruction
        #{instruction}
        
        Based on the instruction, please provide a JSON object with only the fields that need to be updated 
        and a user-friendly message explaining what changes you made.
      PROMPT
    end
    
    def build_business_campaign_context(business_profile, campaign)
      context = ""
      
      # Construct business context
      if business_profile
        context += <<~CONTEXT
          # Business Context
          Business Name: #{business_profile.name}
          Industry: #{business_profile.industry}
          Description: #{business_profile.description}
        CONTEXT
      end
      
      # Construct campaign context
      if campaign
        context += <<~CONTEXT
          # Campaign Context
          Campaign Name: #{campaign.name}
          Campaign Description: #{campaign.description}
          Campaign Type: #{campaign.campaign_type}
        CONTEXT
      end
      
      context
    end
    
    def build_conversation_context
      # Add conversation history context if available
      return "" if conversation_history.blank?
      
      context = "# Conversation History\n"
      conversation_history.each_with_index do |msg, index|
        role = msg[:role] == 'assistant' ? 'Assistant' : 'User'
        context += "#{role}: #{msg[:content]}\n\n"
      end
      
      context
    end

    def parse_general_updates(response)
      # Extract JSON from the response
      json_pattern = /```json\n(.*?)```|{.*?}/m
      json_match = response.match(json_pattern)
      
      return {} unless json_match
      
      json_str = json_match[1] || json_match[0]
      parsed = JSON.parse(json_str)
      
      # Convert keys to symbols
      parsed_attrs = symbolize_keys(parsed)
      
      # Handle special cases that need section injection rather than full replacement
      if parsed_attrs[:features_section].present? || parsed_attrs[:section_update].present?
        # Get the full content array
        content = landing_page.content.deep_dup || []
        
        # Handle features_section specifically 
        if parsed_attrs[:features_section].present? && parsed_attrs[:features_section][:features].is_a?(Array)
          # Find the existing features section
          features_index = content.find_index { |section| section['type'] == 'features' }
          
          if features_index.present?
            # Build the new feature items HTML
            features_html = "<ul style='list-style: none; padding: 0; max-width: 800px; margin: 20px auto;'>"
            
            parsed_attrs[:features_section][:features].each do |feature|
              features_html += "\n    <li style='font-size: 1.2em; color: #555; margin-bottom: 15px;'>\n"
              features_html += "      <strong>#{feature}</strong>: Description for #{feature}.\n"
              features_html += "    </li>"
            end
            
            features_html += "\n  </ul>"
            
            # Get the existing section HTML
            existing_html = content[features_index]['content']
            
            # Replace the entire <ul>...</ul> section
            updated_html = existing_html.gsub(/<ul.*?<\/ul>/m, features_html)
            
            # Update the section
            content[features_index]['content'] = updated_html
            
            return { content: content }
          end
        end
        
        # Handle section_update as a more generic way to update specific parts of HTML
        if parsed_attrs[:section_update].present?
          section_type = parsed_attrs[:section_update][:type]
          section_index = parsed_attrs[:section_update][:index]
          section_content = parsed_attrs[:section_update][:content]
          
          if section_type.present? && section_content.present?
            # Find the section by type and index if provided
            target_index = if section_index.present?
              # Find by index
              section_index.to_i
            else
              # Find first section of this type
              content.find_index { |section| section['type'] == section_type }
            end
            
            if target_index.present? && target_index < content.size
              # Update the section content
              content[target_index]['content'] = section_content
              return { content: content }
            end
          end
        end
      end
      
      # Only allow specific attributes that are valid for landing page
      allowed_attrs = [:headline, :subheadline, :cta_text, :cta_url, :title, 
                       :meta_description, :primary_color, :secondary_color, 
                       :font_family, :content]
                       
      # Filter to only include valid attributes
      filtered_attrs = parsed_attrs.select { |key, _| allowed_attrs.include?(key) }
      
      filtered_attrs
    rescue JSON::ParserError => e
      Rails.logger.error("Failed to parse JSON response: #{e.message}")
      {}
    end
    
    def parse_section_updates(response, section_index)
      # Extract JSON from the response for a section update
      json_pattern = /```json\n(.*?)```|{.*?}/m
      json_match = response.match(json_pattern)
      
      return {} unless json_match
      
      json_str = json_match[1] || json_match[0]
      parsed = JSON.parse(json_str)
      
      # Convert keys to symbols
      section_update = symbolize_keys(parsed)
      
      # Handle special case where the update includes HTML content that contains features
      if section_update[:content].is_a?(String) && 
         section_update[:content].include?('<ul') && 
         section_update[:content].include?('<li')
        # This is a complex HTML content update, let it pass through
        return { new_section: section_update } if section_index >= (landing_page.content || []).size
        
        # Update the specific section in the content array
        content = landing_page.content.deep_dup || []
        if section_index < content.size
          # Update existing section
          content[section_index] = section_update
          return { content: content }
        end
      end
      
      # Only allow valid section attributes (explicitly exclude new_section)
      allowed_keys = [:title, :content, :type, :image_url]
      section_update = section_update.select { |key, _| allowed_keys.include?(key) }
      
      # Prepare the content array update
      content = landing_page.content.deep_dup || []
      
      # If we have a valid section index and update, apply it
      if section_index < content.size && section_update.present?
        # Update the specific section
        content[section_index] = section_update
        
        # Return only the content update
        return { content: content }
      end
      
      # If the section doesn't exist but we have an update, treat it as a new section
      if section_index >= content.size && section_update.present?
        # Instead of appending to content directly, return new_section
        # This aligns with how ApplyLandingPageChangeJob processes new sections
        return { new_section: section_update }
      end
      
      {}
    rescue JSON::ParserError => e
      Rails.logger.error("Failed to parse JSON response for section: #{e.message}")
      {}
    end
    
    def parse_ai_message(response)
      # Try to extract the user-friendly message after the JSON block
      message_pattern = /```json.*?```\s*(.*)/m
      message_match = response.match(message_pattern)
      
      if message_match && message_match[1].present?
        message_match[1].strip
      else
        # If no clear message format, use the whole response minus any JSON
        response.gsub(/```json.*?```/m, '').strip
      end
    end
    
    def symbolize_keys(hash)
      # Convert string keys to symbols recursively
      return hash unless hash.is_a?(Hash)
      
      hash.each_with_object({}) do |(key, value), result|
        new_key = key.to_sym rescue key
        new_value = value.is_a?(Hash) ? symbolize_keys(value) : value
        result[new_key] = new_value
      end
    end
  end
end 