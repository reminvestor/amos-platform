class PlannerAgentService
  attr_reader :user, :entity, :session_id
  
  def initialize(user:, entity:, session_id:)
    @user = user
    @entity = entity
    @session_id = session_id
  end
  
  def plan_workflow(request_text, context = {})
    # First, check if we have a matching workflow template
    template = find_matching_template(request_text)
    
    if template
      # Use template as base and customize
      workflow = template.generate_workflow(extract_template_params(request_text))
      Rails.logger.info "Using workflow template: #{template.name}"
    else
      # Generate a new workflow from scratch
      workflow = generate_custom_workflow(request_text, context)
      Rails.logger.info "Generated custom workflow"
    end
    
    # Validate and optimize the workflow
    validate_workflow!(workflow)
    optimize_workflow!(workflow)
    
    # Create TaskSession to track execution
    task_session = create_task_session(workflow, request_text)
    
    {
      success: true,
      workflow: workflow,
      task_session: task_session,
      template_used: template&.slug
    }
  rescue => e
    Rails.logger.error "Planner failed: #{e.message}"
    { success: false, error: e.message }
  end
  
  private
  
  def find_matching_template(request_text)
    # Use AI to match request to available templates
    templates = WorkflowTemplate.active
    
    # Simple keyword matching for now (can be enhanced with AI)
    templates.find do |template|
      keywords = template.metadata['keywords'] || []
      keywords.any? { |keyword| request_text.downcase.include?(keyword.downcase) }
    end
  end
  
  def extract_template_params(request_text)
    # Extract parameters from request text for template interpolation
    # This would use NLP/AI in production
    {
      time_period: extract_time_period(request_text),
      entity_name: @entity.name,
      user_name: @user.full_name
    }
  end
  
  def generate_custom_workflow(request_text, context)
    # Analyze the request to determine required steps
    intent = analyze_intent(request_text)
    
    steps = []
    
    case intent[:type]
    when 'analytics'
      steps = build_analytics_steps(intent)
    when 'campaign_creation'
      steps = build_campaign_steps(intent)
    when 'data_import'
      steps = build_data_import_steps(intent)
    else
      steps = build_generic_steps(intent)
    end
    
    SimpleWorkflow.new(
      name: intent[:name] || "Custom Workflow",
      description: intent[:description] || request_text,
      steps: steps,
      metadata: {
        generated_at: Time.current,
        intent: intent
      }
    )
  end
  
  def analyze_intent(request_text)
    # Simplified intent analysis (would use AI in production)
    intent = {
      type: 'generic',
      name: nil,
      description: nil,
      entities: [],
      actions: []
    }
    
    # Detect analytics requests
    if request_text.match?(/analyz|report|metric|performance|trend/i)
      intent[:type] = 'analytics'
      intent[:name] = "Analytics Workflow"
      
      # Detect time period
      if request_text.match?(/year|annual|yearly/i)
        intent[:time_period] = 'year'
      elsif request_text.match?(/month|monthly/i)
        intent[:time_period] = 'month'
      elsif request_text.match?(/week|weekly/i)
        intent[:time_period] = 'week'
      end
      
      # Detect data source
      if request_text.match?(/stripe|payment|customer/i)
        intent[:data_source] = 'stripe'
      elsif request_text.match?(/shopify|order|product/i)
        intent[:data_source] = 'shopify'
      end
    end
    
    # Detect campaign creation
    if request_text.match?(/create.*campaign|new.*campaign|build.*campaign/i)
      intent[:type] = 'campaign_creation'
      intent[:name] = "Campaign Creation Workflow"
    end
    
    # Detect data import
    if request_text.match?(/import|sync|fetch.*data|pull.*data/i)
      intent[:type] = 'data_import'
      intent[:name] = "Data Import Workflow"
    end
    
    intent
  end
  
  def build_analytics_steps(intent)
    steps = []
    
    # Step 1: Fetch data from integration
    if intent[:data_source]
      steps << Step.new(
        id: 'fetch_data',
        agent_role: 'executor',
        name: 'Fetch Data',
        description: "Fetch data from #{intent[:data_source]}",
        type: 'tool_call',
        config: {
          tool: 'invoke_operation',
          requires_connection: true
        },
        tool_allowlist: ['list_connections', 'invoke_operation'],
        canvas_allowlist: ['dynamic_canvas'],
        budgets: { max_tool_calls: 5, timeout_seconds: 60 }
      )
    end
    
    # Step 2: Analyze data
    steps << Step.new(
      id: 'analyze_data',
      agent_role: 'analyst',
      name: 'Analyze Data',
      description: 'Perform data analysis and aggregations',
      type: 'tool_call',
      config: {
        tool: 'aggregate_artifact_data',
        depends_on: ['fetch_data']
      },
      dependencies: ['fetch_data'],
      tool_allowlist: ['aggregate_artifact_data', 'fetch_next_page'],
      canvas_allowlist: ['dynamic_canvas', 'analytics_dashboard'],
      budgets: { max_tool_calls: 10, timeout_seconds: 120 }
    )
    
    # Step 3: Generate insights
    steps << Step.new(
      id: 'generate_insights',
      agent_role: 'analyst',
      name: 'Generate Insights',
      description: 'Generate insights and recommendations',
      type: 'tool_call',
      config: {
        tool: 'create_dynamic_visualization',
        depends_on: ['analyze_data']
      },
      dependencies: ['analyze_data'],
      tool_allowlist: ['create_dynamic_visualization'],
      canvas_allowlist: ['dynamic_canvas'],
      budgets: { max_tool_calls: 3, timeout_seconds: 30 }
    )
    
    # Step 4: Verify results
    steps << Step.new(
      id: 'verify_results',
      agent_role: 'verifier',
      name: 'Verify Results',
      description: 'Verify analysis quality and completeness',
      type: 'validation',
      config: {
        rules: [
          { type: 'data_completeness', threshold: 0.8 },
          { type: 'insight_quality', min_insights: 3 }
        ]
      },
      dependencies: ['generate_insights'],
      tool_allowlist: ['get_data'],
      canvas_allowlist: ['task_progress'],
      budgets: { max_tool_calls: 2, timeout_seconds: 30 }
    )
    
    steps
  end
  
  def build_campaign_steps(intent)
    [
      Step.new(
        id: 'define_campaign',
        agent_role: 'executor',
        name: 'Define Campaign',
        description: 'Define campaign parameters',
        type: 'user_input',
        config: {
          fields: [
            { name: 'campaign_name', type: 'text', required: true },
            { name: 'campaign_type', type: 'select', options: ['Email', 'Social'], required: true },
            { name: 'target_audience', type: 'text' }
          ]
        },
        tool_allowlist: [],
        canvas_allowlist: ['campaign_viewer']
      ),
      Step.new(
        id: 'create_campaign',
        agent_role: 'executor',
        name: 'Create Campaign',
        description: 'Create the campaign',
        type: 'tool_call',
        config: {
          tool: 'create_object',
          inputs: { object_type: 'campaigns' }
        },
        dependencies: ['define_campaign'],
        tool_allowlist: ['create_object', 'get_schema'],
        canvas_allowlist: ['campaign_viewer']
      )
    ]
  end
  
  def build_data_import_steps(intent)
    [
      Step.new(
        id: 'select_source',
        agent_role: 'executor',
        name: 'Select Data Source',
        description: 'Select integration to import from',
        type: 'tool_call',
        config: {
          tool: 'list_connections'
        },
        tool_allowlist: ['list_connections', 'describe_connection'],
        canvas_allowlist: ['integrations_manager']
      ),
      Step.new(
        id: 'import_data',
        agent_role: 'executor',
        name: 'Import Data',
        description: 'Import data from selected source',
        type: 'tool_call',
        config: {
          tool: 'invoke_operation'
        },
        dependencies: ['select_source'],
        tool_allowlist: ['invoke_operation', 'fetch_next_page'],
        canvas_allowlist: ['dynamic_canvas']
      )
    ]
  end
  
  def build_generic_steps(intent)
    # Fallback to a simple single-step workflow
    [
      Step.new(
        id: 'execute_task',
        agent_role: 'executor',
        name: 'Execute Task',
        description: intent[:description] || 'Execute the requested task',
        type: 'tool_call',
        config: {
          tool: 'get_data'  # Safe default
        },
        tool_allowlist: ['get_data', 'create_object', 'get_schema'],
        canvas_allowlist: ['dynamic_canvas']
      )
    ]
  end
  
  def validate_workflow!(workflow)
    # Ensure workflow has required properties
    raise "Workflow must have steps" if workflow.steps.empty?
    
    # Validate step dependencies
    step_ids = workflow.steps.map(&:id)
    workflow.steps.each do |step|
      step.dependencies.each do |dep|
        unless step_ids.include?(dep)
          raise "Step #{step.id} has invalid dependency: #{dep}"
        end
      end
    end
    
    # Validate agent roles
    workflow.steps.each do |step|
      unless AgentLoadout::AGENT_ROLES.include?(step.agent_role)
        raise "Step #{step.id} has invalid agent role: #{step.agent_role}"
      end
    end
  end
  
  def optimize_workflow!(workflow)
    # Optimize step order based on dependencies
    # This is a simple topological sort
    sorted_steps = []
    remaining_steps = workflow.steps.dup
    
    while remaining_steps.any?
      # Find steps with no pending dependencies
      ready_steps = remaining_steps.select do |step|
        step.dependencies.all? { |dep| sorted_steps.any? { |s| s.id == dep } }
      end
      
      if ready_steps.empty?
        raise "Circular dependency detected in workflow"
      end
      
      # Add ready steps to sorted list
      sorted_steps.concat(ready_steps)
      remaining_steps -= ready_steps
    end
    
    workflow.steps = sorted_steps
  end
  
  def create_task_session(workflow, request_text)
    TaskSession.create!(
      user: @user,
      status: 'active',
      metadata: {
        session_id: @session_id,
        entity_id: @entity.id,
        request_text: request_text,
        workflow_name: workflow.name,
        total_steps: workflow.steps.length,
        step_order: workflow.steps.map(&:id)
      }
    )
  end
  
  def extract_time_period(text)
    if text.match?(/last\s+year|past\s+year/i)
      'last_year'
    elsif text.match?(/this\s+year|current\s+year/i)
      'this_year'
    elsif text.match?(/last\s+month/i)
      'last_month'
    elsif text.match?(/this\s+month/i)
      'this_month'
    else
      'all_time'
    end
  end
end
