class Step
  attr_reader :id, :type, :config, :status, :started_at, :completed_at, :error, :result
  
  # Step statuses
  STATUSES = %w[pending in_progress completed failed skipped].freeze
  
  # Step types
  TYPES = %w[tool_call user_input form_input data_collection validation conditional].freeze
  
  def initialize(spec)
    spec = spec.with_indifferent_access
    
    @id = spec[:id] || SecureRandom.uuid
    @type = spec[:type] || 'tool_call'
    @config = spec[:config] || {}
    @status = 'pending'
    @started_at = nil
    @completed_at = nil
    @error = nil
    @result = nil
    
    # Validate step type
    unless TYPES.include?(@type)
      raise ArgumentError, "Invalid step type: #{@type}. Must be one of: #{TYPES.join(', ')}"
    end
    
    validate_config!
  end
  
  # Check if step requires user input
  def requires_input?
    case @type
    when 'user_input', 'form_input'
      true
    when 'tool_call'
      @config[:requires_input] == true
    else
      @config[:requires_input] == true
    end
  end
  
  # Execute the step
  def execute(inputs = {})
    @status = 'in_progress'
    @started_at = Time.current
    
    result = case @type
    when 'tool_call'
      execute_tool_call(inputs)
    when 'user_input', 'form_input'
      execute_user_input(inputs)
    when 'data_collection'
      execute_data_collection(inputs)
    when 'validation'
      execute_validation(inputs)
    when 'conditional'
      execute_conditional(inputs)
    else
      { status: 'failed', error: "Unknown step type: #{@type}" }
    end
    
    # Store result for later reference
    @result = result
    
    result
  end
  
  # Mark step as completed
  def mark_completed(result = {})
    @status = 'completed'
    @completed_at = Time.current
    @result = result
  end
  
  # Mark step as failed
  def mark_failed(error_message)
    @status = 'failed'
    @completed_at = Time.current
    @error = error_message
  end
  
  # Mark step as skipped
  def mark_skipped(reason = 'Skipped')
    @status = 'skipped'
    @completed_at = Time.current
    @result = { status: 'skipped', reason: reason }
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
      requires_input: requires_input?
    }
  end
  
  # Get human-readable description
  def description
    @config[:description] || @config[:title] || "#{@type.humanize} step"
  end
  
  # Get form configuration for user input steps
  def form_config
    return nil unless requires_input?
    
    @config[:form] || {
      title: description,
      fields: @config[:fields] || [],
      submit_label: @config[:submit_label] || 'Continue'
    }
  end
  
  private
  
  def validate_config!
    case @type
    when 'tool_call'
      unless @config[:tool].present?
        raise ArgumentError, "tool_call step requires 'tool' in config"
      end
    when 'user_input', 'form_input'
      unless @config[:fields].present?
        raise ArgumentError, "#{@type} step requires 'fields' in config"
      end
    when 'validation'
      unless @config[:rules].present?
        raise ArgumentError, "validation step requires 'rules' in config"
      end
    when 'conditional'
      unless @config[:condition].present?
        raise ArgumentError, "conditional step requires 'condition' in config"
      end
    end
  end
  
  def execute_tool_call(inputs)
    tool_name = @config[:tool]
    tool_inputs = @config[:inputs] || {}
    
    # Merge step inputs with provided inputs
    merged_inputs = tool_inputs.merge(inputs)
    
    # Check if ToolRunner exists, otherwise simulate
    if defined?(ToolRunner)
      ToolRunner.new.call(tool: tool_name, inputs: merged_inputs)
    else
      # Simulate tool execution for now
      simulate_tool_execution(tool_name, merged_inputs)
    end
  end
  
  def execute_user_input(inputs)
    if inputs.empty?
      {
        status: 'awaiting_input',
        form: form_config,
        message: "Please provide input for: #{description}"
      }
    else
      # Validate required fields
      required_fields = @config[:fields]&.select { |f| f[:required] }&.map { |f| f[:name] } || []
      missing_fields = required_fields - inputs.keys.map(&:to_s)
      
      if missing_fields.any?
        {
          status: 'failed',
          error: "Missing required fields: #{missing_fields.join(', ')}"
        }
      else
        {
          status: 'success',
          data: inputs,
          message: "User input collected successfully"
        }
      end
    end
  end
  
  def execute_data_collection(inputs)
    source = @config[:source]
    
    case source
    when 'database'
      execute_database_query(inputs)
    when 'api'
      execute_api_call(inputs)
    when 'user'
      execute_user_input(inputs)
    else
      {
        status: 'failed',
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
      when 'required'
        errors << "#{field} is required" if value.blank?
      when 'email'
        errors << "#{field} must be a valid email" if value.present? && !value.match?(/\A[\w+\-.]+@[a-z\d\-]+(\.[a-z\d\-]+)*\.[a-z]+\z/i)
      when 'min_length'
        errors << "#{field} must be at least #{rule[:value]} characters" if value.present? && value.length < rule[:value]
      when 'max_length'
        errors << "#{field} cannot exceed #{rule[:value]} characters" if value.present? && value.length > rule[:value]
      end
    end
    
    if errors.any?
      {
        status: 'failed',
        error: errors.join(', '),
        validation_errors: errors
      }
    else
      {
        status: 'success',
        message: 'Validation passed',
        data: inputs
      }
    end
  end
  
  def execute_conditional(inputs)
    condition = @config[:condition]
    
    # Simple condition evaluation (can be enhanced)
    result = evaluate_condition(condition, inputs)
    
    {
      status: 'success',
      condition_result: result,
      next_step: result ? @config[:true_step] : @config[:false_step],
      message: "Condition evaluated to: #{result}"
    }
  end
  
  def execute_database_query(inputs)
    # Placeholder for database queries
    # In a real implementation, this would execute the query specified in @config[:query]
    {
      status: 'success',
      data: { message: 'Database query executed (simulated)' },
      query: @config[:query]
    }
  end
  
  def execute_api_call(inputs)
    # Placeholder for API calls
    # In a real implementation, this would make HTTP requests
    {
      status: 'success',
      data: { message: 'API call executed (simulated)' },
      url: @config[:url]
    }
  end
  
  def simulate_tool_execution(tool_name, inputs)
    # Simulate different tool responses for testing
    case tool_name
    when 'generate_landing_page'
      {
        status: 'success',
        data: {
          dsl: { page: { theme: 'clean', sections: [] } },
          html: '<html><body>Generated Landing Page</body></html>'
        },
        message: "Landing page generated successfully"
      }
    when 'create_contact'
      {
        status: 'success',
        data: {
          contact_id: SecureRandom.uuid,
          email: inputs[:email],
          name: "#{inputs[:first_name]} #{inputs[:last_name]}"
        },
        message: "Contact created successfully"
      }
    when 'send_email'
      {
        status: 'success',
        data: {
          message_id: SecureRandom.uuid,
          recipient: inputs[:recipient]
        },
        message: "Email sent successfully"
      }
    else
      {
        status: 'success',
        data: inputs,
        message: "Tool '#{tool_name}' executed successfully (simulated)"
      }
    end
  end
  
  def evaluate_condition(condition, inputs)
    # Simple condition evaluation
    # Format: "field operator value" (e.g., "email contains @example.com")
    parts = condition.split(' ')
    return false if parts.length < 3
    
    field = parts[0]
    operator = parts[1]
    expected_value = parts[2..-1].join(' ')
    
    actual_value = inputs[field] || inputs[field.to_sym]
    
    case operator
    when 'equals', '=='
      actual_value.to_s == expected_value
    when 'contains'
      actual_value.to_s.include?(expected_value)
    when 'starts_with'
      actual_value.to_s.start_with?(expected_value)
    when 'ends_with'
      actual_value.to_s.end_with?(expected_value)
    when 'present', 'exists'
      actual_value.present?
    when 'blank', 'empty'
      actual_value.blank?
    else
      false
    end
  end
end
