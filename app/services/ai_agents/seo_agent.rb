module AiAgents
  class SeoAgent < BaseAgent
    def execute
      Rails.logger.info("SEOAgent: Starting SEO metadata generation")
      
      # Get prompts for this agent
      prompts = context[:agent_prompts]&.dig("seo") || []
      
      if prompts.empty?
        Rails.logger.error("SEOAgent: No prompts found for SEO generation")
        return context
      end
      
      # Use the first prompt for this agent
      task_data = prompts.first
      prompt = task_data[:prompt]
      
      # Generate the SEO metadata
      response = call_openai_api(prompt)
      
      begin
        # Find and parse JSON in the response
        json_match = response.match(/\{.*\}/m)
        return context unless json_match
        
        result = JSON.parse(json_match[0])
        
        # Update context with the SEO metadata
        update_context({
          meta_title: result["meta_title"],
          meta_description: result["meta_description"],
          meta_keywords: result["meta_keywords"]
        })
        
        Rails.logger.info("SEOAgent: Successfully generated SEO metadata")
      rescue JSON::ParserError => e
        Rails.logger.error("SEOAgent: Error parsing response: #{e.message}")
      end
      
      context
    end
  end
end 