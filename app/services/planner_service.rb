# frozen_string_literal: true

# PlannerService - Generates structured execution plans for complex tasks
#
# Works with the Planner agent to:
# 1. Analyze request complexity
# 2. Break down into phases and steps
# 3. Map dependencies
# 4. Assign agents
# 5. Validate feasibility
#
class PlannerService
  attr_reader :entity, :user

  # Complexity thresholds
  COMPLEXITY_THRESHOLDS = {
    simple: { max_steps: 3, max_agents: 1 },
    medium: { max_steps: 10, max_agents: 3 },
    complex: { max_steps: 25, max_agents: 5 },
    epic: { max_steps: Float::INFINITY, max_agents: Float::INFINITY }
  }.freeze

  # Common patterns that indicate complexity
  COMPLEXITY_INDICATORS = {
    simple: [
      /^(show|view|list|get|check)\s/i,
      /^what (is|are)/i,
      /^how many/i
    ],
    complex: [
      /\b(and|with|also|plus)\b/i,      # Multiple things
      /\b(system|platform|suite)\b/i,    # Large scope
      /\b(complete|full|comprehensive)\b/i,
      /\b(integrate|connect|sync)\b/i,   # Integration work
      /\b(automate|workflow|process)\b/i # Automation
    ],
    epic: [
      /\b(entire|everything|all)\b/i,
      /\b(rebuild|replatform|migrate)\b/i,
      /multiple\s+(modules?|systems?|integrations?)/i
    ]
  }.freeze

  def initialize(entity:, user:)
    @entity = entity
    @user = user
  end

  # Analyze a request and determine if planning is needed
  def should_plan?(request)
    complexity = estimate_complexity(request)
    %i[complex epic].include?(complexity)
  end

  # Estimate complexity of a request
  def estimate_complexity(request)
    return :simple if request.length < 30

    # Check for epic indicators first
    if COMPLEXITY_INDICATORS[:epic].any? { |p| request.match?(p) }
      return :epic
    end

    # Count complexity indicators
    complex_matches = COMPLEXITY_INDICATORS[:complex].count { |p| request.match?(p) }
    simple_matches = COMPLEXITY_INDICATORS[:simple].count { |p| request.match?(p) }

    # Word count as additional signal
    word_count = request.split(/\s+/).length

    if complex_matches >= 3 || word_count > 50
      :complex
    elsif complex_matches >= 1 || word_count > 25
      :medium
    elsif simple_matches >= 1
      :simple
    else
      :medium
    end
  end

  # Generate a plan for a complex request
  # First checks for matching templates, then generates dynamically
  def generate_plan_skeleton(request, customizations: {})
    # Try to find a matching template
    template = PlanTemplate.find_best_match(request)
    
    if template
      Rails.logger.info "[PlannerService] Using template: #{template.name}"
      return template.create_plan(
        entity: entity,
        user: user,
        request: request,
        customizations: customizations
      )
    end

    # No template - generate dynamically
    Rails.logger.info "[PlannerService] No template match - generating dynamic plan"
    generate_dynamic_plan(request)
  end

  # Generate a plan without using templates
  def generate_dynamic_plan(request)
    complexity = estimate_complexity(request)
    
    # Detect required components and their agents
    components = detect_components(request)
    
    # Create base plan
    plan = ExecutionPlan.create!(
      entity: entity,
      user: user,
      title: generate_title(request),
      original_request: request,
      complexity: complexity.to_s,
      status: 'planning',
      requires_approval: %i[complex epic].include?(complexity)
    )

    # Generate phases with component-aware steps
    phases = generate_component_aware_phases(request, complexity, components)
    plan.update!(
      phases: phases,
      total_steps: phases.sum { |p| (p['steps'] || []).count }
    )

    plan
  end

  # Get available templates for display
  def available_templates
    PlanTemplate.active.popular.limit(20)
  end

  # Get templates by category
  def templates_for_category(category)
    PlanTemplate.active.by_category(category)
  end

  # Validate a plan before execution
  def validate_plan(plan)
    issues = []
    warnings = []

    # Check all steps have agents
    plan.all_steps.each do |step|
      unless step['agent']
        # Try to find a suitable agent using Smart Router
        router = Agents::SmartRouterService.new(entity: @entity, user: @user)
        results = router.find_best_agent(
          task_description: step['description'] || step['name'],
          tools_needed: step['tools_needed'] || []
        )
        
        if results.any?
          warnings << { step: step['id'], warning: "Will use #{results.first[:agent_slug]} at runtime" }
        else
          issues << { step: step['id'], issue: 'No agent assigned and none found via Smart Router' }
        end
        next
      end

      # Verify agent exists - if not, we'll find one at runtime
      agent = AgentPlugin.find_by(slug: step['agent'], status: 'active')
      unless agent
        # Try Smart Router as fallback
        router = Agents::SmartRouterService.new(entity: @entity, user: @user)
        results = router.find_best_agent(
          task_description: step['description'] || step['name'],
          tools_needed: step['tools_needed'] || []
        )
        
        if results.any?
          warnings << { step: step['id'], warning: "Agent '#{step['agent']}' not found, will use #{results.first[:agent_slug]}" }
        else
          issues << { step: step['id'], issue: "Agent '#{step['agent']}' not found and no alternative available" }
        end
        next
      end

      # Use intent-based tool matching instead of exact match
      tools_needed = step['tools_needed'] || []
      agent_tools = agent.agent_tools.pluck(:tool_name)
      matcher = Tools::ToolIntentMatcher.new(
        agent_tools: agent_tools,
        task_description: step['description'] || step['name']
      )
      match_result = matcher.can_satisfy?(tools_needed)
      
      unless match_result[:satisfied]
        warnings << { step: step['id'], warning: "Agent may lack tools: #{match_result[:missing].join(', ')}" }
      end
    end

    # Check for circular dependencies
    if has_circular_dependencies?(plan)
      issues << { step: nil, issue: 'Circular dependency detected' }
    end

    # Blocking issues are only circular dependencies or completely missing agents with no alternatives
    blocking_issues = issues.select { |i| 
      i[:issue].include?('Circular') || i[:issue].include?('no alternative available')
    }
    
    {
      valid: blocking_issues.empty?,  # Valid if no blocking issues
      issues: issues,
      warnings: warnings,
      can_execute: blocking_issues.empty?  # Can execute if no blocking issues
    }
  end

  # Get recommended agents for a step
  def recommend_agents_for_step(step_description, tools_needed = [])
    router = Agents::SmartRouterService.new(entity: entity, user: user)
    
    router.find_best_agent(
      task_description: step_description,
      tools_needed: tools_needed,
      top_n: 3
    )
  end

  # Re-plan after a step failure
  def handle_step_failure(plan, step_id, error)
    step = plan.find_step(step_id)
    return unless step

    options = []

    # Option 1: Retry with same agent
    if plan.retry_count < 3
      options << {
        action: 'retry',
        description: 'Retry the failed step',
        risk: 'low'
      }
    end

    # Option 2: Try different agent
    alternatives = recommend_agents_for_step(step['description'], step['tools_needed'])
    current_agent = step['agent']
    other_agents = alternatives.reject { |a| a[:agent_slug] == current_agent }

    if other_agents.any?
      options << {
        action: 'reassign',
        description: "Try with #{other_agents.first[:agent_name]}",
        new_agent: other_agents.first[:agent_slug],
        risk: 'medium'
      }
    end

    # Option 3: Skip and continue
    dependent_steps = plan.all_steps.select { |s| (s['dependencies'] || []).include?(step_id) }
    
    if dependent_steps.empty?
      options << {
        action: 'skip',
        description: 'Skip this step and continue',
        risk: 'medium'
      }
    end

    # Option 4: Pause for user input
    options << {
      action: 'pause',
      description: 'Pause and ask user for guidance',
      risk: 'low'
    }

    {
      step_id: step_id,
      error: error,
      options: options,
      recommendation: options.first
    }
  end

  private

  def generate_title(request)
    # Extract key nouns and action
    words = request.split(/\s+/).first(8).join(' ')
    words.length > 50 ? "#{words.truncate(47)}..." : words
  end

  def generate_phases(request, complexity)
    case complexity
    when :simple
      [discovery_phase(request)]
    when :medium
      [discovery_phase(request), build_phase(request)]
    when :complex
      [discovery_phase(request), design_phase(request), build_phase(request), test_phase(request)]
    when :epic
      [
        discovery_phase(request),
        design_phase(request),
        build_phase(request, split: true),
        integration_phase(request),
        test_phase(request),
        deploy_phase(request)
      ]
    end
  end

  def discovery_phase(request)
    {
      'id' => 'phase_discovery',
      'name' => 'Discovery',
      'description' => 'Understand requirements and gather information',
      'status' => 'pending',
      'steps' => [
        {
          'id' => 'step_understand_request',
          'name' => 'Understand Request',
          'description' => 'Analyze user requirements and clarify scope',
          'agent' => nil, # Planner will assign
          'tools_needed' => ['ask_user'],
          'status' => 'pending',
          'dependencies' => [],
          'estimated_minutes' => 5
        },
        {
          'id' => 'step_gather_context',
          'name' => 'Gather Context',
          'description' => 'Review existing data and configurations',
          'agent' => nil,
          'tools_needed' => ['get_data', 'get_schema'],
          'status' => 'pending',
          'dependencies' => ['step_understand_request'],
          'estimated_minutes' => 3
        }
      ]
    }
  end

  def design_phase(request)
    {
      'id' => 'phase_design',
      'name' => 'Design',
      'description' => 'Design the solution architecture',
      'status' => 'pending',
      'steps' => [
        {
          'id' => 'step_create_blueprint',
          'name' => 'Create Blueprint',
          'description' => 'Design the overall solution structure',
          'agent' => 'app_architect',
          'tools_needed' => ['generate_app_blueprint'],
          'status' => 'pending',
          'dependencies' => ['step_gather_context'],
          'estimated_minutes' => 10
        },
        {
          'id' => 'step_user_approval',
          'name' => 'Get User Approval',
          'description' => 'Review design with user and get approval',
          'agent' => nil,
          'tools_needed' => ['ask_user', 'load_canvas'],
          'status' => 'pending',
          'dependencies' => ['step_create_blueprint'],
          'estimated_minutes' => 5,
          'requires_input' => true
        }
      ]
    }
  end

  def build_phase(request, split: false)
    if split
      # For epic complexity, return a placeholder that Planner will expand
      {
        'id' => 'phase_build',
        'name' => 'Build',
        'description' => 'Build all components (Planner will expand)',
        'status' => 'pending',
        'steps' => [
          {
            'id' => 'step_build_components',
            'name' => 'Build Components',
            'description' => 'Build all required modules and components',
            'agent' => 'module_architect',
            'tools_needed' => ['approve_module_design', 'build_app'],
            'status' => 'pending',
            'dependencies' => ['step_user_approval'],
            'estimated_minutes' => 30,
            'expand_into_substeps' => true
          }
        ]
      }
    else
      {
        'id' => 'phase_build',
        'name' => 'Build',
        'description' => 'Build the solution',
        'status' => 'pending',
        'steps' => [
          {
            'id' => 'step_build',
            'name' => 'Build Solution',
            'description' => 'Create modules, canvases, and configurations',
            'agent' => 'module_architect',
            'tools_needed' => ['approve_module_design', 'update_module'],
            'status' => 'pending',
            'dependencies' => ['step_gather_context'],
            'estimated_minutes' => 15
          }
        ]
      }
    end
  end

  def integration_phase(request)
    {
      'id' => 'phase_integration',
      'name' => 'Integration',
      'description' => 'Connect all components together',
      'status' => 'pending',
      'steps' => [
        {
          'id' => 'step_integrate',
          'name' => 'Integrate Components',
          'description' => 'Connect modules, set up workflows, configure automations',
          'agent' => 'integration_architect',
          'tools_needed' => ['create_scheduled_task', 'update_module'],
          'status' => 'pending',
          'dependencies' => ['step_build_components'],
          'estimated_minutes' => 15
        }
      ]
    }
  end

  def test_phase(request)
    {
      'id' => 'phase_test',
      'name' => 'Test',
      'description' => 'Verify everything works correctly',
      'status' => 'pending',
      'steps' => [
        {
          'id' => 'step_test',
          'name' => 'Test Solution',
          'description' => 'Run tests and verify functionality',
          'agent' => nil,
          'tools_needed' => ['preview_app', 'get_data'],
          'status' => 'pending',
          'dependencies' => [], # Will be set based on previous phase
          'estimated_minutes' => 10
        }
      ]
    }
  end

  def deploy_phase(request)
    {
      'id' => 'phase_deploy',
      'name' => 'Deploy',
      'description' => 'Deploy to production',
      'status' => 'pending',
      'steps' => [
        {
          'id' => 'step_deploy',
          'name' => 'Deploy Solution',
          'description' => 'Publish and activate the solution',
          'agent' => nil,
          'tools_needed' => ['publish_app'],
          'status' => 'pending',
          'dependencies' => ['step_test'],
          'estimated_minutes' => 5
        }
      ]
    }
  end

  # Detect what components are needed based on request analysis
  # Returns a hash of component types and their specs
  COMPONENT_PATTERNS = {
    module: {
      patterns: [/\b(module|custom\s+module|data\s+model|schema|fields?)\b/i, /\bwith\s+fields?\b/i],
      agent: 'platform_factory',
      tools: ['start_module_design', 'propose_module_schema', 'approve_module_design'],
      priority: 1
    },
    app: {
      # Note: "app" often means a module with UI, not a separate App record
      # Only match explicit "app" patterns, not when module is also mentioned
      patterns: [/\b(complete\s+app|full\s+app|application\s+with)\b/i],
      agent: 'platform_factory',
      # Use build_app which orchestrates the full app creation flow
      tools: ['build_app', 'start_app_design'],
      priority: 1
    },
    landing_page: {
      patterns: [/\b(landing\s*page|page|website|web\s*page)\b/i],
      agent: 'ai_landing_page_creator',
      tools: ['create_landing_page', 'generate_landing_page'],
      priority: 2
    },
    integration: {
      patterns: [/\b(integration|api|connect|sync|webhook)\b/i],
      agent: 'integration_architect',
      tools: ['create_integration', 'create_integration_foundation', 'test_integration'],
      priority: 3
    },
    tool: {
      patterns: [/\b(tool|function|calculator|custom\s+tool)\b/i],
      agent: 'tool_builder',
      tools: ['create_tool', 'define_tool'],
      priority: 2
    },
    agent: {
      patterns: [/\b(agent|assistant|bot|ai\s+agent)\b/i],
      agent: 'agent_architect',
      tools: ['create_agent', 'design_agent'],
      priority: 3
    },
    workflow: {
      patterns: [/\b(workflow|automation|process|sequence)\b/i],
      agent: 'workflow_architect',
      tools: ['create_workflow', 'define_automation'],
      priority: 3
    },
    campaign: {
      patterns: [/\b(campaign|email\s*campaign|marketing\s*campaign)\b/i],
      agent: nil, # Scout handles directly
      tools: ['create_object'],
      priority: 2
    }
  }.freeze

  def detect_components(request)
    request_lower = request.downcase
    detected = {}

    COMPONENT_PATTERNS.each do |component_type, config|
      if config[:patterns].any? { |p| request_lower.match?(p) }
        detected[component_type] = {
          agent: config[:agent],
          tools: config[:tools],
          priority: config[:priority]
        }
      end
    end

    # IMPORTANT: If both "module" and "app" are detected, use only module
    # The platform factory creates modules; "app" in user requests typically means a module with UI
    if detected[:module] && detected[:app]
      Rails.logger.info "[PlannerService] Both module and app detected - using module only (app is implicit)"
      detected.delete(:app)
    end

    # Default to module if "build" or "create" is mentioned but no specific component detected
    if detected.empty? && request_lower.match?(/\b(build|create|make)\b/)
      detected[:module] = COMPONENT_PATTERNS[:module].except(:patterns)
    end

    Rails.logger.info "[PlannerService] Detected components: #{detected.keys.join(', ')}"
    detected
  end

  # Generate phases based on detected components
  def generate_component_aware_phases(request, complexity, components)
    phases = []
    step_counter = 0
    previous_step_id = nil

    # Sort components by priority (lower = earlier)
    sorted_components = components.sort_by { |_, config| config[:priority] }

    sorted_components.each do |component_type, config|
      step_counter += 1
      step_id = "step_#{component_type}_#{step_counter}"

      step = {
        'id' => step_id,
        'name' => "Build #{component_type.to_s.titleize}",
        'description' => generate_step_description(component_type, request),
        'agent' => config[:agent],
        'tools_needed' => config[:tools],
        'status' => 'pending',
        'dependencies' => previous_step_id ? [previous_step_id] : [],
        'estimated_minutes' => estimate_step_duration(component_type)
      }

      # Group steps into phases by type
      phase_name = phase_for_component(component_type)
      existing_phase = phases.find { |p| p['name'] == phase_name }

      if existing_phase
        existing_phase['steps'] << step
      else
        phases << {
          'id' => "phase_#{phases.length + 1}",
          'name' => phase_name,
          'description' => "#{phase_name} phase",
          'status' => 'pending',
          'steps' => [step]
        }
      end

      previous_step_id = step_id
    end

    # If no components detected, fall back to generic phases
    if phases.empty?
      return generate_phases(request, complexity)
    end

    phases
  end

  def generate_step_description(component_type, request)
    case component_type
    when :module, :app
      "Create the #{component_type} with specified fields and configuration"
    when :landing_page
      "Design and generate the landing page with content"
    when :integration
      "Set up the external API integration and test connectivity"
    when :tool
      "Create the custom tool with specified functionality"
    when :agent
      "Design and configure the specialized agent"
    when :workflow
      "Set up the automation workflow"
    when :campaign
      "Create the marketing campaign"
    else
      "Execute #{component_type} step"
    end
  end

  def phase_for_component(component_type)
    case component_type
    when :module, :app
      'Foundation'
    when :landing_page, :campaign
      'Content'
    when :integration, :workflow
      'Integration'
    when :tool, :agent
      'Automation'
    else
      'Build'
    end
  end

  def estimate_step_duration(component_type)
    case component_type
    when :module then 15
    when :app then 20
    when :landing_page then 10
    when :integration then 15
    when :tool then 10
    when :agent then 15
    when :workflow then 10
    when :campaign then 5
    else 10
    end
  end

  def has_circular_dependencies?(plan)
    # Build dependency graph
    graph = {}
    plan.all_steps.each do |step|
      graph[step['id']] = step['dependencies'] || []
    end

    # DFS to detect cycles
    visited = {}
    rec_stack = {}

    graph.keys.each do |step_id|
      if detect_cycle(step_id, graph, visited, rec_stack)
        return true
      end
    end

    false
  end

  def detect_cycle(step_id, graph, visited, rec_stack)
    return true if rec_stack[step_id]
    return false if visited[step_id]

    visited[step_id] = true
    rec_stack[step_id] = true

    (graph[step_id] || []).each do |dep|
      return true if detect_cycle(dep, graph, visited, rec_stack)
    end

    rec_stack[step_id] = false
    false
  end
end

