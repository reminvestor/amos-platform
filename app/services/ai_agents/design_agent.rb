module AiAgents
  class DesignAgent < BaseAgent
    def execute
      Rails.logger.info("DesignAgent: Starting design recommendation generation")
      
      # Get prompts for this agent
      prompts = context[:agent_prompts]&.dig("design") || []
      
      if prompts.empty?
        Rails.logger.error("DesignAgent: No prompts found for design generation")
        return context
      end
      
      # Use the first prompt for this agent
      task_data = prompts.first
      prompt = task_data[:prompt]
      
      # Generate the design recommendations
      response = call_openai_api(prompt)
      
      begin
        # Find and parse JSON in the response
        json_match = response.match(/\{.*\}/m)
        return context unless json_match
        
        result = JSON.parse(json_match[0])
        
        # Update context with the design recommendations
        update_context({
          primary_color: result["primary_color"],
          secondary_color: result["secondary_color"],
          font_family: result["font_family"],
          design_style: result["design_style"]
        })
        
        Rails.logger.info("DesignAgent: Successfully generated design recommendations")
      rescue JSON::ParserError => e
        Rails.logger.error("DesignAgent: Error parsing response: #{e.message}")
      end
      
      context
    end
  end
end 