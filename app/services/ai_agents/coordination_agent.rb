module AiAgents
  class CoordinationAgent < BaseAgent
    def execute
      log_execution_start
      Rails.logger.info("CoordinationAgent: Starting coordination process")

      # Extract the plan from the context
      plan = context[:landing_page_plan]

      if plan.nil? || plan.empty?
        Rails.logger.error("CoordinationAgent: No plan found in context")
        return context
      end

      Rails.logger.info("CoordinationAgent: Using plan with title '#{plan['page_title']}'")

      # Extract the specialized agents required from the plan
      required_agents = plan["specialized_agents"] || []
      Rails.logger.info("CoordinationAgent: Plan requires agents: #{required_agents.join(', ')}")

      # Determine available agents to dispatch
      Rails.logger.info("CoordinationAgent: Determining available agents")
      available_agents = determine_available_agents(required_agents)
      Rails.logger.info("CoordinationAgent: Available agents: #{available_agents.join(', ')}")

      # Create a workflow plan for agent execution
      Rails.logger.info("CoordinationAgent: Creating workflow plan")
      workflow = create_workflow_plan(available_agents, plan)
      Rails.logger.info("CoordinationAgent: Created workflow with #{workflow.length} tasks")

      # Log workflow details
      workflow.each_with_index do |task, index|
        Rails.logger.info("CoordinationAgent: Task #{index+1}: #{task[:task]} (Agent: #{task[:agent_type]})")
        Rails.logger.info("  - Dependencies: #{task[:dependencies].empty? ? 'None' : task[:dependencies].join(', ')}")
        Rails.logger.info("  - Input keys: #{task[:input_keys].join(', ')}")
        Rails.logger.info("  - Output keys: #{task[:output_keys].join(', ')}")
      end

      # Update context with workflow
      update_context({
        coordination_completed: true,
        agent_workflow: workflow
      })

      Rails.logger.info("CoordinationAgent: Coordination completed with #{workflow.length} tasks")
      log_execution_complete
      context
    end

    private

    def determine_available_agents(required_agents)
      Rails.logger.info("CoordinationAgent: Mapping required agent types to concrete classes")
      # Map the required agent types to their corresponding agent classes
      agent_class_mapping = {
        "content" => "ContentAgent",
        "headline" => "HeadlineAgent",
        "design" => "DesignAgent",
        "image_prompt" => "ImagePromptAgent",
        "seo" => "SEOAgent",
        "feature" => "FeatureSectionAgent",
        "testimonial" => "TestimonialSectionAgent",
        "cta" => "CTAAgent",
        "hero" => "HeroSectionAgent"
      }

      # Filter to only include agents that we have implementations for
      available_agents = []

      required_agents.each do |agent_type|
        agent_class = agent_class_mapping[agent_type]
        if agent_class && AiAgents.const_defined?(agent_class)
          Rails.logger.info("CoordinationAgent: Agent type '#{agent_type}' maps to existing class #{agent_class}")
          available_agents << agent_type
        else
          Rails.logger.warn("CoordinationAgent: Required agent type '#{agent_type}' is not available or has no class mapping")
        end
      end

      # Add default required agents if not already included
      default_agents = [ "content", "headline", "design", "seo" ]
      default_agents.each do |agent_type|
        unless available_agents.include?(agent_type) || !agent_class_mapping.key?(agent_type)
          agent_class = agent_class_mapping[agent_type]
          if AiAgents.const_defined?(agent_class)
            Rails.logger.info("CoordinationAgent: Adding default agent '#{agent_type}' (#{agent_class})")
            available_agents << agent_type
          end
        end
      end

      Rails.logger.info("CoordinationAgent: Final list of available agents: #{available_agents.uniq.join(', ')}")
      available_agents.uniq
    end

    def create_workflow_plan(available_agents, plan)
      Rails.logger.info("CoordinationAgent: Building workflow with dependencies")
      # Create a workflow with dependencies between agents
      workflow = []

      # Add workflow steps in the appropriate order with dependencies

      # 1. Start with high-level planning tasks
      if available_agents.include?("headline")
        Rails.logger.info("CoordinationAgent: Adding headline generation task")
        workflow << {
          agent_type: "headline",
          task: "Generate headline and subheadline",
          dependencies: [],
          input_keys: [ :landing_page_plan ],
          output_keys: [ :headline, :subheadline ]
        }
      end

      if available_agents.include?("design")
        Rails.logger.info("CoordinationAgent: Adding design recommendations task")
        workflow << {
          agent_type: "design",
          task: "Generate design recommendations",
          dependencies: [],
          input_keys: [ :landing_page_plan ],
          output_keys: [ :primary_color, :secondary_color, :font_family, :design_style ]
        }
      end

      # 2. Add content generation tasks based on sections in the plan
      section_agents = {
        "hero" => "hero",
        "features" => "feature",
        "testimonials" => "testimonial",
        "cta" => "cta"
      }

      Rails.logger.info("CoordinationAgent: Adding content generation tasks for #{plan['sections']&.size || 0} sections")

      plan["sections"].each_with_index do |section, index|
        section_type = section["content_type"].to_s
        agent_type = section_agents[section_type] || "content"

        if available_agents.include?(agent_type)
          Rails.logger.info("CoordinationAgent: Adding task for #{section['title']} section (type: #{section_type}, agent: #{agent_type})")
          workflow << {
            agent_type: agent_type,
            task: "Generate content for #{section['title']} section",
            dependencies: [ "headline" ].select { |dep| available_agents.include?(dep) },
            input_keys: [ :landing_page_plan, :headline, :subheadline, :design_style ],
            output_keys: [ "section_content_#{index}".to_sym ],
            section_index: index,
            section_data: section
          }
        else
          Rails.logger.warn("CoordinationAgent: No available agent for section type '#{section_type}', using general content agent")
          if available_agents.include?("content")
            workflow << {
              agent_type: "content",
              task: "Generate content for #{section['title']} section",
              dependencies: [ "headline" ].select { |dep| available_agents.include?(dep) },
              input_keys: [ :landing_page_plan, :headline, :subheadline, :design_style ],
              output_keys: [ "section_content_#{index}".to_sym ],
              section_index: index,
              section_data: section
            }
          else
            Rails.logger.error("CoordinationAgent: Cannot create content task for section '#{section['title']}' - no content agent available")
          end
        end
      end

      # 3. Add image generation prompts after design is completed
      if available_agents.include?("image_prompt")
        Rails.logger.info("CoordinationAgent: Adding image prompt generation task")
        workflow << {
          agent_type: "image_prompt",
          task: "Generate image prompts",
          dependencies: [ "design" ].select { |dep| available_agents.include?(dep) },
          input_keys: [ :landing_page_plan, :design_style ],
          output_keys: [ :image_prompts ]
        }
      end

      # 4. Add SEO optimization at the end
      if available_agents.include?("seo")
        Rails.logger.info("CoordinationAgent: Adding SEO metadata generation task")
        workflow << {
          agent_type: "seo",
          task: "Generate SEO metadata",
          dependencies: [ "headline", "content" ].select { |dep| available_agents.include?(dep) },
          input_keys: [ :landing_page_plan, :headline, :subheadline ],
          output_keys: [ :meta_title, :meta_description, :meta_keywords ]
        }
      end

      Rails.logger.info("CoordinationAgent: Final workflow contains #{workflow.size} tasks")
      workflow
    end
  end
end
