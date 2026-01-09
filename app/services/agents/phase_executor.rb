module Agents
  class PhaseExecutor
    attr_reader :phase, :context, :ai_service

    def initialize(phase, context)
      @phase = phase
      @context = context
      @ai_service = BedrockService.new
      @workflow_execution = context[:workflow_execution]
      @progress_callback = context[:progress_callback]
    end

    # Override in subclasses
    def execute
      raise NotImplementedError, "Subclasses must implement execute method"
    end

    protected

    # Check if phase completion criteria are met
    def check_completion_criteria
      criteria = @phase[:completion_criteria] || @phase["completion_criteria"]
      return true unless criteria

      # Evaluate each criterion
      criteria.all? do |key, value|
        case key.to_s
        when "all_required_knowledge_gathered"
          value ? has_all_required_knowledge? : true
        when "max_conversation_turns"
          @conversation_turns ||= 0
          @conversation_turns < value
        else
          # Custom criteria evaluation
          evaluate_custom_criteria(key, value)
        end
      end
    end

    # Store phase output in WorkflowContext
    def store_phase_output(data, data_type = "extracted_data")
      return unless @workflow_execution && data.present?

      phase_id = @phase[:id] || @phase["id"]
      task_session = @context[:task_session]

      return unless task_session

      data.each do |key, value|
        context_key = "#{phase_id}_#{key}"
        WorkflowContext.create!(
          workflow_execution: @workflow_execution,
          task_session: task_session,
          key: context_key,
          value: value,
          data_type: data_type,
          metadata: {
            phase_id: phase_id,
            extracted_at: Time.current
          }
        )
        Rails.logger.info "📦 Stored #{context_key} in workflow context"
      end
    end

    # Send progress update to UI
    def notify_progress(message, type: "phase_progress", **extra_data)
      @progress_callback&.call({
        type: type,
        phase_id: @phase[:id] || @phase["id"],
        message: message
      }.merge(extra_data))
    end

    # Get workflow context data
    def get_workflow_context(key = nil, data_type = nil)
      return {} unless @workflow_execution

      if key
        context_item = @workflow_execution.workflow_contexts.find_by(key: key)
        context_item&.value
      else
        contexts = @workflow_execution.workflow_contexts
        contexts = contexts.where(data_type: data_type) if data_type
        contexts.each_with_object({}) do |item, hash|
          hash[item.key] = item.value
        end
      end
    end

    # Execute tool with context
    def execute_tool(tool_name, tool_args = {})
      Rails.logger.info "🔧 Phase executing tool: #{tool_name}"

      # ToolCatalog is a singleton - get instance and execute
      catalog = ::Tools::ToolCatalog.instance

      # Build execution context (only keys that tools expect)
      execution_context = {
        user: @context[:user],
        entity: @context[:entity],
        context: @context,  # Full context available but not passed to constructor
        progress_callback: @progress_callback  # Pass progress callback for real-time updates
      }

      catalog.execute_tool(tool_name, tool_args, **execution_context)
    end

    # Use AI to make a decision
    def ai_decide(prompt, options = {})
      system_prompt = options[:system_prompt] || default_system_prompt

      # Format messages for Bedrock
      messages = [
        { role: "system", content: system_prompt },
        { role: "user", content: prompt }
      ]

      response = @ai_service.complete(
        messages: messages,
        max_tokens: options[:max_tokens] || 2000,
        temperature: options[:temperature] || 0.3
      )

      # Try to parse JSON if expected
      if options[:expect_json]
        parse_json_response(response)
      else
        response
      end
    end

    private

    def default_system_prompt
      <<~PROMPT
        You are an intelligent workflow phase executor.
        Your job is to achieve the phase goal efficiently and intelligently.

        Guidelines:
        - Use available context before asking users
        - Be conversational and natural
        - Make smart decisions based on available data
        - Know when to stop and ask for help
      PROMPT
    end

    def parse_json_response(response)
      # Remove markdown code fences if present
      cleaned = response.gsub(/```json\s*|\s*```/, "").strip

      # Try to find JSON object - use a more robust approach
      # Look for the outermost { } pair
      start_idx = cleaned.index("{")
      return { error: "No JSON found", raw: response } unless start_idx

      # Find matching closing brace
      depth = 0
      end_idx = nil

      cleaned[start_idx..-1].each_char.with_index(start_idx) do |char, idx|
        depth += 1 if char == "{"
        depth -= 1 if char == "}"
        if depth == 0
          end_idx = idx
          break
        end
      end

      return { error: "Unmatched braces", raw: response } unless end_idx

      json_str = cleaned[start_idx..end_idx]
      parsed = JSON.parse(json_str)

      Rails.logger.info "✅ Successfully parsed JSON with #{parsed.keys.join(', ')}"
      parsed
    rescue JSON::ParserError => e
      Rails.logger.error "Failed to parse AI JSON response: #{e.message}"
      Rails.logger.error "Response preview: #{response[0..200]}"
      { error: "Invalid JSON response", raw: response }
    end

    def has_all_required_knowledge?
      required = @phase[:required_knowledge] || @phase["required_knowledge"]
      return true unless required

      # Check if all required knowledge fields have been gathered
      gathered = get_workflow_context

      required.all? do |category, fields|
        fields.all? do |field|
          key = "#{@phase[:id]}_#{category}_#{field}".gsub("_", "_")
          gathered.key?(key) || gathered.key?("#{@phase[:id]}_#{field}")
        end
      end
    end

    def evaluate_custom_criteria(key, value)
      # Override in subclasses for custom criteria
      true
    end
  end
end
