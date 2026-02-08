# frozen_string_literal: true

module V3
  # AgentLoop - The V3 agent loop
  #
  # This is the core of V3. The entire loop is:
  #   1. Build system prompt (identity + skills + context)
  #   2. Send to LLM with 10 power tools
  #   3. Execute tool calls
  #   4. If more tool calls → go to 2
  #   5. If done → return response
  #   6. Compact if context too long
  #
  # No preprocessor. No intent classifier. No RAG tool discovery.
  # No LLM refinement. The model has 10 tools and platform skills.
  # It figures out the rest.
  #
  # ~300 lines instead of ~4500 lines.
  #
  class AgentLoop
    MAX_TOOL_TURNS = 25
    MAX_REPEATED_FAILURES = 3
    MAX_HALLUCINATION_RETRIES = 2

    attr_reader :user, :entity, :session_id, :model
    attr_accessor :suggested_canvas, :canvas_data

    # Default model for auto mode - fast and cheap
    DEFAULT_AUTO_MODEL = "qwen3-next-80b"

    # Patterns indicating the model claims to have done something
    ACTION_CLAIM_PATTERNS = [
      /i['']ve (already )?(updated|changed|modified|repositioned|moved|edited|fixed|added|removed|created|addressed|made|built|saved)/i,
      /i (updated|changed|modified|repositioned|moved|edited|fixed|added|removed|created|made|built|saved) (the|your|this|\d+)/i,
      /✅\s*(i['']ve|done|updated|changed|repositioned|moved|complete|created|saved)/i,
      /done\.?\s*(all )?\d+\s*(contacts?|records?|items?|customers?)/i,
      /successfully (updated|changed|modified|repositioned|created|added|built|saved)/i,
      /all \d+ (contacts?|records?|items?) (created|saved|added|updated)/i,
      /(created|added|saved|built).*(successfully|complete)/i,
      /group (created|saved) with/i,
      /proceeding now.*done/i,
      # Future-tense setup without action (model describes what it will do but doesn't call tools)
      /i['']ll (create|build|make|update|send|set up|configure|generate)/i,
      /first,?\s*(creating|building|setting up|let me create|let me build)/i,
      /creating\s+(the\s+)?(welcome\s+)?(email|template|workflow|landing|contact|campaign)/i,
      # Generic "doing it now" without tool calls
      /\bnow\.{2,}$/i,
      /creating.*now/i,
    ].freeze

    # Patterns indicating the user asked for an action
    TASK_NEEDS_ACTION_PATTERNS = [
      /create|make|build|add|save|update|edit|fix|modify|put|place|remove|delete|show|open|view|display/i,
    ].freeze

    # Patterns indicating a confirmation/approval (short messages that reference prior context)
    CONFIRMATION_PATTERNS = [
      /^(yes|yep|yeah|yea|ya|sure|ok|okay|go|do it|build it|create it|make it|let'?s go|proceed|approved?|confirm|absolutely|definitely|go ahead|go for it|sounds? good|perfect|great|let'?s do it|yes,?\s*(please|create|build|do|go))/i,
    ].freeze

    def initialize(user:, entity:, session_id:, model: nil, intent_mode: nil)
      @user = user
      @entity = entity
      @session_id = session_id
      # Use qwen for auto mode (cheap/fast), only use premium if explicitly selected
      @model = model.presence || ENV.fetch("BEDROCK_DEFAULT_MODEL", DEFAULT_AUTO_MODEL)
      @intent_mode = intent_mode
      @ai_service = BedrockService.new(user: user, entity: entity)
      @prompt_builder = V3::SystemPromptBuilder.new(user: user, entity: entity, session_id: session_id)
      @compaction = V3::ConversationCompactionService.new(user: user, entity: entity, model: @model)
      @tools_called = []
      @tool_call_history = []
      @suggested_canvas = nil
      @canvas_data = {}
      
      Rails.logger.info "[V3::AgentLoop] Initialized with model: #{@model} (explicit: #{model.present?})"
    end

    # Process a message with streaming response
    # @param message [String] The user's message
    # @param progress_callback [Proc] Callback for streaming chunks
    # @param conversation_history [Array<Hash>] Previous messages
    # @param current_canvas [String] Current canvas view
    # @return [Hash] { final_response:, tools_used:, suggested_canvas:, canvas_data: }
    def process_message_streaming(message, progress_callback, conversation_history = [], current_canvas = nil)
      Rails.logger.info "[V3::AgentLoop] Processing message (#{message.truncate(100)})"

      # 1. Build system prompt
      system_prompt = @prompt_builder.build(
        current_canvas: current_canvas,
        message: message,
        intent_mode: @intent_mode
      )

      # 2. Prepare conversation messages
      conversation_messages = prepare_messages(conversation_history)

      # 3. Compact if needed
      conversation_messages = @compaction.compact_if_needed(
        conversation_messages,
        system_prompt: system_prompt
      )

      # 4. Add current user message (merge if last message is also from user)
      if conversation_messages.last && conversation_messages.last[:role] == "user"
        # Merge with previous user message to maintain alternating pattern
        existing_text = conversation_messages.last[:content].map { |c| c[:text] }.join("\n")
        conversation_messages.last[:content] = [{ text: "#{existing_text}\n#{message}" }]
        Rails.logger.info "[V3::AgentLoop] Merged consecutive user message with previous"
      else
        conversation_messages << {
          role: "user",
          content: [{ text: message }]
        }
      end

      # 5. Get V3 tools
      tools = V3::ToolRegistry.get_bedrock_tools(entity: entity)

      # Log the message roles to verify alternating pattern
      roles = conversation_messages.map { |m| m[:role] }.join(" → ")
      Rails.logger.info "[V3::AgentLoop] System prompt: #{system_prompt.length} chars, " \
                        "#{conversation_messages.length} messages, #{tools.length} tools"
      Rails.logger.info "[V3::AgentLoop] Message pattern: #{roles}"

      # 6. Run the agent loop
      run_loop(system_prompt, conversation_messages, tools, progress_callback)
    end

    private

    def run_loop(system_prompt, conversation_messages, tools, progress_callback)
      accumulated_content = ""
      turn_count = 0
      failure_counts = Hash.new(0)
      @hallucination_retry_count = 0
      @empty_response_retry_count = 0
      @original_user_message = extract_original_message(conversation_messages)

      loop do
        turn_count += 1
        if turn_count > MAX_TOOL_TURNS
          Rails.logger.warn "[V3::AgentLoop] Max turns (#{MAX_TOOL_TURNS}) exceeded"
          break
        end

        # Call the LLM
        tool_calls = []
        current_tool = nil  # Track current tool being streamed
        tool_input_buffer = ""  # Accumulate JSON input
        client_disconnected = false

        begin
          @ai_service.send_message_streaming(
            system_prompt,
            conversation_messages,
            model: @model,
            max_tokens: 8192,
            temperature: 0.7,
            json_mode: false,
            tools: tools,
            enable_prompt_caching: true
          ) do |chunk|
            case chunk[:type]
            when :content
              # Text content from the model
              text = chunk[:text] || chunk[:content]
              if text.present?
                accumulated_content += text
                progress_callback&.call(chunk)
              end
            when :tool_use_start
              # Tool use is starting - save ID and name
              current_tool = {
                id: chunk[:tool_id],
                name: chunk[:tool_name],
                arguments: {}
              }
              tool_input_buffer = ""
              Rails.logger.info "[V3::AgentLoop] Tool starting: #{chunk[:tool_name]} (#{chunk[:tool_id]})"
            when :tool_use
              # Tool use delta - accumulate input JSON
              if chunk[:tool_use]
                # AWS SDK object - extract input
                if chunk[:tool_use].respond_to?(:input)
                  tool_input_buffer += chunk[:tool_use].input.to_s
                elsif chunk[:tool_use].is_a?(Hash) && chunk[:tool_use][:input]
                  tool_input_buffer += chunk[:tool_use][:input].to_s
                end
              end
            when :content_block_stop
              # Content block complete - finalize current tool if any
              if current_tool
                begin
                  current_tool[:arguments] = JSON.parse(tool_input_buffer) if tool_input_buffer.present?
                rescue JSON::ParserError
                  current_tool[:arguments] = { raw: tool_input_buffer }
                end
                tool_calls << current_tool
                Rails.logger.info "[V3::AgentLoop] Tool complete: #{current_tool[:name]} with args: #{current_tool[:arguments].keys.join(', ')}"
                current_tool = nil
                tool_input_buffer = ""
              end
            when :complete
              # Message complete - finalize any pending tool (fallback)
              if current_tool
                begin
                  current_tool[:arguments] = JSON.parse(tool_input_buffer) if tool_input_buffer.present?
                rescue JSON::ParserError
                  current_tool[:arguments] = { raw: tool_input_buffer }
                end
                tool_calls << current_tool
                Rails.logger.info "[V3::AgentLoop] Tool finalized on message_stop: #{current_tool[:name]}"
                current_tool = nil
                tool_input_buffer = ""
              end
            end
          end
          
          # If we have a pending tool after streaming ends (no :complete event), finalize it
          if current_tool
            begin
              current_tool[:arguments] = JSON.parse(tool_input_buffer) if tool_input_buffer.present?
            rescue JSON::ParserError
              current_tool[:arguments] = { raw: tool_input_buffer }
            end
            tool_calls << current_tool
            Rails.logger.info "[V3::AgentLoop] Tool finalized post-stream: #{current_tool[:name]}"
          end
        rescue => e
          if e.class.name.include?("ClientDisconnected")
            client_disconnected = true
          else
            Rails.logger.error "[V3::AgentLoop] Streaming error: #{e.message}"
            raise e
          end
        end

        # If client disconnected, stop
        if client_disconnected
          return build_result(accumulated_content, "Client disconnected")
        end

        # If no tool calls, check for issues before returning
        if tool_calls.empty?
          # Check for empty response on confirmation message (Qwen sometimes returns nothing)
          if accumulated_content.blank? && @tools_called.empty? && @empty_response_retry_count.to_i == 0
            user_msg = @original_user_message.to_s.strip
            if CONFIRMATION_PATTERNS.any? { |p| user_msg.match?(p) }
              @empty_response_retry_count = 1
              Rails.logger.warn "🔄 [V3] EMPTY RESPONSE ON CONFIRMATION: '#{user_msg.truncate(50)}' — re-prompting with context"
              
              # Extract what was being discussed from the last assistant message
              last_assistant = conversation_messages.select { |m| m[:role] == "assistant" }.last
              prior_context = last_assistant&.dig(:content)&.map { |c| c[:text] }&.join("\n")&.truncate(500) || ""
              
              nudge = <<~NUDGE
                [SYSTEM] The user said "#{user_msg}" to confirm your previous proposal.
                Your previous message was: #{prior_context.truncate(300)}
                
                NOW execute what you proposed. Use the appropriate tool (platform_create, platform_update, etc.) to build what the user approved.
              NUDGE
              
              conversation_messages << { role: "assistant", content: [{ text: "I'll do that now." }] }
              conversation_messages << { role: "user", content: [{ text: nudge }] }
              
              accumulated_content = ""
              next
            end
          end

          # Check if the response claims to have done something without calling tools
          if detect_action_hallucination(accumulated_content, @original_user_message) && @tools_called.empty?
            @hallucination_retry_count += 1
            
            if @hallucination_retry_count <= MAX_HALLUCINATION_RETRIES
              Rails.logger.warn "🎭 [V3] ACTION HALLUCINATION DETECTED (attempt #{@hallucination_retry_count}): " \
                                "Model claimed action without tool calls!"
              Rails.logger.warn "🎭 Response preview: #{accumulated_content.to_s.truncate(200)}"
              
              # Add correction instruction to force tool use
              correction = <<~CORRECTION
                [SYSTEM] ERROR: You described what you would do but did NOT call any tools. Nothing happened.
                
                You MUST call a tool NOW. Do not explain — just call the tool.
                Examples:
                - platform_create(type: "email_template", data: { name: "...", subject: "...", body: "<html>..." })
                - platform_create(type: "workflow", data: { name: "...", trigger: "contact_created", actions: [...] })
                - platform_create(type: "contact", data: { ... })
                - platform_update(type: "...", id: X, data: { ... })
                
                CALL THE TOOL NOW.
              CORRECTION
              
              # Add the failed response and correction to conversation
              conversation_messages << { role: "assistant", content: [{ text: accumulated_content }] }
              conversation_messages << { role: "user", content: [{ text: correction }] }
              
              # Reset and continue the loop
              accumulated_content = ""
              next
            else
              Rails.logger.warn "🎭 [V3] Max hallucination retries exceeded - returning response anyway"
            end
          end
          
          return build_result(accumulated_content)
        end

        # Execute tool calls
        Rails.logger.info "[V3::AgentLoop] Turn #{turn_count}: #{tool_calls.length} tool call(s): #{tool_calls.map { |t| t[:name] }.join(', ')}"

        # Add assistant message with tool calls to conversation
        assistant_content = []
        assistant_content << { text: accumulated_content } if accumulated_content.present?
        tool_calls.each do |tc|
          assistant_content << {
            tool_use: {
              tool_use_id: tc[:id],
              name: tc[:name],
              input: tc[:arguments]
            }
          }
        end
        conversation_messages << { role: "assistant", content: assistant_content }

        # Execute each tool and build results
        tool_results = execute_tools(tool_calls, progress_callback)

        # Check for loops BEFORE adding results (but don't add message yet)
        loop_detected, loop_reason = check_for_loops(tool_calls, tool_results)
        if loop_detected
          Rails.logger.warn "[V3::AgentLoop] Loop detected: #{loop_reason}"
        end

        # Check for repeated failures
        tool_calls.each_with_index do |tc, idx|
          result = tool_results[idx]
          if result_is_error?(result)
            failure_counts[tc[:name]] += 1
            if failure_counts[tc[:name]] >= MAX_REPEATED_FAILURES
              Rails.logger.warn "[V3::AgentLoop] Tool #{tc[:name]} failed #{MAX_REPEATED_FAILURES} times"
            end
          end
        end

        # Add tool results to conversation - MUST immediately follow assistant tool_use
        tool_result_content = tool_calls.each_with_index.map do |tc, idx|
          {
            tool_result: {
              tool_use_id: tc[:id],
              content: format_tool_result(tool_results[idx])
            }
          }
        end
        conversation_messages << { role: "user", content: tool_result_content }
        
        # NOW add loop detection message as a separate user message AFTER tool results
        # This maintains proper alternation: assistant(tool_use) → user(tool_result) → user(system note)
        # The next LLM call will merge consecutive user messages
        if loop_detected
          # If loop detected and we're past halfway, break out
          if turn_count > MAX_TOOL_TURNS / 2
            Rails.logger.warn "[V3::AgentLoop] Breaking loop - past turn limit"
            break
          end
        end

        # Track tools for response
        tool_calls.each { |tc| @tools_called << tc[:name] }

        # Reset accumulated content for next turn
        accumulated_content = ""

        # Stream a progress indicator
        progress_callback&.call({ type: :status, text: "Processing results..." })
      end

      build_result(accumulated_content)
    end

    def execute_tools(tool_calls, progress_callback)
      tool_calls.map do |tc|
        begin
          # Handle canvas loading specially (broadcast to frontend)
          if tc[:name] == "load_canvas"
            @suggested_canvas = tc[:arguments]["canvas_name"] || tc[:arguments][:canvas_name]
            @canvas_data = tc[:arguments]["canvas_data"] || tc[:arguments][:canvas_data] || {}

            progress_callback&.call({
              type: :canvas_suggestion,
              canvas: @suggested_canvas,
              data: @canvas_data
            })

            { success: true, message: "Canvas '#{@suggested_canvas}' loaded" }
          elsif tc[:name] == "ask_user"
            # Handle ask_user suspension
            progress_callback&.call({
              type: :ask_user,
              question: tc[:arguments]["question"] || tc[:arguments][:question]
            })
            
            # This raises ExecutionSuspended which halts the loop
            V3::ToolRegistry.execute(
              tc[:name],
              tc[:arguments],
              user: user,
              entity: entity,
              context: build_tool_context
            )
          else
            # For platform_do: hide thinking indicator since Brain streams its own progress
            if tc[:name] == "platform_do"
              progress_callback&.call({ type: :content, text: "" })
            end

            # Execute through V3 registry
            result = V3::ToolRegistry.execute(
              tc[:name],
              tc[:arguments],
              user: user,
              entity: entity,
              context: build_tool_context,
              progress_callback: progress_callback
            )

            # Auto-open canvas if tool result suggests one (e.g., platform_create returns canvas_type)
            if result.is_a?(Hash) && result[:canvas_type].present? && @suggested_canvas.nil?
              @suggested_canvas = result[:canvas_type]
              @canvas_data = result[:canvas_data] || {}
              Rails.logger.info "[V3::AgentLoop] Auto-canvas from tool result: #{@suggested_canvas}"

              progress_callback&.call({
                type: :canvas_suggestion,
                canvas: @suggested_canvas,
                data: @canvas_data
              })
            end

            result
          end
        rescue ::Tools::AskUserTool::ExecutionSuspended => e
          raise e # Propagate suspension
        rescue => e
          Rails.logger.error "[V3::AgentLoop] Tool #{tc[:name]} error: #{e.message}"
          { success: false, error: e.message }
        end
      end
    end

    def check_for_loops(tool_calls, tool_results)
      # Track history
      tool_calls.each_with_index do |tc, idx|
        @tool_call_history << {
          name: tc[:name],
          args_hash: Digest::MD5.hexdigest((tc[:arguments] || {}).to_json),
          success: !result_is_error?(tool_results[idx]),
          timestamp: Time.current
        }
      end

      # Check for repeated identical calls
      if @tool_call_history.length >= 4
        recent = @tool_call_history.last(4)
        signatures = recent.map { |h| "#{h[:name]}:#{h[:args_hash]}" }

        if signatures.uniq.length == 1
          return [true, "Same tool called 4 times with identical arguments: #{recent.first[:name]}"]
        end

        # Check for alternating pattern (A, B, A, B)
        if signatures.length >= 4 && signatures[0] == signatures[2] && signatures[1] == signatures[3]
          return [true, "Alternating pattern detected between #{recent[0][:name]} and #{recent[1][:name]}"]
        end
      end

      # Check for too many failures
      recent_failures = @tool_call_history.last(6).count { |h| !h[:success] }
      if recent_failures >= 5
        return [true, "5 of last 6 tool calls failed"]
      end

      [false, nil]
    end

    def result_is_error?(result)
      return true unless result.is_a?(Hash)
      result[:success] == false || result["success"] == false
    end

    MAX_TOOL_RESULT_SIZE = 50_000 # 50KB limit per tool result

    def format_tool_result(result)
      json_str = result.is_a?(Hash) ? result.to_json : result.to_s

      if json_str.length > MAX_TOOL_RESULT_SIZE
        # Try to smartly truncate while preserving structure
        truncated = smart_truncate_result(result, MAX_TOOL_RESULT_SIZE)
        truncated_json = truncated.is_a?(String) ? truncated : truncated.to_json

        # Add truncation notice so model knows data is incomplete
        if truncated_json.length < MAX_TOOL_RESULT_SIZE - 200
          notice = "\n\n[NOTE: Result truncated from #{json_str.length} to #{truncated_json.length} chars. " \
                   "Some data may be missing. Ask user to narrow the query if needed.]"
          truncated_json + notice
        else
          json_str.truncate(MAX_TOOL_RESULT_SIZE) +
            "\n\n[TRUNCATED: Original was #{json_str.length} chars. Data incomplete - do NOT fabricate missing items.]"
        end
      else
        json_str
      end
    end

    def smart_truncate_result(result, max_size)
      return result.to_s.truncate(max_size) unless result.is_a?(Hash)

      # For integration results with data arrays, limit the array size
      if result[:data].is_a?(Array) && result[:data].length > 5
        simplified = result.dup
        original_count = result[:data].length
        simplified[:data] = result[:data].first(10) # Keep first 10 items
        simplified[:_truncated] = true
        simplified[:_original_count] = original_count
        simplified[:_message] = "Showing first 10 of #{original_count} items"

        # Also simplify nested objects if still too large
        json = simplified.to_json
        if json.length > max_size
          simplified[:data] = result[:data].first(5).map { |item| simplify_item(item) }
          simplified[:_message] = "Showing simplified first 5 of #{original_count} items"
        end

        return simplified
      end

      result
    end

    def simplify_item(item)
      return item unless item.is_a?(Hash)

      # For Stripe-like objects, keep essential fields only
      essential_keys = %w[id name email status created description amount currency type object]
      item.select { |k, v| essential_keys.include?(k.to_s) || !v.is_a?(Hash) && !v.is_a?(Array) }
    end

    def build_tool_context
      {
        session_id: @session_id,
        execution_context: "v3_agent_loop",
        canvas_suggestion: @suggested_canvas,
        canvas_data: @canvas_data
      }
    end

    def prepare_messages(history)
      return [] if history.blank?

      # Normalize and merge consecutive messages from the same role
      # Claude's API requires alternating user/assistant roles
      merged = []

      history.each do |msg|
        role = msg[:role] || msg["role"]
        content = msg[:content] || msg["content"]

        # Ensure content is in block format
        if content.is_a?(String)
          content = [{ text: content }]
        elsif content.is_a?(Array) && content.first.is_a?(Hash) && content.first[:text]
          # Already in correct format
        elsif content.is_a?(Array) && content.first.is_a?(Hash) && content.first["text"]
          # Convert string keys to symbols
          content = content.map { |c| { text: c["text"] || c[:text] } }
        end

        # If same role as previous message, merge the content
        if merged.last && merged.last[:role] == role
          # Merge text contents with a newline separator
          existing_text = merged.last[:content].map { |c| c[:text] }.join("\n")
          new_text = content.map { |c| c[:text] }.join("\n")
          merged.last[:content] = [{ text: "#{existing_text}\n#{new_text}" }]
        else
          merged << { role: role, content: content }
        end
      end

      merged
    end

    def build_result(content, note = nil)
      # Use the model's response, only provide a minimal fallback if truly empty
      final_message = content.presence
      
      # Only use fallback if content is nil/empty AND no tools were called
      # (tools might have provided their own response via streaming)
      if final_message.nil? && @tools_called.empty?
        final_message = "I'm ready to help. What would you like to do?"
      end

      {
        final_response: {
          message: final_message || "",
          message_already_saved: false
        },
        tools_used: @tools_called.uniq,
        suggested_canvas: @suggested_canvas,
        canvas_data: @canvas_data,
        model_used: @model,
        version: "v3",
        note: note
      }
    end

    # Extract the original user message from conversation for hallucination detection
    def extract_original_message(messages)
      return "" if messages.blank?
      
      # Find the last user message
      user_msg = messages.reverse.find { |m| m[:role] == "user" }
      return "" unless user_msg
      
      content = user_msg[:content]
      if content.is_a?(Array)
        content.map { |c| c[:text] || c["text"] }.compact.join("\n")
      else
        content.to_s
      end
    end

    # Detect when the model claims to have done something without calling tools
    def detect_action_hallucination(response, original_prompt)
      return false if response.blank?
      
      response_text = response.to_s.downcase
      prompt_text = original_prompt.to_s.downcase
      
      # Check if task needed an action
      task_needed_action = TASK_NEEDS_ACTION_PATTERNS.any? { |p| prompt_text =~ p }
      return false unless task_needed_action
      
      # Check if agent claims to have done it
      agent_claimed_action = ACTION_CLAIM_PATTERNS.any? { |p| response_text =~ p }
      return false unless agent_claimed_action
      
      # Response should be relatively short (not a detailed explanation with data)
      is_short_claim = response_text.length < 2500
      
      # No evidence of tool results in the response
      no_tool_evidence = !response_text.include?('tool_use_id') && 
                         !response_text.include?('"success"') &&
                         !response_text.include?('"result"') &&
                         !response_text.include?('tool result')
      
      if task_needed_action && agent_claimed_action && is_short_claim && no_tool_evidence
        Rails.logger.info "🎭 Hallucination check: task_needed=#{task_needed_action}, " \
                          "claimed=#{agent_claimed_action}, short=#{is_short_claim}, no_evidence=#{no_tool_evidence}"
        return true
      end
      
      false
    end
  end
end
