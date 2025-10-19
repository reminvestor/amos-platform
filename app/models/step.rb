class Step
  attr_reader :id, :type, :config, :status, :started_at, :completed_at, :error, :result
  attr_accessor :agent_role, :name, :description, :dependencies, :tool_allowlist,
                :canvas_allowlist, :data_scopes, :budgets, :confirmations, :prompts

  # Step statuses
  STATUSES = %w[pending in_progress completed failed skipped].freeze

  # Step types
  TYPES = %w[tool_call user_input form_input data_collection validation conditional].freeze

  def initialize(spec)
    spec = spec.is_a?(Hash) ? spec.with_indifferent_access : spec.to_h.with_indifferent_access

    @id = spec[:id] || SecureRandom.uuid
    @type = spec[:type] || "tool_call"
    @config = spec[:config] || {}
    @status = "pending"
    @started_at = nil
    @completed_at = nil
    @error = nil
    @result = nil

    # Agent loadout properties (handle both string and symbol keys)
    @agent_role = spec[:agent_role] || spec["agent_role"] || "executor"
    @name = spec[:name] || spec["name"] || "Step #{@id}"
    @description = spec[:description] || spec["description"]
    @dependencies = spec[:dependencies] || spec["dependencies"] || []
    @tool_allowlist = spec[:tool_allowlist] || []
    @canvas_allowlist = spec[:canvas_allowlist] || []
    @data_scopes = spec[:data_scopes] || {}
    @budgets = spec[:budgets] || {}
    @confirmations = spec[:confirmations] || {}
    @prompts = spec[:prompts] || {}

    # Validate step type
    unless TYPES.include?(@type)
      raise ArgumentError, "Invalid step type: #{@type}. Must be one of: #{TYPES.join(', ')}"
    end

    # Validate config after all properties are set
    validate_config!
  end

  # Check if step requires user input
  def requires_input?
    case @type
    when "user_input", "form_input"
      true
    when "tool_call"
      @config[:requires_input] == true
    else
      @config[:requires_input] == true
    end
  end

  # Execute the step
  def execute(inputs = {})
    @status = "in_progress"
    @started_at = Time.current

    result = case @type
    when "tool_call"
      execute_tool_call(inputs)
    when "user_input", "form_input"
      execute_user_input(inputs)
    when "data_collection"
      execute_data_collection(inputs)
    when "validation"
      execute_validation(inputs)
    when "conditional"
      execute_conditional(inputs)
    else
      { status: "failed", error: "Unknown step type: #{@type}" }
    end

    # If step failed and self-healing is enabled, try to fix it
    if (result[:status] == "failed" || result[:status] == "step_failed") &&
       @execution_context&.dig(:enable_self_healing) != false &&
       @type == "tool_call"

      Rails.logger.info "Step #{@id} failed, attempting self-healing with FixerAgent"

      fixer = Agents::Specialized::FixerAgent.new(
        task_session: @execution_context&.dig(:task_session),
        initial_context: @execution_context
      )

      fix_result = fixer.fix_failed_step(
        to_hash,
        { error: result[:error] },
        @execution_context
      )

      if fix_result[:success]
        Rails.logger.info "✅ FixerAgent successfully fixed step #{@id}: #{fix_result[:fix_applied]}"
        result = {
          status: "success",
          data: fix_result[:result],
          result: fix_result[:result],
          fixed: true,
          fix_description: fix_result[:fix_applied]
        }
      else
        Rails.logger.error "❌ FixerAgent could not fix step #{@id} after #{fix_result[:attempts]} attempts"
      end
    end

    # Store result for later reference
    @result = result

    # Update status based on result
    case result[:status]
    when "success", "step_completed"
      mark_completed(result[:result] || result[:data])
    when "failed", "step_failed"
      mark_failed(result[:error])
    end

    result
  end

  # Mark step as completed
  def mark_completed(result = {})
    @status = "completed"
    @completed_at = Time.current
    @result = result
  end

  # Mark step as failed
  def mark_failed(error_message)
    @status = "failed"
    @completed_at = Time.current
    @error = error_message
  end

  # Mark step as skipped
  def mark_skipped(reason = "Skipped")
    @status = "skipped"
    @completed_at = Time.current
    @result = { status: "skipped", reason: reason }
  end

  # Check if all dependencies are met
  def dependencies_met?(completed_steps)
    return true if @dependencies.nil? || @dependencies.empty?

    # All dependencies must be in the completed steps list
    @dependencies.all? { |dep| completed_steps.include?(dep) }
  end

  # Resolve variables in inputs using execution context
  def resolve_variables(inputs)
    return inputs unless inputs.is_a?(Hash)

    resolved = inputs.deep_dup
    workflow_execution = @execution_context&.dig(:workflow_execution)

    Rails.logger.info "🔍 Step #{@id}: Resolving variables in inputs: #{inputs.inspect}"
    Rails.logger.info "🔍 Step #{@id}: WorkflowExecution present: #{workflow_execution.present?}"

    if workflow_execution
      Rails.logger.info "🔍 Step #{@id}: WorkflowExecution ID: #{workflow_execution.id}"
    end

    resolved.each do |key, value|
      if value.is_a?(String) && value.include?("{{") && value.include?("}}")
        # Extract all {{variable}} patterns
        value.scan(/\{\{([^}]+)\}\}/).each do |match|
          variable_name = match[0].strip
          Rails.logger.info "🔍 Step #{@id}: Attempting to resolve variable: {{#{variable_name}}}"

          # Use simple database lookup for variable resolution
          resolved_value = if workflow_execution
            workflow_execution.get_variable(variable_name)
          else
            nil
          end

          if resolved_value
            # Replace the variable with its resolved value
            Rails.logger.info "🔍 Step #{@id}: Resolved {{#{variable_name}}} to: #{resolved_value}"
            resolved[key] = value.gsub("{{#{variable_name}}}", resolved_value.to_s)
          else
            Rails.logger.warn "🔍 Step #{@id}: Could not resolve variable: {{#{variable_name}}}"
            Rails.logger.warn "🔍 Available variables: #{workflow_execution.workflow_variables.pluck(:name).join(', ')}" if workflow_execution
          end
        end
      elsif value.is_a?(Hash)
        resolved[key] = resolve_variables(value)
      elsif value.is_a?(Array)
        resolved[key] = value.map { |v| v.is_a?(Hash) ? resolve_variables(v) : v }
      end
    end

    resolved
  end

  # Get step as hash
  def to_hash
    {
      id: @id,
      type: @type,
      config: @config,
      status: @status,
      started_at: @started_at,
      completed_at: @completed_at,
      error: @error,
      result: @result,
      requires_input: requires_input?,
      agent_role: @agent_role,
      name: @name,
      description: @description,
      dependencies: @dependencies
    }
  end

  # Mark step as started
  def mark_started
    @status = "in_progress"
    @started_at = Time.current
  end

  # Get form fields for input steps
  def form_fields
    return [] unless requires_input?
    {
      fields: @config[:fields] || [],
      submit_label: @config[:submit_label] || "Continue"
    }
  end

  # Get human-readable description
  def description
    @config[:description] || @config[:title] || "#{@type.humanize} step"
  end

  # Get agent loadout for this step
  def agent_loadout
    @agent_loadout ||= AgentLoadout.new(
      step_id: @id,
      agent_role: @agent_role,
      tool_allowlist: @tool_allowlist,
      canvas_allowlist: @canvas_allowlist,
      data_scopes: @data_scopes,
      budgets: @budgets,
      confirmations: @confirmations,
      prompts: @prompts
    )
  end

  # Get form configuration for user input steps
  def form_config
    return nil unless requires_input?

    @config[:form] || {
      title: description,
      fields: @config[:fields] || [],
      submit_label: @config[:submit_label] || "Continue"
    }
  end

  private

  # [DEPRECATED] - Now using database-backed WorkflowVariable lookups
  # This method is kept for reference but should not be used
  def resolve_variable_path(path, workflow)
    return nil unless workflow

    # Parse path like "step_id.result.field"
    parts = path.split(".")
    return nil if parts.empty?

    step_id = parts.first

    # Special case for array access like result[0]
    if parts[1]&.include?("[")
      field_part = parts[1]
      field_name = field_part.split("[").first
      index = field_part.match(/\[(\d+)\]/)[1].to_i

      # Find the step in completed steps
      completed_step = workflow.completed_steps_data.find { |s| s[:id] == step_id }

      # Debug logging
      Rails.logger.info "🔍 Variable resolution for #{path}:"
      Rails.logger.info "  Step ID: #{step_id}"
      Rails.logger.info "  Completed steps available: #{workflow.completed_steps_data.map { |s| s[:id] }}"
      Rails.logger.info "  Completed step found: #{completed_step.present?}"

      return nil unless completed_step

      # Debug the complete step structure
      Rails.logger.info "  Step result: #{completed_step[:result].class.name}"
      if completed_step[:result].is_a?(Hash)
        Rails.logger.info "  Result keys at top level: #{completed_step[:result].keys}"
        if completed_step[:result][:data].is_a?(Hash)
          Rails.logger.info "  Result[:data] keys: #{completed_step[:result][:data].keys}"
          if completed_step[:result][:data][:result].is_a?(Hash)
            Rails.logger.info "  Result[:data][:result] keys: #{completed_step[:result][:data][:result].keys}"
          end
        end
      end

      # The completed_step[:result] contains the complete step execution result
      # Based on actual logs, the structure appears to be:
      # For get_data tool: { status: 'success', data: { result: { records: [...] } }, result: { ... } }
      # Try multiple paths to handle different tool result structures

      # First, let's log the actual structure
      Rails.logger.info "  Looking for field: #{field_name} at index: #{index}"

      # Try to find the data in various locations
      data_result = completed_step.dig(:result, :data, :result) ||
                    completed_step.dig(:result, :result, :data, :result) ||
                    completed_step.dig(:result, :result)

      if data_result
        Rails.logger.info "  Found data_result with keys: #{data_result.keys if data_result.is_a?(Hash)}"
      end

      # Try to get the field value (e.g., 'records')
      current_value = nil
      if data_result.is_a?(Hash)
        current_value = data_result[field_name.to_sym] || data_result[field_name]
      end

      # Handle array access
      if current_value.is_a?(Array) && current_value[index]
        result = current_value[index]
        Rails.logger.info "  Array element at index #{index}: #{result.class.name}"
        Rails.logger.info "  Array element keys: #{result.keys if result.is_a?(Hash)}"

        # Continue navigating if there are more parts
        if parts.length > 2
          parts[2..-1].each do |part|
            if result.is_a?(Hash)
              result = result[part.to_sym] || result[part]
              Rails.logger.info "  Navigated to #{part}: #{result.inspect}"
            else
              Rails.logger.info "  Cannot navigate #{part} on #{result.class.name}"
              return nil
            end
            break unless result
          end
        end

        Rails.logger.info "  Final resolved value: #{result.inspect}"
        return result
      else
        Rails.logger.info "  Could not find array field '#{field_name}' or no element at index #{index}"
        return nil
      end
    else
      # Find the step in completed steps
      completed_step = workflow.completed_steps_data.find { |s| s[:id] == step_id }
      return nil unless completed_step

      # Navigate through the path
      # Start from the result field of the completed step
      current_value = completed_step[:result] || completed_step
      parts[1..-1].each do |part|
        if current_value.is_a?(Hash)
          current_value = current_value[part.to_sym] || current_value[part]
        else
          return nil
        end
      end

      return current_value
    end

    nil
  end

  private

  def validate_config!
    case @type
    when "tool_call"
      # Tool can be specified in config or inferred from tool_allowlist
      unless @config[:tool].present? || @tool_allowlist&.any?
        raise ArgumentError, "tool_call step requires 'tool' in config or tool_allowlist"
      end
    when "user_input", "form_input"
      unless @config[:fields].present?
        raise ArgumentError, "#{@type} step requires 'fields' in config"
      end
    when "validation"
      unless @config[:rules].present?
        raise ArgumentError, "validation step requires 'rules' in config"
      end
    when "conditional"
      unless @config[:condition].present?
        raise ArgumentError, "conditional step requires 'condition' in config"
      end
    end
  end

  def execute_tool_call(inputs)
    tool_name = @config[:tool]
    tool_inputs = @config[:tool_args] || @config[:inputs] || {}

    # Resolve variables in tool_args before merging
    resolved_tool_inputs = resolve_variables(tool_inputs)

    # Merge step inputs with provided inputs (inputs take precedence)
    merged_inputs = resolved_tool_inputs.merge(inputs)

    # For test_tool in test environment, return mock success
    if Rails.env.test? && tool_name == "test_tool"
      return {
        status: "success",
        result: { success: true, message: "Test tool executed successfully" },
        data: { test: true }
      }
    end

    # Use the agent specified in the plan
    agent_role = @agent_role || "executor"
    Rails.logger.info "Step #{@id}: Delegating to #{agent_role.capitalize}Agent for tool '#{tool_name}'"

    begin
      # Create the appropriate agent based on the role specified in the plan
      agent_context = {
        user: @execution_context&.dig(:user),
        entity: @execution_context&.dig(:entity),
        task_session: @execution_context&.dig(:task_session),
        workflow_execution: @execution_context&.dig(:workflow_execution),
        progress_callback: @execution_context&.dig(:progress_callback),
        enable_adaptive_execution: @config[:adaptive] || true, # Enable by default
        step_id: @id,
        step_config: @config
      }

      agent = create_agent_by_role(agent_role, agent_context)

      # Let the specified agent handle the tool execution
      result = agent.execute_step({
        id: @id,
        name: @name,
        type: @type,
        config: @config.merge(tool_args: merged_inputs),
        agent_role: @agent_role
      }, merged_inputs)

      # Convert agent result to workflow format
      if result[:success] || result[:status] == "success"
        {
          status: "step_completed",
          data: result[:data] || result.except(:success, :status),
          result: result,
          executing_step_id: @id
        }
      else
        {
          status: "step_failed",
          error: result[:error] || result[:message] || "Tool execution failed",
          result: result,
          failed_step: @id
        }
      end
    rescue => e
      Rails.logger.error "#{agent_role.capitalize}Agent error: #{e.message}"
      Rails.logger.error e.backtrace.first(5).join("\n")

      # Fallback to direct tool execution if agent fails
      Rails.logger.info "Falling back to direct tool execution"
      fallback_to_direct_execution(tool_name, merged_inputs)
    end
  end

  private

  def create_agent_by_role(role, context)
    task_session = context[:task_session] || @execution_context&.dig(:task_session)

    case role.to_s.downcase
    when "executor"
      Agents::Specialized::ExecutorAgent.new(task_session: task_session, initial_context: context)
    when "planner"
      Agents::Specialized::PlannerAgent.new(task_session: task_session, initial_context: context)
    when "verifier"
      Agents::Specialized::VerifierAgent.new(task_session: task_session, initial_context: context)
    when "analyst"
      Agents::Specialized::AnalystAgent.new(task_session: task_session, initial_context: context)
    else
      # Default to ExecutorAgent for unknown roles
      Rails.logger.warn "Unknown agent role '#{role}', defaulting to ExecutorAgent"
      Agents::Specialized::ExecutorAgent.new(task_session: task_session, initial_context: context)
    end
  end

  def fallback_to_direct_execution(tool_name, merged_inputs)
    tool_catalog = Tools::ToolCatalog.instance

    context = {
      user: @execution_context&.dig(:user),
      entity: @execution_context&.dig(:entity)
    }

    result = tool_catalog.execute_tool(tool_name, merged_inputs, context)

    if result[:success]
      {
        status: "step_completed",
        data: result.except(:success),
        result: result,
        executing_step_id: @id
      }
    else
      {
        status: "step_failed",
        error: result[:error] || "Tool execution failed",
        result: result,
        failed_step: @id
      }
    end
  end

  def execute_user_input(inputs)
    if inputs.empty?
      # Generate a conversational prompt based on the form config
      prompt = generate_conversational_prompt

      # Send the prompt through the progress callback for chat display
      @execution_context[:progress_callback]&.call({
        type: "content_chunk",
        content: prompt
      })

      {
        status: "awaiting_input",
        conversational: true,
        fields_needed: @config[:fields]&.map { |f| f[:name] },
        message: prompt,
        awaiting_user_response: true
      }
    else
        # Process conversational input
        if inputs[:user_message]
          # Use AI to extract structured data from conversational input
          extracted_data = extract_data_from_conversation(inputs[:user_message])

          # Check if we have all required fields
          required_fields = @config[:fields]&.select { |f| f[:required] }&.map { |f| f[:name] } || []
          provided_fields = extracted_data.keys.map(&:to_s)
          missing_fields = required_fields - provided_fields

          if missing_fields.any?
            # Store partial data in workflow context
            if extracted_data.any? && @execution_context[:workflow_execution]
              WorkflowContext.store_user_input(
                @execution_context[:workflow_execution],
                "#{@id}_partial_input",
                extracted_data
              )
            end

            # Ask for missing information conversationally
            follow_up = generate_follow_up_prompt(missing_fields, extracted_data)

            @execution_context[:progress_callback]&.call({
              type: "content_chunk",
              content: follow_up
            })

            {
              status: "awaiting_input",
              conversational: true,
              partial_data: extracted_data,
              fields_needed: missing_fields,
              message: follow_up
            }
          else
            # Store complete data in workflow context
            if @execution_context[:workflow_execution]
              WorkflowContext.store_user_input(
                @execution_context[:workflow_execution],
                "#{@id}_user_input",
                extracted_data
              )
            end

            {
              status: "success",
              data: extracted_data,
              message: "Thanks! I have all the information I need."
            }
          end
        else
        # Fallback to direct field inputs if provided
        {
          status: "success",
          data: inputs,
          message: "Information collected successfully"
        }
        end
    end
  end

  private

  def generate_conversational_prompt
    fields = @config[:fields] || []

    if @config[:user_prompt]
      # Use the configured prompt if available
      return @config[:user_prompt]
    end

    # Generate a natural prompt based on fields
    prompt = @config[:description] || "I need some information from you:"
    prompt += "\n\n"

    fields.each do |field|
      case field[:type]
      when "select"
        options = field[:options]&.map { |opt| opt[:label] || opt[:value] }&.join(", ") || "options"
        prompt += "• #{field[:label] || field[:name]}: Please choose from #{options}\n"
      when "file", "image"
        prompt += "• #{field[:label] || field[:name]}: Please upload your #{field[:type]}\n"
      else
        prompt += "• #{field[:label] || field[:name]}"
        prompt += " (required)" if field[:required]
        prompt += "\n"
      end
    end

    prompt += "\nYou can tell me everything in one message or we can go through it step by step."
    prompt
  end

  def generate_follow_up_prompt(missing_fields, partial_data)
    prompt = "Thanks for that information! "

    if partial_data.any?
      prompt += "I've noted:\n"
      partial_data.each do |key, value|
        prompt += "• #{key}: #{value}\n"
      end
      prompt += "\n"
    end

    prompt += "I still need:\n"

    fields = @config[:fields] || []
    missing_fields.each do |field_name|
      field = fields.find { |f| f[:name] == field_name }
      next unless field

      case field[:type]
      when "select"
        options = field[:options]&.map { |opt| opt[:label] || opt[:value] }&.join(", ") || "options"
        prompt += "• #{field[:label] || field[:name]}: Please choose from #{options}\n"
      else
        prompt += "• #{field[:label] || field[:name]}\n"
      end
    end

    prompt
  end

  def extract_data_from_conversation(message)
    # Use AI to extract structured data from the conversational message
    task_session = @execution_context[:task_session]
    return {} unless task_session

    begin
      ai_service = BedrockService.new

      extraction_prompt = build_extraction_prompt(message)

      response = ai_service.complete(
        system_prompt: "You are a data extraction assistant. Extract structured data from user messages.",
        messages: [ { role: "user", content: extraction_prompt } ],
        max_tokens: 500
      )

      # Parse the JSON response
      json_match = response.match(/\{[\s\S]*\}/)
      return {} unless json_match

      JSON.parse(json_match[0])
    rescue => e
      Rails.logger.error "Failed to extract data from conversation: #{e.message}"
      {}
    end
  end

  def build_extraction_prompt(user_message)
    fields = @config[:fields] || []

    prompt = "Extract the following information from this user message:\n\n"
    prompt += "User message: \"#{user_message}\"\n\n"
    prompt += "Fields to extract:\n"

    fields.each do |field|
      prompt += "- #{field[:name]} (#{field[:type]}): #{field[:label] || field[:name]}"
      if field[:type] == "select" && field[:options]
        prompt += " - valid options: #{field[:options].map { |o| o[:value] }.join(', ')}"
      end
      prompt += "\n"
    end

    prompt += "\nReturn ONLY a JSON object with the extracted fields. Use null for any fields not found in the message."
    prompt
  end

  def execute_data_collection(inputs)
    source = @config[:source]

    case source
    when "database"
      execute_database_query(inputs)
    when "api"
      execute_api_call(inputs)
    when "user"
      execute_user_input(inputs)
    else
      {
        status: "failed",
        error: "Unknown data source: #{source}"
      }
    end
  end

  def execute_validation(inputs)
    rules = @config[:rules]
    errors = []

    rules.each do |rule|
      field = rule[:field]
      value = inputs[field] || inputs[field.to_sym]

      case rule[:type]
      when "required"
        errors << "#{field} is required" if value.blank?
      when "email"
        errors << "#{field} must be a valid email" if value.present? && !value.match?(/\A[\w+\-.]+@[a-z\d\-]+(\.[a-z\d\-]+)*\.[a-z]+\z/i)
      when "min_length"
        errors << "#{field} must be at least #{rule[:value]} characters" if value.present? && value.length < rule[:value]
      when "max_length"
        errors << "#{field} cannot exceed #{rule[:value]} characters" if value.present? && value.length > rule[:value]
      end
    end

    if errors.any?
      {
        status: "failed",
        error: errors.join(", "),
        validation_errors: errors
      }
    else
      {
        status: "success",
        message: "Validation passed",
        data: inputs
      }
    end
  end

  def execute_conditional(inputs)
    condition = @config[:condition]

    # Simple condition evaluation (can be enhanced)
    result = evaluate_condition(condition, inputs)

    {
      status: "success",
      condition_result: result,
      next_step: result ? @config[:true_step] : @config[:false_step],
      message: "Condition evaluated to: #{result}"
    }
  end

  def execute_database_query(inputs)
    # Placeholder for database queries
    # In a real implementation, this would execute the query specified in @config[:query]
    {
      status: "success",
      data: { message: "Database query executed (simulated)" },
      query: @config[:query]
    }
  end

  def execute_api_call(inputs)
    # Placeholder for API calls
    # In a real implementation, this would make HTTP requests
    {
      status: "success",
      data: { message: "API call executed (simulated)" },
      url: @config[:url]
    }
  end

  def simulate_tool_execution(tool_name, inputs)
    # Simulate different tool responses for testing
    case tool_name
    when "analyze_landing_page_request"
      # Simulate analyzing business context
      user = inputs[:user] || {}
      entity = inputs[:entity] || {}

      {
        status: "success",
        data: {
          business_profile: {
            name: entity[:name] || entity["name"] || "#{user[:first_name] || user['first_name']}'s Business",
            industry: "Technology",
            description: "A forward-thinking business focused on innovation",
            target_audience: "Small to medium businesses",
            tone_of_voice: "Professional yet approachable"
          },
          entity: {
            name: entity[:name] || entity["name"] || "My Business",
            subdomain: entity[:subdomain] || entity["subdomain"] || "mybiz"
          },
          message_context: {
            mentions_classes: true,
            mentions_new: true,
            mentions_series: true
          },
          missing_info: [ "specific class/course details", "call to action", "urgency/deadline information" ]
        },
        message: "I've analyzed your business profile. Now let's gather specific details about your classes."
      }
    when "generate_landing_page"
      {
        status: "success",
        data: {
          dsl: { page: { theme: "clean", sections: [] } },
          html: "<html><body>Generated Landing Page</body></html>"
        },
        message: "Landing page generated successfully"
      }
    when "create_contact"
      {
        status: "success",
        data: {
          contact_id: SecureRandom.uuid,
          email: inputs[:email],
          name: "#{inputs[:first_name]} #{inputs[:last_name]}"
        },
        message: "Contact created successfully"
      }
    when "send_email"
      {
        status: "success",
        data: {
          message_id: SecureRandom.uuid,
          recipient: inputs[:recipient]
        },
        message: "Email sent successfully"
      }
    else
      {
        status: "success",
        data: inputs,
        message: "Tool '#{tool_name}' executed successfully (simulated)"
      }
    end
  end

  def evaluate_condition(condition, inputs)
    # Simple condition evaluation
    # Format: "field operator value" (e.g., "email contains @example.com")
    parts = condition.split(" ")
    return false if parts.length < 3

    field = parts[0]
    operator = parts[1]
    expected_value = parts[2..-1].join(" ")

    actual_value = inputs[field] || inputs[field.to_sym]

    case operator
    when "equals", "=="
      actual_value.to_s == expected_value
    when "contains"
      actual_value.to_s.include?(expected_value)
    when "starts_with"
      actual_value.to_s.start_with?(expected_value)
    when "ends_with"
      actual_value.to_s.end_with?(expected_value)
    when "present", "exists"
      actual_value.present?
    when "blank", "empty"
      actual_value.blank?
    else
      false
    end
  end
end
