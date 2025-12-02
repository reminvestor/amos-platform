class PlannerAgentService
  attr_reader :user, :entity, :session_id

  def initialize(user:, entity:, session_id:, progress_callback: nil)
    @user = user
    @entity = entity
    @session_id = session_id
    @progress_callback = progress_callback
    @ai_service = BedrockService.new(user: user, entity: entity)
    @tool_catalog = Tools::ToolCatalog.instance
  end

  def plan_workflow(request_text, context = {})
    # Use LLM to create an intelligent plan
    Rails.logger.info "PlannerAgent: Creating workflow plan for: #{request_text}"

    # Gather context for planning
    planning_context = gather_planning_context(request_text, context)

    # Generate plan using LLM
    llm_result = generate_llm_plan(request_text, planning_context)

    if llm_result[:success]
      workflow = llm_result[:workflow]

      # Validate and optimize the workflow
      validate_workflow!(workflow)
      optimize_workflow!(workflow)

      # Create TaskSession to track execution
      task_session = create_task_session(workflow, request_text)

      {
        success: true,
        workflow: workflow,
        task_session: task_session,
        template_used: llm_result[:template_used],
        planning_rationale: llm_result[:rationale]
      }
    else
      # Return the error from LLM planning
      Rails.logger.error "LLM planning failed: #{llm_result[:error]}"
      { success: false, error: llm_result[:error] || "Planning failed" }
    end
  rescue => e
    Rails.logger.error "Planner failed: #{e.message}"
    { success: false, error: e.message }
  end

  private

  # Send progress updates to UI
  def notify_progress(message, type: "planner_progress")
    @progress_callback&.call({
      type: type,
      message: message,
      source: "planner"
    })
  end

  def gather_planning_context(request_text, context)
    # Analyze request with regex for hints
    intent_hints = analyze_intent(request_text)

    # Get available workflow templates (from DB and files)
    available_templates = WorkflowTemplate.active_with_files.map do |template|
      {
        name: template.name,
        slug: template.slug,
        description: template.description,
        keywords: template.metadata["keywords"] || [],
        category: template.category
      }
    end

    # Get available tools the planner can use
    planner_tools = @tool_catalog.get_tools_for_role("planner")

    {
      intent_hints: intent_hints,
      available_templates: available_templates,
      available_tools: planner_tools,
      conversation_history: context[:conversation_history] || [],
      current_canvas: context[:current_canvas],
      user_context: {
        entity_name: @entity.name,
        user_name: @user.full_name
      }
    }
  end

  def generate_llm_plan(request_text, planning_context)
    # Notify user of planning process
    notify_progress("🤔 Analyzing your request and planning workflow...")

    system_prompt = build_planner_prompt(planning_context)

    user_message = <<~PROMPT
      Create a workflow plan for this request: #{request_text}

      IMPORTANT: Return ONLY the JSON object below, with no additional text before or after:

      CRITICAL: Check if a template matches this request. If it does, ONLY specify the template - DO NOT generate phases.

      Option 1 - Using a template (preferred):
      {
        "workflow_name": "descriptive name",
        "description": "what this workflow does",
        "template_to_use": "template_slug_here",
        "template_version": 2,
        "rationale": "explanation of why this template fits"
      }

      Option 2 - Custom workflow (only if no template matches):
      {
        "workflow_name": "descriptive name",
        "description": "what this workflow does",
        "template_to_use": null,
        "template_version": 2,
        "rationale": "explanation of the plan",
        "phases": [
          {
            "id": "gather_context",
            "type": "gather_context",
            "name": "Gather Information",
            "goal": "Collect all required information",
            "required_fields": [
              {
                "key": "field_name",
                "prompt": "Question to ask user",
                "required": true,
                "validation": "text|email|url|number"
              }
            ],
            "context_sources": ["direct_conversation", "conversation_history", "entity_profile"]
          },
          {
            "id": "execute_goal",
            "type": "execute_goal",#{' '}
            "name": "Execute Task",
            "goal": "Clear description of what to accomplish",
            "execution_strategy": {
              "approach": "adaptive",
              "allowed_tools": ["tool1", "tool2"],
              "constraints": {}
            },
            "requires_from_previous": ["field_name"],
            "ai_instructions": "How to accomplish the goal"
          },
          {
            "id": "validate_result",
            "type": "validate_result",
            "name": "Verify Success",
            "validation_criteria": {
              "required_outputs": ["output1"],
              "quality_checks": []
            },
            "success_message": "Success message"
          }
        ]
      }

      CRITICAL V2 RULES:
      - Use "phases" NOT "steps" (V2 is phase-based!)
      - Phase 1: gather_context (collect info intelligently)
      - Phase 2: execute_goal (do the work adaptively)
      - Phase 3: validate_result (verify success)
      - Each phase is conversational and adaptive
    PROMPT

    begin
      response = @ai_service.complete(
        messages: [
          { role: "system", content: system_prompt },
          { role: "user", content: user_message }
        ],
        max_tokens: 8000,
        temperature: 0.3
      )

      # Extract JSON from response (handle cases where LLM adds text before/after)
      json_str = extract_json_from_response(response)
      plan_data = JSON.parse(json_str)

      # Convert to workflow object
      workflow = build_workflow_from_plan(plan_data)

      {
        success: true,
        workflow: workflow,
        template_used: plan_data["template_to_use"],
        rationale: plan_data["rationale"]
      }
    rescue => e
      Rails.logger.error "LLM planning error: #{e.message}"
      Rails.logger.error "LLM response was: #{response[0..500]}..." if response
      Rails.logger.error "Extracted JSON was: #{json_str[0..500]}..." if defined?(json_str) && json_str
      { success: false, error: e.message }
    end
  end

  def build_planner_prompt(context)
    <<~PROMPT
      You are an intelligent workflow planner for a business automation system.

      Your job is to create step-by-step workflows that accomplish user requests.

      AVAILABLE WORKFLOW TEMPLATES:
      #{context[:available_templates].map { |t| "- #{t[:slug]}: #{t[:description]}" }.join("\n")}

      AVAILABLE TOOLS FOR PLANNING:
      #{context[:available_tools].map { |t| "- #{t[:name]}: #{t[:description]}" }.join("\n")}

      AGENT ROLES:
      - planner: Creates plans and analyzes requirements
      - executor: Executes actions and operations
      - analyst: Analyzes data and generates insights
      - verifier: Validates results and ensures quality

      PLANNING GUIDELINES:
      1. Check if any existing templates match the request - if so, set "template_to_use" to the template slug
      2. If using a template, the system will use the template's actual steps (your step definitions will be ignored)
      3. If no suitable template exists, set "template_to_use" to null and create a custom plan
      4. For custom plans: Break complex tasks into clear, atomic steps
      5. Use appropriate agent roles for each step
      6. Include schema discovery steps before creating objects
      7. Add validation steps for critical operations
      8. Consider user approval points for destructive actions

      CRITICAL OBJECT TYPE RULES for tool_args:
      - For get_data tool: Use PLURAL (campaigns, contacts, email_templates, contact_groups)
      - For create_object tool: Use PLURAL (campaigns, contacts, email_templates, contact_groups)
      - For get_schema tool: Use SINGULAR (campaign, contact, email_template, contact_group)
      - For update_object tool: Use SINGULAR (campaign, contact, email_template, contact_group)

      CONTEXT HINTS:
      #{context[:intent_hints].to_json}

      EXAMPLE TEMPLATES:

      1. AUTONOMOUS WORKFLOW (no user input needed):
      {
        "workflow_name": "Create and Link Email Campaign",
        "description": "Creates a new email campaign and links it to an existing email template",
        "template_to_use": "campaign_with_template_auto",
        "rationale": "Using the campaign_with_template_auto workflow template as it matches this request perfectly for autonomous execution",
        "steps": [
          {
            "id": "get_template",
            "name": "Retrieve Latest Email Template",
            "description": "Find the most recent email template to link to the campaign",
            "agent_role": "executor",
            "type": "tool_call",
            "tool": "get_data",
            "tool_args": {
              "object_type": "email_template",
              "order_by": "created_at DESC",
              "limit": 1
            },
            "dependencies": [],
            "required_tools": ["get_data"]
          },
          {
            "id": "get_schema",
            "name": "Get Campaign Schema",
            "description": "Retrieve the campaign object schema to ensure correct field names",
            "agent_role": "executor",
            "type": "tool_call",
            "tool": "get_schema",
            "tool_args": {
              "object_type": "campaign"
            },
            "dependencies": [],
            "required_tools": ["get_schema"]
          },
          {
            "id": "create_campaign",
            "name": "Create Email Campaign",
            "description": "Create a new email campaign in draft status",
            "agent_role": "executor",
            "type": "tool_call",
            "tool": "create_object",
            "tool_args": {
              "object_type": "campaigns",
              "data": {
                "name": "New Email Campaign",
                "status": "draft",
                "description": "Email campaign created via workflow"
              }
            },
            "dependencies": ["get_schema"],
            "required_tools": ["create_object"]
          },
          {
            "id": "link_template",
            "name": "Link Template to Campaign",
            "description": "Update the campaign to use the selected email template",
            "agent_role": "executor",
            "type": "tool_call",
            "tool": "update_object",
            "tool_args": {
              "object_type": "campaign",
              "id": "{{create_campaign.result.id}}",
              "data": {
                "email_template_id": "{{get_template.result[0].id}}"
              }
            },
            "dependencies": ["get_template", "create_campaign"],
            "required_tools": ["update_object"]
          }
        ]
      }

      2. INTERACTIVE WORKFLOW (requires user input):
      {
        "workflow_name": "Create Landing Page",
        "description": "Interactive process to create a customized landing page with user preferences",
        "template_to_use": "landing_page_creation_v2",
        "rationale": "Using the landing_page_creation_v2 template as it handles all the required user input steps",
        "steps": [
          {
            "id": "analyze_request",
            "name": "Analyze Landing Page Requirements",
            "description": "Extract initial requirements from the user's request",
            "agent_role": "planner",
            "type": "tool_call",
            "tool": "analyze_landing_page_request",
            "tool_args": {
              "user_message": "{{request_text}}"
            },
            "dependencies": [],
            "required_tools": ["analyze_landing_page_request"]
          },
          {
            "id": "collect_info",
            "name": "Collect Business Information",
            "description": "Gather specific business details from the user",
            "agent_role": "executor",
            "type": "user_input",
            "tool": null,
            "tool_args": {},
            "dependencies": ["analyze_request"],
            "required_tools": [],
            "user_prompt": "Please provide your business details:\n- Company name\n- Value proposition\n- Target audience\n- Call to action"
          },
          {
            "id": "design_preferences",
            "name": "Collect Design Preferences",
            "description": "Get user's design and style preferences",
            "agent_role": "executor",
            "type": "user_input",
            "tool": null,
            "tool_args": {},
            "dependencies": ["collect_info"],
            "required_tools": [],
            "user_prompt": "What design style would you prefer?\n- Modern/Classic/Minimalist\n- Color scheme\n- Any specific images or branding elements?"
          },
          {
            "id": "generate_page",
            "name": "Generate Landing Page",
            "description": "Create the landing page based on collected information",
            "agent_role": "executor",
            "type": "tool_call",
            "tool": "generate_ai_landing_page",
            "tool_args": {
              "business_info": "{{collect_info.result}}",
              "design_preferences": "{{design_preferences.result}}"
            },
            "dependencies": ["collect_info", "design_preferences"],
            "required_tools": ["generate_ai_landing_page"]
          }
        ]
      }

      KEY PATTERNS TO FOLLOW:
      - ALWAYS use get_schema before creating/updating objects to get correct field names
      - Use the schema information to ensure you only use valid fields for the object
      - Include dependencies between steps (create_object should depend on get_schema)
      - Use {{step_id.result}} to reference outputs from previous steps
      - For user_input steps, set tool to null and provide user_prompt
      - Specify appropriate agent_role for each step
      - List all required_tools for each step
      - CRITICAL: Only use fields that exist in the schema - do not use made-up fields like "type" for campaigns

      3. CUSTOM WORKFLOW (no matching template):
      {
        "workflow_name": "Analyze Customer Engagement Metrics",
        "description": "Custom analysis workflow to gather and analyze customer engagement data",
        "template_to_use": null,
        "rationale": "No existing template matches this specific analysis request, creating custom workflow",
        "steps": [
          {
            "id": "get_campaigns",
            "name": "Retrieve Recent Campaigns",
            "description": "Get campaigns from the last 30 days",
            "agent_role": "executor",
            "type": "tool_call",
            "tool": "get_data",
            "tool_args": {
              "object_type": "campaigns",
              "options": {
                "filters": {
                  "created_at": {
                    "gte": "30_days_ago"
                  }
                }
              }
            },
            "dependencies": [],
            "required_tools": ["get_data"]
          },
          {
            "id": "analyze_metrics",
            "name": "Analyze Engagement Metrics",
            "description": "Analyze the campaign performance data",
            "agent_role": "analyst",
            "type": "tool_call",
            "tool": "aggregate_artifact_data",
            "tool_args": {
              "data_source": "campaign_data",
              "aggregation_type": "engagement_metrics"
            },
            "dependencies": ["get_campaigns"],
            "required_tools": ["aggregate_artifact_data"]
          }
        ]
      }

      Remember: You can use tools during planning to gather information needed for a better plan.
    PROMPT
  end

  def extract_json_from_response(response)
    # Try to find JSON in the response
    # Look for the outermost JSON object that contains workflow_name or steps

    # First, try to parse the whole response as JSON
    begin
      JSON.parse(response)
      return response
    rescue JSON::ParserError
      # Continue to extraction logic
    end

    # Find all potential JSON objects in the response
    json_candidates = []
    stack = []
    in_string = false
    escape_next = false
    current_json_start = nil

    response.chars.each_with_index do |char, i|
      if escape_next
        escape_next = false
        next
      end

      if char == "\\" && in_string
        escape_next = true
        next
      end

      if char == '"' && !escape_next
        in_string = !in_string
        next
      end

      next if in_string

      if char == "{"
        stack.push(i)
        current_json_start = i if stack.size == 1
      elsif char == "}"
        if stack.size == 1 && current_json_start
          # Found a complete JSON object
          json_str = response[current_json_start..i]
          begin
            parsed = JSON.parse(json_str)
            # Check if this looks like a workflow plan
            if parsed["workflow_name"] || parsed["steps"] || parsed["name"]
              json_candidates << json_str
            end
          rescue JSON::ParserError
            # Not valid JSON, continue
          end
        end
        stack.pop unless stack.empty?
      end
    end

    # Return the best candidate (usually the first valid one)
    if json_candidates.any?
      json_candidates.first
    else
      # Last resort: try to find any JSON-like structure
      json_match = response.match(/\{[\s\S]*\}/m)
      json_match ? json_match[0] : response
    end
  end

  def build_workflow_from_plan(plan_data)
    # If a template is specified, load and use it instead of the AI-generated workflow
    if plan_data["template_to_use"].present?
      template = WorkflowTemplate.active_with_files.find { |t| t.slug == plan_data["template_to_use"] }

      if template
        Rails.logger.info "Using workflow template: #{template.slug}"
        Rails.logger.info "Template object: #{template.inspect[0..200]}"
        Rails.logger.info "Template attributes: #{template.attributes.keys}" if template.respond_to?(:attributes)

        # Get the template's actual workflow structure
        # The structure can vary based on how the template was loaded
        raw_spec = template.template_spec

        # For file-loaded templates, template_spec might be the outer wrapper
        # Check if we need to drill down to the actual spec
        template_data = if raw_spec.is_a?(Hash) && raw_spec[:template_spec]
          Rails.logger.info "Found nested template_spec, using inner spec"
          raw_spec[:template_spec]
        else
          raw_spec
        end

        Rails.logger.info "Template data class: #{template_data.class}"
        Rails.logger.info "Template data keys: #{template_data.keys}" if template_data.is_a?(Hash)
        Rails.logger.info "Looking for phases at: phases=#{template_data[:phases].present?}, 'phases'=#{template_data['phases'].present?}" if template_data.is_a?(Hash)
        Rails.logger.info "Template version at root: #{template_data[:template_version] || template_data['template_version']}" if template_data.is_a?(Hash)

        # V2 detection - be thorough in checking
        is_v2 = false
        if template_data.is_a?(Hash)
          # Check for V2 indicators
          has_version_2 = template_data[:template_version] == 2 || template_data["template_version"] == 2
          has_phases = template_data[:phases].present? || template_data["phases"].present?

          is_v2 = has_version_2 || has_phases
          Rails.logger.info "V2 detection: version_2=#{has_version_2}, has_phases=#{has_phases}, is_v2=#{is_v2}"
        end

        # Fallback: if template slug ends with _v2, it's definitely V2
        if !is_v2 && template.slug.end_with?("_v2")
          Rails.logger.warn "Template #{template.slug} ends with _v2 but V2 markers not found, forcing V2"
          is_v2 = true
          # If we're forcing V2 but no phases found, we need to reload properly
          if template_data.is_a?(Hash) && !template_data[:phases] && !template_data["phases"]
            Rails.logger.error "V2 template missing phases! Keys available: #{template_data.keys}"
          end
        end

        if is_v2
          # V2 Template - return phases as-is
          Rails.logger.info "Using V2 template with phases"

          # Get phases, with extensive fallback checking
          phases = template_data[:phases] || template_data["phases"]

          if phases.nil? || phases.empty?
            Rails.logger.error "V2 template has no phases! Template data: #{template_data.inspect}"
            # Last resort: try to reload the template directly
            Rails.logger.info "Attempting direct reload of template #{template.slug}"
            reloaded = WorkflowTemplateLoader.load_template_by_slug(template.slug)
            if reloaded && (reloaded[:phases] || reloaded["phases"])
              phases = reloaded[:phases] || reloaded["phases"]
              Rails.logger.info "Successfully reloaded phases from template file"
            else
              raise "V2 template #{template.slug} is missing phases definition"
            end
          end

          return SimpleWorkflow.new(
            name: plan_data["workflow_name"] || template_data["name"] || template_data[:name],
            description: plan_data["description"] || template_data["description"] || template_data[:description],
            template_version: 2,
            phases: phases,
            metadata: {
              llm_generated: false,
              template_used: plan_data["template_to_use"],
              rationale: plan_data["rationale"]
            }
          )
        else
          # V1 Template - build steps (legacy)
          Rails.logger.info "Using V1 template with steps"
          steps_data = template_data["steps"] || template_data[:steps] || []
          built_steps = build_steps_from_template(steps_data)

          return SimpleWorkflow.new(
            name: plan_data["workflow_name"] || template_data["name"] || template_data[:name],
            description: plan_data["description"] || template_data["description"] || template_data[:description],
            steps: built_steps,
            metadata: {
              llm_generated: false,
              template_used: plan_data["template_to_use"],
              rationale: plan_data["rationale"]
            }
          )
        end
      else
        Rails.logger.warn "Template '#{plan_data['template_to_use']}' not found, using AI-generated workflow"
      end
    end

    # Fall back to AI-generated workflow if no template or template not found
    # Check if AI generated V2 (phases) or V1 (steps)
    if plan_data["phases"].present? || plan_data["template_version"] == 2
      # V2 AI-generated workflow
      Rails.logger.info "Building V2 workflow from AI-generated phases"
      SimpleWorkflow.new(
        name: plan_data["workflow_name"],
        description: plan_data["description"],
        template_version: 2,
        phases: plan_data["phases"],
        metadata: {
          llm_generated: true,
          template_used: plan_data["template_to_use"],
          rationale: plan_data["rationale"]
        }
      )
    else
      # V1 AI-generated workflow (legacy)
      Rails.logger.info "Building V1 workflow from AI-generated steps"
      steps = plan_data["steps"].map do |step_data|
        Step.new(
          id: step_data["id"],
          name: step_data["name"],
          description: step_data["description"],
          agent_role: step_data["agent_role"] || "executor",
          type: step_data["type"] || "tool_call",
          config: {
            tool: step_data["tool"],
            tool_args: step_data["tool_args"] || {}
          },
          dependencies: step_data["dependencies"] || [],
          tool_allowlist: step_data["required_tools"] || [],
          canvas_allowlist: [ "task_progress" ]
        )
      end

      SimpleWorkflow.new(
        name: plan_data["workflow_name"],
        description: plan_data["description"],
        steps: steps,
        metadata: {
          llm_generated: true,
          template_used: plan_data["template_to_use"],
          rationale: plan_data["rationale"]
        }
      )
    end
  end

  def build_steps_from_template(template_steps)
    template_steps.map.with_index do |step_data, idx|
      # Handle both hash formats (string and symbol keys)
      step_hash = step_data.with_indifferent_access

      Rails.logger.info "Building step #{idx + 1}: #{step_hash[:id]}"
      Rails.logger.info "  Step config present: #{step_hash[:config].present?}"
      Rails.logger.info "  Step tool: #{step_hash[:tool]}" if step_hash[:tool]

      # If config is already built by WorkflowTemplateLoader, use it
      config = if step_hash[:config].present?
        step_hash[:config]
      else
        # Otherwise build it from the template data
        {
          tool: step_hash[:tool],
          tool_args: step_hash[:tool_args] || {}
        }
      end

      Rails.logger.info "  Final config: #{config.inspect}"

      Step.new(
        id: step_hash[:id],
        name: step_hash[:name],
        description: step_hash[:description],
        agent_role: step_hash[:agent_role] || "executor",
        type: step_hash[:type] || "tool_call",
        config: config,
        dependencies: step_hash[:dependencies] || [],
        tool_allowlist: step_hash[:tool_allowlist] || step_hash[:required_tools] || [],
        canvas_allowlist: step_hash[:canvas_allowlist] || [ "task_progress" ]
      )
    end
  rescue => e
    Rails.logger.error "Error building steps from template: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    raise
  end

  def fallback_workflow(request_text, context)
    # Return a failure result so the system can handle it appropriately
    Rails.logger.error "Planning failed - no fallback workflow available"

    {
      success: false,
      error: "Unable to create a workflow plan. Please try rephrasing your request or provide more details.",
      is_fallback: true
    }
  end

  def find_matching_template(request_text)
    # Use AI to intelligently match request to available templates

    # Get list of all available templates
    available_templates = WorkflowTemplateLoader.list_all_templates

    return nil if available_templates.empty?

    # Use AI to select the best template
    template_selection_prompt = <<~PROMPT
      User Request: #{request_text}

      Available Workflow Templates:
      #{JSON.pretty_generate(available_templates)}

      Analyze the user's request and determine which template (if any) best matches their intent.

      Consider:
      - What is the user trying to accomplish?
      - Which template's purpose aligns with this goal?
      - Does the description match the user's needs?

      Respond with JSON:
      {
        "template_slug": "template_slug_here",
        "confidence": "high|medium|low",
        "reasoning": "why this template matches"
      }

      If NO template matches well, respond with:
      {
        "template_slug": null,
        "confidence": "none",
        "reasoning": "why no template matches - AI will create custom plan"
      }
    PROMPT

    begin
      response = @ai_service.complete(
        prompt: template_selection_prompt,
        max_tokens: 500,
        temperature: 0.3
      )

      # Parse AI response
      result = JSON.parse(extract_json(response))

      if result["template_slug"] && result["confidence"] != "none"
        Rails.logger.info "AI selected template: #{result['template_slug']} (#{result['confidence']} confidence)"
        Rails.logger.info "Reasoning: #{result['reasoning']}"

        notify_progress("🎯 Found perfect template: #{result['template_slug']}")
        notify_progress("💭 Reasoning: #{result['reasoning']}")

        # Load and return the selected template
        template_data = WorkflowTemplateLoader.load_template_by_slug(result["template_slug"])

        if template_data
          # Create in-memory template object
          WorkflowTemplate.new(template_data)
        else
          Rails.logger.warn "Template #{result['template_slug']} not found"
          nil
        end
      else
        Rails.logger.info "AI decided no template matches: #{result['reasoning']}"
        nil
      end
    rescue => e
      Rails.logger.error "AI template selection failed: #{e.message}"
      nil
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
    when "analytics"
      steps = build_analytics_steps(intent)
    when "campaign_creation"
      steps = build_campaign_steps(intent)
    when "data_import"
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
      type: "generic",
      name: nil,
      description: nil,
      entities: [],
      actions: []
    }

    # Detect analytics requests
    if request_text.match?(/analyz|report|metric|performance|trend/i)
      intent[:type] = "analytics"
      intent[:name] = "Analytics Workflow"

      # Detect time period
      if request_text.match?(/year|annual|yearly/i)
        intent[:time_period] = "year"
      elsif request_text.match?(/month|monthly/i)
        intent[:time_period] = "month"
      elsif request_text.match?(/week|weekly/i)
        intent[:time_period] = "week"
      end

      # Detect data source
      if request_text.match?(/stripe|payment|customer/i)
        intent[:data_source] = "stripe"
      elsif request_text.match?(/shopify|order|product/i)
        intent[:data_source] = "shopify"
      end
    end

    # Detect campaign creation
    if request_text.match?(/create.*campaign|new.*campaign|build.*campaign/i)
      intent[:type] = "campaign_creation"
      intent[:name] = "Campaign Creation Workflow"

      # Check if template linking is requested
      if request_text.match?(/link.*template|with.*template|use.*template|and.*link/i)
        intent[:requires_template] = true
        intent[:name] = "Campaign Creation with Template Linking"
      end
    end

    # Detect data import
    if request_text.match?(/import|sync|fetch.*data|pull.*data/i)
      intent[:type] = "data_import"
      intent[:name] = "Data Import Workflow"
    end

    intent
  end

  def build_analytics_steps(intent)
    steps = []

    # Step 1: Fetch data from integration
    if intent[:data_source]
      steps << Step.new(
        id: "fetch_data",
        agent_role: "executor",
        name: "Fetch Data",
        description: "Fetch data from #{intent[:data_source]}",
        type: "tool_call",
        config: {
          tool: "invoke_operation",
          requires_connection: true
        },
        tool_allowlist: [ "list_connections", "invoke_operation" ],
        canvas_allowlist: [ "dynamic_canvas" ],
        budgets: { max_tool_calls: 5, timeout_seconds: 60 }
      )
    end

    # Step 2: Analyze data
    steps << Step.new(
      id: "analyze_data",
      agent_role: "analyst",
      name: "Analyze Data",
      description: "Perform data analysis and aggregations",
      type: "tool_call",
      config: {
        tool: "aggregate_artifact_data",
        depends_on: [ "fetch_data" ]
      },
      dependencies: [ "fetch_data" ],
      tool_allowlist: [ "aggregate_artifact_data", "fetch_next_page" ],
      canvas_allowlist: [ "dynamic_canvas", "analytics_dashboard" ],
      budgets: { max_tool_calls: 10, timeout_seconds: 120 }
    )

    # Step 3: Generate insights
    steps << Step.new(
      id: "generate_insights",
      agent_role: "analyst",
      name: "Generate Insights",
      description: "Generate insights and recommendations",
      type: "tool_call",
      config: {
        tool: "create_dynamic_visualization",
        depends_on: [ "analyze_data" ]
      },
      dependencies: [ "analyze_data" ],
      tool_allowlist: [ "create_dynamic_visualization" ],
      canvas_allowlist: [ "dynamic_canvas" ],
      budgets: { max_tool_calls: 3, timeout_seconds: 30 }
    )

    # Step 4: Verify results
    steps << Step.new(
      id: "verify_results",
      agent_role: "verifier",
      name: "Verify Results",
      description: "Verify analysis quality and completeness",
      type: "validation",
      config: {
        rules: [
          { type: "data_completeness", threshold: 0.8 },
          { type: "insight_quality", min_insights: 3 }
        ]
      },
      dependencies: [ "generate_insights" ],
      tool_allowlist: [ "get_data" ],
      canvas_allowlist: [ "task_progress" ],
      budgets: { max_tool_calls: 2, timeout_seconds: 30 }
    )

    steps
  end

  def build_campaign_steps(intent)
    steps = []

    # Step 1: Get campaign schema
    steps << Step.new(
      id: "get_campaign_schema",
      agent_role: "executor",
      name: "Get Campaign Schema",
      description: "Discover available fields for campaigns",
      type: "tool_call",
      config: {
        tool: "get_schema",
        tool_args: { object_type: "campaign" }
      },
      tool_allowlist: [ "get_schema" ],
      canvas_allowlist: [ "task_progress" ]
    )

    # Step 2: Get template if linking is requested
    if intent[:requires_template]
      steps << Step.new(
        id: "get_template",
        agent_role: "executor",
        name: "Find Email Template",
        description: "Find the email template to link",
        type: "tool_call",
        config: {
          tool: "get_data",
          tool_args: {
            object_type: "email_templates",
            options: { limit: 1, order_by: "created_at desc" }
          }
        },
        dependencies: [ "get_campaign_schema" ],
        tool_allowlist: [ "get_data" ],
        canvas_allowlist: [ "task_progress" ]
      )
    end

    # Step 3: Create campaign
    create_step_config = {
      tool: "create_object",
      tool_args: {
        object_type: "campaigns",
        data: {
          name: "{{campaign_name}}",
          status: "draft"
        }
      }
    }

    # Add template linking if needed
    if intent[:requires_template]
      create_step_config[:tool_args][:data][:email_template_id] = "{{template_id}}"
    end

    steps << Step.new(
      id: "create_campaign",
      agent_role: "executor",
      name: "Create Campaign",
      description: intent[:requires_template] ? "Create campaign and link to template" : "Create the campaign",
      type: "tool_call",
      config: create_step_config,
      dependencies: intent[:requires_template] ? [ "get_campaign_schema", "get_template" ] : [ "get_campaign_schema" ],
      tool_allowlist: [ "create_object" ],
      canvas_allowlist: [ "campaign_viewer" ]
    )

    # Step 4: Load campaign viewer
    steps << Step.new(
      id: "show_campaign",
      agent_role: "executor",
      name: "Show Campaign",
      description: "Display the created campaign",
      type: "tool_call",
      config: {
        tool: "load_canvas",
        tool_args: { canvas_name: "campaign_viewer" }
      },
      dependencies: [ "create_campaign" ],
      tool_allowlist: [ "load_canvas" ],
      canvas_allowlist: [ "campaign_viewer" ]
    )

    steps
  end

  def build_data_import_steps(intent)
    [
      Step.new(
        id: "select_source",
        agent_role: "executor",
        name: "Select Data Source",
        description: "Select integration to import from",
        type: "tool_call",
        config: {
          tool: "list_connections"
        },
        tool_allowlist: [ "list_connections", "describe_connection" ],
        canvas_allowlist: [ "integrations_manager" ]
      ),
      Step.new(
        id: "import_data",
        agent_role: "executor",
        name: "Import Data",
        description: "Import data from selected source",
        type: "tool_call",
        config: {
          tool: "invoke_operation"
        },
        dependencies: [ "select_source" ],
        tool_allowlist: [ "invoke_operation", "fetch_next_page" ],
        canvas_allowlist: [ "dynamic_canvas" ]
      )
    ]
  end

  def build_generic_steps(intent)
    # Fallback to a simple single-step workflow
    [
      Step.new(
        id: "execute_task",
        agent_role: "executor",
        name: "Execute Task",
        description: intent[:description] || "Execute the requested task",
        type: "tool_call",
        config: {
          tool: "get_data"  # Safe default
        },
        tool_allowlist: [ "get_data", "create_object", "get_schema" ],
        canvas_allowlist: [ "dynamic_canvas" ]
      )
    ]
  end

  def validate_workflow!(workflow)
    # V2 workflows have phases, V1 workflows have steps
    if workflow.respond_to?(:v2?) && workflow.v2?
      # V2 workflow validation
      raise "V2 Workflow must have phases" if workflow.phases.nil? || workflow.phases.empty?
      Rails.logger.info "✅ V2 workflow validated with #{workflow.phases.length} phases"
    else
      # V1 workflow validation (legacy)
      raise "V1 Workflow must have steps" if workflow.steps.nil? || workflow.steps.empty?

      # Validate step dependencies
      step_ids = workflow.steps.map(&:id)
      workflow.steps.each do |step|
        step.dependencies.each do |dep|
          unless step_ids.include?(dep)
            raise "Step #{step.id} has invalid dependency: #{dep}"
          end
        end
      end
      Rails.logger.info "✅ V1 workflow validated with #{workflow.steps.length} steps"

      # Validate agent roles (V1 only)
      workflow.steps.each do |step|
        unless AgentLoadout::AGENT_ROLES.include?(step.agent_role)
          raise "Step #{step.id} has invalid agent role: #{step.agent_role}"
        end
      end
    end
  end

  def optimize_workflow!(workflow)
    # V2 workflows are already optimized by design - phases flow naturally
    if workflow.respond_to?(:v2?) && workflow.v2?
      Rails.logger.info "✅ V2 workflow - no optimization needed (phases are pre-optimized)"
      return
    end

    # V1 workflow optimization (legacy)
    # Optimize step order based on dependencies (topological sort)
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
      status: "active",
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
      "last_year"
    elsif text.match?(/this\s+year|current\s+year/i)
      "this_year"
    elsif text.match?(/last\s+month/i)
      "last_month"
    elsif text.match?(/this\s+month/i)
      "this_month"
    else
      "all_time"
    end
  end
end
