class WorkflowExecution < ApplicationRecord
  belongs_to :task_session
  belongs_to :user
  belongs_to :entity
  belongs_to :workflow_template, optional: true
  has_many :workflow_step_executions, dependent: :destroy
  has_many :workflow_variables, dependent: :destroy
  has_many :workflow_contexts, dependent: :destroy

  # Status enum
  enum :status, {
    pending: "pending",
    running: "running",
    awaiting_input: "awaiting_input",
    completed: "completed",
    failed: "failed",
    paused: "paused",
    cancelled: "cancelled"
  }, prefix: true

  # Scopes
  scope :active, -> { where(status: [ "pending", "running", "paused" ]) }
  scope :recent, -> { order(created_at: :desc) }

  # Callbacks
  before_create :set_started_at

  # Get a variable by name
  def get_variable(name)
    workflow_variables.by_name(name).first&.value
  end

  # Set a variable
  def set_variable(name, value, source: nil, data_type: nil)
    var = workflow_variables.find_or_initialize_by(name: name)
    var.value = value
    var.source = source if source
    var.data_type = data_type || detect_data_type(value)
    var.save!
    var
  end

  # Extract and save variables from step output
  def extract_variables_from_step(step_execution)
    return unless step_execution.output_data.present?

    Rails.logger.info "Extracting variables from step #{step_execution.step_id}"
    Rails.logger.info "Output data keys: #{step_execution.output_data.keys}"

    # Use AI to intelligently extract variables
    ai_service = BedrockService.new

    # Build extraction prompt
    extraction_prompt = build_extraction_prompt(step_execution)

    begin
      response = ai_service.complete(
        prompt: extraction_prompt,
        max_tokens: 1000,
        temperature: 0.2 # Low temperature for consistent extraction
      )

      # Parse the AI response
      extracted_vars = parse_extraction_response(response)

      if extracted_vars.is_a?(Hash)
        # Store each extracted variable
        extracted_vars.each do |var_name, var_value|
          set_variable(var_name, var_value, source: step_execution)
          Rails.logger.info "AI extracted variable: #{var_name} = #{var_value}"
        end
      else
        Rails.logger.warn "AI variable extraction failed, falling back to pattern matching"
        # Fallback to simple pattern extraction
        extract_common_patterns(step_execution.output_data.with_indifferent_access, step_execution)
      end
    rescue => e
      Rails.logger.error "AI variable extraction error: #{e.message}"
      # Fallback to simple pattern extraction
      extract_common_patterns(step_execution.output_data.with_indifferent_access, step_execution)
    end
  end

  def build_extraction_prompt(step_execution)
    # Get the next steps to understand what variables they might need
    next_steps = workflow_step_executions.status_pending.limit(3)
    next_step_configs = next_steps.map do |next_step|
      # Find the step definition from the workflow spec
      step_def = workflow_spec.dig("steps")&.find { |s| s["id"] == next_step.step_id } ||
                 workflow_spec.dig(:steps)&.find { |s| s[:id] == next_step.step_id }
      step_def || { id: next_step.step_id }
    end

    <<~PROMPT
      You are a data extraction expert. Your job is to extract useful variables from step output data.

      Step Information:
      - Step ID: #{step_execution.step_id}
      - Step Type: #{step_execution.step_type}

      Step Output Data:
      #{JSON.pretty_generate(step_execution.output_data).first(2000)}

      Next Steps That May Need Variables:
      #{next_step_configs.map { |s| "- #{s['id'] || s[:id]}: #{s['tool_args'] || s[:tool_args] || {}}" }.join("\n")}

      Common Variable Patterns:
      - IDs of created/fetched records (e.g., template_id, campaign_id, contact_id)
      - Counts and totals
      - Status values
      - Names and descriptions
      - Any field that might be referenced by {{variable_name}} in future steps

      Based on the step name and output data, extract the most useful variables.
      Use simple, intuitive variable names.

      For example:
      - If step is "get_template", extract "template_id" from the first record's ID
      - If step is "create_campaign", extract "campaign_id" from the created record's ID
      - If data contains multiple records, extract the first one's ID as "{type}_id"

      IMPORTANT: Look at the output data structure carefully. Common patterns:
      - data.result.records[0].id
      - data.result.record.id
      - result.records[0].id
      - data.records[0].id

      Respond with ONLY a JSON object mapping variable names to values:
      {
        "variable_name": "value",
        "another_variable": 123
      }

      If you cannot extract any meaningful variables, respond with an empty object: {}
    PROMPT
  end

  def parse_extraction_response(response)
    # Try to extract JSON from the response
    json_match = response.match(/\{[^{}]*\}/m)
    if json_match
      JSON.parse(json_match[0])
    else
      # Try parsing the whole response
      JSON.parse(response.strip)
    end
  rescue JSON::ParserError => e
    Rails.logger.error "Failed to parse AI extraction response: #{e.message}"
    Rails.logger.debug "AI response was: #{response}"
    nil
  end

  def extract_variables_recursively(data, prefix, source, depth = 0)
    # Limit depth to prevent infinite recursion
    return if depth > 3

    case data
    when Hash
      # For objects, extract meaningful fields
      data.each do |key, value|
        next if key.to_s.start_with?("_") # Skip internal fields
        next if %w[metadata headers].include?(key.to_s) # Skip noisy fields

        var_name = [ prefix, key ].compact.join(".")

        case value
        when String, Numeric, TrueClass, FalseClass
          # Store simple values directly
          set_variable(var_name, value, source: source)
        when Array
          # For arrays, store the count and first few items
          set_variable("#{var_name}.count", value.length, source: source)
          value.first(3).each_with_index do |item, idx|
            if item.is_a?(Hash) || item.is_a?(Array)
              extract_variables_recursively(item, "#{var_name}[#{idx}]", source, depth + 1)
            else
              set_variable("#{var_name}[#{idx}]", item, source: source)
            end
          end
        when Hash
          # Recurse into nested objects
          extract_variables_recursively(value, var_name, source, depth + 1)
        end
      end
    when Array
      # Handle top-level arrays
      data.first(3).each_with_index do |item, idx|
        extract_variables_recursively(item, "#{prefix}[#{idx}]", source, depth + 1)
      end
    end
  end

  def extract_common_patterns(output, step_execution)
    step_id = step_execution.step_id

    # Pattern 1: Records with IDs (common in get_data results)
    records_paths = [
      [ "data", "result", "records" ],
      [ "result", "result", "records" ],
      [ "data", "records" ],
      [ "result", "records" ]
    ]

    records_paths.each do |path|
      if records = output.dig(*path)
        if records.is_a?(Array) && records.first.is_a?(Hash)
          # Store first record's ID with a simple name
          if first_id = records.first["id"]
            # Try to infer what type of ID this is from the step name
            if step_id.include?("template")
              set_variable("template_id", first_id, source: step_execution)
            elsif step_id.include?("campaign")
              set_variable("campaign_id", first_id, source: step_execution)
            elsif step_id.include?("contact")
              set_variable("contact_id", first_id, source: step_execution)
            else
              # Generic ID variable
              set_variable("#{step_id}_id", first_id, source: step_execution)
            end
          end
        end
      end
    end

    # Pattern 2: Created/updated records (common in create_object results)
    record_paths = [
      [ "data", "result", "record" ],
      [ "result", "result", "record" ],
      [ "data", "record" ],
      [ "result", "record" ]
    ]

    record_paths.each do |path|
      if record = output.dig(*path)
        if record.is_a?(Hash) && record["id"]
          # Store the ID with an intuitive name
          if step_id.include?("create")
            # Extract what was created from step name
            created_type = step_id.gsub("create_", "").gsub("create", "")
            if created_type.empty?
              # Try to infer from the record itself
              created_type = record["object_type"] || record["type"] || step_id
            end
            set_variable("#{created_type}_id", record["id"], source: step_execution)
          else
            set_variable("#{step_id}_id", record["id"], source: step_execution)
          end
        end
      end
    end
  end

  # Get next pending step
  def next_pending_step
    workflow_step_executions.status_pending.order(:created_at).first
  end

  # Check if all steps are complete
  def all_steps_complete?
    workflow_step_executions.status_pending.none? &&
    workflow_step_executions.status_running.none?
  end

  # Mark as completed
  def mark_completed!
    update!(status: :completed, completed_at: Time.current)
  end

  # Mark as failed
  def mark_failed!(error_message)
    update!(status: :failed, error_message: error_message, completed_at: Time.current)
  end

  private

  def set_started_at
    self.started_at ||= Time.current
  end

  def detect_data_type(value)
    case value
    when String then "string"
    when Integer then "integer"
    when Float then "float"
    when TrueClass, FalseClass then "boolean"
    when Array then "array"
    when Hash then "object"
    else "unknown"
    end
  end
end
