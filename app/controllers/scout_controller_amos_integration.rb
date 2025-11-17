# Example of how to refactor ScoutController to use Amos
# This shows the migration path from the current architecture to Amos

class ScoutControllerAmosIntegration
  
  # Before: Complex chat_stream method with lots of logic
  def chat_stream_old
    # ... 800+ lines of complex logic ...
  end
  
  # After: Simple delegation to Amos
  def chat_stream_new
    include ActionController::Live
    
    response.headers['Content-Type'] = 'text/event-stream'
    response.headers['Cache-Control'] = 'no-cache'
    
    message = params[:message]
    attached_files = params[:attached_files]
    
    # Initialize Amos
    orchestrator = Amos::Orchestrator.new(
      current_user,
      current_entity,
      session[:scout_session_id]
    )
    
    # Let Amos handle everything
    orchestrator.process_message(
      message,
      source: :user,
      metadata: {
        attached_files: attached_files,
        canvas: params[:canvas],
        voice_mode: params[:voice_mode]
      }
    )
    
    # That's it! Amos handles:
    # - Intent detection
    # - Tool selection
    # - Job delegation
    # - Response streaming
    # - Error handling
    
  ensure
    response.stream.close
  end
  
  # Example: Parallel processing detection moves to Amos
  def should_use_parallel_processing_old?(message, attached_files)
    # Complex regex patterns and logic
    return true if attached_files.length > 1
    return true if message.match?(/\band\s+(also|then)/i)
    # ... etc
  end
  
  # New: This logic moves inside Amos::Orchestrator#analyze_intent
  # No need for controller to know about this
  
  # Example: Tool execution
  def execute_with_tools_old
    # Initialize service
    # service = ScoutGenericToolsServiceV2.new(user, entity, session_id)
    
    # Complex tool selection
    # tools = select_tools_for_request(message)
    
    # Execute
    # result = service.process_message_with_tools(message, tools)
    
    # Handle result
    # ... lots of code
  end
  
  # New: Amos handles tool selection internally
  def execute_with_tools_new
    # Amos determines if tools are needed
    # If yes, it delegates to appropriate agent
    # Controller doesn't need to know about tools
  end
  
  # Example: Workflow execution
  def handle_workflow_old
    # Detect workflow need
    # if message.match?(/landing.*page/i)
    #   # Initialize workflow service
    #   workflow_service = InteractiveTaskService.new(user, entity, session_id)
    #   
    #   # Complex workflow handling
    #   # ... 100+ lines of code
    # end
  end
  
  # New: Workflows are just another agent type
  def handle_workflow_new
    # Amos detects workflow need
    # Delegates to LandingPageAgent or appropriate agent
    # Agent handles all workflow logic
    # Controller stays simple
  end
  
  # Benefits of migration:
  # 1. Controller reduced from 2700+ lines to ~100 lines
  # 2. Clear separation of concerns
  # 3. Easy to add new agent types
  # 4. Consistent handling of all requests
  # 5. Better testability
  # 6. Scalable architecture
  
  # Migration steps:
  # 1. Start by wrapping existing logic in Amos
  # 2. Gradually move logic from controller to orchestrator
  # 3. Create specialized agents for each domain
  # 4. Replace direct tool calls with agent delegation
  # 5. Unify all streaming through Amos response buffer
end

