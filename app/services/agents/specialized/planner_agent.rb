module Agents
  module Specialized
    class PlannerAgent < Agents::Base::BaseAgent
      def initialize(task_session: nil, initial_context: {})
        super(
          role: :planner,
          capabilities: [
            'workflow_planning',
            'task_decomposition', 
            'resource_estimation',
            'dependency_analysis',
            'template_selection',
            'cost_optimization',
            'risk_assessment'
          ],
          context: initial_context,
          task_session: task_session
        )
        
        @workflow_templates = WorkflowTemplate.active_with_files rescue []
        
        # Tool catalog is required for planning
        begin
          @tool_catalog = ::Tools::ToolCatalog.instance
          Rails.logger.info "Tool catalog loaded with #{@tool_catalog.tools.size} tools"
        rescue => e
          Rails.logger.error "Failed to load tool catalog: #{e.message}"
          @tool_catalog = nil
        end
        
        @learning_engine = LearningEngine.new rescue nil
        
        # AI service is required - fail fast if not available
        begin
          @ai_service = BedrockService.new
        rescue => e
          Rails.logger.error "Failed to initialize BedrockService: #{e.message}"
          raise "Cannot initialize PlannerAgent without AI service: #{e.message}"
        end
      end
      
      # Override system prompt for planning expertise
      def system_prompt
        <<~PROMPT
          You are an expert AI Planning Agent responsible for creating optimal workflow plans.
          
          Your responsibilities:
          1. Analyze user requests and decompose them into actionable steps
          2. Select appropriate workflow templates when available
          3. Estimate resource costs and execution time
          4. Identify dependencies and optimal execution order
          5. Consider parallel execution opportunities
          6. Learn from past successes and failures
          7. Assign appropriate agent roles to each step
          
          IMPORTANT: You are the PLANNER, not the EXECUTOR.
          - You CREATE plans but DO NOT execute them
          - Other specialized agents (executor, analyst, verifier) will execute the steps you plan
          - Assign agent_role to steps based on what they do:
            * "executor" for action steps (create, update, invoke tools)
            * "analyst" for thinking/analysis steps (analyze data, make decisions)
            * "verifier" for validation steps (check results, verify requirements)
          - NEVER assign "planner" as an agent_role for execution steps!
          
          Available workflow templates:
          #{@workflow_templates.any? ? @workflow_templates.map { |t| "- #{t.name}: #{t.description}" }.join("\n") : "No templates available"}
          
          Read-only tools (for analysis/discovery):
          #{@tool_catalog ? @tool_catalog.read_only_tools.map { |t| "- #{t[:name]}: #{t[:description]}" }.join("\n") : "Tool catalog not available"}
          
          Runnable tools (modify state):
          #{@tool_catalog ? @tool_catalog.runnable_tools.map { |t| "- #{t[:name]}: #{t[:description]}" }.join("\n") : "Tool catalog not available"}
          
          IMPORTANT: Only use tools from the above list. Common tools include:
          - get_data: Retrieve data from the system (uses PLURAL object types: campaigns, contacts, email_templates)
          - create_object: Create new objects (uses PLURAL object types: campaigns, contacts, email_templates)
          - get_schema: Get database schema information (uses SINGULAR object types: campaign, contact, email_template)
          - update_object: Update existing objects (accepts both singular/plural object types)
          - manage_task_list: Create and manage task lists
          - generate_ai_landing_page: Generate AI-powered landing pages
          - update_landing_page_content: Update landing page content
          - web_search: Search the web for information
          
          CRITICAL OBJECT TYPE RULES:
          - get_schema: ALWAYS use SINGULAR (campaign, contact, email_template, contact_group)
          - create_object: ALWAYS use PLURAL (campaigns, contacts, email_templates, contact_groups)
          - get_data: ALWAYS use PLURAL (campaigns, contacts, email_templates, contact_groups)
          - update_object: Can use either (tool will normalize)
          
          Always create plans that are:
          - Efficient (minimize time and cost)
          - Robust (handle likely failure cases)
          - Clear (each step has defined inputs/outputs)
          - Measurable (include success criteria)
        PROMPT
      end
      
      # Main planning method
      def plan_workflow(request_text, context = {}, attempt = 0)
        Rails.logger.info "PlannerAgent #{@id}: Creating workflow plan for: #{request_text} (attempt #{attempt + 1})"
        
        # Prevent infinite recursion
        if attempt >= 3
          Rails.logger.error "Max planning attempts reached"
          return {
            success: false,
            error: "Failed to create valid plan after 3 attempts",
            issues: context[:issues] || []
          }
        end
        
        # Analyze the request
        Rails.logger.info "Step 1: Analyzing request..."
        analysis = analyze_request(request_text, context)
        Rails.logger.info "Analysis complete: #{analysis[:intent]}, complexity: #{analysis[:complexity]}"
        
        # Check if we can use an existing template
        Rails.logger.info "Step 2: Finding matching template..."
        if template = find_matching_template(analysis)
          Rails.logger.info "Found template: #{template.name}"
          plan = adapt_template_to_request(template, analysis)
        else
          Rails.logger.info "No template found, creating custom plan..."
          # Create custom plan
          plan = create_custom_plan(analysis)
        end
        Rails.logger.info "Plan created with #{plan['steps']&.count || 0} steps"
        
        # Optimize the plan
        Rails.logger.info "Step 3: Optimizing plan..."
        optimized_plan = optimize_plan(plan, context)
        Rails.logger.info "Optimization complete"
        
        # Validate the plan
        Rails.logger.info "Step 4: Validating plan..."
        validation_result = validate_plan(optimized_plan)
        Rails.logger.info "Validation result: #{validation_result[:valid] ? 'valid' : 'invalid'}"
        
        if validation_result[:valid]
          # Learn from this planning decision
          @memory.store_long_term(:successful_plans, {
            request: request_text,
            analysis: analysis,
            plan: optimized_plan,
            template_used: template&.slug
          })
          
          Rails.logger.info "Step 5: Building workflow from plan..."
          workflow = build_workflow_from_plan(optimized_plan)
          Rails.logger.info "Workflow built successfully"
          
          {
            success: true,
            workflow: workflow,
            confidence: calculate_plan_confidence(optimized_plan),
            estimated_cost: estimate_plan_cost(optimized_plan),
            estimated_duration: estimate_plan_duration(optimized_plan),
            risks: identify_risks(optimized_plan)
          }
        else
          # Try to fix the plan or request help
          fixed_plan = attempt_plan_repair(optimized_plan, validation_result[:issues])
          
          if fixed_plan
            # Pass the issues in context and increment attempt counter
            plan_workflow(request_text, context.merge(issues: validation_result[:issues]), attempt + 1)
          else
            request_planning_assistance(request_text, validation_result[:issues])
          end
        end
      end
      
      # Create recovery plan for failed steps
      def create_recovery_plan(failed_step:, error:, context:)
        Rails.logger.info "PlannerAgent #{@id}: Creating recovery plan for failed step: #{failed_step[:id]}"
        
        # Analyze the failure
        failure_analysis = analyze_failure(failed_step, error, context)
        
        # Find similar past failures and their solutions
        past_solutions = @memory.find_relevant_patterns({
          type: 'failure_recovery',
          step_type: failed_step[:type],
          error_type: error.class.name
        })
        
        # Generate recovery options
        recovery_options = generate_recovery_options(failure_analysis, past_solutions)
        
        # Select best recovery strategy
        best_strategy = select_recovery_strategy(recovery_options, context)
        
        # Build recovery workflow
        recovery_workflow = build_recovery_workflow(best_strategy, failed_step)
        
        {
          success: true,
          workflow: recovery_workflow,
          strategy: best_strategy[:name],
          confidence: best_strategy[:confidence]
        }
      end
      
      protected
      
      def has_pending_decisions?
        # Check if there are planning requests in our context
        planning_requests = @context.read(:planning_requests) || []
        planning_requests.any?
      end
      
      private
      
      def analyze_request(request_text, context)
        # Use AI to deeply analyze the request
        prompt = <<~PROMPT
          Analyze this request and extract key information:
          
          Request: "#{request_text}"
          Context: #{context.to_json}
          
          Extract:
          1. Primary intent/goal
          2. Required capabilities
          3. Data inputs needed
          4. Expected outputs
          5. Constraints (time, cost, quality)
          6. Dependencies
          7. Success criteria
          
          Respond in JSON format.
        PROMPT
        
        response = @ai_service.complete(
          messages: [
            { role: 'system', content: 'You are a request analysis expert.' },
            { role: 'user', content: prompt }
          ],
          temperature: 0.3,
          max_tokens: 4000
        )
        
        begin
          # The complete method returns just the content string
          analysis = JSON.parse(response, symbolize_names: true)
          
          # Enhance with pattern matching
          analysis[:patterns] = detect_request_patterns(request_text)
          analysis[:complexity] = estimate_complexity(analysis)
          
          analysis
        rescue => e
          Rails.logger.error "Failed to analyze request: #{e.message}"
          
          # Fallback analysis
          {
            intent: 'unknown',
            required_capabilities: [],
            patterns: detect_request_patterns(request_text),
            complexity: :medium
          }
        end
      end
      
      def detect_request_patterns(text)
        patterns = []
        
        # Multi-step patterns
        patterns << :multi_step if text.match?(/\b(and then|after that|followed by|steps?)\b/i)
        patterns << :conditional if text.match?(/\b(if|when|unless|depending on)\b/i)
        patterns << :iterative if text.match?(/\b(all|each|every|for each)\b/i)
        
        # Domain patterns
        patterns << :campaign if text.match?(/\b(campaign|email|newsletter)\b/i)
        patterns << :landing_page if text.match?(/\b(landing page|website|page)\b/i)
        patterns << :analytics if text.match?(/\b(analyze|report|metrics|data)\b/i)
        patterns << :integration if text.match?(/\b(connect|integrate|api|sync)\b/i)
        
        patterns
      end
      
      def estimate_complexity(analysis)
        # Estimate complexity based on various factors
        score = 0
        
        # Check required capabilities
        score += (analysis[:required_capabilities]&.size || 0) * 2
        
        # Check number of expected outputs
        score += (analysis[:expected_outputs]&.size || 0)
        
        # Check for integrations
        score += 3 if analysis[:dependencies]&.any? { |d| d.to_s.include?('integration') }
        
        # Check for data volume
        score += 2 if analysis[:data_inputs]&.any? { |d| d.to_s.include?('large') || d.to_s.include?('bulk') }
        
        # Determine complexity level
        case score
        when 0..3
          'simple'
        when 4..7
          'medium'
        else
          'complex'
        end
      end
      
      def find_matching_template(analysis)
        # Score each template
        template_scores = @workflow_templates.map do |template|
          score = calculate_template_match_score(template, analysis)
          { template: template, score: score }
        end
        
        # Get best match if score is high enough
        best_match = template_scores.max_by { |ts| ts[:score] }
        best_match[:score] > 0.7 ? best_match[:template] : nil
      end
      
      def calculate_template_match_score(template, analysis)
        score = 0.0
        
        # Keyword matching
        template_keywords = template.metadata['keywords'] || []
        analysis_keywords = extract_keywords(analysis)
        
        keyword_overlap = (template_keywords & analysis_keywords).size
        score += keyword_overlap * 0.2
        
        # Capability matching
        template_capabilities = extract_template_capabilities(template)
        required_capabilities = analysis[:required_capabilities] || []
        
        capability_match = (template_capabilities & required_capabilities).size.to_f / 
                          [required_capabilities.size, 1].max
        score += capability_match * 0.5
        
        # Pattern matching
        if analysis[:patterns]&.include?(template.category.to_sym)
          score += 0.3
        end
        
        [score, 1.0].min
      end
      
      def extract_keywords(analysis)
        keywords = []
        
        # Extract from intent
        keywords.concat(analysis[:intent].to_s.split(/\W+/))
        
        # Extract from patterns
        keywords.concat(analysis[:patterns].map(&:to_s)) if analysis[:patterns]
        
        keywords.map(&:downcase).uniq
      end
      
      def extract_template_capabilities(template)
        # Extract required tools from template steps
        capabilities = []
        
        if template.template_spec['steps']
          template.template_spec['steps'].each do |step|
            if step['required_tools']
              capabilities.concat(step['required_tools'])
            end
          end
        end
        
        capabilities.uniq
      end
      
      def adapt_template_to_request(template, analysis)
        plan = template.template_spec.deep_dup
        
        # Customize the plan based on analysis
        plan['name'] = "#{template.name} - Customized"
        plan['context'] = analysis
        
        # V2 templates have phases, V1 templates have steps
        if plan['phases']
          # V2 template - preserve phases structure
          Rails.logger.info "Adapting V2 template with #{plan['phases'].length} phases"
          # For V2, we generally don't need to adapt phases - they're already flexible
          # The phase executors will handle context intelligently
        elsif plan['steps']
          # V1 template - adapt steps (legacy support)
          Rails.logger.info "Adapting V1 template with #{plan['steps'].length} steps"
          plan['steps'] = plan['steps'].map do |step|
            adapt_step_to_context(step, analysis)
          end
        end
        
        plan
      end
      
      def adapt_step_to_context(step, analysis)
        adapted_step = step.dup
        
        # Add context-specific parameters
        if adapted_step['tool_args']
          adapted_step['tool_args'] = inject_context_into_args(
            adapted_step['tool_args'],
            analysis
          )
        end
        
        adapted_step
      end
      
      def inject_context_into_args(args, analysis)
        # Replace template variables with actual values from analysis
        args.deep_transform_values do |value|
          if value.is_a?(String) && value.include?('{{')
            # Simple template replacement
            value.gsub(/\{\{(\w+)\}\}/) do |match|
              key = $1.to_sym
              analysis[key] || match
            end
          else
            value
          end
        end
      end
      
      def create_custom_plan(analysis)
        Rails.logger.info "Creating custom plan for complexity: #{analysis[:complexity]}"
        
        # AI service is required for planning
        if @ai_service.nil?
          raise "AI service is not available - cannot create workflow plans without AI"
        end
        
        prompt = build_planning_prompt(analysis)
        
        response = @ai_service.complete(
          messages: [
            { role: 'system', content: system_prompt },
            { role: 'user', content: prompt }
          ],
          temperature: 0.5,
          max_tokens: 8000
        )
        
        begin
          plan_json = extract_json_from_response(response)
          validate_plan_structure(plan_json)
          plan_json
        rescue => e
          Rails.logger.error "Failed to create custom plan: #{e.message}"
          create_fallback_plan(analysis)
        end
      end
      
      def build_planning_prompt(analysis)
        <<~PROMPT
          Create a workflow plan for this analyzed request:
          
          #{analysis.to_json}
          
          The plan should be in this V2 PHASE-BASED JSON format:
          {
            "name": "Workflow name",
            "description": "What this workflow does",
            "template_version": 2,
            "phases": [
              {
                "id": "gather_context",
                "type": "gather_context",
                "name": "Gather Information",
                "required_fields": [
                  {
                    "key": "field_name",
                    "prompt": "What should I ask the user?",
                    "required": true,
                    "validation": "email|url|text|number"
                  }
                ],
                "context_sources": ["user_input", "uploaded_files", "existing_data"]
              },
              {
                "id": "execute_goal",
                "type": "execute_goal",
                "name": "Execute the Task",
                "goal": "Clear description of what to accomplish",
                "execution_strategy": {
                  "approach": "adaptive",
                  "allowed_tools": ["tool1", "tool2"],
                  "constraints": {
                    "max_cost": 100,
                    "timeout_seconds": 300
                  }
                },
                "requires_from_previous": ["field_name"],
                "ai_instructions": "Instructions for AI on how to accomplish the goal"
              },
              {
                "id": "validate_result",
                "type": "validate_result",
                "name": "Verify Success",
                "validation_criteria": {
                  "required_outputs": ["output1"],
                  "quality_checks": ["check1"]
                },
                "success_message": "Message to show user on success"
              }
            ]
          }
          
          CRITICAL V2 PHASE RULES:
          - Use "phases" NOT "steps" (this is V2!)
          - Phase 1 is ALWAYS "gather_context" type (collect any needed info)
          - Phase 2 is ALWAYS "execute_goal" type (do the work)
          - Phase 3 is ALWAYS "validate_result" type (verify success)
          - Each phase is conversational and can interact with the user naturally
          
          Include error handling and parallel execution where appropriate.
          
          CRITICAL: Only use these exact tool names in the "tool" field:
          - get_data
          - create_object
          - get_schema
          - manage_task_list
          - generate_ai_landing_page
          - update_landing_page_content
          - analyze_landing_page_request
          - process_landing_page_images
          - web_search
          - list_connections
          - invoke_operation
          - create_rag_store
          - aggregate_artifact_data
          - create_dynamic_visualization
          
          DO NOT make up tool names!
          
          CRITICAL OBJECT TYPE RULES for tool_args:
          - For get_data tool: Use PLURAL (campaigns, contacts, email_templates, contact_groups)
          - For create_object tool: Use PLURAL (campaigns, contacts, email_templates, contact_groups)
          - For get_schema tool: Use SINGULAR (campaign, contact, email_template, contact_group)
          - For update_object tool: Use SINGULAR (campaign, contact, email_template, contact_group)
          
          These rules are MANDATORY. Never use singular for create_object!
        PROMPT
      end
      
      def extract_json_from_response(response)
        # The complete method returns just the content string
        content = response.is_a?(String) ? response : response.to_s
        
        # Find JSON in response
        json_match = content.match(/\{.*\}/m)
        raise "No JSON found in response" unless json_match
        
        JSON.parse(json_match[0])
      end
      
      def validate_plan_structure(plan)
        raise "Plan missing required fields" unless plan['name'] && plan['steps']
        
        plan['steps'].each do |step|
          raise "Step missing required fields" unless step['id'] && step['type']
        end
      end
      
      def create_fallback_plan(analysis)
        {
          'name' => 'Generic Workflow',
          'description' => 'Fallback workflow for request',
          'steps' => [
            {
              'id' => 'analyze',
              'name' => 'Analyze Requirements',
              'type' => 'tool_call',
              'tool' => 'get_schema',
              'tool_args' => {},
              'agent_role' => 'analyst',
              'dependencies' => []
            },
            {
              'id' => 'execute',
              'name' => 'Execute Task',
              'type' => 'tool_call',
              'tool' => 'create_object',
              'tool_args' => {},
              'agent_role' => 'executor',
              'dependencies' => ['analyze']
            }
          ]
        }
      end
      
      def optimize_plan(plan, context)
        optimized = plan.dup
        
        # Identify parallelization opportunities
        optimized['steps'] = identify_parallel_steps(plan['steps'])
        
        # Optimize resource usage
        optimized = optimize_resource_allocation(optimized, context)
        
        # Add caching where beneficial
        optimized = add_caching_steps(optimized)
        
        # Learn from past optimizations
        past_optimizations = @memory.get_long_term(:optimization_patterns) || []
        optimized = apply_learned_optimizations(optimized, past_optimizations)
        
        optimized
      end
      
      def identify_parallel_steps(steps)
        # Group steps that can run in parallel
        dependency_graph = build_dependency_graph(steps)
        parallel_groups = find_parallel_groups(dependency_graph)
        
        # Mark steps for parallel execution
        steps.map do |step|
          if group = parallel_groups.find { |g| g.include?(step['id']) }
            step['parallel_group'] = group.first
          end
          step
        end
      end
      
      def build_dependency_graph(steps)
        graph = {}
        
        steps.each do |step|
          graph[step['id']] = {
            dependencies: step['dependencies'] || [],
            dependents: []
          }
        end
        
        # Build reverse dependencies
        graph.each do |step_id, info|
          info[:dependencies].each do |dep_id|
            graph[dep_id][:dependents] << step_id if graph[dep_id]
          end
        end
        
        graph
      end
      
      def find_parallel_groups(dependency_graph)
        groups = []
        
        # Find steps with same dependencies (can run in parallel)
        dependency_graph.each do |step_id, info|
          next if groups.any? { |g| g.include?(step_id) }
          
          parallel_candidates = dependency_graph.select do |other_id, other_info|
            other_id != step_id && 
            other_info[:dependencies] == info[:dependencies]
          end.keys
          
          if parallel_candidates.any?
            groups << [step_id] + parallel_candidates
          end
        end
        
        groups
      end
      
      def optimize_resource_allocation(plan, context)
        if context[:optimization_preference] == 'cost'
          # Prefer sequential execution for cost optimization
          plan['execution_mode'] = 'sequential'
        elsif context[:optimization_preference] == 'speed'
          # Prefer parallel execution for speed
          plan['execution_mode'] = 'parallel'
        else
          # Balanced approach
          plan['execution_mode'] = 'balanced'
        end
        
        plan
      end
      
      def add_caching_steps(plan)
        # Add caching for expensive operations
        plan['steps'].each do |step|
          if step['estimated_cost'] && step['estimated_cost'] > 10
            step['cache_result'] = true
            step['cache_duration'] = 3600 # 1 hour
          end
        end
        
        plan
      end
      
      def apply_learned_optimizations(plan, past_optimizations)
        # Apply successful optimization patterns from the past
        relevant_patterns = past_optimizations.select do |opt|
          opt[:applicable_to] == plan['name'] || 
          opt[:pattern_type] == 'general'
        end
        
        relevant_patterns.each do |pattern|
          plan = apply_optimization_pattern(plan, pattern)
        end
        
        plan
      end
      
      def apply_optimization_pattern(plan, pattern)
        case pattern[:optimization_type]
        when 'step_reordering'
          reorder_steps(plan, pattern[:reordering_rules])
        when 'tool_substitution'
          substitute_tools(plan, pattern[:substitutions])
        when 'step_merger'
          merge_steps(plan, pattern[:merge_candidates])
        else
          plan
        end
      end
      
      def validate_plan(plan)
        issues = []
        
        # Check for circular dependencies
        if has_circular_dependencies?(plan['steps'])
          issues << 'Circular dependencies detected'
        end
        
        # Check for missing tools
        missing_tools = find_missing_tools(plan['steps'])
        if missing_tools.any?
          issues << "Missing tools: #{missing_tools.join(', ')}"
        end
        
        # Check resource constraints
        if exceeds_resource_limits?(plan)
          issues << 'Plan exceeds resource limits'
        end
        
        # Check for unreachable steps
        unreachable = find_unreachable_steps(plan['steps'])
        if unreachable.any?
          issues << "Unreachable steps: #{unreachable.join(', ')}"
        end
        
        {
          valid: issues.empty?,
          issues: issues
        }
      end
      
      def has_circular_dependencies?(steps)
        # Simple DFS to detect cycles
        visited = Set.new
        rec_stack = Set.new
        
        steps.each do |step|
          if !visited.include?(step['id'])
            return true if has_cycle?(step['id'], steps, visited, rec_stack)
          end
        end
        
        false
      end
      
      def has_cycle?(step_id, steps, visited, rec_stack)
        visited.add(step_id)
        rec_stack.add(step_id)
        
        step = steps.find { |s| s['id'] == step_id }
        return false unless step
        
        (step['dependencies'] || []).each do |dep_id|
          if !visited.include?(dep_id)
            return true if has_cycle?(dep_id, steps, visited, rec_stack)
          elsif rec_stack.include?(dep_id)
            return true
          end
        end
        
        rec_stack.delete(step_id)
        false
      end
      
      def find_missing_tools(steps)
        required_tools = steps
          .select { |s| s['type'] == 'tool_call' }
          .map { |s| s['tool'] }
          .compact
          .uniq
        
        available_tools = @tool_catalog ? @tool_catalog.all_tools.keys : []
        
        required_tools - available_tools
      end
      
      def exceeds_resource_limits?(plan)
        # Check against resource manager if available
        return false unless @task_session
        
        resource_manager = ResourceManager.new(@task_session.user.entity)
        
        estimated_cost = plan['estimated_total_cost'] || 0
        !resource_manager.can_afford?(:api_calls, estimated_cost)
      end
      
      def find_unreachable_steps(steps)
        # Find steps that can't be reached from the start
        reachable = Set.new
        
        # Find steps with no dependencies (starting points)
        queue = steps.select { |s| (s['dependencies'] || []).empty? }.map { |s| s['id'] }
        
        while queue.any?
          current = queue.shift
          reachable.add(current)
          
          # Find steps that depend on current
          dependents = steps.select { |s| (s['dependencies'] || []).include?(current) }
          dependents.each do |dep|
            # Add to queue if all dependencies are reachable
            if (dep['dependencies'] - reachable.to_a).empty?
              queue << dep['id']
            end
          end
        end
        
        all_steps = steps.map { |s| s['id'] }
        all_steps - reachable.to_a
      end
      
      def attempt_plan_repair(plan, issues)
        Rails.logger.info "Attempting to repair plan with issues: #{issues.join(', ')}"
        
        repaired_plan = plan.dup
        
        issues.each do |issue|
          case issue
          when /Circular dependencies/
            repaired_plan = break_circular_dependencies(repaired_plan)
          when /Missing tools: (.*)/
            missing_tools = $1.split(', ')
            repaired_plan = substitute_missing_tools(repaired_plan, missing_tools)
          when /exceeds resource limits/
            repaired_plan = reduce_resource_usage(repaired_plan)
          when /Unreachable steps: (.*)/
            unreachable = $1.split(', ')
            repaired_plan = fix_unreachable_steps(repaired_plan, unreachable)
          end
        end
        
        # Validate repaired plan
        validation = validate_plan(repaired_plan)
        validation[:valid] ? repaired_plan : nil
      end
      
      def break_circular_dependencies(plan)
        # Simple approach: remove problematic dependencies
        plan['steps'].each do |step|
          if creates_cycle?(step, plan['steps'])
            # Remove the dependency that creates the cycle
            step['dependencies'] = remove_cyclic_dependencies(step, plan['steps'])
          end
        end
        
        plan
      end
      
      def creates_cycle?(step, all_steps)
        has_circular_dependencies?([step] + all_steps.select { |s| s['id'] != step['id'] })
      end
      
      def remove_cyclic_dependencies(step, all_steps)
        # Remove dependencies one by one until no cycle
        dependencies = step['dependencies'] || []
        
        dependencies.select do |dep_id|
          test_step = step.dup
          test_step['dependencies'] = dependencies - [dep_id]
          !creates_cycle?(test_step, all_steps)
        end
      end
      
      def substitute_missing_tools(plan, missing_tools)
        # Find alternative tools or create custom steps
        plan['steps'].each do |step|
          if missing_tools.include?(step['tool'])
            alternative = find_alternative_tool(step['tool'])
            if alternative
              step['tool'] = alternative
              step['tool_substituted'] = true
            else
              # Convert to user input step
              step['type'] = 'user_input'
              step['original_tool'] = step['tool']
              step.delete('tool')
            end
          end
        end
        
        plan
      end
      
      def find_alternative_tool(tool_name)
        # Find tools with similar capabilities
        similar_tools = @tool_catalog ? @tool_catalog.all_tools.select do |name, info|
          similar_tool?(tool_name, name, info[:metadata])
        end.keys : []
        
        similar_tools.first
      end
      
      def similar_tool?(tool1, tool2, tool2_metadata)
        # Simple similarity check based on name and category
        return false if tool1 == tool2
        
        name_similarity = tool1.split('_') & tool2.split('_')
        name_similarity.size > 1
      end
      
      def reduce_resource_usage(plan)
        # Remove non-essential expensive steps
        essential_steps = identify_essential_steps(plan['steps'])
        
        plan['steps'] = plan['steps'].select do |step|
          essential_steps.include?(step['id']) || 
          (step['estimated_cost'] || 0) < 5
        end
        
        # Update dependencies
        fix_broken_dependencies(plan)
        
        plan
      end
      
      def identify_essential_steps(steps)
        # Steps that produce required outputs
        essential = Set.new
        
        # Work backwards from final steps
        final_steps = steps.select { |s| 
          steps.none? { |other| (other['dependencies'] || []).include?(s['id']) }
        }
        
        queue = final_steps.map { |s| s['id'] }
        
        while queue.any?
          current = queue.shift
          essential.add(current)
          
          step = steps.find { |s| s['id'] == current }
          next unless step
          
          (step['dependencies'] || []).each do |dep_id|
            queue << dep_id unless essential.include?(dep_id)
          end
        end
        
        essential
      end
      
      def fix_broken_dependencies(plan)
        available_ids = plan['steps'].map { |s| s['id'] }
        
        plan['steps'].each do |step|
          if step['dependencies']
            step['dependencies'] = step['dependencies'] & available_ids
          end
        end
      end
      
      def fix_unreachable_steps(plan, unreachable_ids)
        # Remove unreachable steps or connect them
        plan['steps'].reject! { |s| unreachable_ids.include?(s['id']) }
        
        # Fix any broken dependencies
        fix_broken_dependencies(plan)
        
        plan
      end
      
      def request_planning_assistance(request_text, issues)
        Rails.logger.info "Requesting planning assistance for issues: #{issues.join(', ')}"
        
        # Find agents that can help with planning
        helper_agents = AgentRegistry.find_by_capabilities(['workflow_planning', 'problem_solving'])
        
        if helper_agents.any?
          # Ask for help
          request_assistance({
            task_type: 'planning_help',
            request_text: request_text,
            issues: issues,
            required_capabilities: ['workflow_planning']
          })
        end
        
        # Return failure for now
        {
          success: false,
          error: "Failed to create valid plan: #{issues.join(', ')}",
          issues: issues
        }
      end
      
      def build_workflow_from_plan(plan)
        # Check if this is a V2 phase-based plan or V1 step-based plan
        is_v2 = plan['template_version'] == 2 || plan['phases'].present?
        
        if is_v2
          # Build V2 phase-based workflow
          workflow_spec = {
            name: plan['name'],
            description: plan['description'],
            template_version: 2,
            type: plan['type'] || 'custom',
            metadata: {
              estimated_duration: plan['estimated_total_duration'],
              estimated_cost: plan['estimated_total_cost'],
              optimization_mode: plan['execution_mode']
            },
            phases: plan['phases']  # Use phases as-is from the plan
          }
        else
          # Fall back to V1 step-based workflow (legacy)
          workflow_spec = {
            name: plan['name'],
            description: plan['description'],
            type: plan['type'] || 'custom',
            metadata: {
              estimated_duration: plan['estimated_total_duration'],
              estimated_cost: plan['estimated_total_cost'],
              optimization_mode: plan['execution_mode']
            },
            steps: build_workflow_steps(plan['steps'])
          }
        end
        
        # Create the workflow
        if @task_session
          SimpleWorkflow.new(workflow_spec)
        else
          workflow_spec
        end
      end
      
      def build_workflow_steps(plan_steps)
        plan_steps.map do |plan_step|
          {
            id: plan_step['id'],
            name: plan_step['name'],
            type: plan_step['type'],
            description: plan_step['description'],
            agent_role: plan_step['agent_role'],
            config: build_step_config(plan_step),
            dependencies: plan_step['dependencies'] || [],
            tool_allowlist: plan_step['required_tools'] || [plan_step['tool']].compact,
            canvas_allowlist: plan_step['canvas_allowlist'] || ['task_progress'],
            parallel_group: plan_step['parallel_group'],
            estimated_duration: plan_step['estimated_duration'],
            estimated_cost: plan_step['estimated_cost']
          }
        end
      end
      
      def build_step_config(plan_step)
        config = {}
        
        case plan_step['type']
        when 'tool_call'
          config[:tool] = plan_step['tool']
          config[:tool_args] = plan_step['tool_args'] || {}
          config[:cache_result] = plan_step['cache_result'] if plan_step['cache_result']
        when 'user_input'
          config[:form] = plan_step['form'] || {}
        when 'conditional'
          config[:condition] = plan_step['condition']
          config[:then_steps] = plan_step['then_steps']
          config[:else_steps] = plan_step['else_steps']
        when 'parallel'
          config[:parallel_steps] = plan_step['parallel_steps']
        end
        
        config
      end
      
      def calculate_plan_confidence(plan)
        confidence = 0.5 # Base confidence
        
        # Higher confidence if using a template
        confidence += 0.2 if plan['template_based']
        
        # Higher confidence if similar plans succeeded
        successful_similar = @memory.find_relevant_patterns({
          type: 'successful_plan',
          category: plan['category']
        })
        
        if successful_similar.size > 3
          confidence += 0.2
        elsif successful_similar.size > 0
          confidence += 0.1
        end
        
        # Lower confidence for complex plans
        step_count = plan['steps']&.size || 0
        if step_count > 10
          confidence -= 0.1
        elsif step_count > 20
          confidence -= 0.2
        end
        
        [confidence, 0.95].min
      end
      
      def estimate_plan_cost(plan)
        base_cost = 0
        
        plan['steps']&.each do |step|
          if step['estimated_cost']
            base_cost += step['estimated_cost']
          else
            # Estimate based on step type
            base_cost += estimate_step_cost(step)
          end
        end
        
        # Adjust for execution mode
        if plan['execution_mode'] == 'parallel'
          base_cost *= 1.2 # Parallel execution has overhead
        end
        
        base_cost.round(2)
      end
      
      def estimate_step_cost(step)
        case step['type']
        when 'tool_call'
          estimate_tool_cost(step['tool'] || 'unknown')
        when 'user_input'
          0 # No cost for user input
        when 'conditional'
          2 # Small cost for condition evaluation
        else
          5 # Default cost
        end
      end
      
      def estimate_plan_duration(plan)
        if plan['execution_mode'] == 'parallel'
          estimate_parallel_duration(plan['steps'])
        else
          estimate_sequential_duration(plan['steps'])
        end
      end
      
      def estimate_sequential_duration(steps)
        total = 0
        
        steps&.each do |step|
          if step['estimated_duration']
            total += step['estimated_duration']
          else
            total += estimate_step_duration(step)
          end
        end
        
        total
      end
      
      def estimate_parallel_duration(steps)
        # Group by parallel execution groups
        groups = {}
        
        steps&.each do |step|
          group_id = step['parallel_group'] || step['id']
          groups[group_id] ||= []
          groups[group_id] << step
        end
        
        # Sum max duration per group
        total = groups.values.sum do |group_steps|
          group_steps.map { |s| 
            s['estimated_duration'] || estimate_step_duration(s) 
          }.max || 0
        end
        
        total
      end
      
      def estimate_step_duration(step)
        case step['type']
        when 'tool_call'
          30 # 30 seconds default
        when 'user_input'
          300 # 5 minutes for user input
        when 'conditional'
          5 # Quick evaluation
        else
          60 # 1 minute default
        end
      end
      
      def identify_risks(plan)
        risks = []
        
        # Dependency risks
        if has_long_dependency_chains?(plan['steps'])
          risks << {
            type: 'dependency_chain',
            severity: 'medium',
            description: 'Long dependency chains may cause delays'
          }
        end
        
        # Resource risks
        if plan['estimated_total_cost'] && plan['estimated_total_cost'] > 100
          risks << {
            type: 'high_cost',
            severity: 'high',
            description: 'Plan has high estimated cost'
          }
        end
        
        # Complexity risks
        if plan['steps']&.size && plan['steps'].size > 15
          risks << {
            type: 'complexity',
            severity: 'medium',
            description: 'Complex plan with many steps'
          }
        end
        
        # Tool availability risks
        unreliable_tools = find_unreliable_tools(plan['steps'])
        if unreliable_tools.any?
          risks << {
            type: 'tool_reliability',
            severity: 'low',
            description: "Some tools have lower reliability: #{unreliable_tools.join(', ')}"
          }
        end
        
        risks
      end
      
      def has_long_dependency_chains?(steps)
        return false unless steps
        
        # Find longest path in dependency graph
        longest_path = 0
        
        steps.each do |step|
          path_length = calculate_dependency_depth(step['id'], steps)
          longest_path = [longest_path, path_length].max
        end
        
        longest_path > 5
      end
      
      def calculate_dependency_depth(step_id, all_steps, visited = Set.new)
        return 0 if visited.include?(step_id)
        
        visited.add(step_id)
        
        step = all_steps.find { |s| s['id'] == step_id }
        return 0 unless step
        
        dependencies = step['dependencies'] || []
        return 0 if dependencies.empty?
        
        max_depth = dependencies.map do |dep_id|
          calculate_dependency_depth(dep_id, all_steps, visited)
        end.max || 0
        
        1 + max_depth
      end
      
      def find_unreliable_tools(steps)
        return [] unless steps
        
        tools = steps
          .select { |s| s['type'] == 'tool_call' }
          .map { |s| s['tool'] }
          .compact
          .uniq
        
        # Check tool reliability from memory
        tools.select do |tool|
          reliability = calculate_tool_reliability(tool)
          reliability < 0.8
        end
      end
      
      def calculate_tool_reliability(tool_name)
        # Get historical success rate from memory
        tool_history = @memory.find_relevant_patterns({
          type: 'tool_execution',
          tool: tool_name
        })
        
        return 0.9 if tool_history.empty? # Default reliability
        
        successes = tool_history.count { |h| h[:value][:success] }
        total = tool_history.size
        
        successes.to_f / total
      end
      
      def analyze_failure(failed_step, error, context)
        {
          step_id: failed_step[:id],
          step_type: failed_step[:type],
          error_type: error.class.name,
          error_message: error.message,
          error_backtrace: error.backtrace&.first(5),
          context: context,
          timestamp: Time.current,
          potential_causes: identify_failure_causes(failed_step, error)
        }
      end
      
      def identify_failure_causes(step, error)
        causes = []
        
        # Common error patterns
        case error
        when Timeout::Error
          causes << 'Operation timeout - service may be slow or unresponsive'
        when JSON::ParserError
          causes << 'Invalid JSON response - API may have changed'
        when StandardError
          if error.message.include?('rate limit')
            causes << 'Rate limit exceeded - too many requests'
          elsif error.message.include?('unauthorized')
            causes << 'Authentication failure - credentials may be invalid'
          elsif error.message.include?('not found')
            causes << 'Resource not found - may have been deleted'
          end
        end
        
        # Step-specific causes
        if step[:type] == 'tool_call'
          causes << 'Tool may be unavailable or misconfigured'
        elsif step[:type] == 'user_input'
          causes << 'User input validation failed'
        end
        
        causes
      end
      
      def generate_recovery_options(failure_analysis, past_solutions)
        options = []
        
        # Retry with backoff
        options << {
          name: 'retry_with_backoff',
          description: 'Retry the operation with exponential backoff',
          confidence: 0.7,
          steps: build_retry_steps(failure_analysis)
        }
        
        # Alternative approach
        if alternative = find_alternative_approach(failure_analysis)
          options << {
            name: 'alternative_approach',
            description: 'Use alternative method to achieve the goal',
            confidence: 0.6,
            steps: alternative[:steps]
          }
        end
        
        # Manual intervention
        options << {
          name: 'manual_intervention',
          description: 'Request user intervention to resolve the issue',
          confidence: 0.9,
          steps: build_manual_intervention_steps(failure_analysis)
        }
        
        # Learn from past solutions
        past_solutions.each do |solution|
          if applicable_solution?(solution, failure_analysis)
            options << {
              name: "past_solution_#{solution[:id]}",
              description: solution[:description],
              confidence: solution[:success_rate] || 0.5,
              steps: adapt_past_solution(solution, failure_analysis)
            }
          end
        end
        
        options.sort_by { |o| -o[:confidence] }
      end
      
      def build_retry_steps(failure_analysis)
        [
          {
            id: 'wait_before_retry',
            type: 'wait',
            duration: 5,
            description: 'Wait before retrying'
          },
          {
            id: 'retry_operation',
            type: failure_analysis[:step_type],
            description: 'Retry the failed operation',
            config: {
              max_retries: 3,
              backoff_factor: 2
            }
          }
        ]
      end
      
      def find_alternative_approach(failure_analysis)
        # Look for alternative tools or methods
        case failure_analysis[:step_type]
        when 'tool_call'
          alternative_tool = find_alternative_tool(failure_analysis[:tool])
          if alternative_tool
            {
              steps: [{
                id: 'alternative_tool',
                type: 'tool_call',
                tool: alternative_tool,
                description: "Use #{alternative_tool} instead"
              }]
            }
          end
        else
          nil
        end
      end
      
      def build_manual_intervention_steps(failure_analysis)
        [
          {
            id: 'notify_user',
            type: 'notification',
            description: 'Notify user of the issue',
            config: {
              message: "Failed to execute #{failure_analysis[:step_id]}: #{failure_analysis[:error_message]}"
            }
          },
          {
            id: 'request_user_action',
            type: 'user_input',
            description: 'Request user to resolve the issue',
            config: {
              form: {
                title: 'Manual Intervention Required',
                fields: [
                  {
                    name: 'resolution',
                    type: 'select',
                    options: ['retry', 'skip', 'provide_alternative']
                  }
                ]
              }
            }
          }
        ]
      end
      
      def applicable_solution?(solution, failure_analysis)
        # Check if past solution applies to current failure
        solution[:error_type] == failure_analysis[:error_type] ||
        solution[:step_type] == failure_analysis[:step_type]
      end
      
      def adapt_past_solution(solution, failure_analysis)
        # Adapt the past solution to current context
        solution[:steps].map do |step|
          adapted = step.dup
          adapted[:context] = failure_analysis[:context]
          adapted
        end
      end
      
      def select_recovery_strategy(options, context)
        # Select best strategy based on context
        if context[:user_preference] == 'manual'
          options.find { |o| o[:name] == 'manual_intervention' }
        elsif context[:time_critical]
          options.first # Highest confidence
        else
          # Balance confidence and user disruption
          options.min_by { |o| 
            disruption_score = o[:name] == 'manual_intervention' ? 10 : 1
            -o[:confidence] + disruption_score * 0.2
          }
        end
      end
      
      def build_recovery_workflow(strategy, failed_step)
        {
          name: "Recovery for #{failed_step[:id]}",
          description: strategy[:description],
          type: 'recovery',
          metadata: {
            original_step: failed_step,
            strategy: strategy[:name],
            confidence: strategy[:confidence]
          },
          steps: strategy[:steps]
        }
      end
    end
  end
end
