module AiAgents
  class PromptAgent < BaseAgent
    def execute
      Rails.logger.info("PromptAgent: Starting prompt generation")
      
      # Extract workflow and agent info from context
      workflow = context[:agent_workflow]
      
      if workflow.nil? || workflow.empty?
        Rails.logger.error("PromptAgent: No workflow found in context")
        return context
      end
      
      # Generate prompts for each agent in the workflow
      prompts = {}
      workflow.each do |task|
        agent_type = task[:agent_type]
        agent_task = task[:task]
        
        # Generate a specialized prompt for this agent and task
        prompt = generate_agent_prompt(agent_type, agent_task, task)
        
        # Store the prompt in the prompts hash
        prompts[agent_type] ||= []
        prompts[agent_type] << {
          task: agent_task,
          prompt: prompt,
          task_data: task
        }
      end
      
      # Update context with the generated prompts
      update_context({
        prompt_generation_completed: true,
        agent_prompts: prompts
      })
      
      Rails.logger.info("PromptAgent: Prompt generation completed")
      context
    end
    
    private
    
    def generate_agent_prompt(agent_type, task, task_data)
      # Base context information available to all prompts
      plan = context[:landing_page_plan] || {}
      business_profile = context[:business_profile]
      entity = context[:entity]
      
      # Common basic instructions for all agents
      basic_instructions = <<~INSTRUCTIONS
        You are a specialized AI agent responsible for #{task}.
        You are part of a multi-agent system creating a landing page for a business.
        
        Business Name: #{business_profile&.name || entity&.name || 'Unknown'}
        Industry: #{business_profile&.industry || 'Unknown'}
        Description: #{business_profile&.description || 'Unknown'}
        Page Type: #{plan['page_type'] || 'lead_generation'}
        
        The plan for this landing page includes:
        - Page Title: #{plan['page_title']}
        - Headline: #{plan['headline']}
      INSTRUCTIONS
      
      # Generate specialized prompts based on agent type
      case agent_type
      when "headline"
        generate_headline_prompt(plan, basic_instructions)
      when "design"
        generate_design_prompt(plan, basic_instructions)
      when "content", "hero", "feature", "testimonial", "cta"
        generate_content_prompt(plan, basic_instructions, task_data)
      when "image_prompt"
        generate_image_prompt_agent_prompt(plan, basic_instructions)
      when "seo"
        generate_seo_prompt(plan, basic_instructions)
      else
        # Generic prompt for unknown agent types
        <<~PROMPT
          #{basic_instructions}
          
          Your task is to: #{task}
          
          Please provide your specialized output based on the landing page plan and your expertise.
          
          Format your response as a structured JSON object.
        PROMPT
      end
    end
    
    def generate_headline_prompt(plan, basic_instructions)
      design_considerations = plan["design_considerations"] || {}
      conversion_strategy = plan["conversion_strategy"] || {}
      
      <<~PROMPT
        #{basic_instructions}
        
        Your specific task is to create a compelling headline and subheadline for this landing page.
        
        Design Tone: #{design_considerations["tone"] || "Professional"}
        Value Proposition: #{conversion_strategy["value_proposition"] || "Unknown"}
        
        Create a strong, engaging headline that:
        - Clearly communicates the main value proposition
        - Uses action-oriented language
        - Is concise (ideally 5-10 words)
        - Appeals to the target audience
        
        Also create a supporting subheadline that:
        - Expands on the headline
        - Addresses potential pain points
        - Contains 1-2 sentences (15-25 words)
        - Motivates the visitor to continue reading
        
        Return your response as a JSON object with the following format:
        {
          "headline": "Your compelling headline here",
          "subheadline": "Your supporting subheadline here"
        }
      PROMPT
    end
    
    def generate_design_prompt(plan, basic_instructions)
      design_considerations = plan["design_considerations"] || {}
      
      <<~PROMPT
        #{basic_instructions}
        
        Your specific task is to create design recommendations for this landing page.
        
        Based on the plan, the design should have these characteristics:
        - Color Scheme: #{design_considerations["color_scheme"] || "Professional"}
        - Tone: #{design_considerations["tone"] || "Informative"}
        - Imagery: #{design_considerations["imagery"] || "Industry-related"}
        
        Please provide specific design recommendations including:
        - Primary color (provide a specific hex code)
        - Secondary color (provide a specific hex code)
        - Font family recommendation from standard web fonts
        - Overall design style (minimalist, bold, etc.)
        
        Consider the business industry and purpose of the landing page when making your recommendations.
        
        Return your response as a JSON object with the following format:
        {
          "primary_color": "#hexcode",
          "secondary_color": "#hexcode",
          "font_family": "Font Name, fallback",
          "design_style": "description of overall style"
        }
      PROMPT
    end
    
    def generate_content_prompt(plan, basic_instructions, task_data)
      section_data = task_data[:section_data] || {}
      section_title = section_data["title"] || "Content"
      section_purpose = section_data["purpose"] || "Provide information"
      section_type = section_data["content_type"] || "content"
      
      headline = context[:headline] || plan["headline"] || "Main Headline"
      subheadline = context[:subheadline] || "Supporting subheadline"
      
      <<~PROMPT
        #{basic_instructions}
        
        Current Headline: #{headline}
        Current Subheadline: #{subheadline}
        
        Your specific task is to generate content for the #{section_title} section.
        This section's purpose is to: #{section_purpose}
        Section type: #{section_type}
        
        Guidelines for this section:
        #{generate_section_specific_guidelines(section_type)}
        
        Please generate compelling, conversion-focused content for this section.
        
        Return your response as a JSON object with the following format:
        {
          "title": "Section title (if needed)",
          "content": "HTML content for this section",
          "type": "#{section_type}"
        }
      PROMPT
    end
    
    def generate_section_specific_guidelines(section_type)
      case section_type
      when "hero"
        <<~GUIDELINES
          - Create an attention-grabbing opening
          - Reinforce the headline and subheadline
          - Include a clear call-to-action
          - Keep it concise and focused
        GUIDELINES
      when "features"
        <<~GUIDELINES
          - Highlight 3-5 key features or benefits
          - Use bullet points or short paragraphs
          - Focus on value to the user, not just technical details
          - Consider using a feature grid or cards format
          - Include relevant icons or visual cues
        GUIDELINES
      when "testimonial"
        <<~GUIDELINES
          - Create 1-3 realistic testimonials
          - Include name, position, and company for each testimonial
          - Focus on specific results or benefits experienced
          - Keep testimonials concise and authentic-sounding
          - Consider including a photo placeholder indication
        GUIDELINES
      when "cta"
        <<~GUIDELINES
          - Create a compelling call-to-action section
          - Include a strong, action-oriented button text
          - Add supporting text that reduces friction
          - Consider adding trust indicators (guarantees, security badges, etc.)
          - Make the value proposition clear and immediate
        GUIDELINES
      else
        <<~GUIDELINES
          - Ensure content is clear, concise, and compelling
          - Focus on benefits rather than features
          - Use action-oriented language
          - Maintain consistency with the overall page tone and message
          - Include appropriate HTML formatting
        GUIDELINES
      end
    end
    
    def generate_image_prompt_agent_prompt(plan, basic_instructions)
      design_considerations = plan["design_considerations"] || {}
      
      <<~PROMPT
        #{basic_instructions}
        
        Your specific task is to create image prompts for DALL-E to generate images for this landing page.
        
        Design Style: #{context[:design_style] || design_considerations["style"] || "Professional"}
        Imagery Guidelines: #{design_considerations["imagery"] || "Industry-related"}
        Color Scheme: Primary - #{context[:primary_color] || "#0d6efd"}, Secondary - #{context[:secondary_color] || "#6c757d"}
        
        Please create detailed, specific image prompts for:
        1. Hero section (main banner)
        2. Feature section illustrations (if applicable)
        3. Background or supporting imagery
        
        For each image prompt:
        - Be detailed about composition, style, colors, mood
        - Avoid requesting text in the images
        - Make them realistic and professional
        - Ensure they align with the business and landing page purpose
        
        Return your response as a JSON object with the following format:
        {
          "hero_image": "detailed prompt for hero image",
          "feature_images": ["prompt 1", "prompt 2", "prompt 3"],
          "background_image": "prompt for background image"
        }
      PROMPT
    end
    
    def generate_seo_prompt(plan, basic_instructions)
      headline = context[:headline] || plan["headline"] || "Main Headline"
      subheadline = context[:subheadline] || "Supporting subheadline"
      
      <<~PROMPT
        #{basic_instructions}
        
        Current Headline: #{headline}
        Current Subheadline: #{subheadline}
        
        Your specific task is to create SEO metadata for this landing page.
        
        Based on the landing page content and purpose, generate:
        1. A meta title (50-60 characters) that includes important keywords and drives clicks
        2. A meta description (150-160 characters) that summarizes the page value proposition
        3. Relevant meta keywords (5-8 keywords/phrases) that searchers might use to find this content
        
        Follow SEO best practices:
        - Include primary keywords in the title and description
        - Make the meta description compelling to increase CTR
        - Ensure keywords are relevant to the business and landing page
        
        Return your response as a JSON object with the following format:
        {
          "meta_title": "Your SEO title here",
          "meta_description": "Your meta description here",
          "meta_keywords": "keyword1, keyword2, keyword3"
        }
      PROMPT
    end
  end
end 