# frozen_string_literal: true

module V3
  # AgentLoop - The V3 agent loop (Pi-inspired architecture)
  #
  # Trust the model. Simple loop:
  #   1. Build system prompt (identity + skills + context)
  #   2. Send to LLM (tool_choice: auto — model decides when to talk vs use tools)
  #   3. If model outputs text only → stream it, we're done
  #   4. If model calls tools → execute ALL of them, add results, loop back to 2
  #   5. Compact if context too long
  #
  # Key insight from Pi: the model is smarter than our guardrails.
  # No forced tool_choice, no respond_to_user tool, no nudges, no loop detection.
  # The model outputs text when it wants to talk and calls tools when it needs to act.
  #
  class AgentLoop
    include V3::AgentEvents

    MAX_TOOL_TURNS = 25
    MAX_REPEATED_FAILURES = 3
    MAX_TOOL_RESULT_SIZE = 50_000 # 50KB limit per tool result

    attr_reader :user, :entity, :session_id, :model
    attr_accessor :suggested_canvas, :canvas_data

    # Default model for auto mode - fast and cheap
    DEFAULT_AUTO_MODEL = "qwen3-next-80b"

    # Tiered escalation: each model escalates to the next tier
    # Qwen/cheap → Sonnet 4.6 → Opus 4.6 (terminal)
    ESCALATION_MAP = {
      # Default/cheap models escalate to Sonnet 4.6
      "qwen3-next-80b"    => "claude-sonnet-4-6",
      "qwen-3-32b"        => "claude-sonnet-4-6",
      "qwen-coder"        => "claude-sonnet-4-6",
      "deepseek-v3"       => "claude-sonnet-4-6",
      "deepseek-r1"       => "claude-sonnet-4-6",
      "mistral-large-3"   => "claude-sonnet-4-6",
      # Sonnet 4.6 escalates to Opus 4.6
      "claude-sonnet-4-6" => "claude-opus-4-6",
      "claude-sonnet-4-5" => "claude-opus-4-6", # Legacy alias
      "claude-haiku-4-5"  => "claude-sonnet-4-6",
      # Opus 4.6 is terminal — no further escalation
      "claude-opus-4-6"   => nil,
    }.freeze

    # Legacy constant for backward compat
    ESCALATION_MODEL = "claude-sonnet-4-6"

    # Models that are truly top-tier — no further escalation possible
    TOP_TIER_MODELS = %w[
      claude-opus-4-6
    ].freeze

    def initialize(user:, entity:, session_id:, model: nil, client_ip: nil)
      @user = user
      @entity = entity
      @session_id = session_id
      @model = model.presence || ENV.fetch("BEDROCK_DEFAULT_MODEL", DEFAULT_AUTO_MODEL)
      @ai_service = BedrockService.new(user: user, entity: entity)
      @prompt_builder = V3::SystemPromptBuilder.new(user: user, entity: entity, session_id: session_id, client_ip: client_ip)
      @compaction = V3::ConversationCompactionService.new(user: user, entity: entity, model: @model)
      @tools_called = []
      @tool_call_history = []  # Records tool name per call for loop detection
      @tool_turns = []         # Records per-turn tool usage: [{turn: 1, tools: ["platform_create", "platform_create", ...]}]
      @suggested_canvas = nil
      @canvas_data = {}
      @loop_start_time = nil
      @user_message = nil
      @hallucination_guard_count = 0  # Number of times hallucination guard has fired (allows up to 2 nudges)
      @escalated = false
      @original_model = @model

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
        message: message
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
      roles = conversation_messages.map { |m| m[:role] }.join(" -> ")
      Rails.logger.info "[V3::AgentLoop] System prompt: #{system_prompt.length} chars, " \
                        "#{conversation_messages.length} messages, #{tools.length} tools"
      Rails.logger.info "[V3::AgentLoop] Message pattern: #{roles}"

      # 6. Run the agent loop
      @loop_start_time = Time.current
      @user_message = message
      result = run_loop(system_prompt, conversation_messages, tools, progress_callback)

      # 7. Check if we need to escalate to a stronger model
      if should_escalate?(result, message)
        result = escalate_and_retry!(system_prompt, conversation_messages, tools, progress_callback, result)
      end

      # Include the full conversation history so callers (benchmarks, multi-turn sessions)
      # can pass it back for subsequent turns
      result[:conversation_history] = conversation_messages

      result
    end

    private

    # ═══════════════════════════════════════════════════════════════
    # THE LOOP — Pi-inspired: simple, trust the model
    #
    # Each turn:
    #   1. Stream LLM response (text + tool calls)
    #   2. Text content → stream to user immediately
    #   3. If no tool calls → model is done talking, return
    #   4. If tool calls → execute all, add results, next turn
    # ═══════════════════════════════════════════════════════════════
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

        # ── Stream LLM response ──
        tool_calls = []
        current_tool = nil
        tool_input_buffer = ""
        turn_text = ""

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
            # No tool_choice — model decides when to talk vs use tools (Pi pattern)
          ) do |chunk|
            case chunk[:type]
            when :content
              text = chunk[:text] || chunk[:content]
              if text.present?
                turn_text += text
                accumulated_content += text
                # Stream text to user immediately — this IS the model talking
                progress_callback&.call(content_event(text))
              end
            when :tool_use_start
              current_tool = {
                id: chunk[:tool_id],
                name: chunk[:tool_name],
                arguments: {}
              }
              tool_input_buffer = ""
              Rails.logger.info "[V3::AgentLoop] Tool starting: #{chunk[:tool_name]} (#{chunk[:tool_id]})"
            when :tool_use
              if chunk[:tool_use]
                if chunk[:tool_use].respond_to?(:input)
                  tool_input_buffer += chunk[:tool_use].input.to_s
                elsif chunk[:tool_use].is_a?(Hash) && chunk[:tool_use][:input]
                  tool_input_buffer += chunk[:tool_use][:input].to_s
                end
              end
            when :content_block_stop
              if current_tool
                finalize_tool_call(current_tool, tool_input_buffer, tool_calls)
                current_tool = nil
                tool_input_buffer = ""
              end
            when :complete
              if current_tool
                finalize_tool_call(current_tool, tool_input_buffer, tool_calls)
                current_tool = nil
                tool_input_buffer = ""
              end
            end
          end

          # Finalize any pending tool after stream ends
          if current_tool
            finalize_tool_call(current_tool, tool_input_buffer, tool_calls)
          end
        rescue => e
          if e.class.name.include?("ClientDisconnected")
            return build_result(accumulated_content, "Client disconnected")
          else
            Rails.logger.error "[V3::AgentLoop] Streaming error: #{e.message}"
            raise e
          end
        end

        # ── No tool calls = model is done talking ──
        if tool_calls.empty?
          # ── Hallucination check-in (escalating nudges) ──
          # If the user asked for an action and the model responded with text that looks
          # like it completed the action without calling any tools, nudge the model.
          # Fires up to 2 times with increasing severity, on any turn (not just turn 1).
          # For build/create requests: uses a stronger, more explicit nudge.
          if @tools_called.empty? && @hallucination_guard_count < 2 &&
             !conversation_has_tool_results?(conversation_messages) &&
             user_requested_action?(@user_message) && response_claims_completion?(turn_text)
            @hallucination_guard_count += 1
            is_build_request = @user_message.match?(/\b(build|create|make|generate)\b.*\b(app|module|tracker|planner|tool|system|dashboard)\b/i)
            Rails.logger.warn "[V3::AgentLoop] Possible hallucinated action (nudge #{@hallucination_guard_count}) — sending check-in"

            # Add the model's response to conversation, then inject a system check-in
            conversation_messages << { role: "assistant", content: [{ text: turn_text }] }

            nudge_text = if @hallucination_guard_count == 1 && is_build_request
              "[SYSTEM] STOP. You described what you would build but did NOT call any tool. " \
              "Describing what you would create is NOT the same as creating it. " \
              "You MUST call platform_create(type: \"app\", data: { name: \"...\", description: \"...\" }) NOW. " \
              "Do not explain — just call the tool."
            elsif @hallucination_guard_count == 1
              "[SYSTEM] You responded with text but did NOT call any tools. " \
              "The user's message was a direct command: \"#{@user_message.truncate(80)}\". " \
              "Direct commands must be executed immediately with the appropriate tool " \
              "(platform_create, platform_execute, platform_query, or platform_update). " \
              "Do NOT describe what you will do — call the tool NOW."
            else
              "[SYSTEM] FINAL WARNING: You have responded TWICE without calling a tool. " \
              "The user asked for a concrete action. You MUST call a tool in your next response. " \
              "If you cannot perform the action, say so honestly instead of pretending you did it."
            end

            conversation_messages << { role: "user", content: [{ text: nudge_text }] }
            next
          end

          Rails.logger.info "[V3::AgentLoop] Turn #{turn_count}: text only (#{turn_text.length} chars) — done"
          break
        end

        # ── Tool calls: execute all of them (Pi pattern — no 1-tool limit) ──
        Rails.logger.info "[V3::AgentLoop] Turn #{turn_count}: #{tool_calls.length} tool call(s): #{tool_calls.map { |t| t[:name] }.join(', ')}"

        # Add assistant message (text + tool calls) to conversation
        assistant_content = []
        assistant_content << { text: turn_text } if turn_text.present?
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

        # Execute tools (with steering check between each)
        tool_results = execute_tools_with_steering(tool_calls, progress_callback)

        # Track failure counts
        tool_calls.each_with_index do |tc, idx|
          if result_is_error?(tool_results[idx])
            failure_counts[tc[:name]] += 1
            if failure_counts[tc[:name]] >= MAX_REPEATED_FAILURES
              Rails.logger.warn "[V3::AgentLoop] Tool #{tc[:name]} failed #{MAX_REPEATED_FAILURES} times"
            end
          end
        end

        # Add tool results to conversation (MUST immediately follow assistant tool_use)
        tool_result_content = tool_calls.each_with_index.map do |tc, idx|
          {
            tool_result: {
              tool_use_id: tc[:id],
              content: format_tool_result(tool_results[idx])
            }
          }
        end
        conversation_messages << { role: "user", content: tool_result_content }

        # Track tools used (both for result reporting and escalation detection)
        turn_tools = []
        tool_calls.each do |tc|
          @tools_called << tc[:name]
          @tool_call_history << tc[:name]
          turn_tools << tc[:name]
        end
        @tool_turns << { turn: turn_count, tools: turn_tools }

        # ── Research check-in ──
        # Gentle, progressive nudges to keep the model goal-oriented during research.
        # We WANT deep research — better data = better answers. But we also want to
        # prevent aimless cycling. Nudges escalate gradually:
        #   3 turns: gentle reminder to stay goal-oriented
        #   5 turns: firmer nudge to start synthesizing
        #   7+ turns: strong push to deliver
        # Only nudge once per threshold (not every turn after).
        research_tools = %w[web_search read_file search_memory]
        research_turns = @tool_turns.count { |t| (t[:tools] & research_tools).any? }
        nudge = case research_turns
                when 3
                  "[SYSTEM] Check-in: You've done #{research_turns} research calls. If you have enough data to give a solid answer, go ahead and synthesize. If you genuinely need more, keep going — quality matters more than speed."
                when 5
                  "[SYSTEM] You've done #{research_turns} research calls — that's a good amount of data. Start working toward your final answer. You can do one more search if truly needed, but prioritize delivering a thorough response."
                when 7
                  "[SYSTEM] #{research_turns} research calls completed. Time to deliver. Synthesize everything you've gathered into a comprehensive response now."
                end

        if nudge && accumulated_content.length < 200
          conversation_messages << { role: "user", content: [{ text: nudge }] }
          Rails.logger.info "[V3::AgentLoop] Research check-in (turn #{research_turns}): #{research_turns <= 3 ? 'gentle' : research_turns <= 5 ? 'firm' : 'strong'}"
        end

        # Reset text for next turn
        accumulated_content = "" if turn_text.blank?

        # Show progress indicator
        progress_callback&.call(working_event("processing"))
      end

      build_result(accumulated_content)
    end

    # ═══════════════════════════════════════════════════════════════
    # TOOL EXECUTION — with steering message support (Phase 3)
    #
    # Execute tools sequentially. After each tool, check if the user
    # sent a new message (steering). If so, skip remaining tools.
    # ═══════════════════════════════════════════════════════════════
    def execute_tools_with_steering(tool_calls, progress_callback)
      results = []

      tool_calls.each_with_index do |tc, idx|
        # Check for steering message before executing (skip for first tool)
        if idx > 0 && steering_message_pending?
          Rails.logger.info "[V3::AgentLoop] Steering message detected — skipping remaining #{tool_calls.length - idx} tools"
          # Return "skipped" results for remaining tools
          (idx...tool_calls.length).each do
            results << { success: false, error: "Skipped: user sent a new message" }
          end
          break
        end

        # Show working indicator
        progress_callback&.call(working_event(tc[:name]))

        # Execute the tool
        result = execute_single_tool(tc, progress_callback)
        results << result
      end

      results
    end

    def execute_single_tool(tc, progress_callback)
      if tc[:name] == "load_canvas"
        # Handle canvas loading (broadcast to frontend)
        @suggested_canvas = tc[:arguments]["canvas_name"] || tc[:arguments][:canvas_name]
        @canvas_data = tc[:arguments]["canvas_data"] || tc[:arguments][:canvas_data] || {}

        progress_callback&.call(canvas_event(@suggested_canvas, @canvas_data))

        { success: true, message: "Canvas '#{@suggested_canvas}' loaded" }
      else
        # Execute through V3 registry
        result = V3::ToolRegistry.execute(
          tc[:name],
          tc[:arguments],
          user: user,
          entity: entity,
          context: build_tool_context,
          progress_callback: progress_callback
        )

        # Auto-open canvas if tool result suggests one
        if result.is_a?(Hash) && result[:canvas_type].present? && @suggested_canvas.nil?
          @suggested_canvas = result[:canvas_type]
          @canvas_data = result[:canvas_data] || {}
          Rails.logger.info "[V3::AgentLoop] Auto-canvas from tool result: #{@suggested_canvas}"

          progress_callback&.call(canvas_event(@suggested_canvas, @canvas_data))
        end

        result
      end
    rescue ::Tools::AskUserTool::ExecutionSuspended => e
      raise e # Propagate suspension
    rescue => e
      Rails.logger.error "[V3::AgentLoop] Tool #{tc[:name]} error: #{e.class}: #{e.message}\n#{e.backtrace&.first(3)&.join("\n")}"
      V3::AiErrorTransformer.transform(e, tool: tc[:name])
    end

    # ═══════════════════════════════════════════════════════════════
    # STEERING — Check if user sent a new message while we're working
    #
    # Looks for ScoutMessage records created after the loop started.
    # This allows the user to redirect the agent mid-work (Pi pattern).
    # ═══════════════════════════════════════════════════════════════
    def steering_message_pending?
      return false unless @loop_start_time

      # Check for any user message saved after our loop started
      # Uses user_id + entity_id (not session_id, which is a daily unified key)
      ScoutMessage.where(
        user_id: @user.id,
        entity_id: @entity.id,
        role: "user"
      ).where("created_at > ?", @loop_start_time).exists?
    rescue => e
      Rails.logger.debug "[V3::AgentLoop] Steering check failed: #{e.message}"
      false
    end

    # ═══════════════════════════════════════════════════════════════
    # HELPERS
    # ═══════════════════════════════════════════════════════════════

    def finalize_tool_call(current_tool, tool_input_buffer, tool_calls)
      begin
        current_tool[:arguments] = JSON.parse(tool_input_buffer) if tool_input_buffer.present?
      rescue JSON::ParserError
        current_tool[:arguments] = { raw: tool_input_buffer }
      end
      tool_calls << current_tool
      Rails.logger.info "[V3::AgentLoop] Tool complete: #{current_tool[:name]} (#{current_tool[:arguments].keys.join(', ')})"
    end

    def result_is_error?(result)
      return true unless result.is_a?(Hash)
      result[:success] == false || result["success"] == false
    end

    def format_tool_result(result)
      json_str = result.is_a?(Hash) ? result.to_json : result.to_s

      if json_str.length > MAX_TOOL_RESULT_SIZE
        truncated = smart_truncate_result(result, MAX_TOOL_RESULT_SIZE)
        truncated_json = truncated.is_a?(String) ? truncated : truncated.to_json

        if truncated_json.length < MAX_TOOL_RESULT_SIZE - 200
          notice = "\n\n[NOTE: Result truncated from #{json_str.length} to #{truncated_json.length} chars. " \
                   "Some data may be missing. Ask user to narrow the query if needed.]"
          truncated_json + notice
        else
          json_str.truncate(MAX_TOOL_RESULT_SIZE) +
            "\n\n[TRUNCATED: Original was #{json_str.length} chars. Data incomplete.]"
        end
      else
        json_str
      end
    end

    def smart_truncate_result(result, max_size)
      return result.to_s.truncate(max_size) unless result.is_a?(Hash)

      if result[:data].is_a?(Array) && result[:data].length > 5
        simplified = result.dup
        original_count = result[:data].length
        simplified[:data] = result[:data].first(10)
        simplified[:_truncated] = true
        simplified[:_original_count] = original_count
        simplified[:_message] = "Showing first 10 of #{original_count} items"

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
      essential_keys = %w[id name email status created description amount currency type object]
      item.select { |k, v| essential_keys.include?(k.to_s) || !v.is_a?(Hash) && !v.is_a?(Array) }
    end

    # Check if the conversation history already contains tool results (successful tool executions).
    # This prevents the hallucination guard from firing after escalation, where the previous
    # model's successful tool calls are in the conversation history.
    def conversation_has_tool_results?(conversation_messages)
      conversation_messages.any? do |msg|
        next false unless msg[:content].is_a?(Array)
        msg[:content].any? do |block|
          block[:tool_result].present? || block.dig(:tool_result, :content).present?
        end
      end
    end

    # Check if the USER's message is asking for a concrete action (create, edit, update, delete, etc.)
    # Also catches follow-ups where the user says "you didn't do it" or "it's still not there".
    # Pure discussion/question messages should NOT trigger the guard.
    def user_requested_action?(message)
      return false if message.blank?
      msg = message.downcase

      # Direct action verbs that indicate the user wants something DONE
      action_patterns = /\b(create|make|build|add|edit|update|change|modify|delete|remove|send|publish|fix|set up|generate|pull|import|connect|integrate)\b/i

      # Follow-up complaints that imply the action wasn't actually done
      # e.g., "you didn't actually create it", "it's still not in my assets", "i don't see it"
      complaint_patterns = /\b(didn['']t (actually|really)|still not|don['']t see|not (there|showing|in my|visible|working|created)|you didn['']t|not actually|where is it|it['']s not)\b/i

      # Exclude purely conversational patterns
      discussion_patterns = /\b(what do you think|analyze|opinion|explain|tell me about|compare|discuss|how does|can you tell|what is|who is|describe)\b/i

      # Exclude exploratory/brainstorming patterns that use action verbs hypothetically
      # e.g., "what would it take to build X?", "could we create X?", "ideas for building X"
      exploratory_patterns = /\b(what would|could (we|you|i)|ideas for|thoughts on|how would|would it be possible|what if we|talk about|thinking about|interested in)\b/i

      return false if msg.match?(discussion_patterns)
      return false if msg.match?(exploratory_patterns)
      msg.match?(action_patterns) || msg.match?(complaint_patterns)
    end

    # Check if the model's response claims it completed an action without actually calling a tool.
    # Five tiers:
    #   1. Short responses (<500 chars) with completion language (e.g., "Done! I've updated it")
    #   2. ANY length response that narrates executing a tool action (e.g., "Let me pull... Here are your results:")
    #      This catches models that fabricate detailed fake data instead of calling tools.
    #   3. ANY length response that claims to have built/created an app/module with details
    #      (e.g., "Your Weekly Task Tracker module has been created. ✅ 7 columns...")
    #   4. Feature lists with creation-related words
    #   5. Intent-without-action: model says what it WILL do instead of doing it
    #      (e.g., "I'll create a landing page..." without calling platform_create)
    def response_claims_completion?(text)
      return false if text.blank?

      # EXEMPTION: Proposals and offers to build are NOT completion claims.
      # If the model is asking for permission or offering to create something, that's correct
      # behavior (confirming before acting). Don't penalize this.
      proposal_patterns = /\b(want me to|would you like me to|shall i|should i|i can (create|build|make|generate|set up)|i could (create|build|make|generate)|if you['']d like|ready to (build|create|start)|let me know if|would that work)\b/i
      ends_with_question = text.strip.end_with?('?')
      if text.match?(proposal_patterns) && ends_with_question
        Rails.logger.info "[V3::AgentLoop] Hallucination guard: skipping — response is a proposal/offer, not a completion claim"
        return false
      end

      # Tier 0: Intent-without-action — model describes what it WILL do but doesn't call tools.
      # The user gave a direct command, and the model responded with "I'll create..." or
      # "Let me build..." without actually invoking a tool. This is the #1 failure mode.
      intent_patterns = /\b(i['']ll (create|build|make|generate|set up|add|send|delete)|let me (create|build|make|generate|set up|add|send)|i['']m going to (create|build|make)|i will (create|build|make|generate|set up)|here['']s what i['']ll (do|create|build))\b/i
      if text.match?(intent_patterns) && !ends_with_question
        Rails.logger.info "[V3::AgentLoop] Hallucination guard: intent-without-action detected"
        return true
      end

      # Tier 1: Short direct claims (original check)
      if text.length <= 500
        return true if text.match?(/\b(done|completed|updated|created|made the|applied|i['']ve (updated|created|changed|edited|deleted|modified|removed|added|sent|published|fixed))\b/i)
      end

      # Tier 2: Response narrates performing a tool action — at ANY length
      # This catches hallucinated data dumps where the model pretends it called a tool
      # e.g., "Let me execute the integration... Here are your 10 customers: 1. Emma Rivera..."
      narrates_action = text.match?(/\b(let me (execute|pull|retrieve|fetch|run|call|query)|here['']?s? (the|your)|have been (retrieved|pulled|fetched|created|updated))\b/i)
      claims_results = text.match?(/\b(here are|retrieved|results|summary|customers?|contacts?|records?)\b/i) &&
                       text.match?(/\d+\.\s+\*?\*?[A-Z]/)  # Numbered list with capitalized names = fabricated data
      return true if narrates_action && claims_results

      # Tier 3: Claims to have built/created an app or module (at any length)
      # Catches patterns like: "Your Weekly Task Tracker module has been created"
      # "I've created the module" / "module is now live" / "is ready to use"
      claims_creation = text.match?(/\b(has been (created|built|generated|set up)|is now (live|ready|active|available)|module.{0,30}(created|built|ready)|app.{0,30}(created|built|ready)|i['']?m now creating|has now been actually created)\b/i)
      has_feature_list = text.scan(/✅/).length >= 2 || text.match?(/\n-\s+.+\n-\s+/)  # Checklist or bullet list of "features"
      return true if claims_creation

      # Tier 4: Response lists "features" of something that was supposedly created
      # e.g., "✅ Title ✅ Description ✅ Priority" — without any tool call
      # Only trigger if text also uses past-tense completion language (not just mentioning "module" or "app")
      return true if has_feature_list && text.match?(/\b(created|built|ready to use|is live|now active)\b/i)

      false
    end

    def build_tool_context
      {
        session_id: @session_id,
        execution_context: "v3_agent_loop",
        canvas_suggestion: @suggested_canvas,
        canvas_data: @canvas_data,
        user_message: @user_message
      }
    end

    def prepare_messages(history)
      return [] if history.blank?

      merged = []

      history.each do |msg|
        role = msg[:role] || msg["role"]
        content = msg[:content] || msg["content"]

        if content.is_a?(String)
          content = [{ text: content }]
        elsif content.is_a?(Array) && content.first.is_a?(Hash) && content.first[:text]
          # Already in correct format
        elsif content.is_a?(Array) && content.first.is_a?(Hash) && content.first["text"]
          content = content.map { |c| { text: c["text"] || c[:text] } }
        end

        if merged.last && merged.last[:role] == role
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
      final_message = content.presence

      # Only use fallback if content is nil/empty AND no tools were called
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
        note: note,
        escalated: @escalated,
        original_model: @original_model
      }
    end

    # ═══════════════════════════════════════════════════════════════
    # MODEL ESCALATION — Smart routing from cheap to capable models
    #
    # When a Tier 1 model (Haiku/Qwen) produces a low-quality result:
    #   - Empty or near-empty response with no tool calls
    #   - Hallucination guard fired (claimed action without tools)
    #   - Repeated tool failures (same tool failing 3+ times)
    #   - Tool loop detected (same tool called 5+ times in a row)
    #
    # Tiered escalation: Qwen → Sonnet 4.5 → Opus 4.6 (terminal)
    # We clear the bad output, escalate to the next tier, and re-run.
    #
    # Key constraints:
    #   - Only escalate once per request (no escalation chains)
    #   - Opus models are terminal — no further escalation
    #   - User-selected models still escalate on hallucination (safety net)
    #   - Other user-selected model failures are respected (no escalation)
    # ═══════════════════════════════════════════════════════════════

    def should_escalate?(result, message)
      # Already escalated this request — no double escalation
      return false if @escalated

      # Model was explicitly chosen by user — respect their choice (unless hallucinating)
      # Exception: even user-selected models escalate on hallucination_guard
      reason = detect_escalation_reason(result, message)
      return false unless reason

      if user_selected_model? && reason != "hallucination_guard"
        return false
      end

      # Check if there's an escalation target for this model
      escalation_target = get_escalation_target(@model)
      return false unless escalation_target

      Rails.logger.info "[V3::AgentLoop] Escalation triggered: #{reason} (#{@model} → #{escalation_target})"
      true
    end

    def detect_escalation_reason(result, message)
      response_text = result.dig(:final_response, :message) || ""
      tools_used = result[:tools_used] || []

      # Pattern 1: Empty/near-empty response — model returned nothing useful
      if response_text.length < 20 && tools_used.empty?
        return "empty_response"
      end

      # Pattern 2: Generic fallback response — model didn't engage
      if response_text.include?("I'm ready to help") && tools_used.empty? && message.length > 20
        return "generic_fallback"
      end

      # Pattern 3: Hallucination guard fired — model claimed action without tools
      if @hallucination_guard_count > 0
        return "hallucination_guard"
      end

      # Pattern 4: Tool loop — same tool called across MULTIPLE turns
      # Important: calling platform_create 10x in ONE turn is a batch operation (good).
      # Calling the same tool across 4+ separate turns suggests the model is stuck in a loop.
      if @tool_turns.length >= 4
        # Count how many distinct turns each tool appears in
        tool_turn_counts = Hash.new(0)
        @tool_turns.each do |turn_info|
          turn_info[:tools].uniq.each { |tool| tool_turn_counts[tool] += 1 }
        end
        if tool_turn_counts.any? { |_tool, turn_count| turn_count >= 4 }
          looping_tool = tool_turn_counts.max_by { |_, c| c }.first
          return "tool_loop:#{looping_tool}"
        end
      end

      # Pattern 5: User asked for complex work but model gave short non-tool response
      if complex_request?(message) && tools_used.empty? && response_text.length < 200
        return "complex_request_no_tools"
      end

      nil
    end

    def escalate_and_retry!(system_prompt, conversation_messages, tools, progress_callback, failed_result)
      @escalated = true
      escalation_model = get_escalation_target(@model) || ESCALATION_MODEL
      failed_response = failed_result.dig(:final_response, :message) || ""
      reason = detect_escalation_reason(failed_result, @user_message)

      Rails.logger.warn "[V3::AgentLoop] ⬆ Escalating from #{@model} to #{escalation_model} (reason: #{reason})"

      # Clear any content the failed model streamed
      progress_callback&.call(clear_content_event)

      # Brief notification to the user
      progress_callback&.call(content_event(""))

      # Switch model
      old_model = @model
      @model = escalation_model

      # Reset state for the retry
      @tools_called = []
      @tool_call_history = []
      @tool_turns = []
      @hallucination_guard_count = 0
      @suggested_canvas = nil
      @canvas_data = {}

      # Strip the failed assistant response from conversation if it was added
      # We want the escalated model to see the original user message cleanly
      strip_failed_response!(conversation_messages, failed_response)

      # Run the loop again with the stronger model
      result = run_loop(system_prompt, conversation_messages, tools, progress_callback)

      # Log the escalation for tracking
      log_escalation(old_model, escalation_model, reason)

      result
    end

    def strip_failed_response!(conversation_messages, failed_response)
      # Remove trailing assistant messages that were part of the failed attempt
      # Keep the conversation history up to and including the user's message
      while conversation_messages.last && conversation_messages.last[:role] == "assistant"
        conversation_messages.pop
      end

      # Also remove any system correction messages we injected (hallucination nudges)
      while conversation_messages.last &&
            conversation_messages.last[:role] == "user" &&
            conversation_messages.last[:content]&.any? { |c| c[:text]&.include?("[SYSTEM]") }
        conversation_messages.pop
        # Remove the assistant message before the system correction too
        conversation_messages.pop if conversation_messages.last&.dig(:role) == "assistant"
      end
    end

    def user_selected_model?
      # If the model differs from the auto-default, user explicitly picked it
      @original_model != DEFAULT_AUTO_MODEL &&
        @original_model != ENV.fetch("BEDROCK_DEFAULT_MODEL", DEFAULT_AUTO_MODEL)
    end

    def high_capability_model?(model_name)
      TOP_TIER_MODELS.any? { |m| model_name.include?(m) }
    end

    # Get the next escalation target for a given model
    # Returns nil if no escalation is possible (top-tier model)
    def get_escalation_target(model_name)
      # Direct lookup first
      target = ESCALATION_MAP[model_name]
      return target if ESCALATION_MAP.key?(model_name)

      # Fuzzy match (handles variants like "claude-sonnet-4.5" vs "claude-sonnet-4-5")
      normalized = model_name.to_s.gsub('.', '-')
      target = ESCALATION_MAP[normalized]
      return target if ESCALATION_MAP.key?(normalized)

      # Check if any key is a substring match
      ESCALATION_MAP.each do |key, value|
        return value if model_name.include?(key) || key.include?(model_name)
      end

      # Unknown model — default escalation to Sonnet 4.5 (unless already Sonnet+)
      if model_name.include?("sonnet")
        "claude-opus-4-6"
      elsif model_name.include?("opus")
        nil  # Opus is terminal
      else
        ESCALATION_MODEL  # Default: escalate to Sonnet 4.6
      end
    end

    def complex_request?(message)
      return false if message.blank?
      msg = message.downcase

      # Requests that typically need stronger reasoning
      complex_patterns = /\b(build|create.*app|design|architect|analyze|summarize|explain.*pdf|review.*document|multi.?step|integrate|migrate|refactor|plan)\b/i
      msg.match?(complex_patterns)
    end

    def log_escalation(from_model, to_model, reason)
      Rails.logger.info "[V3::AgentLoop] ESCALATION: #{from_model} -> #{to_model} | reason: #{reason} | user: #{@user.id} | entity: #{@entity.id}"

      # Store escalation in user memory for pattern tracking
      UserMemory.create(
        user: @user,
        entity: @entity,
        memory_type: "pattern",
        category: "product",
        source: "observation",
        content: "Model escalated: #{from_model} -> #{to_model} | reason: #{reason} | session: #{@session_id} | #{Time.current.iso8601}",
        confidence: 1.0
      )
    rescue => e
      # Non-critical — just log and move on
      Rails.logger.warn "[V3::AgentLoop] Failed to persist escalation record: #{e.message}"
    end
  end
end
