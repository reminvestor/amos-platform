module AiAgents
  class ImagePromptAgent < BaseAgent
    def execute
      Rails.logger.info("ImagePromptAgent: Starting image prompt generation")
      
      # Get prompts for this agent
      prompts = context[:agent_prompts]&.dig("image_prompt") || []
      
      if prompts.empty?
        Rails.logger.error("ImagePromptAgent: No prompts found for image prompt generation")
        return context
      end
      
      # Use the first prompt for this agent
      task_data = prompts.first
      prompt = task_data[:prompt]
      
      # Generate the image prompts
      response = call_openai_api(prompt)
      
      begin
        # Find and parse JSON in the response
        json_match = response.match(/\{.*\}/m)
        return context unless json_match
        
        result = JSON.parse(json_match[0])
        
        # Update context with the image prompts
        update_context({
          image_prompts: {
            hero_image: result["hero_image"],
            feature_images: result["feature_images"] || [],
            background_image: result["background_image"]
          }
        })
        
        Rails.logger.info("ImagePromptAgent: Successfully generated image prompts")
      rescue JSON::ParserError => e
        Rails.logger.error("ImagePromptAgent: Error parsing response: #{e.message}")
      end
      
      context
    end
  end
end 