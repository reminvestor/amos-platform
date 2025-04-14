module AiAgents
  class PlanningAgent < BaseAgent
    def execute
      log_execution_start
      Rails.logger.info("PlanningAgent: Starting planning process")
      
      # Extract relevant information from context
      topic = context[:topic]
      page_type = context[:page_type]
      entity = context[:entity]
      business_profile = context[:business_profile]
      
      Rails.logger.info("PlanningAgent: Planning for topic '#{topic}', page type '#{page_type}'")
      
      # Query vector store for relevant information
      Rails.logger.info("PlanningAgent: Querying vector store for relevant information")
      search_results = query_relevant_information(topic, page_type)
      Rails.logger.info("PlanningAgent: Retrieved #{search_results.size} relevant items from vector store")
      
      # Create a plan based on the information
      Rails.logger.info("PlanningAgent: Creating landing page plan")
      plan = create_plan(topic, page_type, entity, business_profile, search_results)
      
      # Validate and enhance the plan if needed
      plan = validate_and_enhance_plan(plan, topic)
      
      Rails.logger.info("PlanningAgent: Plan created with #{plan['sections']&.size || 0} sections")
      
      # Log detailed section information
      if plan['sections'].present?
        Rails.logger.info("PlanningAgent: Section details:")
        plan['sections'].each_with_index do |section, index|
          Rails.logger.info("  - Section #{index+1}: #{section['title']} (#{section['content_type']})")
          Rails.logger.info("    Purpose: #{section['purpose']}")
          if section['content_guidelines'].present?
            # Convert to string before truncating to handle both string and complex objects
            guidelines_str = section['content_guidelines'].is_a?(String) ? 
                             section['content_guidelines'] : 
                             section['content_guidelines'].to_s
            Rails.logger.info("    Guidelines: #{guidelines_str[0...100]}#{guidelines_str.length > 100 ? '...' : ''}")
          end
        end
      end
      
      # Update context with the plan
      # Ensure the landing_page_plan is stored in the context with the proper structure
      # This is what the Orchestrator expects to find
      context_update = {
        planning_completed: true,
        landing_page_plan: plan
      }
      
      # Add the plan to the context and log it
      Rails.logger.info("PlanningAgent: Adding plan to context with #{plan['sections']&.size || 0} sections")
      Rails.logger.info("PlanningAgent: Plan structure: #{plan.keys.join(', ')}")
      
      update_context(context_update)
      
      # Verify the plan was added to the context
      verified_plan = context[:landing_page_plan]
      if verified_plan.present?
        Rails.logger.info("PlanningAgent: Plan successfully added to context")
        Rails.logger.info("PlanningAgent: Verified plan has #{verified_plan['sections']&.size || 0} sections")
      else
        Rails.logger.error("PlanningAgent: Plan was not properly added to context")
      end
      
      # Log plan details
      Rails.logger.info("PlanningAgent: Plan summary:")
      Rails.logger.info("  - Page title: #{plan['page_title']}")
      Rails.logger.info("  - Headline: #{plan['headline']}")
      Rails.logger.info("  - Sections: #{plan['sections']&.size || 0}")
      Rails.logger.info("  - Design: #{plan['design_considerations']['color_scheme']} theme, #{plan['design_considerations']['tone']} tone")
      Rails.logger.info("  - Agents: #{plan['specialized_agents']&.join(', ')}")
      
      Rails.logger.info("PlanningAgent: Planning completed")
      log_execution_complete
      context
    end
    
    private
    
    def query_relevant_information(topic, page_type)
      # Create queries for the vector store based on the topic and page type
      queries = [
        "#{topic} landing page structure",
        "#{topic} #{page_type} page best practices",
        "#{topic} marketing copy",
        "#{topic} key benefits",
        "#{topic} visitor conversion strategies"
      ]
      
      # Query the vector store for each query and collect the results
      results = []
      queries.each_with_index do |query, index|
        Rails.logger.info("PlanningAgent: Executing vector search #{index+1}/#{queries.size}: '#{query}'")
        query_results = query_vector_store(query)
        Rails.logger.info("PlanningAgent: Query '#{query}' returned #{query_results.size} results")
        results.concat(query_results)
      end
      
      # Remove duplicates
      unique_results = results.uniq { |r| r[0] }
      Rails.logger.info("PlanningAgent: After deduplication, retrieved #{unique_results.size} unique items")
      
      unique_results
    end
    
    def create_plan(topic, page_type, entity, business_profile, search_results)
      # Format the search results for inclusion in the prompt
      Rails.logger.info("PlanningAgent: Formatting search results for inclusion in prompt")
      formatted_results = search_results.map.with_index do |(text, similarity, metadata), index|
        "Source #{index + 1}: [#{metadata[:title] || 'Untitled'}]\n#{text}\n"
      end.join("\n")
      
      Rails.logger.info("PlanningAgent: Creating prompt for landing page plan generation")
      # Create a prompt for the planning agent
      prompt = <<~PROMPT
        I need to create a detailed plan for a landing page about "#{topic}" for a business with the following profile:
        
        Business Name: #{business_profile&.name || entity&.name || 'Unknown'}
        Industry: #{business_profile&.industry || 'Unknown'}
        Description: #{business_profile&.description || 'Unknown'}
        Page Type: #{page_type || 'lead_generation'}
        
        Based on research, here is relevant information:
        
        #{formatted_results}
        
        Please create a detailed landing page plan that includes:
        
        1. Overall structure (sections of the page)
        2. Recommended content for each section with specific guidelines
        3. Required specialized agents to execute this plan
        4. Design considerations
        5. Conversion strategy
        
        For each section, please include:
        - title: The section title
        - purpose: What this section should accomplish
        - content_type: The type of content (hero, features, testimonials, cta, etc.)
        - content_guidelines: Specific suggestions for what should be included
        
        Format your response as a structured JSON object with the following keys:
        - page_title: String with the recommended page title
        - headline: String with the main headline
        - sections: Array of section objects with title, purpose, content_type, and content_guidelines
        - design_considerations: Object with color scheme, tone, imagery guidelines
        - specialized_agents: Array of required agent types (content, headline, design, image_prompt, seo)
        - conversion_strategy: Object describing the conversion approach
        
        IMPORTANT: Each section must have a clear content_type and useful content_guidelines to help generate the actual content.
      PROMPT
      
      Rails.logger.info("PlanningAgent: Calling OpenAI for plan generation")
      start_time = Time.current
      response = call_openai_api(prompt, "gpt-4o", 0.7, 4000)
      generation_time = Time.current - start_time
      Rails.logger.info("PlanningAgent: Received response in #{generation_time.round(2)}s")
      
      begin
        # Find JSON object in the response
        json_match = response.match(/\{.*\}/m)
        unless json_match
          Rails.logger.warn("PlanningAgent: No JSON object found in response")
          # Safely handle the response which might not be a string
          response_str = response.is_a?(String) ? response : response.to_s
          Rails.logger.debug("PlanningAgent: Raw response: #{response_str[0...300]}#{response_str.length > 300 ? '...' : ''}")
          return fallback_plan(topic)
        end
        
        plan = JSON.parse(json_match[0])
        Rails.logger.info("PlanningAgent: Successfully parsed plan JSON")
        plan
      rescue JSON::ParserError => e
        Rails.logger.error("PlanningAgent: Error parsing plan: #{e.message}")
        Rails.logger.error(e.backtrace.join("\n"))
        # Safely handle the response which might not be a string
        response_str = response.is_a?(String) ? response : response.to_s
        Rails.logger.debug("PlanningAgent: Problematic response: #{response_str[0...300]}#{response_str.length > 300 ? '...' : ''}")
        # Return a minimal plan structure if parsing fails
        fallback_plan(topic)
      end
    end
    
    def validate_and_enhance_plan(plan, topic)
      # Ensure all required keys exist
      Rails.logger.info("PlanningAgent: Validating and enhancing the generated plan")
      
      # Add missing top-level keys
      plan['page_title'] ||= "#{topic} Landing Page"
      plan['headline'] ||= "Discover #{topic}"
      plan['specialized_agents'] ||= ["content", "headline", "design", "image_prompt", "seo"]
      
      # Ensure design considerations exist
      plan['design_considerations'] ||= {
        "color_scheme" => "Professional",
        "tone" => "Informative",
        "imagery" => "Industry-related"
      }
      
      # Ensure conversion strategy exists
      plan['conversion_strategy'] ||= {
        "primary_cta" => "Sign Up",
        "secondary_cta" => "Learn More",
        "value_proposition" => "Save time and increase results with our solution"
      }
      
      # Ensure sections exist and have required fields
      if plan['sections'].nil? || plan['sections'].empty?
        Rails.logger.warn("PlanningAgent: No sections found in plan, adding default sections")
        plan['sections'] = default_sections(topic)
      else
        # Validate each section
        plan['sections'].each_with_index do |section, index|
          # Add section index if missing
          section['section_index'] = index
          
          # Ensure required fields exist
          section['title'] ||= "Section #{index + 1}"
          section['purpose'] ||= "Provide information about #{topic}"
          section['content_type'] ||= default_content_type_for_index(index)
          
          # Add content guidelines if missing
          if section['content_guidelines'].nil? || section['content_guidelines'].empty?
            section['content_guidelines'] = "Create compelling content about #{topic} that focuses on the #{section['purpose']}"
          end
          
          Rails.logger.debug("PlanningAgent: Validated section #{index+1}: #{section['title']}")
        end
      end
      
      Rails.logger.info("PlanningAgent: Plan validation complete, #{plan['sections'].size} sections processed")
      plan
    end
    
    def default_content_type_for_index(index)
      case index
      when 0 then "hero"
      when 1 then "features"
      when 2 then "testimonials"
      else "text"
      end
    end
    
    def default_sections(topic)
      [
        {
          "title" => "Hero",
          "purpose" => "Grab attention and introduce the value proposition",
          "content_type" => "hero",
          "content_guidelines" => "Create a compelling headline and subheadline that clearly communicates the value of #{topic}. Include a brief description and a strong call-to-action.",
          "section_index" => 0
        },
        {
          "title" => "Features & Benefits",
          "purpose" => "Explain the key features and benefits",
          "content_type" => "features",
          "content_guidelines" => "List 3-5 key features of #{topic} with benefit-focused descriptions. Use icons or images to make each feature stand out.",
          "section_index" => 1
        },
        {
          "title" => "Social Proof",
          "purpose" => "Build trust through testimonials",
          "content_type" => "testimonials",
          "content_guidelines" => "Include 2-3 testimonials or case studies that highlight success with #{topic}. Use real names and specific results when possible.",
          "section_index" => 2
        },
        {
          "title" => "Call to Action",
          "purpose" => "Convert visitors into leads",
          "content_type" => "cta",
          "content_guidelines" => "Create a compelling final call-to-action that summarizes the value proposition and encourages immediate action.",
          "section_index" => 3
        }
      ]
    end
    
    def fallback_plan(topic)
      Rails.logger.info("PlanningAgent: Using fallback plan for topic: #{topic}")
      {
        "page_title" => "#{topic} Landing Page",
        "headline" => "Discover the Power of #{topic}",
        "sections" => default_sections(topic),
        "design_considerations" => {
          "color_scheme" => "Professional",
          "tone" => "Informative",
          "imagery" => "Industry-related"
        },
        "specialized_agents" => ["content", "headline", "design", "image_prompt", "seo"],
        "conversion_strategy" => {
          "primary_cta" => "Get Started Now",
          "secondary_cta" => "Learn More",
          "value_proposition" => "Save time and increase results with our #{topic} solution"
        }
      }
    end
  end
end 