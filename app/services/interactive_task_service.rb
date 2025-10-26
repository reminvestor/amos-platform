class InteractiveTaskService
  attr_reader :task_session, :workflow_engine, :user, :entity

  def initialize(user, entity, session_id = nil)
    @user = user
    @entity = entity
    @session_id = session_id || SecureRandom.uuid

    # Find or create task session
    @task_session = find_or_create_task_session

    # Initialize workflow engine
    @workflow_engine = WorkflowEngine.new(@task_session)

    # Set up progress callback for real-time updates
    @progress_callback = nil
    @additional_context = {}
  end

  # Set additional context for the service
  def set_context(context = {})
    @additional_context.merge!(context)
  end

  # Process a message and determine if it should use interactive workflow
  def process_message(message, conversation_history = [], current_canvas = nil)
    # Check if we're awaiting plan approval
    if @task_session.metadata['awaiting_approval'] == true
      Rails.logger.info "InteractiveTaskService: Plan awaiting approval, handling user response"
      return handle_plan_response(message)
    end

    # Check if we have an active workflow awaiting input
    if @task_session.workflow_spec && workflow_awaiting_input?
      Rails.logger.info "InteractiveTaskService: Active workflow awaiting input, continuing with user message"
      return continue_workflow_with_message(message)
    end

    # Check if there's a V2 workflow awaiting input
    if v2_workflow_awaiting_input?
      Rails.logger.info "InteractiveTaskService: V2 workflow awaiting input, resuming with user message"
      return resume_v2_workflow_with_message(message)
    end

    # Check if we're in post-workflow conversation mode (just completed a workflow)
    # Stay in conversational mode for follow-up questions
    state = @task_session.state || {}
    if state["workflow_context_active"] == true
      Rails.logger.info "InteractiveTaskService: In post-workflow conversation, staying conversational"

      # Check if this is a new action request (not a follow-up)
      # Keywords that indicate a NEW action should trigger planner
      new_action_keywords = /\b(create|make|build|start|new|generate|set up another|add another)\b/i

      if message.match?(new_action_keywords)
        Rails.logger.info "InteractiveTaskService: Detected new action request, clearing post-workflow mode"
        @task_session.update_state(workflow_context_active: false)
      end
    end

    # Always default to autonomous mode - let the AI decide if it needs planning
    Rails.logger.info "InteractiveTaskService: Processing message in autonomous mode (AI-driven)"

    # Store mode detection in task session
    @task_session.update!(
      session_type: 'autonomous',
      metadata: @task_session.metadata.merge(
        mode_confidence: 1.0,
        detected_intent: "AI will analyze and determine best approach",
        ai_driven: true
      )
    )

    # Let the AI handle everything - it will delegate to planner if needed
    handle_autonomous_mode(message, conversation_history, current_canvas)
  end
  
  # Set progress callback for real-time updates
  def on_progress(&block)
    @progress_callback = block
    @workflow_engine.on_progress(&block)
  end
  
  # Handle user response when plan is awaiting approval
  def handle_plan_response(message)
    Rails.logger.info "InteractiveTaskService: Processing user response during plan approval"
    
    # Normalize message for keyword detection
    normalized_message = message.downcase.strip
    
    # Check for explicit approval keywords
    approval_keywords = ['yes', 'approve', 'go ahead', 'proceed', 'sounds good', 'looks good', 'do it', 'yes please', 'yep', 'yeah', 'ok', 'okay']
    rejection_keywords = ['no', 'cancel', 'stop', 'don\'t', 'nevermind', 'never mind']
    modification_keywords = ['change', 'modify', 'adjust', 'different', 'instead']
    
    if approval_keywords.any? { |keyword| normalized_message.include?(keyword) } && !rejection_keywords.any? { |keyword| normalized_message.include?(keyword) }
      # User is approving the plan
      Rails.logger.info "InteractiveTaskService: User approved plan via conversational response"
      return handle_plan_approval('approve')
    elsif rejection_keywords.any? { |keyword| normalized_message.include?(keyword) }
      # User is rejecting/cancelling the plan
      Rails.logger.info "InteractiveTaskService: User cancelled plan via conversational response"
      return handle_plan_approval('cancel')
    elsif modification_keywords.any? { |keyword| normalized_message.include?(keyword) }
      # User wants to modify the plan
      Rails.logger.info "InteractiveTaskService: User requested modifications via conversational response"
      
      # Clear awaiting_approval and let AI handle the modification request
      @task_session.update!(
        metadata: @task_session.metadata.merge(
          awaiting_approval: false,
          modification_requested: true,
          modification_feedback: message
        )
      )
      
      # Let the AI interpret the modification request and adjust the plan
      @progress_callback&.call({
        type: 'intermediate_message',
        content: "I'll adjust the plan based on your feedback. Let me rethink this...",
        role: 'assistant'
      })
      
      # Delegate back to AI to handle the modification
      main_chat_loadout = AgentLoadout.new(agent_role: 'main_chat')
      generic_tools_service = ScoutGenericToolsServiceV2.new(@user, @entity, @session_id, agent_loadout: main_chat_loadout)
      
      modification_context = "User provided feedback on the workflow plan: #{message}\n\nOriginal request: #{@task_session.metadata['request_text']}\n\nPlease create a revised plan incorporating their feedback."
      
      if @progress_callback
        return generic_tools_service.process_message_with_tools_streaming(
          modification_context,
          @progress_callback,
          [],
          nil
        )
      else
        return generic_tools_service.process_message_with_tools(modification_context, [], nil)
      end
    else
      # Ambiguous response - ask for clarification
      Rails.logger.info "InteractiveTaskService: Ambiguous response during plan approval, asking for clarification"
      
      {
        success: true,
        message: "I'm not sure if you want me to proceed with the plan or make changes. Could you please say:\n\n- \"Yes\" or \"Approve\" to start executing the plan\n- \"Modify\" or \"Change\" followed by your feedback if you want adjustments\n- \"Cancel\" if you don't want to proceed\n\nOr you can be more specific about what you'd like me to do!",
        awaiting_approval: true,
        canvas_type: 'task_progress',
        canvas_data: {
          workflow: @task_session.metadata['workflow_plan'],
          awaiting_approval: true
        }
      }
    end
  end
  
  # Continue an existing workflow with user input
  def continue_workflow(user_inputs)
    unless @task_session.workflow_spec
      return {
        success: false,
        message: 'No active workflow to continue',
        canvas: 'conversation'
      }
    end
    
    # Resume workflow
    result = @workflow_engine.resume_workflow(user_inputs)
    
    # Handle workflow result
    handle_workflow_result(result)
  end
  
  # Get current workflow status
  def workflow_status
    return { status: 'no_workflow' } unless @task_session.workflow_spec
    
    @workflow_engine.progress
  end
  
  private
  
  def workflow_awaiting_input?
    state = @task_session.state || {}
    workflow_state = state['workflow_state'] || {}
    current_step = workflow_state['current_step']
    
    return false unless current_step
    
    # Check if the current step result indicates awaiting input
    last_result = workflow_state['last_step_result'] || {}
    last_result['status'] == 'awaiting_input'
  end
  
  def v2_workflow_awaiting_input?
    state = @task_session.state || {}
    return false unless state['current_phase']
    return false unless state['workflow_status'] == 'awaiting_input'
    
    true
  end
  
  def resume_v2_workflow_with_message(message)
    Rails.logger.info "InteractiveTaskService: Resuming V2 workflow with user message"
    
    # Initialize workflow engine if needed
    @workflow_engine = WorkflowEngine.new(@task_session) unless @workflow_engine
    @workflow_engine.set_progress_callback(@progress_callback)
    
    # Resume the V2 workflow
    result = @workflow_engine.resume_v2_workflow(message)
    
    # Convert to our response format
    case result[:status]
    when 'awaiting_input'
      {
        success: true,
        message: result[:message],
        canvas: 'conversation',
        canvas_data: {},
        mode: 'workflow_gathering',
        awaiting_input: true
      }
    when 'completed'
      {
        success: true,
        message: result[:message],
        canvas: result[:canvas_type] || 'conversation',
        canvas_data: result[:canvas_data] || {},
        mode: 'workflow_completed'
      }
    when 'failed'
      {
        success: false,
        message: result[:error] || "Workflow failed",
        canvas: 'conversation',
        canvas_data: {},
        mode: 'workflow_failed'
      }
    else
      {
        success: true,
        message: result[:message] || "Workflow continuing...",
        canvas: 'conversation',
        canvas_data: {},
        mode: 'workflow_running'
      }
    end
  end
  
  def continue_workflow_with_message(message)
    Rails.logger.info "InteractiveTaskService: Continuing workflow with conversational input"
    
    # Pass the message as user input
    result = @workflow_engine.resume_workflow(user_message: message)
    
    # Handle workflow result
    handle_workflow_result(result)
  end
  
  def handle_plan_approval(approval_action, feedback = nil)
    Rails.logger.info "InteractiveTaskService: Handling plan approval - action: #{approval_action}"
    
    case approval_action
    when 'approve'
      # Execute the approved workflow
      Rails.logger.info "InteractiveTaskService: User approved the plan, starting execution"
      
      # Update task session to remove awaiting_approval flag
      @task_session.update!(
        metadata: @task_session.metadata.merge(
          awaiting_approval: false,
          approved_at: Time.current
        ),
        status: 'active'
      )
      
      # Start workflow execution with streaming updates
      workflow_engine = WorkflowEngineV2.new(@task_session)
      workflow_spec = @task_session.metadata['workflow_plan']
      
      # Set up progress callback for real-time updates
      progress_callback = lambda do |update|
        # Stream progress updates to the user
        case update[:type]
        when :step_started
          @progress_callback&.call("🔧 Starting: #{update[:step_name]}")
        when :step_completed
          @progress_callback&.call("✅ Completed: #{update[:step_name]}")
        when :step_failed
          @progress_callback&.call("❌ Failed: #{update[:step_name]} - #{update[:error]}")
        when :tool_call
          @progress_callback&.call("🔧 Using tool: #{update[:tool_name]}")
        when :tool_result
          if update[:success]
            @progress_callback&.call("✅ Tool completed: #{update[:tool_name]}")
          else
            @progress_callback&.call("❌ Tool failed: #{update[:tool_name]} - #{update[:error]}")
          end
        when :workflow_completed
          @progress_callback&.call("🎉 Workflow completed successfully!")
        when :workflow_failed
          @progress_callback&.call("❌ Workflow failed: #{update[:error]}")
        end
      end
      
      # Start workflow with progress callback
      begin
        # Send initial message
        @progress_callback&.call({
          type: 'intermediate_message',
          content: "✅ Plan approved! Starting execution...",
          role: 'assistant'
        })
        
        # Immediately switch to task progress canvas
        @progress_callback&.call({
          type: 'canvas_update',
          canvas_type: 'task_progress',
          canvas_data: {
            task_session_id: @task_session.id
          }
        })
        
        # Execute workflow (this is synchronous and will call progress_callback during execution)
        workflow_result = workflow_engine.start_workflow(workflow_spec, {}, progress_callback)
        
        # Generate AI-powered summary of what was accomplished
        final_message = if workflow_result[:status] == 'completed'
          generate_workflow_summary(workflow_spec, workflow_engine)
        elsif workflow_result[:status] == 'failed'
          "❌ Workflow failed: #{workflow_result[:error] || 'Unknown error'}"
        else
          "⏸️ Workflow paused: #{workflow_result[:message] || 'Awaiting input'}"
        end
        
        @progress_callback&.call({
          type: 'intermediate_message',
          content: final_message,
          role: 'assistant'
        })
        
        # Force canvas update to task_progress
        @progress_callback&.call({
          type: 'canvas_update',
          canvas_type: 'task_progress',
          canvas_data: {
            task_session_id: @task_session.id
          }
        })
        
        {
          success: true,
          message: final_message, # Include the final message
          message_already_saved: true, # Mark that message was already saved via progress_callback
          mode: 'autonomous', # Mark as autonomous to prevent duplicate saving
          canvas_type: 'task_progress',
          canvas_data: {
            task_session_id: @task_session.id
          },
          streaming: false # Workflow is complete, no more streaming
        }
      rescue => e
        Rails.logger.error "Workflow execution failed: #{e.message}"
        Rails.logger.error e.backtrace.join("\n")
        
        @progress_callback&.call({
          type: 'intermediate_message',
          content: "❌ Workflow execution failed: #{e.message}",
          role: 'assistant'
        })
        
        {
          success: false,
          message: nil,
          error: e.message
        }
      end
      
    when 'modify'
      # User wants to modify the plan
      Rails.logger.info "InteractiveTaskService: User requested plan modification"
      
      {
        success: true,
        message: "Please tell me what changes you'd like to make to the plan.",
        awaiting_modification: true
      }
      
    when 'cancel'
      # Cancel the planning session
      Rails.logger.info "InteractiveTaskService: User cancelled the plan"
      
      @task_session.update!(status: 'cancelled')
      
      {
        success: true,
        message: "Plan cancelled. How else can I help you?"
      }
      
    else
      {
        success: false,
        message: "Invalid approval action: #{approval_action}"
      }
    end
  end
  
  private
  
  def generate_workflow_summary(workflow_spec, workflow_engine)
    # Gather workflow execution details
    workflow_execution = workflow_engine.instance_variable_get(:@workflow_execution)
    completed_steps = []
    
    if workflow_execution
      # Get steps from workflow_spec or workflow_execution
      steps_array = workflow_spec[:steps] || 
                   workflow_spec['steps'] || 
                   workflow_execution.workflow_spec&.dig('steps') ||
                   workflow_execution.workflow_spec&.dig(:steps) ||
                   []
      
      workflow_execution.workflow_step_executions.status_completed.each do |step_exec|
        step_def = steps_array.find { |s| (s[:id] || s['id']) == step_exec.step_id }
        
        # Extract key results from step output
        key_results = extract_key_results(step_exec)
        
        completed_steps << {
          name: step_def&.dig(:name) || step_def&.dig('name') || step_exec.step_name || step_exec.step_id,
          description: step_def&.dig(:description) || step_def&.dig('description') || '',
          tool: step_def&.dig(:tool) || step_def&.dig('tool') || step_exec.step_type,
          results: key_results
        }
      end
    end
    
    # Get any created entities
    created_entities = extract_created_entities(workflow_execution)
    
    # Build AI prompt for summary
    summary_prompt = build_summary_prompt(workflow_spec, completed_steps, created_entities)
    
    # Get AI summary
    begin
      ai_service = BedrockService.new
      response = ai_service.complete(
        messages: [
          { role: 'user', content: summary_prompt }
        ],
        max_tokens: 500,
        temperature: 0.7
      )
      
      # Ensure we have a good summary
      if response.present? && response.length > 20
        response
      else
        # Fallback to basic summary
        generate_basic_summary(workflow_spec, completed_steps, created_entities)
      end
    rescue => e
      Rails.logger.error "Failed to generate AI summary: #{e.message}"
      # Fallback to basic summary
      generate_basic_summary(workflow_spec, completed_steps, created_entities)
    end
  end
  
  def extract_key_results(step_execution)
    return {} unless step_execution.output_data.present?
    
    output = step_execution.output_data.with_indifferent_access
    results = {}
    
    # Extract common patterns
    if records = output.dig(:data, :records) || output.dig(:result, :records)
      if records.is_a?(Array) && records.first
        results[:record_count] = records.length
        results[:first_record] = records.first.slice('id', 'name', 'subject', 'status')
      end
    end
    
    if record = output.dig(:data, :result, :record) || output.dig(:result, :record)
      results[:created] = record.slice('id', 'name', 'status', 'email_template_id')
    end
    
    results
  end
  
  def extract_created_entities(workflow_execution)
    entities = []
    
    return entities unless workflow_execution
    
    # Look for campaigns
    if campaign_var = workflow_execution.workflow_variables.find_by(name: 'campaign_id')
      entities << { type: 'Campaign', id: campaign_var.value }
    end
    
    # Look for other common entities
    %w[contact_id landing_page_id email_template_id].each do |var_name|
      if var = workflow_execution.workflow_variables.find_by(name: var_name)
        type = var_name.gsub('_id', '').humanize
        entities << { type: type, id: var.value }
      end
    end
    
    entities
  end
  
  def build_summary_prompt(workflow_spec, completed_steps, created_entities)
    <<~PROMPT
      You are a helpful AI assistant having a conversation with a user. You just completed a workflow for them.
      Create a friendly, conversational response that summarizes what was done AND asks what they'd like to do next.
      
      Workflow: #{workflow_spec[:name]}
      Description: #{workflow_spec[:description]}
      
      Completed Steps:
      #{completed_steps.map { |step| "- #{step[:name]}: #{step[:description]}" }.join("\n")}
      
      Created/Modified Entities:
      #{created_entities.map { |e| "- #{e[:type]} (ID: #{e[:id]})" }.join("\n")}
      
      Step Results:
      #{completed_steps.map { |step| 
        results = step[:results]
        result_summary = []
        result_summary << "#{results[:record_count]} records found" if results[:record_count]
        result_summary << "Created: #{results[:created][:name]}" if results.dig(:created, :name)
        "- #{step[:name]}: #{result_summary.join(', ')}"
      }.join("\n")}
      
      Your response should:
      1. Start with a success emoji and enthusiasm
      2. Clearly state what was accomplished in user-friendly terms (1-2 sentences)
      3. Mention specific entities created with IDs for reference
      4. Confirm any linkages or relationships established
      5. Ask an engaging follow-up question about what they'd like to do next
      6. Suggest 2-3 specific next actions they might want to take
      
      Example suggestions could include:
      - Viewing or editing what was created
      - Creating more similar items
      - Moving to the next logical step in their workflow
      - Running a test or preview
      
      Be conversational and helpful, like a colleague who just helped them complete a task.
    PROMPT
  end
  
  def generate_basic_summary(workflow_spec, completed_steps, created_entities)
    summary = "🎉 #{workflow_spec[:name]} completed successfully! "
    
    # Add specific accomplishments
    if campaign = created_entities.find { |e| e[:type] == 'Campaign' }
      summary += "Your new email campaign (ID: #{campaign[:id]}) has been created "
      if completed_steps.any? { |s| s[:name]&.include?('Link') || s[:name]&.include?('Verify') }
        summary += "and linked to your email template. "
      end
    elsif landing_page = created_entities.find { |e| e[:type] == 'Landing page' }
      summary += "Your landing page (ID: #{landing_page[:id]}) has been created. "
    else
      summary += "All #{completed_steps.length} steps were executed successfully. "
    end
    
    summary += "\n\nWhat would you like to do next? You could:\n"
    summary += "• Preview or edit what was just created\n"
    summary += "• Create another campaign with different settings\n"
    summary += "• Add contacts to your campaign\n"
    summary += "• Schedule the campaign for sending"
    
    summary
  end
  
  def find_or_create_task_session
    # Try to find existing active session for this user
    existing_session = TaskSession.active
                                  .where(user: @user)
                                  .where("metadata->>'session_id' = ?", @session_id)
                                  .first
    
    if existing_session
      Rails.logger.info "InteractiveTaskService: Found existing task session #{existing_session.id}"
      existing_session
    else
      Rails.logger.info "InteractiveTaskService: Creating new task session for session #{@session_id}"
      TaskSession.create!(
        user: @user,
        status: 'active',
        metadata: {
          session_id: @session_id,
          entity_id: @entity&.id,
          created_from: 'scout_chat'
        }
      )
    end
  end
  
  def handle_interactive_mode(message, mode_info)
    Rails.logger.info "InteractiveTaskService: Starting interactive workflow"
    
    # Determine workflow type
    workflow_type = mode_info[:suggested_workflow] || 'generic_interactive_wizard'
    
    # Create appropriate workflow
    workflow_spec = case workflow_type
    when 'landing_page_wizard'
      create_landing_page_workflow(message)
    when 'campaign_strategy_wizard'
      create_campaign_workflow(message)
    else
      create_generic_interactive_workflow(message)
    end
    
    # Start the workflow
    result = @workflow_engine.start_workflow(workflow_spec, { user_message: message })
    
    # Handle the result
    handle_workflow_result(result)
  end
  
  def handle_autonomous_mode(message, conversation_history, current_canvas)
    Rails.logger.info "InteractiveTaskService: Processing autonomous mode"
    
    # Store any attached files in task session metadata for now
    # They'll be moved to workflow context when workflow is created
    if @additional_context[:attached_files]&.any?
      current_files = @task_session.metadata['attached_files'] || []
      current_files += @additional_context[:attached_files]
      @task_session.update!(
        metadata: @task_session.metadata.merge('attached_files' => current_files)
      )
      Rails.logger.info "Stored #{@additional_context[:attached_files].length} files in task session"
    end
    
    # Let the AI decide if it needs planning - no more keyword checking
    main_chat_loadout = AgentLoadout.new(agent_role: 'main_chat')
    generic_tools_service = ScoutGenericToolsServiceV2.new(@user, @entity, @session_id, agent_loadout: main_chat_loadout)
    
    # Pass task session context and any additional context (like files) so AI can delegate if needed
    generic_tools_service.set_context(task_session: @task_session, **@additional_context)
    
    # Use streaming version (required for V2) - provide no-op callback if none given
    callback = @progress_callback || ->(event, data) { } # No-op callback for tests
    response = generic_tools_service.process_message_with_tools_streaming(
      message,
      callback,
      conversation_history,
      current_canvas
    )
    
    # Check if a workflow was delegated and needs execution
    if response && response[:workflow_approval_needed]
      Rails.logger.info "Workflow delegated to planner, auto-executing workflow"
      
      # Load the workflow from task session
      task_session = TaskSession.find(response[:task_session_id])
      workflow_spec = task_session.state['workflow_spec']
      
      # Check if workflow creation was successful
      if workflow_spec.is_a?(Hash) && workflow_spec['success'] == false
        Rails.logger.error "Workflow creation failed: #{workflow_spec['error']}"
        return {
          success: false,
          message: "I encountered an issue creating the workflow: #{workflow_spec['error']}. Let me try a different approach.",
          canvas: 'conversation',
          canvas_data: {},
          tools_used: response[:tools_used] || [],
          mode: 'autonomous'
        }
      end
      
      # Auto-approve and execute the workflow
      workflow_name = workflow_spec.is_a?(Hash) ? (workflow_spec['workflow']&.dig('name') || workflow_spec['name']) : 'workflow'
      @progress_callback&.call({
        type: 'intermediate_message',
        content: "🚀 Executing workflow: #{workflow_name}...",
        role: 'assistant'
      })
      
      # Execute the workflow using WorkflowEngine
      begin
        workflow_engine = WorkflowEngine.new(task_session)
        workflow_engine.set_progress_callback(@progress_callback)
        
        # Check if this is a V2 phase-based workflow
        workflow = workflow_spec['workflow']
        is_v2 = workflow['template_version'] == 2 || workflow['phases'].present?
        
        if is_v2
          Rails.logger.info "🚀 Starting V2 phase-based workflow"
          # Use V2 execution path
          workflow_result = workflow_engine.execute_v2_workflow(workflow, {})
        else
          Rails.logger.info "🚀 Starting V1 step-based workflow"
          # Fall back to V1 execution for legacy workflows
          workflow_result = workflow_engine.start_workflow(workflow, {})
        end
        
        # Handle different workflow states
        case workflow_result[:status]
        when 'awaiting_input'
          # Workflow paused for user input
          Rails.logger.info "✋ Workflow paused for user input"
          return {
            success: true,
            message: workflow_result[:message] || response[:final_response][:message],
            message_already_saved: false,
            canvas: 'conversation',
            canvas_data: {},
            tools_used: response[:tools_used],
            mode: 'workflow_gathering',
            awaiting_input: true
          }
        when 'completed'
          # Workflow completed successfully
          return {
            success: true,
            message: workflow_result[:message] || "Workflow completed successfully!",
            message_already_saved: false,
            canvas: workflow_result[:canvas_type] || 'conversation',
            canvas_data: workflow_result[:canvas_data] || {},
            tools_used: response[:tools_used],
            mode: 'workflow_completed',
            workflow_executed: true
          }
        when 'failed'
          # Workflow execution failed
          return {
            success: false,
            message: "Workflow execution failed: #{workflow_result[:error]}",
            canvas: 'conversation',
            canvas_data: {},
            tools_used: response[:tools_used],
            mode: 'workflow_failed'
          }
        else
          # Unknown state - return error
          return {
            success: false,
            message: "Unexpected workflow state: #{workflow_result[:status]}",
            canvas: 'conversation',
            canvas_data: {},
            tools_used: response[:tools_used],
            mode: 'autonomous'
          }
        end
      rescue => e
        Rails.logger.error "Workflow execution error: #{e.message}"
        Rails.logger.error e.backtrace.join("\n")
        
        return {
          success: false,
          message: "Workflow execution encountered an error: #{e.message}",
          canvas: 'conversation',
          canvas_data: {},
          tools_used: response[:tools_used],
          mode: 'autonomous'
        }
      end
    end
    
    # Handle response safely
    if response && response[:final_response] && response[:final_response][:message]
      # Convert response to our format
      {
        success: true,
        message: response[:final_response][:message],
        message_already_saved: response[:final_response][:message_already_saved] || false,
        canvas: response[:canvas_type] || 'conversation',
        canvas_data: response[:canvas_data],
        tools_used: response[:tools_used],
        mode: 'autonomous'
      }
    elsif response && response[:message]
      # Handle direct message format
      {
        success: true,
        message: response[:message],
        message_already_saved: response[:message_already_saved] || false,
        canvas: response[:canvas_type] || 'conversation',
        canvas_data: response[:canvas_data],
        tools_used: response[:tools_used],
        mode: 'autonomous'
      }
    else
      # Handle error case
      {
        success: false,
        error: "Failed to process message in autonomous mode",
        message: "I'm having trouble processing that right now. Could you try rephrasing your request?",
        canvas: 'conversation',
        canvas_data: {},
        tools_used: [],
        mode: 'autonomous'
      }
    end
  end
  
  def handle_hybrid_mode(message, mode_info)
    Rails.logger.info "InteractiveTaskService: Starting hybrid workflow"
    
    # For hybrid mode, start with an interactive workflow that can call autonomous tools
    workflow_spec = create_hybrid_workflow(message, mode_info)
    
    result = @workflow_engine.start_workflow(workflow_spec, { user_message: message })
    handle_workflow_result(result)
  end
  
  def handle_workflow_result(result)
    case result[:status]
    when 'awaiting_input'
      {
        success: true,
        message: result[:message],
        canvas: 'interactive_wizard',
        canvas_data: {
          step: result[:step],
          form: result[:form],
          progress: @workflow_engine.progress
        },
        mode: 'interactive',
        awaiting_input: true
      }
      
    when 'step_completed'
      # Check if we just completed a user_input step and the next is a tool_call
      if result[:next_step] && result[:next_step][:type] == 'tool_call'
        Rails.logger.info "Step completed, next is tool_call - showing task_progress"
        {
          success: true,
          message: result[:message],
          canvas: 'task_progress',
          canvas_data: {
            progress: @workflow_engine.progress,
            current_step: result[:next_step],
            workflow_status: @workflow_engine.workflow&.status,
            task_session_id: @task_session.id
          },
          mode: 'interactive',
          step_completed: true,
          next_step: result[:next_step]
        }
      elsif result[:next_step] && result[:next_step][:type] == 'user_input'
        Rails.logger.info "Step completed, next is user_input - showing interactive_wizard"
        {
          success: true,
          message: result[:message],
          canvas: 'interactive_wizard',
          canvas_data: {
            step: result[:next_step],
            progress: @workflow_engine.progress
          },
          mode: 'interactive',
          step_completed: true,
          next_step: result[:next_step],
          awaiting_input: true
        }
      else
        {
          success: true,
          message: result[:message],
          canvas: determine_canvas_for_result(result),
          canvas_data: extract_canvas_data(result),
          mode: 'interactive',
          step_completed: true,
          next_step: result[:next_step]
        }
      end
      
    when 'completed'
      {
        success: true,
        message: result[:message],
        canvas: determine_final_canvas(result),
        canvas_data: extract_final_canvas_data(result),
        mode: 'interactive',
        workflow_completed: true
      }
      
    when 'failed'
      {
        success: false,
        message: result[:message],
        canvas: 'conversation',
        error: result[:error],
        failed_step: result[:failed_step],
        mode: 'interactive'
      }
      
    else
      {
        success: true,
        message: result[:message] || 'Processing...',
        canvas: 'task_progress',
        canvas_data: {
          progress: @workflow_engine.progress,
          current_result: result
        },
        mode: 'interactive'
      }
    end
  end
  
  def create_landing_page_workflow(message)
    {
      type: 'landing_page_creation',
      description: 'Create a landing page with guided input',
      metadata: {
        original_message: message,
        workflow_type: 'landing_page_wizard'
      },
      steps: [
        {
          id: 'analyze_context',
          type: 'tool_call',
          config: {
            tool: 'analyze_landing_page_request',
            description: 'Analyze existing business information and landing page request',
            inputs: {
              user_input: message,
              context: {
                user: @user.as_json(only: [:id, :email, :first_name, :last_name]),
                entity: @entity.as_json(only: [:id, :name, :subdomain])
              }
            }
          }
        },
        {
          id: 'collect_specific_info',
          type: 'user_input',
          config: {
            title: 'Landing Page Details',
            description: 'Let\'s gather specific information for your landing page',
            fields: [
              {
                name: 'page_purpose',
                type: 'select',
                required: true,
                label: 'What is the main purpose of this landing page?',
                options: [
                  'Promote a new product/service',
                  'Event registration',
                  'Lead generation',
                  'Special offer/promotion',
                  'Course/class enrollment',
                  'Newsletter signup',
                  'Coming soon/launch',
                  'Other'
                ]
              },
              {
                name: 'specific_details',
                type: 'textarea',
                required: true,
                label: 'Tell us more about what you\'re promoting',
                placeholder: 'What are you promoting? What makes it special? Any key details visitors should know?',
                rows: 4
              },
              { 
                name: 'call_to_action', 
                type: 'text', 
                required: true, 
                label: 'Primary Call to Action',
                placeholder: 'e.g., "Register Now", "Sign Up Today", "Learn More"'
              },
              {
                name: 'urgency_factor',
                type: 'select',
                label: 'Is there a deadline or limited availability?',
                options: [
                  'No urgency',
                  'Limited time offer',
                  'Limited spots available',
                  'Early bird pricing',
                  'Other deadline'
                ]
              },
              {
                name: 'additional_info',
                type: 'textarea',
                label: 'Any other important information?',
                placeholder: 'Pricing, testimonials, special features, etc.'
              }
            ]
          }
        },
        {
          id: 'collect_design_preferences',
          type: 'user_input',
          config: {
            title: 'Design Preferences & Images',
            description: 'Choose the look, feel, and images for your landing page',
            fields: [
              { 
                name: 'theme', 
                type: 'select', 
                required: true, 
                label: 'Theme Style',
                options: ['clean', 'modern', 'bold', 'professional', 'creative'],
                descriptions: {
                  'clean' => 'Minimalist and simple',
                  'modern' => 'Contemporary with gradients',
                  'bold' => 'High contrast and energetic',
                  'professional' => 'Corporate and trustworthy',
                  'creative' => 'Playful and artistic'
                }
              },
              { 
                name: 'primary_color', 
                type: 'color', 
                label: 'Primary Color (optional)',
                placeholder: '#2563eb'
              },
              {
                name: 'images_section',
                type: 'custom',
                label: 'Images for your landing page',
                template: 'image_upload_blocks'
              },
              { 
                name: 'style_notes', 
                type: 'textarea', 
                label: 'Additional Style Notes',
                placeholder: 'Any specific design requirements or preferences?'
              }
            ]
          }
        },
        {
          id: 'process_uploaded_images',
          type: 'tool_call',
          config: {
            tool: 'store_uploaded_images',
            description: 'Store uploaded images and prepare context for AI',
            inputs: {
              _resolve_from_steps: {
                image_data: ['collect_design_preferences']
              },
              user_id: @user.id,
              entity_id: @entity.id
            }
          }
        },
        {
          id: 'generate_landing_page',
          type: 'tool_call',
          config: {
            tool: 'generate_landing_page_dsl',
            description: 'Generate your landing page using AI',
            inputs: {
              # These will be resolved by the workflow engine from step results
              _resolve_from_steps: {
                business_info: ['analyze_context', 'collect_specific_info'],
                design_preferences: ['collect_design_preferences'],
                image_preferences: ['collect_design_preferences'],
                stored_images: ['process_uploaded_images']
              }
            }
          }
        },
        {
          id: 'compile_and_save',
          type: 'tool_call',
          config: {
            tool: 'compile_landing_page_html',
            description: 'Compile and save your landing page',
            inputs: {
              _resolve_from_steps: {
                dsl: ['generate_landing_page'],
                business_name: ['analyze_context'],
                user_id: @user.id,
                entity_id: @entity.id
              }
            }
          }
        }
      ]
    }
  end
  
  def create_campaign_workflow(message)
    {
      type: 'campaign_creation',
      description: 'Create and configure a marketing campaign',
      metadata: {
        original_message: message,
        workflow_type: 'campaign_wizard'
      },
      steps: [
        {
          id: 'campaign_details',
          type: 'user_input',
          config: {
            title: 'Campaign Details',
            description: 'Basic information about your campaign',
            fields: [
              { name: 'campaign_name', type: 'text', required: true, label: 'Campaign Name' },
              { name: 'campaign_type', type: 'select', required: true, label: 'Campaign Type',
                options: ['Email', 'Social Media', 'Mixed'] },
              { name: 'description', type: 'textarea', label: 'Campaign Description' }
            ]
          }
        },
        {
          id: 'select_audience',
          type: 'tool_call',
          config: {
            tool: 'get_contact_groups',
            description: 'Load your contact groups'
          }
        },
        {
          id: 'create_campaign',
          type: 'tool_call',
          config: {
            tool: 'create_campaign',
            description: 'Create your campaign'
          }
        }
      ]
    }
  end
  
  def create_generic_interactive_workflow(message)
    {
      type: 'generic_interactive',
      description: 'Interactive workflow for general tasks',
      metadata: {
        original_message: message,
        workflow_type: 'generic_wizard'
      },
      steps: [
        {
          id: 'gather_requirements',
          type: 'user_input',
          config: {
            title: 'Tell us more',
            description: 'We need a bit more information to help you effectively',
            fields: [
              { 
                name: 'specific_goal', 
                type: 'textarea', 
                required: true, 
                label: 'What specifically would you like to accomplish?',
                placeholder: 'Please describe your goal in detail...'
              },
              {
                name: 'timeline',
                type: 'select',
                label: 'When do you need this completed?',
                options: ['ASAP', 'This week', 'This month', 'No rush']
              },
              {
                name: 'additional_context',
                type: 'textarea',
                label: 'Any additional context or requirements?'
              }
            ]
          }
        },
        {
          id: 'process_requirements',
          type: 'tool_call',
          config: {
            tool: 'process_generic_request',
            description: 'Process your requirements'
          }
        }
      ]
    }
  end
  
  def create_hybrid_workflow(message, mode_info)
    {
      type: 'hybrid_workflow',
      description: 'Hybrid workflow combining autonomous and interactive steps',
      metadata: {
        original_message: message,
        workflow_type: 'hybrid',
        mode_info: mode_info
      },
      steps: [
        {
          id: 'analyze_request',
          type: 'tool_call',
          config: {
            tool: 'analyze_hybrid_request',
            description: 'Analyze your request to determine the best approach'
          }
        },
        {
          id: 'gather_missing_info',
          type: 'user_input',
          config: {
            title: 'Additional Information Needed',
            description: 'We need some additional details to complete your request',
            fields: mode_info[:missing_inputs].map do |input|
              {
                name: input,
                type: 'text',
                required: true,
                label: input.humanize
              }
            end
          }
        },
        {
          id: 'execute_autonomous_tasks',
          type: 'tool_call',
          config: {
            tool: 'execute_autonomous_workflow',
            description: 'Execute the autonomous parts of your request'
          }
        }
      ]
    }
  end
  
  def determine_canvas_for_result(result)
    # Determine which canvas to show based on the step result
    if result[:next_step]
      next_step_type = result[:next_step][:type]
      
      case next_step_type
      when 'user_input', 'form_input'
        'interactive_wizard'
      when 'tool_call'
        'task_progress'
      else
        'conversation'
      end
    else
      'conversation'
    end
  end
  
  def extract_canvas_data(result)
    {
      step: result[:next_step],
      progress: @workflow_engine.progress,
      completed_step: result[:result],
      workflow_status: @workflow_engine.workflow&.status
    }
  end
  
  def determine_final_canvas(result)
    # Determine final canvas based on workflow type
    workflow_type = @task_session.workflow_spec&.dig('type')
    
    case workflow_type
    when 'landing_page_creation'
      'landing_page_editor'
    when 'campaign_creation'
      'campaign_viewer'
    else
      'conversation'
    end
  end
  
  def extract_final_canvas_data(result)
    workflow_type = @task_session.workflow_spec&.dig('type')
    
    case workflow_type
    when 'landing_page_creation'
      # Extract landing page data from workflow results
      landing_page_data = extract_landing_page_from_workflow(result)
      {
        landing_page_id: landing_page_data[:landing_page_id],
        landing_page: landing_page_data,
        workflow_completed: true,
        final_result: result[:result]
      }
      
    when 'campaign_creation'
      # Extract campaign data from workflow results
      campaign_data = extract_campaign_from_workflow(result)
      {
        campaign: campaign_data,
        workflow_completed: true,
        final_result: result[:result]
      }
      
    else
      {
        workflow_completed: true,
        final_result: result[:result],
        message: result[:message]
      }
    end
  end
  
  def extract_landing_page_from_workflow(result)
    # Get landing page data from completed workflow steps
    execution_history = @workflow_engine.execution_history
    
    # Find the generation step result
    generation_step = execution_history.find { |step| step[:id] == 'generate_landing_page' }
    compilation_step = execution_history.find { |step| step[:id] == 'compile_and_save' }
    
    if generation_step && compilation_step
      compilation_data = compilation_step[:result][:data] || compilation_step[:result]
      generation_data = generation_step[:result][:data] || generation_step[:result]
      
      {
        dsl: generation_data[:dsl] || generation_data['dsl'],
        html: compilation_data[:html] || compilation_data['html'],
        slug: compilation_data[:slug] || compilation_data['slug'],
        landing_page_id: compilation_data[:landing_page_id] || compilation_data['landing_page_id'],
        landing_page: compilation_data[:landing_page] || compilation_data['landing_page'],
        business_info: generation_data[:business_info] || generation_data['business_info'],
        design_preferences: generation_data[:design_preferences] || generation_data['design_preferences']
      }
    else
      {
        error: 'Could not extract landing page data from workflow'
      }
    end
  end
  
  def extract_campaign_from_workflow(result)
    # Get campaign data from completed workflow steps
    execution_history = @workflow_engine.execution_history
    
    # Find the campaign creation step result
    creation_step = execution_history.find { |step| step[:id] == 'create_campaign' }
    
    if creation_step
      {
        campaign_id: creation_step[:result][:data][:campaign_id],
        campaign_data: creation_step[:result][:data][:campaign_data]
      }
    else
      {
        error: 'Could not extract campaign data from workflow'
      }
    end
  end
  
  # Create a streaming progress update
  def stream_progress_update(progress_data)
    return unless @progress_callback
    
    @progress_callback.call({
      type: 'progress_update',
      data: progress_data,
      timestamp: Time.current
    })
  end
  
  def requires_planning?(message)
    # Detect patterns that indicate multi-step operations
    multi_step_patterns = [
      /create.*and.*link/i,
      /create.*then.*link/i,
      /create.*then.*find.*link/i,  # Add this specific pattern
      /build.*and.*send/i,
      /setup.*and.*configure/i,
      /import.*and.*analyze/i,
      /fetch.*and.*create/i,
      /generate.*and.*publish/i
    ]
    
    # Check for explicit multi-step indicators
    multi_step_words = ['and then', 'followed by', 'after that', 'next', 'finally']
    
    # Check if message matches multi-step patterns
    has_multi_step_pattern = multi_step_patterns.any? { |pattern| message.match?(pattern) }
    has_multi_step_words = multi_step_words.any? { |phrase| message.downcase.include?(phrase) }
    
    # Check for compound operations (e.g., "create X and Y")
    has_multiple_actions = message.scan(/\b(create|build|setup|configure|link|send|publish|analyze|import|export)\b/i).length > 1
    
    result = has_multi_step_pattern || has_multi_step_words || has_multiple_actions
    
    Rails.logger.info "InteractiveTaskService: requires_planning? for '#{message}' = #{result}"
    Rails.logger.info "  has_multi_step_pattern: #{has_multi_step_pattern}"
    Rails.logger.info "  has_multi_step_words: #{has_multi_step_words}"
    Rails.logger.info "  has_multiple_actions: #{has_multiple_actions}"
    
    result
  end
  
  def trigger_planning_phase(message, conversation_history, current_canvas)
    Rails.logger.info "InteractiveTaskService: Triggering planning phase"
    
    # Send planning in progress message
    @progress_callback&.call({
      type: 'intermediate_message',
      content: "🤔 I'm analyzing your request and creating a detailed plan...\n\nThis may take a moment as I determine the best approach. The plan will appear on the intelligent canvas for your approval.",
      role: 'assistant'
    })
    
    # Create planner service
    planner = PlannerAgentService.new(
      user: @user,
      entity: @entity,
      session_id: @session_id,
      progress_callback: @progress_callback
    )
    
    # Generate workflow plan
    plan_result = planner.plan_workflow(message, {
      conversation_history: conversation_history,
      current_canvas: current_canvas
    })
    
    if plan_result[:success]
      workflow = plan_result[:workflow]
      
      # Store the plan in task session for approval
      @task_session.update!(
        session_type: 'autonomous',
        metadata: @task_session.metadata.merge(
          workflow_plan: workflow.to_h,
          awaiting_approval: true,
          plan_created_at: Time.current
        )
      )
      
      # Send plan ready message
      @progress_callback&.call({
        type: 'intermediate_message',
        content: "✅ I've created a plan for your request. Please review it below:",
        role: 'assistant'
      })
      
      # Format the plan for user approval
      plan_message = format_plan_for_approval(workflow)
      
      {
        success: true,
        message: plan_message,
        canvas_type: 'task_progress',
        canvas_data: {
          workflow: workflow.to_h,
          awaiting_approval: true,
          approval_actions: [
            { id: 'approve', label: 'Approve & Execute', style: 'primary' },
            { id: 'modify', label: 'Modify Plan', style: 'secondary' },
            { id: 'cancel', label: 'Cancel', style: 'danger' }
          ]
        },
        mode: 'planning',
        awaiting_approval: true
      }
    else
      # Planning failed, fall back to direct autonomous execution
      Rails.logger.error "Planning failed: #{plan_result[:error]}"
      
      # Delegate to autonomous system with main_chat loadout
      main_chat_loadout = AgentLoadout.new(agent_role: 'main_chat')
      generic_tools_service = ScoutGenericToolsServiceV2.new(@user, @entity, @session_id, agent_loadout: main_chat_loadout)
      
      if @progress_callback
        generic_tools_service.process_message_with_tools_streaming(
          message, 
          @progress_callback, 
          conversation_history, 
          current_canvas
        )
      else
        generic_tools_service.process_message_with_tools(message, conversation_history, current_canvas)
      end
    end
  end
  
  def format_plan_for_approval(workflow)
    message = "## 📋 Workflow Plan: #{workflow.name}\n\n"
    message += "I've created a plan to complete your request. Here's what I'll do:\n\n"
    
    workflow.steps.each_with_index do |step, index|
      message += "### Step #{index + 1}: #{step.name}\n"
      message += "- **Agent**: #{step.agent_role.capitalize}\n"
      message += "- **Action**: #{step.description}\n"
      
      if step.dependencies.any?
        message += "- **Depends on**: #{step.dependencies.join(', ')}\n"
      end
      
      if step.tool_allowlist.any?
        message += "- **Tools**: #{step.tool_allowlist.join(', ')}\n"
      end
      
      message += "\n"
    end
    
    message += "---\n\n"
    message += "**Would you like me to proceed with this plan?**\n\n"
    message += "You can:\n"
    message += "- ✅ **Approve** - Execute the plan as shown\n"
    message += "- ✏️ **Modify** - Request changes to the plan\n"
    message += "- ❌ **Cancel** - Stop and try a different approach\n"
    
    message
  end
  
  def store_files_in_context(file_urls)
    return unless @task_session.workflow_execution
    
    file_urls.each_with_index do |file_info, index|
      key = "uploaded_file_#{index + 1}"
      WorkflowContext.store_file(
        @task_session.workflow_execution,
        key,
        file_info
      )
      Rails.logger.info "Stored file #{file_info['filename']} as #{key} in workflow context"
    end
  end
  
end
