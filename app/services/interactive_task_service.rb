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
  end
  
  # Process a message and determine if it should use interactive workflow
  def process_message(message, conversation_history = [], current_canvas = nil)
    # Detect task mode
    mode_detector = TaskModeDetector.new
    mode_info = mode_detector.detect(message)
    
    Rails.logger.info "InteractiveTaskService: Detected mode '#{mode_info[:mode]}' with confidence #{mode_info[:confidence]}"
    
    # Store mode detection in task session
    @task_session.update!(
      session_type: mode_info[:mode],
      metadata: @task_session.metadata.merge(
        mode_confidence: mode_info[:confidence],
        detected_intent: mode_info[:rationale],
        suggested_workflow: mode_info[:suggested_workflow]
      )
    )
    
    case mode_info[:mode]
    when 'interactive'
      handle_interactive_mode(message, mode_info)
    when 'autonomous'
      handle_autonomous_mode(message, conversation_history, current_canvas)
    when 'hybrid'
      handle_hybrid_mode(message, mode_info)
    else
      # Fallback to interactive
      handle_interactive_mode(message, mode_info)
    end
  end
  
  # Set progress callback for real-time updates
  def on_progress(&block)
    @progress_callback = block
    @workflow_engine.on_progress(&block)
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
    Rails.logger.info "InteractiveTaskService: Delegating to autonomous mode"
    
    # Delegate to existing autonomous system
    generic_tools_service = ScoutGenericToolsService.new(@user, @entity, @session_id)
    response = generic_tools_service.process_message_with_tools(message, conversation_history, current_canvas)
    
    # Convert response to our format
    {
      success: true,
      message: response[:final_response][:message],
      canvas: response[:canvas_type] || 'conversation',
      canvas_data: response[:canvas_data],
      tools_used: response[:tools_used],
      mode: 'autonomous'
    }
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
      {
        success: true,
        message: result[:message],
        canvas: determine_canvas_for_result(result),
        canvas_data: extract_canvas_data(result),
        mode: 'interactive',
        step_completed: true,
        next_step: result[:next_step]
      }
      
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
              user_message: message,
              user: @user.as_json(only: [:id, :email, :first_name, :last_name]),
              entity: @entity.as_json(only: [:id, :name, :subdomain])
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
                label: 'Tell us about your new classes',
                placeholder: 'What classes are you offering? When do they start? What makes them special?'
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
            title: 'Design Preferences',
            description: 'Choose the look and feel for your landing page',
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
                name: 'style_notes', 
                type: 'textarea', 
                label: 'Additional Style Notes',
                placeholder: 'Any specific design requirements or preferences?'
              }
            ]
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
                design_preferences: ['collect_design_preferences']
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
end
