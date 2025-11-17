# General purpose agent that handles complex tasks using Scout tools
module AgentJobs
  class GeneralAgentJob < BaseAgentJob
    
    def execute_agent_task
      Rails.logger.info "[GeneralAgent] Processing: #{@task}"
      
      # Stream initial acknowledgment
      stream_content("I'll help you with that. Let me process your request...")
      
      update_status('running', 'Analyzing request...', progress: 20)
      
      # Initialize the Scout tools service with full capabilities
      scout_service = initialize_scout_service
      
      # Process the task using Scout's comprehensive toolset
      process_with_scout_tools(scout_service)
    end
    
    private
    
    def initialize_scout_service
      # Load conversation history from context
      conversation_history = load_conversation_history
      
      # Create agent loadout with appropriate tools for the task
      agent_loadout = create_agent_loadout
      
      # Get user and entity from context
      user = User.find(@context[:user_id])
      entity = Entity.find(@context[:entity_id])
      
      # Initialize Scout service
      ScoutGenericToolsServiceV2.new(
        user,
        entity,
        @context[:session_id],
        agent_loadout: agent_loadout
      )
    end
    
    def create_agent_loadout
      # Analyze task to determine which tools might be needed
      task_lower = @task.downcase
      
      # Start with general tools
      tools = ['web_search', 'generate_content', 'update_object', 'fetch_object']
      
      # Add specific tools based on task content
      if task_lower.match?(/analyz|report|metric|data/i)
        tools += ['generate_analytics_report', 'query_rag_store']
      end
      
      if task_lower.match?(/landing.*page|website|web.*page/i)
        tools += ['create_landing_page', 'update_landing_page_content', 'get_landing_page']
      end
      
      if task_lower.match?(/contact|lead|customer/i)
        tools += ['create_contact', 'get_contacts', 'update_contact']
      end
      
      if task_lower.match?(/email|campaign|send|newsletter/i)
        tools += ['create_contact_for_email_capture', 'create_email_template']
      end
      
      if task_lower.match?(/document|file|pdf/i)
        tools += ['read_document', 'generate_document']
      end
      
      if task_lower.match?(/image|picture|photo|visual/i)
        tools += ['generate_image', 'edit_image']
      end
      
      # Create loadout with selected tools
      AgentLoadout.new(
        agent_role: "general_assistant",
        tools: tools,
        model_preference: @context[:metadata][:model_preference] || 'claude-sonnet-4-5'
      )
    end
    
    def load_conversation_history
      # Get recent messages from the session
      messages = @context[:recent_messages] || []
      
      # Ensure proper format for Scout service
      messages.map do |msg|
        {
          role: msg[:role] || 'user',
          content: msg[:content],
          timestamp: msg[:timestamp]
        }
      end
    end
    
    def process_with_scout_tools(scout_service)
      update_status('running', 'Processing with specialized tools...', progress: 40)
      
      # Set up streaming callback
      scout_service.on_stream do |chunk|
        handle_scout_stream(chunk)
      end
      
      begin
        # Process the message with tools
        result = scout_service.process_message_with_tools_streaming(
          @task,
          load_conversation_history,
          nil # No specific canvas context
        )
        
        # Handle the result
        handle_scout_result(result)
        
      rescue => e
        Rails.logger.error "[GeneralAgent] Scout processing error: #{e.message}"
        Rails.logger.error e.backtrace.join("\n")
        
        stream_content(
          "I encountered an issue while processing your request. " +
          "Let me try a different approach..."
        )
        
        # Fallback to simpler processing
        fallback_processing
      end
    end
    
    def handle_scout_stream(chunk)
      case chunk[:type]
      when 'content'
        # Stream content to user
        stream_content(chunk[:content])
        
      when 'tool_use'
        # Update status with tool usage
        tool_name = chunk[:tool_name]
        update_status('running', "Using tool: #{format_tool_name(tool_name)}...", progress: 60)
        
      when 'tool_result'
        # Log tool results but don't stream raw results
        Rails.logger.info "[GeneralAgent] Tool result: #{chunk[:tool_name]} completed"
        
      when 'final_response'
        # Handle final response
        update_status('running', 'Finalizing response...', progress: 90)
        
        # Stream final content if not already streamed
        if chunk[:message] && !chunk[:already_streamed]
          stream_content(chunk[:message])
        end
        
      when 'error'
        # Handle errors gracefully
        Rails.logger.error "[GeneralAgent] Stream error: #{chunk[:error]}"
        stream_content("I encountered an issue: #{chunk[:error]}")
        
      when 'canvas_update'
        # Handle canvas updates (if any)
        broadcast_canvas_update(chunk[:canvas], chunk[:canvas_data])
      end
    end
    
    def handle_scout_result(result)
      if result[:success]
        # Extract key information from result
        tools_used = result[:tools_used] || []
        canvas_type = result[:canvas_type]
        canvas_data = result[:canvas_data]
        
        # Log tools used
        if tools_used.any?
          Rails.logger.info "[GeneralAgent] Tools used: #{tools_used.join(', ')}"
        end
        
        # Handle canvas updates if present
        if canvas_type && canvas_type != 'conversation'
          broadcast_canvas_update(canvas_type, canvas_data)
        end
        
        # Return success
        {
          success: true,
          tools_used: tools_used,
          canvas_type: canvas_type,
          message: "Task completed successfully"
        }
      else
        # Handle failure
        error_message = result[:error] || "Unknown error occurred"
        Rails.logger.error "[GeneralAgent] Task failed: #{error_message}"
        
        {
          success: false,
          error: error_message,
          message: "Task could not be completed"
        }
      end
    end
    
    def broadcast_canvas_update(canvas_type, canvas_data)
      # Notify Amos to update the UI with canvas data
      stream_to_amos({
        type: 'canvas_update',
        canvas: canvas_type,
        canvas_data: canvas_data
      })
    end
    
    def format_tool_name(tool_name)
      # Make tool names user-friendly
      case tool_name
      when 'web_search'
        'Searching the web'
      when 'generate_content'
        'Generating content'
      when 'query_rag_store'
        'Searching knowledge base'
      when 'create_landing_page'
        'Creating landing page'
      when 'generate_analytics_report'
        'Generating analytics'
      when 'read_document'
        'Reading document'
      else
        tool_name.humanize
      end
    end
    
    def fallback_processing
      # Simple fallback when Scout tools fail
      update_status('running', 'Using alternative approach...', progress: 70)
      
      # Try to provide helpful guidance based on task
      guidance = generate_task_guidance(@task)
      
      stream_content(guidance)
      
      {
        success: true,
        message: "Provided guidance for the task",
        fallback: true
      }
    end
    
    def generate_task_guidance(task)
      task_lower = task.downcase
      
      case task_lower
      when /how.*to|explain|what.*is/i
        "I'll explain that for you:\n\n" +
        "This is a complex topic that typically involves:\n" +
        "1. Understanding the basic concepts\n" +
        "2. Learning the key components\n" +
        "3. Applying best practices\n\n" +
        "Would you like me to break this down further?"
        
      when /create|build|make|generate/i
        "To create this, you'll typically need to:\n\n" +
        "1. Define your requirements\n" +
        "2. Plan the structure\n" +
        "3. Implement step by step\n" +
        "4. Test and refine\n\n" +
        "Shall I help you with a specific part?"
        
      when /fix|solve|debug|troubleshoot/i
        "Let's troubleshoot this together:\n\n" +
        "1. First, identify the symptoms\n" +
        "2. Check for common issues\n" +
        "3. Test potential solutions\n" +
        "4. Verify the fix works\n\n" +
        "What specific issue are you seeing?"
        
      else
        "I understand you're asking about: #{task}\n\n" +
        "This is a task that requires careful consideration. " +
        "Could you provide more specific details about what you're trying to achieve? " +
        "This will help me give you the most relevant assistance."
      end
    end
  end
end
