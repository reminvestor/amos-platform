class ParallelTaskOrchestrator
  include Rails.application.routes.url_helpers
  
  TASK_TYPES = {
    voice_immediate: { queue: 'critical', model: 'claude-haiku', max_wait_ms: 500 },
    voice_followup: { queue: 'critical', model: 'claude-sonnet-4-5', max_wait_ms: 3000 },
    background: { queue: 'default', model: 'claude-sonnet-4-5', max_wait_ms: nil },
    interactive: { queue: 'default', model: 'claude-opus-4-1', max_wait_ms: nil },
    interactive_workflow: { queue: 'default', model: 'claude-sonnet-4-5', max_wait_ms: nil },
    scheduled: { queue: 'maintenance', model: 'claude-haiku', max_wait_ms: nil },
    analysis: { queue: 'embeddings', model: 'claude-opus-4-1', max_wait_ms: nil }
  }.freeze

  def initialize(user, entity, parent_conversation_id = nil)
    @user = user
    @entity = entity
    @parent_conversation_id = parent_conversation_id
    @tasks = []
  end

  # Main entry point for processing user input
  def process_request(message, context = {})
    # Analyze intent and decompose into tasks
    task_plan = analyze_and_decompose(message, context)
    
    # Create task sessions
    created_tasks = create_task_sessions(task_plan)
    
    # Handle voice mode special case
    if context[:voice_mode]
      handle_voice_mode(created_tasks)
    else
      # Queue all tasks for parallel execution
      queue_tasks(created_tasks)
    end
    
    created_tasks
  end
  
  # Process a pre-created task specification (for workflows)
  def process_task_spec(task_spec)
    # Create task sessions from the spec
    created_tasks = create_task_sessions(task_spec)
    
    # Queue all tasks for parallel execution
    queue_tasks(created_tasks)
    
    {
      success: true,
      message: "Processing #{created_tasks.length} tasks in parallel.",
      tasks: created_tasks
    }
  end

  private

  def analyze_and_decompose(message, context)
    # Use a lightweight model to quickly analyze and decompose the request
    analyzer_service = BedrockService.new
    
    prompt = build_decomposition_prompt(message, context)
    
    Rails.logger.info "🧩 Sending task decomposition request to Bedrock..."
    
    response = analyzer_service.send_message(
      "You are a task decomposition expert. Analyze requests and break them into parallel executable tasks.",
      [{ role: "user", content: prompt }],
      model: "claude-haiku",
      json_mode: true,
      max_tokens: 2000
    )
    
    # Handle response format
    response_text = if response.is_a?(Hash)
                     response.dig(:response, :text) || response[:text] || response.to_json
                   else
                     response.to_s
                   end
    
    Rails.logger.info "🔍 Response preview: #{response_text[0..200]}"
    
    # Strip markdown code blocks if present
    cleaned_response = response_text.strip
    if cleaned_response.start_with?('```json')
      cleaned_response = cleaned_response.sub(/^```json\s*\n?/, '').sub(/\n?```\s*$/, '')
    elsif cleaned_response.start_with?('```')
      cleaned_response = cleaned_response.sub(/^```\s*\n?/, '').sub(/\n?```\s*$/, '')
    end
    
    # Parse JSON response
    parsed = JSON.parse(cleaned_response, symbolize_names: true)
    
    # Ensure we have a tasks array
    parsed[:tasks] ||= []
    parsed
  rescue JSON::ParserError => e
    Rails.logger.error "Task decomposition JSON parse error: #{e.message}"
    Rails.logger.error "Response was: #{response_text}"
    # Return a default single task if parsing fails
    {
      immediate_response: "I'll help you with that request.",
      tasks: [{
        type: 'interactive',
        description: message,
        dependencies: [],
        estimated_duration_ms: 5000,
        required_tools: [],
        model_preference: nil
      }]
    }
  rescue => e
    Rails.logger.error "Task decomposition failed: #{e.message}"
    # Fallback to single task
    { tasks: [{ type: 'interactive', description: message, dependencies: [] }] }
  end

  def build_decomposition_prompt(message, context)
    <<~PROMPT
      Analyze this request and break it into tasks that can run in parallel.
      
      Request: #{message}
      
      Return a simple JSON with this structure:
      {
        "immediate_response": "I'll help you with that",
        "tasks": [
          {
            "type": "background",
            "description": "First task description",
            "dependencies": []
          },
          {
            "type": "interactive_workflow",
            "description": "Create landing page with user guidance",
            "workflow_type": "landing_page_wizard",
            "dependencies": []
          }
        ]
      }
      
      Rules:
      - Each distinct action should be a separate task
      - Tasks with no dependencies can run in parallel
      - Keep descriptions short and clear
      - Use type "background" for data fetching, analysis, queries
      - Use type "interactive_workflow" for tasks that need user input like:
        * Creating landing pages (workflow_type: "landing_page_wizard")
        * Creating campaigns (workflow_type: "campaign_wizard")
        * Creating email templates (workflow_type: "email_template_wizard")
      - Return valid JSON only, no explanations
    PROMPT
  end

  def create_task_sessions(task_plan)
    tasks = []
    task_id_map = {}
    
    # Ensure we have tasks array
    return [] unless task_plan[:tasks].is_a?(Array)
    
    # Create all task sessions first
    task_plan[:tasks].each_with_index do |task_spec, index|
      task_type = (task_spec[:type] || 'background').to_s
      
      task_session = TaskSession.create!(
        user: @user,
        status: 'active',
        session_type: task_type == 'interactive_workflow' ? 'interactive' : 'autonomous',
        parent_conversation_id: @parent_conversation_id,
        task_type: task_type,
        priority: calculate_priority(task_type),
        model_preference: task_spec[:model_preference] || TASK_TYPES[task_type.to_sym]&.dig(:model),
        metadata: {
          description: task_spec[:description] || "Task #{index + 1}",
          estimated_duration_ms: task_spec[:estimated_duration_ms] || 5000,
          required_tools: task_spec[:required_tools] || [],
          immediate_response: task_plan[:immediate_response],
          index: index,
          workflow_type: task_spec[:workflow_type] || task_spec['workflow_type'],
          interactive: task_type == 'interactive_workflow'
        }.merge(task_spec[:metadata] || {})
      )
      
      tasks << task_session
      task_id_map[index.to_s] = task_session.id
    end
    
  # Create dependencies
  task_plan[:tasks].each_with_index do |task_spec, index|
    dependencies = task_spec[:dependencies] || []
    next if dependencies.blank?
    
    dependencies.each do |dep|
      # Handle both numeric indices and string descriptions
      dep_task_id = if dep.is_a?(Integer) || dep.to_s =~ /^\d+$/
        # Numeric index
        task_id_map[dep.to_s]
      else
        # String description - find matching task
        matching_task = task_plan[:tasks].find_index { |t| t[:description] == dep }
        task_id_map[matching_task.to_s] if matching_task
      end
      
      next unless dep_task_id
      
      TaskDependency.create!(
        task_session_id: task_id_map[index.to_s],
        depends_on_task_id: dep_task_id,
        dependency_type: 'blocking',
        status: 'pending'
      )
    end
  end
    
    tasks
  end

  def calculate_priority(task_type)
    case task_type.to_sym
    when :voice_immediate then 10
    when :voice_followup then 9
    when :interactive then 7
    when :analysis then 5
    when :background then 3
    when :scheduled then 1
    else 5
    end
  end

  def handle_voice_mode(tasks)
    # Find immediate response task
    immediate_task = tasks.find { |t| t.task_type == 'voice_immediate' }
    
    if immediate_task
      # Execute immediately in-process for ultra-low latency
      VoiceImmediateProcessor.new(immediate_task).process!
      
      # Mark as completed
      immediate_task.update!(
        status: 'completed',
        started_at: Time.current,
        progress: 100
      )
    end
    
    # Queue remaining tasks
    remaining_tasks = tasks.reject { |t| t.task_type == 'voice_immediate' }
    queue_tasks(remaining_tasks)
  end

  def queue_tasks(tasks)
    tasks.each do |task|
      job_class = job_class_for_task_type(task.task_type)
      queue_name = TASK_TYPES[task.task_type.to_sym][:queue]
      
      # Check dependencies
      if task.task_dependencies.any?
        # Schedule with dependency check
        TaskExecutionJob
          .set(queue: queue_name, wait: 0.1) # 100ms delay
          .perform_later(task.id)
      else
        # Queue immediately
        job_class
          .set(queue: queue_name)
          .perform_later(task.id)
      end
    end
  end

  def job_class_for_task_type(task_type)
    case task_type
    when 'voice_followup'
      VoiceFollowupJob
    else
      # All other task types use the generic TaskExecutionJob
      # which routes to appropriate services internally
      TaskExecutionJob
    end
  end
end
