# frozen_string_literal: true

module Tools
  # Initiates an interactive module design session with the user
  # This enables a conversational flow for designing custom modules
  class StartModuleDesignTool < BaseTool
    def self.metadata
      {
        name: 'start_module_design',
        description: 'Start an interactive session to design a custom module with the user. ' \
                     'Use this when the user wants to build something custom and you need to ' \
                     'gather requirements before building. This begins a conversational design flow.',
        category: 'module_building',
        input_schema: {
          type: 'object',
          properties: {
            module_name: {
              type: 'string',
              description: 'Proposed name for the module (can be refined later)'
            },
            user_description: {
              type: 'string',
              description: "The user's description of what they want to build"
            },
            initial_questions: {
              type: 'array',
              items: { type: 'string' },
              description: 'Initial clarifying questions to ask the user'
            }
          },
          required: %w[module_name user_description]
        }
      }
    end

    def execute(args)
      log_execution(args)
      
      entity = @entity
      # Support both naming conventions (name/module_name, description/user_description)
      module_name = get_arg(args, :module_name) || get_arg(args, :name)
      user_description = get_arg(args, :user_description) || get_arg(args, :description) || ''
      initial_questions = get_arg(args, :initial_questions) || default_questions(user_description)
      
      # Validate we have the minimum required info
      if module_name.blank?
        return { success: false, error: "Module name is required. Please provide 'module_name' or 'name'." }
      end
      
      # Check for existing active session
      existing_session = ModuleDesignSession.active.for_entity(entity.id).first
      if existing_session
        return {
          success: false,
          message: "You already have an active design session for '#{existing_session.module_name}'. " \
                   "Would you like to continue with that, or cancel it to start fresh?",
          existing_session: existing_session.conversation_summary
        }
      end
      
      # Create new design session
      session = ModuleDesignSession.create!(
        entity: entity,
        status: 'gathering_requirements',
        module_name: module_name,
        user_description: user_description,
        conversation_context: {
          started_at: Time.current.iso8601,
          initial_description: user_description
        }
      )
      
      {
        success: true,
        session_id: session.id,
        message: "I've started a design session for '#{module_name}'. Let me ask a few questions to make sure I build exactly what you need:",
        questions: initial_questions,
        next_step: 'After the user answers, use propose_module_schema to suggest a data structure'
      }
    end
    
    private
    
    def default_questions(description)
      questions = []
      
      # Analyze description to generate relevant questions
      desc_lower = (description || '').downcase
      
      # Data structure questions
      questions << "What are the main items or records you want to track?"
      
      # Relationship questions
      if desc_lower.include?('contact') || desc_lower.include?('customer') || desc_lower.include?('client')
        questions << "Should each record be linked to a Contact?"
      else
        questions << "Do you need to connect this to Contacts, Campaigns, or other existing data?"
      end
      
      # Field-specific questions based on domain
      if desc_lower.include?('calendar') || desc_lower.include?('schedule')
        questions << "What date/time fields do you need? (e.g., scheduled date, due date, published date)"
      end
      
      if desc_lower.include?('social') || desc_lower.include?('post')
        questions << "Which social media platforms should this support?"
        questions << "Do you need to track engagement metrics (likes, comments, shares)?"
      end
      
      if desc_lower.include?('inventory') || desc_lower.include?('stock')
        questions << "Do you need to track quantities, costs, or reorder points?"
      end
      
      if desc_lower.include?('project') || desc_lower.include?('task')
        questions << "Do you need status tracking (e.g., To Do, In Progress, Done)?"
        questions << "Should tasks have assignees or due dates?"
      end
      
      # General questions
      questions << "What actions would you like to perform? (e.g., create, schedule, track, report)"
      
      questions.first(4) # Limit to 4 questions to not overwhelm
    end
  end
end
