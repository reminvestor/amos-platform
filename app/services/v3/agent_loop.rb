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

    attr_reader :user, :entity, :session_id, :model
    attr_accessor :suggested_canvas, :canvas_data

    def initialize(user:, entity:, session_id:, model: nil, intent_mode: nil)
      @user = user
      @entity = entity
      @session_id = session_id
      @model = model || ENV.fetch("BEDROCK_DEFAULT_MODEL", "anthropic.claude-sonnet-4-v1")
      @intent_mode = intent_mode
      @ai_service = BedrockService.new(user: user, entity: entity)
      @prompt_builder = V3::SystemPromptBuilder.new(user: user, entity: entity, session_id: session_id)
      @compaction = V3::ConversationCompactionService.new(user: user, entity: entity, model: @model)
      @tools_called = []
      @tool_call_history = []
      @suggested_canvas = nil
      @canvas_data = {}
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

      # 4. Add current user message
      conversation_messages << {
        role: "user",
        content: [{ text: message }]
      }

      # 5. Get V3 tools
      tools = V3::ToolRegistry.get_bedrock_tools(entity: entity)

      Rails.logger.info "[V3::AgentLoop] System prompt: #{system_prompt.length} chars, " \
                        "#{conversation_messages.length} messages, #{tools.length} tools"

      # 6. Run the agent loop
      run_loop(system_prompt, conversation_messages, tools, progress_callback)
    end

    private

    def run_loop(system_prompt, conversation_messages, tools, progress_callback)
      accumulated_content = ""
      turn_count = 0
      failure_counts = Hash.new(0)

      loop do
        turn_count += 1
        if turn_count > MAX_TOOL_TURNS
          Rails.logger.warn "[V3::AgentLoop] Max turns (#{MAX_TOOL_TURNS}) exceeded"
          break
        end

        # Call the LLM
        tool_calls = []
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
              accumulated_content += chunk[:text] if chunk[:text]
              progress_callback&.call(chunk)
            when :tool_use
              tool_calls << {
                id: chunk[:tool_use_id],
                name: chunk[:name],
                arguments: chunk[:input] || {}
              }
            end
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

        # If no tool calls, we're done
        if tool_calls.empty?
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

        # Check for loops
        loop_detected, loop_reason = check_for_loops(tool_calls, tool_results)
        if loop_detected
          Rails.logger.warn "[V3::AgentLoop] Loop detected: #{loop_reason}"
          # Add a message telling the model about the loop
          conversation_messages << {
            role: "user",
            content: [{ text: "[SYSTEM] Loop detected: #{loop_reason}. Please try a different approach or ask the user for more information." }]
          }
          # Continue but with reduced patience
          if turn_count > MAX_TOOL_TURNS / 2
            break
          end
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

        # Add tool results to conversation
        tool_result_content = tool_calls.each_with_index.map do |tc, idx|
          {
            tool_result: {
              tool_use_id: tc[:id],
              content: format_tool_result(tool_results[idx])
            }
          }
        end
        conversation_messages << { role: "user", content: tool_result_content }

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
            # Execute through V3 registry
            V3::ToolRegistry.execute(
              tc[:name],
              tc[:arguments],
              user: user,
              entity: entity,
              context: build_tool_context,
              progress_callback: progress_callback
            )
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

    def format_tool_result(result)
      if result.is_a?(Hash)
        result.to_json.truncate(15_000) # Keep tool results under 15KB
      else
        result.to_s.truncate(15_000)
      end
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

      # Normalize message format for Bedrock
      history.map do |msg|
        role = msg[:role] || msg["role"]
        content = msg[:content] || msg["content"]

        # Ensure content is in block format
        if content.is_a?(String)
          content = [{ text: content }]
        end

        { role: role, content: content }
      end
    end

    def build_result(content, note = nil)
      {
        final_response: {
          message: content.presence || "Done.",
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
  end
end
