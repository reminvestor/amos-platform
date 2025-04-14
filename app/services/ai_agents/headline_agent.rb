module AiAgents
  class HeadlineAgent < BaseAgent
    def execute
      Rails.logger.info("HeadlineAgent: Starting headline generation")
      
      # Get prompts for this agent
      prompts = context[:agent_prompts]&.dig("headline") || []
      
      if prompts.empty?
        Rails.logger.error("HeadlineAgent: No prompts found for headline generation")
        return context
      end
      
      # Use the first prompt for this agent (there might be multiple tasks)
      task_data = prompts.first
      prompt = task_data[:prompt]
      
      # Generate the headline and subheadline using the prompt
      response = call_openai_api(prompt)
      
      begin
        # Find and parse JSON in the response
        json_match = response.match(/\{.*\}/m)
        return context unless json_match
        
        result = JSON.parse(json_match[0])
        
        # Update context with the headline and subheadline
        update_context({
          headline: result["headline"],
          subheadline: result["subheadline"]
        })
        
        Rails.logger.info("HeadlineAgent: Successfully generated headline: #{result['headline']}")
      rescue JSON::ParserError => e
        Rails.logger.error("HeadlineAgent: Error parsing response: #{e.message}")
      end
      
      context
    end
  end
end 