module AiAgents
  class Orchestrator
    attr_reader :context
    
    def initialize(initial_context = {})
      @context = initial_context
      @executed_agents = []
      Rails.logger.info("="*100)
      Rails.logger.info("ORCHESTRATOR: Initialized")
      Rails.logger.info("="*100)
    end
    
    def generate_landing_page(topic, entity, business_profile, page_type = 'lead_generation')
      start_time = Time.current
      Rails.logger.info("="*100)
      Rails.logger.info("ORCHESTRATOR: Starting landing page generation for topic: #{topic}")
      Rails.logger.info("ORCHESTRATOR: Entity: #{entity.name} (ID: #{entity.id})")
      Rails.logger.info("ORCHESTRATOR: Business profile: #{business_profile&.name || 'None'}")
      Rails.logger.info("ORCHESTRATOR: Page type: #{page_type}")
      Rails.logger.info("="*100)
      
      # Set up initial context
      @context = {
        topic: topic,
        entity: entity,
        business_profile: business_profile,
        page_type: page_type,
        start_time: start_time
      }
      
      # Step 1: Web Search & Info Gathering
      Rails.logger.info("ORCHESTRATOR: STEP 1 - Starting Web Search & Info Gathering")
      execute_agent(WebSearchAgent)
      Rails.logger.info("ORCHESTRATOR: STEP 1 - Completed Web Search with #{@context[:search_results_count] || 0} results")
      
      # Step 2: Planning
      Rails.logger.info("ORCHESTRATOR: STEP 2 - Starting Planning")
      execute_agent(PlanningAgent)
      Rails.logger.info("ORCHESTRATOR: STEP 2 - Completed Planning with #{@context[:landing_page_plan]&.dig('sections')&.size || 0} sections")
      
      # Step 3: Coordination
      Rails.logger.info("ORCHESTRATOR: STEP 3 - Starting Coordination")
      execute_agent(CoordinationAgent)
      Rails.logger.info("ORCHESTRATOR: STEP 3 - Completed Coordination with #{@context[:agent_workflow]&.size || 0} tasks")
      
      # Step 4: Prompt Generation
      Rails.logger.info("ORCHESTRATOR: STEP 4 - Starting Prompt Generation")
      execute_agent(PromptAgent)
      Rails.logger.info("ORCHESTRATOR: STEP 4 - Completed Prompt Generation with prompts for #{@context[:agent_prompts]&.keys&.size || 0} agent types")
      
      # Step 5: Execute specialized agents based on the workflow
      Rails.logger.info("ORCHESTRATOR: STEP 5 - Starting Specialized Agent Execution")
      execute_workflow
      Rails.logger.info("ORCHESTRATOR: STEP 5 - Completed Specialized Agent Execution")
      
      # Step 6: Build the final landing page model from the context
      Rails.logger.info("ORCHESTRATOR: STEP 6 - Building final landing page model")
      landing_page = build_landing_page
      
      duration = Time.current - start_time
      Rails.logger.info("="*100)
      Rails.logger.info("ORCHESTRATOR: Landing page generation completed in #{duration.round(2)} seconds")
      Rails.logger.info("ORCHESTRATOR: Generated landing page with title: #{landing_page.title}")
      Rails.logger.info("ORCHESTRATOR: Content sections: #{landing_page.content&.size || 0}")
      Rails.logger.info("="*100)
      
      landing_page
    end
    
    private
    
    def execute_agent(agent_class)
      agent_name = agent_class.name.demodulize
      Rails.logger.info("ORCHESTRATOR: Executing agent: #{agent_name}")
      
      # Skip if this agent has already been executed
      if @executed_agents.include?(agent_class)
        Rails.logger.info("ORCHESTRATOR: Agent #{agent_name} has already been executed, skipping")
        return
      end
      
      start_time = Time.current
      
      # Instantiate and execute the agent
      agent = agent_class.new(@context)
      result = agent.execute
      
      # Special case for PlanningAgent to ensure the landing_page_plan is properly transferred
      if agent_class == PlanningAgent
        Rails.logger.info("ORCHESTRATOR: PlanningAgent execution completed, checking for landing_page_plan")
        
        # The result from the agent is the updated context
        if result.is_a?(Hash) && result[:landing_page_plan].present?
          Rails.logger.info("ORCHESTRATOR: Found landing_page_plan in agent result with #{result[:landing_page_plan]['sections']&.size || 0} sections")
          @context[:landing_page_plan] = result[:landing_page_plan]
        else
          Rails.logger.error("ORCHESTRATOR: No landing_page_plan found in agent result")
          # Let's look for it in the agent's context directly
          if agent.context.is_a?(Hash) && agent.context[:landing_page_plan].present?
            Rails.logger.info("ORCHESTRATOR: Found landing_page_plan in agent context with #{agent.context[:landing_page_plan]['sections']&.size || 0} sections")
            @context[:landing_page_plan] = agent.context[:landing_page_plan]
          else
            Rails.logger.error("ORCHESTRATOR: Landing page plan not found in agent context either")
          end
        end
        
        # Debug log the context after PlanningAgent
        Rails.logger.info("ORCHESTRATOR: Context keys after PlanningAgent: #{@context.keys.join(', ')}")
        if @context[:landing_page_plan]
          Rails.logger.info("ORCHESTRATOR: Context includes landing_page_plan with sections: #{@context[:landing_page_plan]['sections']&.size || 0}")
        end
      else
        # For other agents, just update our context with theirs
        @context = result
      end
      
      duration = Time.current - start_time
      Rails.logger.info("ORCHESTRATOR: Agent #{agent_name} execution completed in #{duration.round(2)} seconds")
      
      # Record that this agent has been executed
      @executed_agents << agent_class
    end
    
    def execute_workflow
      # Get the workflow from the context
      workflow = @context[:agent_workflow] || []
      
      if workflow.empty?
        Rails.logger.error("ORCHESTRATOR: No workflow found in context")
        return
      end
      
      Rails.logger.info("ORCHESTRATOR: Preparing to execute workflow with #{workflow.size} tasks")
      
      # Map agent types to agent classes
      agent_class_mapping = {
        "headline" => HeadlineAgent,
        "design" => DesignAgent,
        "content" => ContentAgent,
        "image_prompt" => ImagePromptAgent,
        "seo" => SeoAgent,
        "hero" => ContentAgent,
        "feature" => ContentAgent,
        "testimonial" => ContentAgent,
        "cta" => ContentAgent
      }
      
      # Sort tasks by dependencies (topological sort)
      executed_tasks = []
      remaining_tasks = workflow.dup
      
      execution_round = 0
      
      # Execute tasks until none remain or we can't make progress
      while remaining_tasks.any?
        execution_round += 1
        Rails.logger.info("ORCHESTRATOR: Workflow execution round #{execution_round}")
        Rails.logger.info("ORCHESTRATOR: #{remaining_tasks.size} tasks remaining")
        
        tasks_executed_in_round = 0
        
        remaining_tasks.dup.each do |task|
          agent_type = task[:agent_type]
          agent_task = task[:task]
          
          # Check if all dependencies have been executed
          dependencies_satisfied = task[:dependencies].all? do |dep|
            executed_tasks.any? { |et| et[:agent_type] == dep }
          end
          
          if dependencies_satisfied
            Rails.logger.info("ORCHESTRATOR: Task '#{agent_task}' (Agent: #{agent_type}) is ready to execute")
            Rails.logger.info("ORCHESTRATOR: Dependencies satisfied: #{task[:dependencies].join(', ')}")
          else
            Rails.logger.info("ORCHESTRATOR: Task '#{agent_task}' (Agent: #{agent_type}) has unsatisfied dependencies: #{task[:dependencies].join(', ')}")
            next
          end
          
          # Execute the task if dependencies are satisfied
          agent_class = agent_class_mapping[agent_type]
          
          if agent_class
            Rails.logger.info("ORCHESTRATOR: Executing agent #{agent_class.name.demodulize} for task: #{agent_task}")
            execute_agent(agent_class)
            executed_tasks << task
            remaining_tasks.delete(task)
            tasks_executed_in_round += 1
          else
            Rails.logger.warn("ORCHESTRATOR: No agent class found for type: #{agent_type}")
            remaining_tasks.delete(task)
            tasks_executed_in_round += 1
          end
        end
        
        # Break if we're stuck (couldn't execute any tasks in this round)
        if tasks_executed_in_round == 0
          Rails.logger.warn("ORCHESTRATOR: No tasks could be executed in this round, breaking workflow execution")
          break
        else
          Rails.logger.info("ORCHESTRATOR: Executed #{tasks_executed_in_round} tasks in round #{execution_round}")
        end
      end
      
      if remaining_tasks.any?
        Rails.logger.warn("ORCHESTRATOR: Some tasks could not be executed due to unsatisfied dependencies")
        remaining_tasks.each do |task|
          Rails.logger.warn("ORCHESTRATOR: - Unexecuted task: #{task[:task]} (Agent: #{task[:agent_type]})")
          Rails.logger.warn("ORCHESTRATOR:   Dependencies: #{task[:dependencies].join(', ')}")
        end
      else
        Rails.logger.info("ORCHESTRATOR: All workflow tasks completed successfully")
      end
    end
    
    def build_landing_page
      Rails.logger.info("ORCHESTRATOR: Building landing page model from context")
      
      # Create a landing page model from the context
      landing_page = LandingPage.new(
        title: @context[:landing_page_plan]&.dig("page_title") || "Landing Page: #{@context[:topic]}",
        headline: @context[:headline],
        subheadline: @context[:subheadline],
        primary_color: @context[:primary_color],
        secondary_color: @context[:secondary_color],
        font_family: @context[:font_family],
        meta_description: @context[:meta_description],
        meta_keywords: @context[:meta_keywords],
        user_id: find_appropriate_user_id,
        entity_id: @context[:entity]&.id,
        status: 'draft',
        page_type: @context[:page_type],
        cta_text: @context[:landing_page_plan]&.dig("conversion_strategy", "primary_cta") || "Sign Up Now",
        cta_url: "#form",
        ai_settings: {
          generated_at: Time.current,
          generation_time: @context[:start_time] ? (Time.current - @context[:start_time]).to_i : 0,
          model: "multi-agent-system",
          topic: @context[:topic],
          original_plan: @context[:landing_page_plan]
        }
      )
      
      # Build content based on generated sections
      sections = @context[:generated_sections] || []
      
      if sections.empty?
        Rails.logger.warn("ORCHESTRATOR: No generated sections found in context. Checking for raw plan sections.")
        
        # Fall back to using the raw sections from the plan
        if @context[:landing_page_plan] && @context[:landing_page_plan]['sections'].present?
          Rails.logger.info("ORCHESTRATOR: Using sections from landing page plan as fallback")
          
          # Convert plan sections to content format
          raw_sections = @context[:landing_page_plan]['sections']
          sections = raw_sections.map.with_index do |section, index|
            {
              section_index: section['section_index'] || index,
              title: section['title'],
              content: section['content_guidelines'] || section['purpose'],
              type: section['content_type'] || 'text'
            }
          end
          
          Rails.logger.info("ORCHESTRATOR: Created #{sections.size} fallback sections")
        else
          Rails.logger.error("ORCHESTRATOR: No sections found in plan or generated content")
          # Create a minimal default section
          sections = [
            {
              section_index: 0,
              title: "About #{@context[:topic]}",
              content: "Information about #{@context[:topic]}.",
              type: "text"
            }
          ]
          Rails.logger.info("ORCHESTRATOR: Created 1 default section as fallback")
        end
      end
      
      content = []
      
      Rails.logger.info("ORCHESTRATOR: Processing #{sections.size} content sections")
      
      # Sort sections by their original index in the plan
      sections.sort_by { |s| s[:section_index] }.each_with_index do |section, index|
        Rails.logger.info("ORCHESTRATOR: Adding section #{index+1}: #{section[:title]} (Type: #{section[:type]})")
        
        # Ensure section has valid content
        if section[:content].blank?
          Rails.logger.warn("ORCHESTRATOR: Section #{index+1} has no content, adding placeholder")
          section[:content] = "Content for #{section[:title]}"
        end
        
        content << {
          title: section[:title],
          content: section[:content],
          type: section[:type]
        }
        
        Rails.logger.debug("ORCHESTRATOR: Section #{index+1} content length: #{section[:content].to_s.size} characters")
      end
      
      landing_page.content = content
      
      # If we have image prompts, store them
      if @context[:image_prompts].present?
        Rails.logger.info("ORCHESTRATOR: Adding image prompts to landing page")
        landing_page.image_prompts = @context[:image_prompts]
        
        if @context[:image_prompts]['hero_image'].present?
          Rails.logger.info("ORCHESTRATOR: Hero image prompt: #{@context[:image_prompts]['hero_image'].truncate(100)}")
        end
        
        if @context[:image_prompts]['feature_images'].present?
          Rails.logger.info("ORCHESTRATOR: #{@context[:image_prompts]['feature_images'].size} feature image prompts included")
        end
      end
      
      Rails.logger.info("ORCHESTRATOR: Landing page model creation complete with #{content.size} sections")
      landing_page
    end
    
    def find_appropriate_user_id
      if @context[:entity]&.owner&.id
        Rails.logger.info("ORCHESTRATOR: Using entity owner's user ID for landing page")
        @context[:entity].owner.id
      else
        # Try to find an admin user
        admin_user = User.where(role: 'admin').first
        if admin_user
          Rails.logger.info("ORCHESTRATOR: Using admin user ID for landing page")
          admin_user.id
        else
          # Fallback to the first user in the system
          first_user = User.first
          if first_user
            Rails.logger.info("ORCHESTRATOR: Using first available user ID for landing page")
            first_user.id
          else
            Rails.logger.error("ORCHESTRATOR: No users found in the system")
            raise "No users available to assign as owner of the landing page"
          end
        end
      end
    end
  end
end 