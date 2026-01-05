# frozen_string_literal: true

module Tools
  # StartAppDesignTool - Initiates the app discovery and design process
  #
  # This tool is called when a user wants to build a new application.
  # It creates an App record in 'designing' status and begins the
  # discovery conversation to understand user needs.
  #
  class StartAppDesignTool < BaseTool
    def self.metadata
      {
        name: "start_app_design",
        description: "Start designing a new application. This begins a discovery conversation to understand what the user needs.",
        category: "app_building",
        input_schema: {
          type: "object",
          properties: {
            app_name: {
              type: "string",
              description: "The name of the app to create (e.g., 'Social Media Manager', 'Inventory Tracker')"
            },
            user_description: {
              type: "string",
              description: "The user's description of what they want the app to do"
            },
            app_type: {
              type: "string",
              description: "Optional: Type of app (e.g., 'content_management', 'tracking', 'workflow', 'analytics')"
            }
          },
          required: ["app_name", "user_description"]
        }
      }
    end
    
    def execute(args)
      log_execution(args)
      
      app_name = get_arg(args, :app_name)
      user_description = get_arg(args, :user_description)
      app_type = get_arg(args, :app_type)
      
      if error = validate_required_args(args, [:app_name, :user_description])
        return error
      end
      
      # Create the app in designing status
      app = App.create!(
        entity: entity,
        created_by: user,
        name: app_name,
        description: user_description,
        status: 'designing',
        intent: {
          user_description: user_description,
          app_type: app_type,
          started_at: Time.current.iso8601
        },
        metadata: {
          design_phase: 'discovery',
          conversation_history: []
        }
      )
      
      # Generate discovery questions based on the description
      discovery_questions = generate_discovery_questions(user_description, app_type)
      
      success_response(
        app_id: app.id,
        app_name: app.name,
        status: 'designing',
        phase: 'discovery',
        discovery_questions: discovery_questions,
        next_step: 'Ask the user these questions to understand their needs',
        message: <<~MSG
          I've started designing your **#{app_name}** app! 
          
          To make sure I build exactly what you need, I have some questions:
          
          #{format_questions(discovery_questions)}
          
          Take your time answering - the more detail you give me, the better I can design your app!
        MSG
      )
    rescue ActiveRecord::RecordInvalid => e
      error_response("Failed to create app: #{e.message}")
    end
    
    private
    
    def generate_discovery_questions(description, app_type)
      questions = []
      
      # Core questions for any app
      questions << {
        id: 'users',
        category: 'users',
        question: "Who will use this app? (Just you? A team? Clients?)",
        why: "This helps me design the right permissions and views"
      }
      
      questions << {
        id: 'workflow',
        category: 'workflow',
        question: "What's the typical workflow? (What steps happen from start to finish?)",
        why: "This helps me design the right stages and actions"
      }
      
      # Conditional questions based on description analysis
      if mentions_scheduling?(description)
        questions << {
          id: 'scheduling',
          category: 'features',
          question: "For scheduling - do you want automatic execution, or just tracking of when things should happen?",
          why: "This determines if we need automation capabilities"
        }
      end
      
      if mentions_approval?(description)
        questions << {
          id: 'approval',
          category: 'workflow',
          question: "For approvals - who needs to approve, and what happens if something is rejected?",
          why: "This helps design the approval workflow"
        }
      end
      
      if mentions_external_platforms?(description)
        questions << {
          id: 'integrations',
          category: 'integrations',
          question: "Do you want to connect to external platforms (like social media, email, etc.), or is this for internal tracking only?",
          why: "This determines if we need integrations"
        }
      end
      
      if mentions_analytics?(description)
        questions << {
          id: 'analytics',
          category: 'features',
          question: "What metrics or analytics are most important to track?",
          why: "This helps me design the right dashboards and reports"
        }
      end
      
      if mentions_team?(description)
        questions << {
          id: 'team_features',
          category: 'features',
          question: "Do team members need to be assigned to items? Should there be notifications when things change?",
          why: "This helps design collaboration features"
        }
      end
      
      # AI assistance question
      questions << {
        id: 'ai_help',
        category: 'features',
        question: "Would you like AI help within this app? (Like help writing content, analyzing data, or making suggestions?)",
        why: "I can add an AI assistant specifically trained for your app"
      }
      
      questions
    end
    
    def format_questions(questions)
      questions.map.with_index do |q, i|
        "**#{i + 1}. #{q[:question]}**"
      end.join("\n\n")
    end
    
    def mentions_scheduling?(text)
      keywords = %w[schedule calendar plan timing date when publish post]
      keywords.any? { |k| text.downcase.include?(k) }
    end
    
    def mentions_approval?(text)
      keywords = %w[approve approval review reject permission authorize sign-off]
      keywords.any? { |k| text.downcase.include?(k) }
    end
    
    def mentions_external_platforms?(text)
      keywords = %w[
        facebook linkedin instagram twitter social publish post 
        email send sync integrate api connect platform
      ]
      keywords.any? { |k| text.downcase.include?(k) }
    end
    
    def mentions_analytics?(text)
      keywords = %w[analytics metrics track measure report performance engagement roi]
      keywords.any? { |k| text.downcase.include?(k) }
    end
    
    def mentions_team?(text)
      keywords = %w[team member assign collaborate share permission role]
      keywords.any? { |k| text.downcase.include?(k) }
    end
  end
end
