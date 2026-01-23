# This is the MAIN Scout service that handles all LLM interactions with tools
# 
# IMPORTANT: This is the PRIMARY prompt being used in unified mode
# The prompt is built in the build_system_prompt method below
# 
# Flow: Orchestrator → SimpleQueryHandler → ScoutToolsService → THIS SERVICE
class ScoutGenericToolsServiceV2
  attr_reader :user, :entity, :session_id, :agent_loadout, :model, :fresh_start_at
  attr_accessor :suggested_canvas, :canvas_data, :intent_mode

  def initialize(user, entity, session_id, agent_loadout: nil, model: nil, fresh_start_at: nil, intent_mode: nil)
    @user = user
    @entity = entity
    @session_id = session_id
    @agent_loadout = agent_loadout
    @model = model # Model to use (defaults to ENV['BEDROCK_DEFAULT_MODEL'] or 'claude-sonnet-4-5')
    @fresh_start_at = fresh_start_at # Filter memory to only after this time
    @ai_service = BedrockService.new(user: user, entity: entity)
    @ai_provider_name = Rails.application.config.ai_service.to_s.capitalize
    @tool_catalog = Tools::ToolCatalog.instance
    @suggested_canvas = nil
    @canvas_data = {}
    @saved_message_content = Set.new
    @messages_saved_during_streaming = false
    @context = {}
    @sources = [] # Track sources from tool responses
    @model_used = nil # Track actual model used (may differ from requested due to fallback)
    @model_name = nil # Human-readable model name
    @canvas_already_broadcast = false # Track if canvas was broadcast during tool execution
    @hallucination_retry_attempted = false # Track if we've already retried for hallucinated tool use
    @intent_mode = intent_mode # Intent mode for role adaptation: :personal, :ideate, :operate, :create
    
    # AMOS Orchestrator integration for platform awareness
    @amos_integration = Amos::ScoutIntegration.new(entity: entity, user: user) rescue nil
  end
  
  # Set the intent mode for role adaptation
  # @param mode [Symbol] :personal, :ideate, :operate, :create
  def set_intent_mode(mode)
    @intent_mode = mode&.to_sym
  end

  def set_context(context = {})
    @context = @context.merge(context)
  end

  # Set model selection mode (:auto, :quick, :standard, :deep, :maximum)
  # Legacy modes (fast, balanced, powerful) are mapped to new thinking depths
  def set_model_mode(mode)
    @model_mode = mode
    
    # Map legacy modes to new thinking depth system
    depth = case mode.to_sym
            when :fast, :quick then :light
            when :balanced, :standard then :medium
            when :powerful, :maximum then :deep
            else mode.to_sym
            end
    
    set_thinking_depth(depth)
  end

  # Set thinking depth directly (:auto, :light, :medium, :deep)
  def set_thinking_depth(depth)
    @thinking_depth_mode = depth
  end

  # Get current thinking depth configuration
  def thinking_depth_config
    @thinking_depth_config ||= begin
      service = ThinkingDepthService.new
      # Use the last user message for auto-detection
      message = @last_user_message || ""
      service.determine_depth(message: message, user_mode: @thinking_depth_mode || :auto)
    end
  end

  # Clear cached thinking depth config (call when message changes)
  def reset_thinking_depth
    @thinking_depth_config = nil
  end

  # Preprocess message for model selection and canvas routing
  # Runs in parallel for minimal latency impact
  def preprocess_message(user_message, current_canvas = nil, conversation_history = nil)
    # Use the new UnifiedPreprocessorService for comprehensive parallel preprocessing
    # This pre-loads: canvas, tools, agents, integrations, modules in parallel
    preprocessor = UnifiedPreprocessorService.new(
      entity: @entity,
      user: @user,
      current_canvas: current_canvas,
      session_id: @session_id,
      conversation_history: conversation_history
    )

    result = preprocessor.preprocess(message: user_message)

    # Update model if auto-selected
    if @model.nil? || @model_mode == :auto
      @model = result[:suggested_model]
      Rails.logger.info "[Scout] Unified preprocessor: model=#{result[:suggested_model]}, " \
                        "intent=#{result[:classification_method]}, " \
                        "tools=#{result[:tools]&.length || 0}, " \
                        "agents=#{result[:suggested_agents]&.length || 0}, " \
                        "latency=#{result[:latency_ms]}ms"
    end

    # Store preprocessing result for context injection AND tool selection
    @preprocess_result = result
    
    # Pre-warm suggested agents for faster delegation
    @prewarmed_agents = result[:suggested_agents]
    
    # Pre-load integration context for prompt enhancement
    @prewarmed_integrations = result[:integration_context]
    
    result
  end

  # Truncate large tool results to prevent context overflow
  # Max characters for a single tool result (roughly 4 chars per token, aiming for ~8000 tokens max per result)
  MAX_TOOL_RESULT_CHARS = 32000
  
  def truncate_tool_result(result)
    json_str = result.to_json
    
    if json_str.length <= MAX_TOOL_RESULT_CHARS
      return json_str
    end
    
    Rails.logger.warn "⚠️ Truncating large tool result: #{json_str.length} chars → #{MAX_TOOL_RESULT_CHARS} chars"
    
    # Try to preserve structure by truncating intelligently
    if result.is_a?(Hash)
      # For hash results, try to truncate nested arrays/data
      truncated = truncate_hash_result(result)
      truncated_json = truncated.to_json
      if truncated_json.length <= MAX_TOOL_RESULT_CHARS
        return truncated_json
      end
    elsif result.is_a?(Array)
      # For array results, take fewer items
      truncated = result.first(10)
      truncated_json = truncated.to_json
      if truncated_json.length <= MAX_TOOL_RESULT_CHARS
        return truncated_json + "\n[... #{result.length - 10} more items truncated for context limit]"
      end
    end
    
    # Fallback: hard truncate with message
    json_str.first(MAX_TOOL_RESULT_CHARS - 100) + "\n\n[... TRUNCATED - result too large for context window. Total size: #{json_str.length} chars]"
  end
  
  def truncate_hash_result(hash, max_depth: 2, current_depth: 0)
    return "[nested data]" if current_depth > max_depth
    
    hash.transform_values do |value|
      case value
      when Array
        if value.length > 10
          value.first(10) + ["... #{value.length - 10} more items"]
        else
          value.map { |v| v.is_a?(Hash) ? truncate_hash_result(v, max_depth: max_depth, current_depth: current_depth + 1) : v }
        end
      when Hash
        truncate_hash_result(value, max_depth: max_depth, current_depth: current_depth + 1)
      when String
        value.length > 2000 ? value.first(2000) + "... [truncated]" : value
      else
        value
      end
    end
  end

  # Parse JSON from tool arguments with repair for common LLM errors
  # Handles missing quotes, trailing commas, corrupted dates, etc.
  def parse_tool_arguments(args_string)
    return {} if args_string.blank?
    return args_string if args_string.is_a?(Hash)
    
    # First try standard parse
    JSON.parse(args_string)
  rescue JSON::ParserError => e
    Rails.logger.warn "⚠️ JSON parse failed, attempting repair: #{e.message}"
    
    # Try to repair common LLM JSON errors
    repaired = repair_json(args_string)
    
    begin
      JSON.parse(repaired)
    rescue JSON::ParserError => repair_error
      Rails.logger.error "❌ JSON repair failed: #{repair_error.message}"
      Rails.logger.error "   Original: #{args_string.to_s.truncate(500)}"
      Rails.logger.error "   Repaired: #{repaired.to_s.truncate(500)}"
      
      # Last resort: try to extract the most essential data
      # For create_freeform_canvas, we really just need title and data
      if args_string.include?('create_freeform_canvas') || args_string.include?('"title"')
        extracted = attempt_partial_extraction(args_string)
        return extracted if extracted.present?
      end
      
      # Return empty hash rather than crashing - let tool handle the error
      Rails.logger.warn "⚠️ Returning empty hash due to unrepairable JSON"
      {}
    end
  end
  
  # Attempt to extract partial data from corrupted JSON
  def attempt_partial_extraction(json_string)
    result = {}
    
    # Try to extract title
    if json_string =~ /"title"\s*:\s*"([^"]+)"/
      result["title"] = $1
    end
    
    # Try to extract html_content if present
    if json_string =~ /"html_content"\s*:\s*"((?:[^"\\]|\\.)*)"/m
      result["html_content"] = $1.gsub('\\"', '"').gsub('\\n', "\n")
    end
    
    # If we got at least a title, return what we have
    if result["title"].present?
      Rails.logger.info "🔧 Partial extraction succeeded: title=#{result['title']}"
      result["data"] ||= {}
      return result
    end
    
    nil
  end
  
  # Repair common JSON errors from LLMs
  def repair_json(json_string)
    repaired = json_string.dup
    
    # Fix corrupted date strings like "2026-0-- "1:38:00" or "2026-,012T08":05:00"
    # These have colons escaping quotes and corrupted date formats
    # First, fix colons that escaped their quotes: "08":05:00 → "08:05:00"
    repaired.gsub!(/(\d)":(\d{2}):(\d{2})/, '\1:\2:\3')
    repaired.gsub!(/(\d)":(\d{2})"/, '\1:\2"')
    
    # Fix dates with spaces in them: "2026-0 -01-2T" → "2026-01-12T"
    # This is aggressive but dates shouldn't have spaces
    repaired.gsub!(/(\d{4})-(\d)\s*-(\d{2})-?(\d)T/) do
      "#{$1}-#{$2}#{$3[0]}-#{$3[1]}#{$4}T"
    end
    
    # Fix dates with commas instead of dashes: "2026-,012" → "2026-01-12"
    repaired.gsub!(/(\d{4})-,(\d{3})T/) do
      year = $1
      rest = $2  # e.g., "012"
      month = rest[0..1]  # "01"
      day = rest[2]       # "2" - but this is often truncated, assume 12
      "#{year}-#{month}-12T"
    end
    
    # Fix dates like "2026-0-- " at the start
    repaired.gsub!(/"(\d{4})-(\d)--\s*"/, '"\\1-0\\2-12T')
    
    # Fix missing quotes before keys: {key: "value"} → {"key": "value"}
    # Pattern: { or , followed by whitespace and unquoted word and :
    repaired.gsub!(/([{,])\s*([a-zA-Z_][a-zA-Z0-9_]*)\s*:/) do
      "#{$1}\"#{$2}\":"
    end
    
    # Fix trailing commas before closing braces: {a: 1,} → {a: 1}
    repaired.gsub!(/,\s*([}\]])/, '\1')
    
    # Fix single quotes to double quotes (but be careful with apostrophes)
    # Only convert if it looks like a JSON string: 'value' → "value"
    repaired.gsub!(/:\s*'([^']*)'/, ':"\\1"')
    
    # Fix broken string concatenation: "text1" "text2" → "text1 text2"
    repaired.gsub!(/"\s+"/, ' ')
    
    # Fix spaces before colons in dates that broke out: T08 :30:00 → T08:30:00
    repaired.gsub!(/T(\d{2})\s*:(\d{2})\s*:(\d{2})/, 'T\1:\2:\3')
    
    # Remove any trailing garbage after the JSON object
    if repaired.include?('{')
      # Find matching closing brace
      brace_count = 0
      end_pos = nil
      repaired.each_char.with_index do |char, idx|
        if char == '{'
          brace_count += 1
        elsif char == '}'
          brace_count -= 1
          if brace_count == 0
            end_pos = idx
            break
          end
        end
      end
      repaired = repaired[0..end_pos] if end_pos
    end
    
    Rails.logger.info "🔧 JSON repaired" if repaired != json_string
    repaired
  end

  def process_message_with_tools_streaming(user_message, progress_callback, conversation_history = [], current_canvas = nil)
    @stop_after_delegation = false # Reset flag at start
    @canvas_already_broadcast = false # Reset canvas broadcast flag
    @original_user_message = user_message # Store for intent detection (e.g., edit vs display)
    @conversation_history = conversation_history # Store for context-aware routing
    @current_canvas = current_canvas # Store for context-aware tool injection
    begin
      # PHASE 1: Parallel preprocessing (model selection + canvas routing)
      # This runs in ~20-50ms and doesn't block the main flow
      # CRITICAL: Store as instance variable so tool selection can access preloaded tools
      @preprocess_result = preprocess_message(user_message, current_canvas, conversation_history)
      
      # Handle auto canvas loading (before Amos even starts)
      if @preprocess_result[:canvas] && @preprocess_result[:canvas] != :keep_current && !@preprocess_result[:canvas_delegate]
        # Broadcast canvas load immediately - user sees it before Amos responds
        broadcast_auto_canvas(@preprocess_result[:canvas], progress_callback)
      end

      # Build system prompt (now lighter - canvas logic offloaded)
      system_prompt = build_system_prompt(current_canvas)

      # Inject preprocessor context (very compact, ~20-50 tokens)
      if @preprocess_result[:context_inject].present?
        system_prompt = inject_canvas_context(system_prompt, @preprocess_result[:context_inject])
      end

      # Enhance user message with context
      enhanced_message = enhance_message_with_canvas_context(user_message, current_canvas)

      # Format conversation
      conversation_messages = format_conversation_for_ai(conversation_history, enhanced_message)

      Rails.logger.info "Sending #{conversation_messages.length} messages to #{@ai_provider_name}"
      progress_callback&.call("🤖 Processing request...")

      # TOOL & MODEL SELECTION: Use preloaded data from UnifiedPreprocessor
      # The preprocessor already ran parallel threads to discover relevant tools/agents
      
      # Model was pre-selected by UnifiedPreprocessor (but can be overridden)
      @model = @preprocess_result[:suggested_model] || 'qwen3-next-80b'
      
      # DeepSeek R1 is for reasoning only - no tools
      if @model == 'deepseek-r1'
        tools = []
        Rails.logger.info "🧠 Using DeepSeek R1 for reasoning (no tools)"
      else
        # Use pre-discovered tools from UnifiedPreprocessor (parallel RAG search)
        # Lower threshold to 5 tools to prefer the focused toolset
        if @preprocess_result[:tools].present? && @preprocess_result[:tools].length >= 5
          # Preprocessor found enough relevant tools - use them
          tools = build_tools_from_preloaded(@preprocess_result[:tools])
          tool_names = tools.map { |t| t[:name] || t["name"] }
          has_integration_tools = tool_names.include?("execute_integration")
          Rails.logger.info "⚡ Using #{tools.length} preloaded tools (integration tools: #{has_integration_tools}): #{tool_names.first(8).join(', ')}..."
        else
          # Fallback to traditional discovery (handles edge cases)
          tools = get_filtered_tools(prompt: user_message)
          tool_names = tools.map { |t| t[:name] || t["name"] }
          has_integration_tools = tool_names.include?("execute_integration")
          Rails.logger.info "🔧 Fallback: #{tools.length} tools (integration tools: #{has_integration_tools}): #{tool_names.first(8).join(', ')}..."
        end
      end

      # Stream the response
      accumulated_content = ""
      tool_calls = []
      streaming_started = false
      client_disconnected = false
      @repetition_loop_detected = false  # Reset loop detection flag

      begin
      # Store user message for thinking depth auto-detection
      @last_user_message = user_message
      reset_thinking_depth
      
      # Get thinking depth configuration (auto-detects based on message complexity)
      depth_config = thinking_depth_config
      Rails.logger.info "[Scout] Thinking depth: #{depth_config[:depth]} (#{depth_config[:reasoning]})"
      
      # Apply thinking depth to system prompt (adds /think, /no_think, or chain-of-thought)
      thinking_service = ThinkingDepthService.new
      modified_system_prompt = thinking_service.apply_to_prompt(system_prompt, depth_config[:depth])
      
      @ai_service.send_message_streaming(
        modified_system_prompt,
        conversation_messages,
        model: @model,
        max_tokens: depth_config[:max_tokens],
        temperature: depth_config[:temperature],
        json_mode: false,
        tools: tools,
        enable_prompt_caching: true
      ) do |chunk|
          result = handle_streaming_chunk(chunk, accumulated_content, tool_calls, streaming_started, progress_callback)
        streaming_started = true if chunk[:type] == :content
          
          # If repetition loop detected, break out of streaming
          if result == :stop_streaming || @repetition_loop_detected
            Rails.logger.warn "🛑 Stopping stream due to repetition loop"
            break
          end
        end
      rescue Scout::Streaming::ClientDisconnectedError => e
        # Client disconnected - stop streaming gracefully
        Rails.logger.info "🔌 Streaming stopped early: client disconnected"
        client_disconnected = true
        # Continue with any tool calls that were already detected
      end

      # If client disconnected, stop processing and return early
      if client_disconnected
        Rails.logger.info "🔌 Client disconnected - skipping further processing"
        return {
          final_response: {
            message: accumulated_content.presence || "Processing interrupted",
            message_already_saved: @messages_saved_during_streaming
          },
          tools_used: tool_calls.map { |tc| tc[:name] },
          client_disconnected: true
        }
      end

      # Execute any tool calls
      # NOTE: Qwen 3 32B handles tools natively (100% success rate)
      # No handoff logic needed anymore!
      if tool_calls.any?
        tool_results = execute_tool_calls(tool_calls, progress_callback)

        # Add the assistant's response with tool calls to conversation
        conversation_messages << {
          role: "assistant",
          content: [
            { type: "text", text: accumulated_content.strip.presence || "I'll help you with that." },
            *tool_calls.map do |tool_call|
              # Parse arguments - handle string, hash, or empty (with JSON repair)
              input = parse_tool_arguments(tool_call[:arguments])

              {
                type: "tool_use",
                tool_use: {
                  id: tool_call[:id],
                  name: tool_call[:name],
                  input: input
                }
              }
            end
          ].compact
        }

        # Get final response after tools
        final_response = get_continuation_after_tools(
          system_prompt,
          conversation_messages,
          tool_calls,
          tool_results,
          progress_callback
        )

        # If delegation occurred, return appropriate response with the delegation message
        if @stop_after_delegation
          # Use the delegation message if we have one, otherwise use accumulated content
          delegation_response = @delegation_message || accumulated_content
          # CRITICAL: Clean any internal markers that may have leaked through
          clean_delegation_response = clean_internal_markers(delegation_response)
          
          response = {
            final_response: {
              message: clean_delegation_response,
              message_already_saved: @messages_saved_during_streaming,
              delegation_occurred: true
            },
            tools_used: tool_calls.map { |tc| tc[:name] },
            sources: @sources,
            model_used: @model_used,
            model_name: @model_name,
            delegation_occurred: true
          }
          
          # Only include canvas info if a canvas was suggested
          if @suggested_canvas
            response[:canvas_type] = @suggested_canvas
            response[:canvas_data] = @canvas_data
          else
            response[:canvas_type] = "conversation"
          end
          
          response
        else
        final_response
        end
      else
        # No tools used, return the accumulated content
        # CRITICAL: Clean any internal markers that may have leaked through
        clean_response = clean_internal_markers(accumulated_content)
        
        # HALLUCINATED TOOL USE DETECTION:
        # Some models (especially Qwen) say "let me read/call/use X" without actually calling tools
        # Detect this pattern and retry with a stronger prompt
        if detect_hallucinated_tool_use(clean_response) && !@hallucination_retry_attempted
          @hallucination_retry_attempted = true
          Rails.logger.warn "🎭 HALLUCINATED TOOL USE DETECTED: Model said it would use tools but didn't"
          Rails.logger.warn "🎭 Response: #{clean_response.truncate(200)}"
          
          # Add a correction message and retry
          retry_messages = conversation_messages + [
            { role: "assistant", content: [{ type: "text", text: clean_response }] },
            { role: "user", content: [{ type: "text", text: "You said you would read the document or use a tool, but you didn't actually call any tools. Please ACTUALLY use the read_document tool now to read the document, don't just describe what you'll do. Call the tool." }] }
          ]
          
          # Retry with the correction
          return process_message_with_tools_streaming(
            system_prompt,
            retry_messages,
            tools,
            progress_callback
          )
        end
        
        response = {
          final_response: {
            message: clean_response,
            message_already_saved: @messages_saved_during_streaming,
            delegation_occurred: @stop_after_delegation || false
          },
          tools_used: [],
          sources: @sources,
          model_used: @model_used,
          model_name: @model_name,
          delegation_occurred: @stop_after_delegation || false
        }
        
        # Only include canvas info if a canvas was suggested
        if @suggested_canvas
          response[:canvas_type] = @suggested_canvas
          response[:canvas_data] = @canvas_data
        else
          response[:canvas_type] = "conversation"
        end
        
        response
      end
    rescue => e
      Rails.logger.error "ScoutGenericToolsServiceV2 error: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")

      {
        final_response: {
          message: "I encountered an error: #{e.message}",
          error: true
        },
        canvas_type: "conversation",
        tools_used: []
      }
    end
  end

  def execute_tool_by_name(tool_name, args, progress_callback = nil)
    Rails.logger.info "🔧 Executing tool: #{tool_name}"

    # Check if tool is allowed by agent loadout
    if @agent_loadout && !@agent_loadout.tool_allowed?(tool_name)
      Rails.logger.warn "Tool #{tool_name} not allowed by agent loadout"
      return { success: false, error: "Tool not permitted for current context" }
    end

    # Special handling for canvas loading
    if tool_name == "load_canvas"
      return execute_load_canvas(args, progress_callback)
    end

    # Create context that will be shared with the tool
    # IMPORTANT: Memory tools need session_id to access Redis storage
    tool_context = {
      session_id: @session_id,
      canvas_suggestion: nil,
      canvas_data: {},
      **@context  # Include any additional context (like task_session)
    }

    # Execute through tool catalog
    result = @tool_catalog.execute_tool(
      tool_name,
      args,
      user: @user,
      entity: @entity,
      context: tool_context,
      progress_callback: progress_callback
    )

    # Handle any canvas suggestions from tools
    if tool_context[:canvas_suggestion]
      safe_load_canvas(tool_context[:canvas_suggestion], tool_context[:canvas_data] || {})
      
      # Broadcast canvas update immediately for all canvas types
      if progress_callback && @suggested_canvas
        progress_callback.call({
          type: "canvas_update",
          canvas_type: @suggested_canvas,
          canvas_data: @canvas_data
        })
        # Mark that we've already broadcast this canvas
        @canvas_already_broadcast = true
      end
    end

    result
  end

  private
  
  # ═══════════════════════════════════════════════════════════════
  # 🤝 DEEPSEEK-MISTRAL HANDOFF HELPERS
  # ═══════════════════════════════════════════════════════════════
  
  # Strip HTML tags from text, keeping meaningful content
  # Used when Amos incorrectly outputs HTML directly instead of using create_freeform_canvas
  def strip_html_to_text(html_content)
    return "" if html_content.blank?
    
    # First, add newlines for block elements
    text = html_content.gsub(/<(div|p|h[1-6]|li|br)[^>]*>/i, "\n")
    
    # Remove all HTML tags
    text = text.gsub(/<[^>]+>/, '')
    
    # Clean up excessive whitespace
    text = text.gsub(/\n{3,}/, "\n\n")
    text = text.gsub(/\s{2,}/, ' ')
    
    # Decode basic HTML entities
    text = text.gsub('&nbsp;', ' ')
    text = text.gsub('&amp;', '&')
    text = text.gsub('&lt;', '<')
    text = text.gsub('&gt;', '>')
    text = text.gsub('&quot;', '"')
    
    text.strip
  end

  # Clean internal coordination markers from conversation history
  # These markers should NEVER be seen by models as they cause confusion/repetition/garbled output
  def clean_internal_markers(content)
    return "" if content.blank?
    
    cleaned = content.dup
    
    # Remove handoff markers - full and partial versions
    cleaned.gsub!(/\[HANDOFF_TO_MISTRAL:[^\]]*\]?/i, '')  # Full marker
    cleaned.gsub!(/\[?HANDOFF_TO_MISTRAL:[^\]]*\]?/i, '') # Partial (missing opening bracket)
    cleaned.gsub!(/_MISTRAL:[^\]]*\]?/i, '')              # Very partial (just _MISTRAL:...)
    cleaned.gsub!(/HANDOFF_TO_MISTRAL/i, '')              # Just the marker name
    
    # Remove "Switching to tool mode" artifacts
    cleaned.gsub!(/🔧\s*Switching to tool mode\.{0,3}/i, '')
    
    # Remove fake tool calls from DeepSeek/Qwen
    cleaned.gsub!(/\[Called\s+\w+\s+with\s+\{[^}]*\}\]/m, '')
    cleaned.gsub!(/<function=\w+>[^<]*<\/function>/m, '')
    cleaned.gsub!(/<function=\w+>/m, '')
    
    # Remove action descriptions that got partially streamed (with or without closing bracket)
    cleaned.gsub!(/Let me (?:pull up|fetch|read|get) the .*? to (?:provide|access|analyze)[^\]]*\]?/i, '')
    
    # Fix repetition patterns like "the kind of* of* the kind of*" 
    # This happens when models get confused by handoff content
    cleaned.gsub!(/(\*\s*of\*\s*)+/i, '')
    cleaned.gsub!(/(\w+\s*\*\s*){3,}/i, '') # Remove word* word* word* patterns
    
    # Remove corrupted unicode (replacement characters and broken emoji sequences)
    cleaned.gsub!(/[\u{FFFD}]+/, '') # Unicode replacement character
    cleaned.gsub!(/(?:[\u{FE00}-\u{FE0F}]){3,}/, '') # Excessive variation selectors
    
    # Clean up multiple consecutive newlines/spaces
    cleaned.gsub!(/\n{3,}/, "\n\n")
    cleaned.gsub!(/\s{3,}/, " ")
    
    # Remove leading/trailing whitespace
    cleaned.strip
  end
  
  # Detect when model "hallucinates" tool usage - says it will use a tool but doesn't
  # This is common with some models (especially Qwen) that narrate actions instead of executing them
  # Pattern: "Let me read/call/fetch..." or "First, let me..." but tool_calls is empty
  def detect_hallucinated_tool_use(response)
    return false if response.blank?
    return false if response.length > 2000 # Long responses are likely complete
    
    # Patterns that indicate the model intended to use a tool
    tool_intent_patterns = [
      /first,?\s+let\s+me\s+(read|fetch|get|load|check|pull|search|query|look up)/i,
      /let\s+me\s+(read|fetch|get|load|check|pull|search|query|look up)\s+(the|your|this)/i,
      /i('ll|'m going to| will)\s+(now\s+)?(read|fetch|get|load|check|pull|search|query|access|analyze)/i,
      /i need to\s+(first\s+)?(read|fetch|get|load|check|pull|search|query|access)/i,
      /reading (the|your)\s+(document|file|data)/i,
      /i('ll|'m going to| will) now (synthesize|analyze|process)/i,
      /first, (i'll|let me|i need to)/i
    ]
    
    # Check if response ends abruptly (no real conclusion)
    abrupt_endings = [
      /\.\.\.\s*$/,  # Ends with ...
      /:\s*$/,       # Ends with :
      /plan\.?\s*$/i, # Ends with "plan"
      /strategy\.?\s*$/i, # Ends with "strategy"
      /document:\s*$/i, # Ends with "document:"
    ]
    
    has_tool_intent = tool_intent_patterns.any? { |pattern| response =~ pattern }
    has_abrupt_ending = abrupt_endings.any? { |pattern| response =~ pattern }
    is_short = response.length < 500
    
    # Hallucination detected if:
    # 1. Model said it would use a tool, AND
    # 2. Response is short OR ends abruptly
    has_tool_intent && (is_short || has_abrupt_ending)
  end
  
  # NOTE: Handoff logic removed - Qwen 3 32B handles tools natively!
  # Benchmarked: 100% tool success, 376ms avg (fastest)
  # No need for DeepSeek → Qwen handoff anymore.
  
  # MULTI-MODEL PIPELINE: Detect if we should switch to DeepSeek for visualization
  # This happens when:
  # 1. execute_integration returned data successfully
  # 2. The user's original request mentioned "canvas", "display", "show", "visualization"
  # 3. We have data to display (not just a status message)
  # 4. User is NOT trying to EDIT/MODIFY something (those actions need the main model)
  def should_switch_to_visualization_model?(tool_calls, tool_results)
    return false unless tool_calls.any? && tool_results.any?
    
    user_message = @original_user_message&.downcase || ""
    
    # CRITICAL: Don't switch to visualization if user intent is to EDIT/MODIFY
    edit_intent_patterns = [
      /\b(edit|update|change|modify|remove|delete|add|fix|replace|correct)\b/,
      /\b(can you|please|could you).*(edit|update|change|modify|remove|delete|add|fix)/,
      /\bremove\s+(them|it|this|these|the)\b/,
      /\bget rid of\b/,
      /\bdon't have\b/,
    ]
    
    if edit_intent_patterns.any? { |pattern| user_message.match?(pattern) }
      Rails.logger.info "🎨 Skipping visualization mode - user intent is to EDIT, not display"
      return false
    end
    
    # CRITICAL: Don't switch to visualization for simple "show me X" requests
    # These should just load the appropriate canvas, not create custom visualizations
    # Visualization mode is ONLY for explicit chart/graph/comparison requests
    simple_show_patterns = [
      /\b(show|view|see|list|display)\s+(me\s+)?(my\s+)?(the\s+)?(landing\s*pages?|contacts?|campaigns?|emails?|templates?|documents?)/i,
      /\bwhat\s+(are\s+)?(my|the)\s+(landing\s*pages?|contacts?|campaigns?)/i,
      /\bhow\s+many\s+(landing\s*pages?|contacts?|campaigns?)/i,
    ]
    
    if simple_show_patterns.any? { |pattern| user_message.match?(pattern) }
      Rails.logger.info "🎨 Skipping visualization mode - simple show request, use canvas instead"
      return false
    end
    
    # Only trigger visualization for EXPLICIT visualization requests
    visualization_patterns = [
      /\b(chart|graph|visuali[sz]e|plot|dashboard|compare|comparison|trend|analytics)\b/i,
      /\b(pie\s*chart|bar\s*chart|line\s*chart|histogram)\b/i,
      /\b(show\s+me\s+a\s+)(chart|graph|visualization)\b/i,
    ]
    
    unless visualization_patterns.any? { |pattern| user_message.match?(pattern) }
      Rails.logger.info "🎨 Skipping visualization mode - no explicit visualization request"
      return false
    end
    
    # Check if any tool was a data-fetching tool that returned data
    tool_calls.each_with_index do |tool_call, idx|
      tool_name = tool_call[:name]
      result = tool_results[idx]
      
      # Data fetching tools that would benefit from visualization
      data_tools = %w[execute_integration get_data query_document_content]
      next unless data_tools.include?(tool_name)
      
      # Check if the result has data (not just a status message)
      if result.is_a?(Hash)
        has_data = result[:data].present? || 
                   result[:records].present? || 
                   result[:customers].present? ||
                   result[:results].present? ||
                   (result[:success] && result.keys.any? { |k| result[k].is_a?(Array) && result[k].length > 0 })
        
        return true if has_data
      end
    end
    
    false
  end
  
  # Build a specialized prompt for DeepSeek to generate visualization
  # Key principle: Use Bootstrap classes, minimal CSS, embed data directly
  def build_visualization_only_prompt(base_prompt, tool_results)
    # Extract the actual data from tool results
    data_summary = tool_results.map { |r| r.is_a?(Hash) ? r.to_json : r.to_s }.join("\n")
    
    <<~PROMPT
      Generate Bootstrap HTML with ACTUAL DATA VALUES embedded. NO template syntax!
      
      DATA:
      #{data_summary}
      
      STRUCTURE (if showing a list):
      1. Title
      2. Summary box with key insights (count, date range, notable items) - use alert-info
      3. Cards or table with each item's real values
      
      RESPOND WITH ONLY THIS JSON:
      ```json
      {
        "title": "Title",
        "html": "<div class='container py-4'><h2>Title</h2><div class='alert alert-info mb-4'><strong>Summary:</strong> X items from [date range]. Key insight here.</div><div class='card mb-2'><div class='card-body'><h5>Real Name</h5><p class='text-muted'>real@email.com</p></div></div>...more cards...</div>"
      }
      ```
      
      ⚠️ Write REAL values from the data - not {{name}} or placeholders!
      
      Bootstrap: container, card, card-body, alert, alert-info, table, table-striped, text-muted
    PROMPT
  end
  
  # Convert tool_use and tool_result blocks to plain text for models that don't support tools
  # This is needed because Bedrock throws "toolConfig field must be defined" if we have tool blocks but no toolConfig
  def convert_tool_blocks_to_text(conversation_messages, tool_results)
    conversation_messages.map do |msg|
      next msg unless msg[:content].is_a?(Array)
      
      # Check if this message has tool blocks
      has_tool_blocks = msg[:content].any? { |c| c[:type] == 'tool_use' || c[:type] == 'tool_result' }
      next msg unless has_tool_blocks
      
      # Convert tool blocks to text
      new_content = msg[:content].map do |content_block|
        case content_block[:type]
        when 'text'
          content_block
        when 'tool_use'
          tool_use = content_block[:tool_use]
          {
            type: 'text',
            text: "[Called #{tool_use[:name]} with #{tool_use[:input].to_json.truncate(500)}]"
          }
        when 'tool_result'
          tool_result = content_block[:tool_result]
          result_text = tool_result[:content]&.first&.dig(:text) || 'No result'
          {
            type: 'text',
            text: "[Tool result: #{result_text.truncate(2000)}]"
          }
        else
          content_block
        end
      end
      
      msg.merge(content: new_content)
    end
  end
  
  # Handle DeepSeek's JSON output for visualization and load the freeform canvas
  def handle_visualization_json_output(raw_output, progress_callback)
    viz_data = parse_visualization_json(raw_output)
    
    return { success: false } unless viz_data
    
    # Execute the create_freeform_canvas tool with the generated content
    canvas_args = {
      title: viz_data['title'] || 'Data Visualization',
      html: viz_data['html'] || '<div>No content generated</div>',
      css: viz_data['css'] || '',
      javascript: viz_data['javascript'] || '',
      data: viz_data['data'] || {}
    }
    
    result = execute_tool_by_name('create_freeform_canvas', canvas_args, progress_callback)
    
    if result[:success]
      progress_callback&.call({
        type: "canvas_update",
        canvas_type: @suggested_canvas || 'freeform_canvas',
        canvas_data: @canvas_data
      })
      
      return {
        success: true,
        response: {
          final_response: {
            message: "Here's your data visualization! 📊",
            message_already_saved: false
          },
          tools_used: ['execute_integration', 'create_freeform_canvas'],
          sources: @sources,
          model_used: @model_used,
          model_name: @model_name,
          canvas_type: @suggested_canvas || 'freeform_canvas',
          canvas_data: @canvas_data
        }
      }
    else
      Rails.logger.warn "🎨 create_freeform_canvas failed: #{result[:error]}"
      { success: false }
    end
  end
  
  # Parse visualization JSON with robust error handling
  def parse_visualization_json(raw_output)
    # Extract JSON from markdown code blocks
    json_content = raw_output.gsub(/```json\s*/i, '').gsub(/```\s*/m, '').strip
    
    # Try direct parse first
    begin
      return JSON.parse(json_content)
    rescue JSON::ParserError
      # Continue to fallback extraction
    end
    
    # Fallback: Extract fields individually using regex
    # This handles cases where the "data" field contains malformed JSON
    Rails.logger.info "🎨 Falling back to regex extraction for visualization JSON"
    
    title = extract_json_string(json_content, 'title') || 'Data Visualization'
    html = extract_json_string(json_content, 'html')
    css = extract_json_string(json_content, 'css') || ''
    javascript = extract_json_string(json_content, 'javascript') || ''
    
    if html.present?
      Rails.logger.info "🎨 Regex extraction successful - title: #{title.truncate(50)}"
      { 'title' => title, 'html' => html, 'css' => css, 'javascript' => javascript, 'data' => {} }
    else
      Rails.logger.warn "🎨 Could not extract visualization content from DeepSeek output"
      nil
    end
  end
  
  # Extract a string value from JSON using regex (handles escaped quotes)
  def extract_json_string(json_content, key)
    # Match "key": "value" where value can contain escaped quotes
    # Use non-greedy match and look for the closing pattern
    pattern = /"#{key}"\s*:\s*"((?:[^"\\]|\\.)*)"/m
    
    match = json_content.match(pattern)
    return nil unless match
    
    # Unescape the string
    value = match[1]
    value.gsub('\\n', "\n").gsub('\\"', '"').gsub('\\\\', '\\')
  end

  # Smart routing to detect if tools are needed
  # Returns: { needs_tools: bool, tool_categories: [], suggested_model: string, reasoning: string }
  def smart_route_request(message, conversation_history: nil)
    router = SmartRequestRouter.new(entity: @entity, user: @user)
    
    # Pass recent conversation context to help with follow-up detection
    context = {}
    if conversation_history.present?
      # Get last 3 messages for context
      recent = conversation_history.last(3)
      context[:recent_messages] = recent.map do |msg|
        {
          role: msg[:role] || msg['role'],
          content: (msg[:content] || msg['content']).to_s.truncate(500)
        }
      end
    end
    
    result = router.analyze(message: message, context: context)
    
    Rails.logger.info "[SmartRouter] #{result[:needs_tools] ? '🔧' : '⚡'} needs_tools=#{result[:needs_tools]}, method=#{result[:detection_method]}, latency=#{result[:latency_ms]}ms"
    
    result
  rescue => e
    Rails.logger.error "[SmartRouter] Error: #{e.message}, defaulting to tools"
    { needs_tools: true, tool_categories: [:general], suggested_model: nil, reasoning: 'Router error' }
  end

  # Get selective tools based on detected categories
  def get_selective_tools(categories, message)
    router = SmartRequestRouter.new(entity: @entity, user: @user)
    tool_names = router.tools_for_categories(categories)
    
    # Get all available tools then filter to just the ones we need
    all_tools = get_filtered_tools(prompt: message)
    
    # Keep tools that match the category OR are in ESSENTIAL_TOOLS
    # CRITICAL: Always include core interaction tools + canvas/navigation tools
    # Without these, Amos can only talk - he can't actually DO things
    selected = all_tools.select do |tool|
      name = tool[:name] || tool["name"]
      tool_names.include?(name) || ESSENTIAL_TOOLS.include?(name)
    end
    
    # Safety: If selective filtering is too aggressive, fall back to full tools
    # This prevents Amos from being stuck with only 2 tools
    if selected.length < 10
      Rails.logger.warn "⚠️ Selective tools too restrictive (#{selected.length}), using full set"
      return all_tools
    end
    
    selected
  end

  # ═══════════════════════════════════════════════════════════════
  # ESSENTIAL TOOLS - The absolute minimum Amos needs (~12 tools)
  # These are ALWAYS sent, regardless of intent or preprocessing.
  # Everything else is discovered dynamically based on the message.
  # ═══════════════════════════════════════════════════════════════
  ESSENTIAL_TOOLS = %w[
    ask_user
    get_data
    get_schema
    load_canvas
    web_search
    view_web_page
    delegate_to_agent
    list_available_agents
    create_object
    update_object
    discover_tools
  ].freeze

  # Build tools from preloaded tool names (from UnifiedPreprocessor)
  # This converts tool names back to full Bedrock-compatible tool definitions
  def build_tools_from_preloaded(tool_names)
    catalog = Tools::ToolCatalog.instance
    
    # Check for dynamically discovered tools from previous turn
    session_discovered = get_session_discovered_tools
    
    # Merge: ESSENTIAL + preloaded + session-discovered (deduped)
    all_names = (ESSENTIAL_TOOLS + (tool_names || []) + session_discovered).uniq
    
    Rails.logger.info "🔧 Tool merge: #{ESSENTIAL_TOOLS.length} essential + #{tool_names&.length || 0} preloaded + #{session_discovered.length} session = #{all_names.length} unique"
    
    tools = []
    
    all_names.each do |tool_name|
      # Special handling for load_canvas (needs dynamic canvas enum)
      if tool_name == "load_canvas"
        canvas_enum = catalog.send(:build_canvas_enum, @entity)
        tools << {
          name: "load_canvas",
          description: "Load a specific canvas view in the Scout interface. For custom modules, use the exact format shown in the enum.",
          parameters: {
            type: "object",
            properties: {
              canvas_name: {
                type: "string",
                description: "The name of the canvas to load. For module canvases, use the exact slug from the enum (e.g., 'module_social_media_calendar_list').",
                enum: canvas_enum
              },
              canvas_data: {
                type: "object",
                description: "Optional data to pass to the canvas (e.g., campaign_id, landing_page_id)",
                properties: {},
                additionalProperties: true
              }
            },
            required: ["canvas_name"]
          }
        }
        next
      end
      
      # get_tool_definition returns the full tool definition hash
      tool_def = catalog.get_tool_definition(tool_name)
      next unless tool_def
      
      tools << {
        name: tool_def[:name],
        description: tool_def[:description],
        parameters: tool_def[:parameters] || tool_def[:input_schema]
      }
    end
    
    # IMPORTANT: Filter out EXCLUDED_TOOLS (specialist tools Amos should delegate)
    # This is a security boundary - these tools should ONLY be used by agents
    excluded_tools = ScoutLoadoutConfiguration::EXCLUDED_TOOLS
    tools = tools.reject { |t| excluded_tools.include?(t[:name]) }
    
    # Safety: Ensure we have minimum tools
    if tools.length < 10
      Rails.logger.warn "⚠️ Preloaded tools insufficient (#{tools.length}), falling back to discovery"
      return get_filtered_tools(prompt: nil)
    end
    
    # Cap total tools to prevent prompt bloat
    max_tools = TieredDiscoveryService::MAX_TOTAL_TOOLS
    if tools.length > max_tools
      Rails.logger.info "🔧 Preloaded tool cap: #{tools.length} → #{max_tools}"
      tools = tools.first(max_tools)
    end
    
    # Personal space filtering - hide business tools unless explicitly needed
    tools = apply_space_tool_filtering(tools)
    
    tools
  end
  
  # Get tools that were discovered dynamically in a previous turn
  # These are cached by discover_tools tool and should be included in subsequent calls
  def get_session_discovered_tools
    return [] unless @session_id.present?
    
    cache_key = "discovered_tools:#{@session_id}"
    tools = Rails.cache.read(cache_key) || []
    
    if tools.any?
      Rails.logger.info "🔍 Found #{tools.length} session-discovered tools: #{tools.first(5).join(', ')}"
    end
    
    tools
  end
  
  # Filter tools based on current space
  # Uses SpaceDefinition.default_tool_loadout to determine allowed tools per space
  def apply_space_tool_filtering(tools)
    return tools unless @user.present?
    
    active_space = @user.active_space
    # Normalize old space slugs
    active_space = 'operations' if active_space == 'work' || active_space == 'team'
    return tools if active_space.blank?
    
    # Get space-specific tool loadout
    space_def = SpaceDefinition.find_by(slug: active_space)
    return tools unless space_def&.tool_loadout.present?
    
    allowed_tools = space_def.tool_loadout.dup
    
    # ═══════════════════════════════════════════════════════════════
    # CONTEXT-AWARE TOOL INJECTION
    # When user is in specific editor contexts, ALWAYS include relevant tools
    # This prevents the model from hallucinating without the right tools
    # ═══════════════════════════════════════════════════════════════
    if @current_canvas.present?
      canvas_type = @current_canvas[:type] || @current_canvas['type']
      
      case canvas_type
      when 'landing_page_editor'
        # ALWAYS include landing page tools when editing a landing page
        landing_page_tools = %w[
          update_landing_page_content
          edit_landing_page_section
          read_landing_page_sections
        ]
        allowed_tools = (allowed_tools + landing_page_tools).uniq
        Rails.logger.info "📄 Landing page editor context: injected #{landing_page_tools.join(', ')}"
      when 'app_designer', 'module_manager'
        # Include app/module building tools
        app_tools = %w[
          start_module_design
          propose_module_schema
          refine_module_schema
          approve_module_design
          build_app
          preview_app
        ]
        allowed_tools = (allowed_tools + app_tools).uniq
      when 'workflow_designer'
        # Include workflow tools
        workflow_tools = %w[
          generate_automation_code
          create_scheduled_task
          list_scheduled_tasks
        ]
        allowed_tools = (allowed_tools + workflow_tools).uniq
      end
    end
    
    before_count = tools.length
    
    tools = tools.select do |tool|
      name = tool[:name] || tool["name"]
      allowed_tools.include?(name)
    end
    
    if tools.length < before_count
      Rails.logger.info "🏠 #{active_space.titleize} space: filtered to #{tools.length}/#{before_count} tools"
    end
    
    tools
  end

  def get_filtered_tools(prompt: nil)
    # ═══════════════════════════════════════════════════════════════
    # SCOUT TOOL ACCESS - TIERED SYSTEM:
    # TIER 1: CORE_TOOLS (~13 tools) - Scout's native abilities, always available
    # TIER 2: CONFIGURABLE_TOOLS - User-enabled extensions
    # TIER 3: EXCLUDED_TOOLS - Always delegate to agents
    # ═══════════════════════════════════════════════════════════════
    
    # Get or create Scout's configuration from DB
    scout_config = nil
    if @entity.present?
      scout_config = ScoutLoadoutConfiguration.for_entity(@entity)
    end

    # Get effective tool allowlist (CORE + user-configured)
    if scout_config.present?
      effective_allowlist = scout_config.effective_tool_allowlist
      
      # Create/update the agent loadout with Scout's specific tools
      # IMPORTANT: Pass agent_role and entity during initialization so apply_role_defaults runs
      # This ensures canvas_allowlist gets set from ScoutLoadoutConfiguration
      @agent_loadout ||= AgentLoadout.new(agent_role: "main_chat", entity: @entity)
      @agent_loadout.tool_allowlist = effective_allowlist
      
      # Log tool summary (single line)
      stats = scout_config.tool_stats
      tiered = scout_config&.use_tiered_discovery ? "+discovery" : ""
      Rails.logger.info "🤖 Scout: #{stats[:total_enabled]} tools (#{stats[:core_count]} core, #{stats[:configured_count]} configured#{tiered})"
    end

    # Get tools from catalog
    tools = @tool_catalog.get_bedrock_tools(
      agent_loadout: @agent_loadout,
      enable_caching: true,
      user: @user,
      entity: @entity,
      prompt: prompt
    )

    # NOTE: Dynamic tools (from tool_definitions) are now INCLUDED for Scout
    # This allows users to create custom tools (like get_current_weather) that Scout can use
    # Previously these were excluded, but that prevented Scout from using user-created tools

    # Final exclusion list - tools that should NEVER be available to Scout
    # These are handled by EXCLUDED_TOOLS in ScoutLoadoutConfiguration
    # but we double-check here for safety
    excluded_tools = ScoutLoadoutConfiguration::EXCLUDED_TOOLS

    filtered = tools.reject { |tool| excluded_tools.include?(tool["name"] || tool[:name]) }
    
    # Apply space filtering FIRST (before cap) to prioritize space-relevant tools
    # This ensures tools like update_landing_page_content make it through in design space
    filtered = apply_space_tool_filtering(filtered)
    
    # CAP TOTAL TOOLS to prevent prompt bloat (fallback protection)
    # Target: ~25 tools = ~6,000 tokens for tool definitions
    max_tools = TieredDiscoveryService::MAX_TOTAL_TOOLS
    if filtered.length > max_tools
      Rails.logger.info "🔧 Fallback tool cap: #{filtered.length} → #{max_tools}"
      filtered = filtered.first(max_tools)
    end
    
    filtered
  end

  def format_current_canvas_for_prompt(canvas)
    return "" unless canvas.present?
    
    # Convert to hash if needed
    if canvas.respond_to?(:to_unsafe_h)
      canvas = canvas.to_unsafe_h
    elsif canvas.respond_to?(:to_h) && !canvas.is_a?(Hash)
      canvas = canvas.to_h
    end
    
    return "" unless canvas.is_a?(Hash)
    
    canvas_type = canvas["type"] || canvas[:type]
    canvas_data = canvas["data"] || canvas[:data] || {}
    
    # Log canvas details for debugging
    if canvas_type == "landing_page_editor"
      Rails.logger.info "🎯 Scout Canvas Context - Type: #{canvas_type}"
      Rails.logger.info "🎯 Scout Canvas Data: #{canvas_data.inspect}"
    end
    
    # Format based on canvas type
    case canvas_type
    when "document_viewer"
      asset_id = canvas_data["asset_id"] || canvas_data[:asset_id]
      filename = canvas_data["filename"] || canvas_data[:filename]
      "CURRENT VIEW: Document '#{filename}' (ID: #{asset_id})"
    when "document_search_results"
      query = canvas_data["query"] || canvas_data[:query]
      "CURRENT VIEW: Document search results for '#{query}'"
    when "landing_page_editor"
      page_id = canvas_data["landing_page_id"] || canvas_data[:landing_page_id]
      Rails.logger.info "🎯 Scout Landing Page Editor ID: #{page_id}"
      "CURRENT VIEW: Landing page editor (ID: #{page_id})"
    when "campaign_viewer", "email_campaign_viewer"
      "CURRENT VIEW: Email campaigns list"
    when "contact_viewer"
      "CURRENT VIEW: Contacts list"
    when "analytics_dashboard"
      "CURRENT VIEW: Analytics dashboard"
    when "parallel_tasks"
      "CURRENT VIEW: Task monitor"
    else
      "CURRENT VIEW: #{canvas_type&.humanize || 'Unknown'}"
    end
  end

  def build_system_prompt(current_canvas = nil)
    # Use AmosIdentity core identity as the foundation
    # Pass the intent mode for seamless role adaptation (if set)
    space_definition = @user&.active_space_definition
    ai_identity = AmosIdentity.build_system_prompt(
      user: @user,
      mode: @intent_mode,  # Mode from intent analysis: :personal, :ideate, :operate, :create
      space_definition: space_definition
    )

    # Current date/time in user's timezone (default to Pacific)
    current_time = Time.current.in_time_zone('America/Los_Angeles')
    current_datetime = current_time.strftime("%A, %B %d, %Y at %I:%M %p %Z")

    available_models = ScoutDataRegistry.available_object_types
    
    # Load business context
    business_context = format_business_context_for_prompt

    # Load additional context
    user_memories = format_user_memories_for_prompt
    scout_personality = format_scout_personality_for_prompt
    scout_learnings = format_scout_learnings_for_prompt
    conversation_summaries = format_conversation_summaries_for_prompt
    ai_rulesets = format_ai_rulesets_for_prompt

    prompt = <<~PROMPT
      #{ai_identity}

      📅 CURRENT DATE/TIME: #{current_datetime}
      
      #{scout_personality}
      
      #{business_context}
      
      #{user_memories}
      
      #{scout_learnings}
      
      #{conversation_summaries}
      
      #{format_current_canvas_for_prompt(current_canvas)}

      #{ai_rulesets}

      ═══════════════════════════════════════════════════════════════
      🎯 SCOUT IDENTITY - WHO YOU ARE
      ═══════════════════════════════════════════════════════════════
      
      You are the ORCHESTRATOR - the team lead, not the solo operator.
      You have a team of specialist agents. Use them!
      
      YOUR ROLE:
      • SHOW data (queries, canvases, visualizations)
      • ROUTE to specialists (creative work, integrations, complex builds)
      • REMEMBER context (memory, preferences, past conversations)
      • COORDINATE team work (check on delegated tasks, relay questions)
      
      THE TEAM DOES THE HEAVY LIFTING. You orchestrate.
      
      #{format_team_roster_for_prompt}
      
      🧠 TEAM-FIRST MINDSET:
      • For SPECIALIST domains (integrations, creative content) → Delegate
      • Integration agents KNOW their APIs intimately - use them!
      • Module agents KNOW their data schemas - use them!
      • You DON'T need to know everything - your team does
      
      🎯 COMMUNICATION STYLE:
      • Be concise and action-focused
      • Don't narrate what you're doing - just DO it
      • Found documents? SHOW them immediately
      • Focus on the CURRENT request
      • Get straight to the answer
      • When referencing canvases/visualizations, say "as displayed" (NOT "above" - the canvas is beside the chat, not above it)
      
      🛑 AGENCY BOUNDARIES (CRITICAL):
      • SUGGEST actions, let user CONFIRM before executing multi-step workflows
      • For SIMPLE requests (show data, answer question): just do it
      • For COMPLEX operations (syncing, creating multiple records, bulk updates):
        - Explain what you COULD do
        - Ask "Would you like me to proceed?" or offer numbered options
        - Wait for explicit confirmation before executing
      • Over time, as you learn the user's patterns, you may take more initiative
      • When in doubt: SUGGEST first, act second
      
      🔍 VERIFY BEFORE ASSERTING (Core Principle):
      Never assume. Assumptions lead nowhere good.
      • Before stating something as fact, verify it with your context or tools
      • "I don't see any connections" → Check the CONNECTED INTEGRATIONS section first
      • "There are no campaigns" → Use get_data to verify
      • If your context already has the answer, use it. If not, check.
      • When uncertain, say "Let me check..." and actually check
      This applies to EVERYTHING - integrations, data, status, capabilities.
      
      📚 LEARN BEFORE ACT (Core Principle):
      Don't be impulsive. Thoughtfulness beats speed.
      
      🔌 INTEGRATION TOOL SYNTAX (CRITICAL):
      The execute_integration tool has SPECIFIC field names. Use EXACTLY this syntax:
      
        execute_integration(
          integration: "stripe",     # ← REQUIRED: lowercase slug (NOT integration_slug, NOT integration_id)
          operation: "list_customers", # ← REQUIRED: operation name from list_operations
          params: { limit: 10 }      # ← Optional: operation-specific parameters
        )
      
      ⚠️ WRITE OPERATIONS REQUIRE CONSULTATION:
      For CREATE, UPDATE, DELETE operations on integrations:
      1. ALWAYS check if there's a specialist agent first: find_best_agent(task_description: "...")
      2. If a specialist exists, DELEGATE to them - they know the API quirks
      3. Only proceed directly for READ operations (list, get, query) if you're confident
      
      📖 If you don't know the exact parameters:
      • Call list_operations(integration_slug: "stripe") to see available operations
      • Each integration has unique query patterns:
        - QuickBooks: SQL-like (SELECT * FROM Invoice WHERE Balance > '0')
        - Stripe: cursor pagination (limit, starting_after, created[gte])
        - Shopify: GraphQL for complex queries
      
      🤝 The specialist agents have deep knowledge:
      • QuickBooks Agent → Knows QB Query Language, entity relationships
      • Stripe Agent → Knows Stripe's pagination, webhook handling
      • Integration Architect → Can diagnose any integration issue
      
      Rule of thumb: If a tool fails once, READ THE ERROR MESSAGE LITERALLY.
      "Missing required fields: integration" means add a field named "integration".
      
      📊 DATA ACCURACY:
      • When displaying data, use EXACTLY what you fetched
      • Do NOT mix data from different sources
      • If you fetched Stripe customers, display Stripe customers (not CRM contacts)
      • If uncertain about data source, clarify with user
      
      🚨 DON'T FABRICATE DATA 🚨
      NEVER make up data. If you don't know, say so.
      "I don't have that information" is always better than inventing something.
      Use tools to fetch real data.
      
      🔄 FRESH START AWARENESS:
      When user does a "Fresh Start", their mental state has reset.
      Past context = REFERENCE MATERIAL only, not active requests.

      ═══════════════════════════════════════════════════════════════
      🏠 INTERNAL vs EXTERNAL DATA - CRITICAL DISTINCTION
      ═══════════════════════════════════════════════════════════════
      
      The platform has TWO types of data. Know the difference!
      
      🏠 INTERNAL PLATFORM DATA (CRM & App-Built):
      These live IN the platform. Use platform tools directly:
      ┌─────────────────────────────────────────────────────────────┐
      │ Data Type          │ Tools to Use                          │
      ├─────────────────────────────────────────────────────────────┤
      │ Contacts           │ get_schema("contact") + create_object │
      │ Contact Groups     │ get_schema + create_object            │
      │ Campaigns          │ get_schema + create_object            │
      │ Email Templates    │ get_schema + create_object            │
      │ Landing Pages      │ delegate to landing_page_manager      │
      │ Documents          │ read_document, query_document_content │
      │ App-Built Models*  │ get_schema + create_object            │
      └─────────────────────────────────────────────────────────────┘
      
      *App-Built Models: Users can create NEW data types via Platform Factory
      (e.g., "Projects", "Inventory", "Tickets"). These become platform objects
      accessible via get_schema/create_object just like native CRM data.
      Check AVAILABLE DATA MODELS below for the full list!
      
      🔌 EXTERNAL INTEGRATION DATA (QuickBooks, Stripe, etc.):
      These live in EXTERNAL systems. Use integration tools:
      • list_integrations - See what's connected
      • list_operations - See available API operations
      • execute_integration - Call the external API
      
      ⚠️ NEVER use execute_integration for internal CRM data!
      ⚠️ NEVER use create_object for external integration data!
      
      EXAMPLES:
      • "Create a contact named John" → get_schema("contact") → create_object
      • "Show my Stripe customers" → execute_integration(stripe, list_customers)
      • "Add a new project" → get_schema("project") → create_object (if Project module exists)
      • "Get QuickBooks invoices" → execute_integration(quickbooks, list_invoices)

      ═══════════════════════════════════════════════════════════════
      👁️ YOUR NATIVE ABILITIES
      ═══════════════════════════════════════════════════════════════
      
      DATA OPERATIONS (for internal platform data):
      • get_schema - ALWAYS call first to see required fields
      • create_object - Create new records (contacts, campaigns, app-built models)
      • update_object - Modify existing records
      • get_data - Query/list records
      
      DISPLAY DATA:
      • Platform data (contacts, campaigns, etc.) → Canvas auto-loads, just respond naturally
      • External data (Stripe, APIs, custom) → create_freeform_canvas with Bootstrap HTML
      
      ⚡ CREATE ≠ DISPLAY:
      • "Create a contact" → create_object (create record, no canvas)
      • "Show Stripe customers" → fetch data, then create_freeform_canvas
      
      SEARCH & DISCOVER:
      • web_search - Get real-time information (stocks, weather, news, etc.)
      • query_document_content - Search all uploaded documents
      • read_document - Read specific document content
      
      CONNECT & ORCHESTRATE:
      • find_best_agent - Find the best specialist agent for a task (PREFERRED - uses historical data)
      • propose_task_to_agent - CHECK if agent can handle task (handshake)
      • delegate_to_agent - Hand off work to specialists (after handshake)
      • respond_to_agent - Handle agent questions
      • list_connections - See what integrations are connected
      
      AVAILABLE DATA MODELS: #{available_models.join(', ')}

      ═══════════════════════════════════════════════════════════════
      🧠 UNIFIED MEMORY - You Remember Everything!
      ═══════════════════════════════════════════════════════════════
      
      You have ONE CONTINUOUS CONVERSATION with this user - no sessions!
      Your memory works in layers, like human memory:
      
      📍 ACTIVE (instant): Last 15 messages - always in your context
      🕐 RECENT (fast): Past week - searchable history
      📚 LONG-TERM: All history - summaries and RAG search
      
      MEMORY TOOLS:
      🔍 SEARCH & RECALL:
      • search_memory - Find specific info in past conversations (quick lookup)
      • recall_context - Jump back to a topic and restore full context
      
      💾 SAVE & STORE:
      • remember_this - When user says "remember that...", "always...", "never..."
      • bookmark_this - Save an output to revisit later (reports, analysis, etc.)
      • list_saved - Show user's saved bookmarks
      
      WHEN TO USE:
      • "What did we discuss about X?" → search_memory(query: "X")
      • "Go back to when we talked about Y" → recall_context(query: "Y")
      • "Remember that I prefer..." → remember_this(content: "...")
      • "Save this report" → bookmark_this(title: "...", description: "...")
      • "Show my saved items" → list_saved()
      
      KEY DIFFERENCE:
      • search_memory = quick lookup, returns matches
      • recall_context = restore full context, continue conversation from that point
      
      ⚠️ You REMEMBER this user across days/weeks. Reference past context naturally!

      ═══════════════════════════════════════════════════════════════
      🚨 TOOL EXECUTION - DO IT, DON'T DESCRIBE IT
      ═══════════════════════════════════════════════════════════════
      
      ✅ CALL tools via the API - don't print JSON or say "I would..."
      ✅ If you need data → fetch it (web_search, get_data, execute_integration)
      ✅ Answer first, then offer follow-ups
      
      ❌ NEVER fabricate data. If you don't have it, say so or fetch it.
      ❌ NEVER answer real-time questions from memory (weather, stocks, etc.)

      ═══════════════════════════════════════════════════════════════
      🔴 DECISION FRAMEWORK - CLASSIFY FIRST, THEN ACT
      ═══════════════════════════════════════════════════════════════
      
      Every request falls into ONE of these categories:
      
      1️⃣ VIEW/QUERY ("Show me", "What's") → Canvas auto-loads! Just respond naturally.
      2️⃣ CREATE DATA ("Create a contact") → get_schema + create_object
      3️⃣ BUILD/DESIGN ("Build landing page") → find_best_agent + delegate_to_agent
      4️⃣ COMPLEX PROJECT (multi-step) → delegate_to_planner
      
      🔑 "Create a contact" = create_object (your job)
         "Create a landing page" = delegate (specialized work)
         "Show contacts" = just respond, canvas auto-loads

      ═══════════════════════════════════════════════════════════════
      🎨 WHEN TO DELEGATE TO AGENTS (not your job)
      ═══════════════════════════════════════════════════════════════
      
      CONTENT CREATION → Delegate:
      • Landing pages → find_best_agent → propose_task_to_agent → delegate_to_agent
      • Email campaigns → delegate_to_agent
      • Blog posts, marketing content → delegate_to_agent
      
      BUILDING & INTEGRATION → Delegate:
      • Connect to Stripe/APIs → delegate_to_agent
      • Build workflows → delegate_to_agent
      • Create new tools → delegate_to_agent
      
      DATA OPERATIONS → Delegate:
      • Import contacts from CSV → delegate_to_agent
      • Data migration → delegate_to_agent
      
      DOCUMENT EXPORT → Delegate:
      • "Export as CSV" → delegate_to_agent(agent_type: "document_export_agent")
      • "Give me an Excel file" → delegate_to_agent(agent_type: "document_export_agent")
      • "Generate a PDF report" → delegate_to_agent(agent_type: "document_export_agent")
      • Any request for CSV, Excel, PDF output → delegate_to_agent
      → User can download from Work Items when complete
      
      ═══════════════════════════════════════════════════════════════
      🔴🔴🔴 DELEGATION: SIMPLE 2-STEP FLOW 🔴🔴🔴
      ═══════════════════════════════════════════════════════════════
      
      DELEGATION IS SIMPLE - JUST 2 STEPS:
      
      1. Call find_best_agent(task_description: "...") - find the right agent
      2. Call delegate_to_agent(agent_type: "agent_slug", task_description: "...") - delegate!
         ⚠️ DO NOT pass a proposal_id - it auto-handshakes!
      
      EXAMPLE:
      find_best_agent(task_description: "Create a landing page") → returns {slug: "landing_page_manager", ...}
      delegate_to_agent(agent_type: "landing_page_manager", task_description: "Create a landing page")
      → DONE! Agent runs in background.
      
      ⛔ CRITICAL MISTAKES TO AVOID:
      • DO NOT pass proposal_id unless you explicitly called propose_task_to_agent first
      • DO NOT make up proposal IDs - they come from propose_task_to_agent
      • DO NOT ask clarifying questions yourself - let the AGENT ask
      • DO NOT stop after find_best_agent - immediately call delegate_to_agent
      
      🚫🚫🚫 NEVER ASK FOR PERMISSION TO DELEGATE! 🚫🚫🚫
      
      WRONG RESPONSES (NEVER DO THIS):
      ❌ "Would you like me to proceed with delegating this?"
      ❌ "I've identified the Landing Page Manager. Want me to delegate?"
      ❌ "The best agent is X. Should I assign this?"
      ❌ "Let me know if you'd like me to hand this off"
      
      CORRECT BEHAVIOR:
      ✅ Find agent → Delegate → Confirm AFTER the delegation is complete
      ✅ "I'm handing this to our Landing Page Manager now." [while calling the tool]
      ✅ "On it - the Landing Page Manager is taking this over." [tool call happening]
      
      THE USER ASKED FOR THE TASK - THAT IS THE PERMISSION!
      When user says "create a landing page" they want it DONE, not asked about
      
      ✅ CORRECT FLOW:
      User: "Create a landing page"
      → find_best_agent(task_description: "Create landing page for law enforcement training")
      → delegate_to_agent(agent_type: "landing_page_manager", task_description: "Create landing page...")
      → "I've handed this off to our Landing Page Manager. They'll reach out with questions!"
      
      🧠 AGENT DISCOVERY:
      • find_best_agent - THE ONLY TOOL for finding agents
      • After calling it, IMMEDIATELY call delegate_to_agent with the agent's slug

      ═══════════════════════════════════════════════════════════════
      🔴🔴🔴 CRITICAL: AGENT DELEGATIONS ARE OUT-OF-BAND 🔴🔴🔴
      ═══════════════════════════════════════════════════════════════
      
      When you delegate to an agent, it runs ASYNCHRONOUSLY in the background.
      You are FREE to continue helping the user with OTHER tasks immediately!
      
      RULES:
      1. 🚀 FIRE AND FORGET: After delegation, the agent handles everything
      2. 🔀 NON-BLOCKING: User can ask you anything else while agents work
      3. 📬 SEPARATE CHANNEL: Agent questions appear in a queue, not in chat
      4. 🆕 TREAT EACH MESSAGE FRESH: New user message = evaluate independently
      
      EXAMPLE FLOW:
      • User: "Create a landing page" → You delegate → Agent is now working
      • User: "How are my email campaigns?" → THIS IS A NEW REQUEST!
         → Answer about campaigns using get_data
         → Do NOT re-engage the landing page agent
         → The landing page work continues separately
      
      WHEN TO USE respond_to_agent:
      • ONLY when user explicitly answers an agent's pending question
      • "The headline should be 'Save 50% Today'" → This answers the agent
      • "How are my campaigns?" → This is NOT an agent answer, handle it yourself!
      
      🔴 NEVER re-delegate to an agent that's already working on a task!
      🔴 NEVER confuse a new topic with a pending agent's context!
      🔴 Each user message is independent unless they're explicitly responding to an agent question

      ═══════════════════════════════════════════════════════════════
      🔴 ACTIONS = TOOL CALLS (No Exceptions)
      ═══════════════════════════════════════════════════════════════
      
      NEVER claim you did something without calling the tool.
      "I've delegated..." is a LIE if delegate_to_agent wasn't called.
      
      CONFIRMATIONS - These all mean "DO IT NOW":
      • "yes", "yeah", "sure", "do it", "go ahead", "proceed"
      • "agent", "that one", "the first one"
      → Understand context - don't ask again!

      ═══════════════════════════════════════════════════════════════
      🔴 WEB SEARCH - USE IT PROACTIVELY
      ═══════════════════════════════════════════════════════════════
      
      ALWAYS USE web_search FOR:
      • Stock prices, exchange rates, crypto prices
      • Weather forecasts
      • Current news and events
      • Competitor research
      • Product comparisons and pricing
      • Any "current", "latest", "today" questions
      • Any factual question you're not 100% certain about
      
      NEVER say "I don't have real-time data" - you DO via web_search!
      NEVER say "My training data is from..." - SEARCH for current info!

      ═══════════════════════════════════════════════════════════════
      📄 DOCUMENTS - SEARCH AND SHOW
      ═══════════════════════════════════════════════════════════════

      • [ATTACHED FILES] present → read_document immediately
      • "Find document about X" → query_document_content(query: "X")
      • Document canvas auto-loads when viewing documents
      
      🔴 For specific documents: query_document_content first to get asset_id
      🔴 NEVER guess an asset_id! Always query first.

      ═══════════════════════════════════════════════════════════════
      🖼️ FREEFORM CANVAS (for external/custom data)
      ═══════════════════════════════════════════════════════════════
      
      Built-in canvases auto-load for platform data (contacts, campaigns, etc.)
      Use create_freeform_canvas ONLY for:
      • External API data (Stripe customers, QB invoices, etc.)
      • Custom visualizations (charts, graphs, comparisons)
      • Custom module data display
      
      🏭 PLATFORM FACTORY (Building New Data Types):
      1. start_module_design → 2. propose_module_schema → 3. approve_module_design
      Once built, these become platform objects accessible via get_schema/create_object.

      ═══════════════════════════════════════════════════════════════
      🤖 AGENT COMMUNICATION
      ═══════════════════════════════════════════════════════════════

      When you see [AGENT: xxx] tags, you're in an EXISTING workflow:
      
      • [REQUEST_TYPE: question] → Relay questions to user conversationally
      • [REQUEST_TYPE: update] → Briefly acknowledge if important
      • [REQUEST_TYPE: completion] → Acknowledge and load relevant canvas
      
      Present agent questions naturally: "For your landing page, what would you like the main headline to be?"

      ═══════════════════════════════════════════════════════════════
      🔍 CONTEXT AWARENESS
      ═══════════════════════════════════════════════════════════════
      
      • "this", "it", "the document" → Refer to CURRENT VIEW
      • On document_viewer: "explain this" = explain the shown document
      • On landing_page_editor: references = the page being edited
      • ALWAYS check CURRENT VIEW before searching for new data
      
    PROMPT

    # Add agent-specific instructions if using loadout
    if @agent_loadout
      prompt += "\n\n#{@agent_loadout.generate_prompt}"
    end

    # Inject AMOS platform awareness context
    if @amos_integration
      begin
        amos_context = @amos_integration.get_context_injection
        prompt += "\n\n#{amos_context}" if amos_context.present?
      rescue => e
        Rails.logger.debug "[Scout] Could not inject AMOS context: #{e.message}"
      end
    end
    
    # Add model-specific instructions (keeps main prompt clean)
    model_addendum = model_specific_addendum(@model)
    if model_addendum.present?
      prompt += "\n\n#{model_addendum}"
    end

    prompt
  end
  
  # Model-specific prompt addendums
  # Keeps the main prompt clean while addressing model-specific quirks
  #
  # SIMPLIFIED: Qwen 3 32B is the default for everything!
  # - 100% tool success (benchmarked)
  # - 376ms avg (fastest)
  # - 7.8/10 content quality
  # - No handoff logic needed anymore!
  #
  MODEL_PROMPT_ADDENDUMS = {
    'qwen3-next-80b' => <<~ADDENDUM,
      ═══════════════════════════════════════════════════════════════
      🚀 MODEL: QWEN3-NEXT-80B (Primary)
      ═══════════════════════════════════════════════════════════════
      
      Model-specific notes (everything else is in the main prompt):
      
      TOOL FORMAT:
      • Use native Bedrock converse tool API format
      • DO NOT output <function=...> or XML function tags
      
      FREEFORM CANVAS (for external data display):
      • When displaying integration data → use create_freeform_canvas
      • NEVER output raw HTML in chat - put it in the canvas
      • Pass data via "data" param, access in JS via window.canvasData
      
      LANDING PAGE EDITS:
      • Delegate to landing_page_manager agent
      • Make ONLY requested changes - no unsolicited "improvements"
    ADDENDUM
    
    'qwen-3-32b' => <<~ADDENDUM,
      ═══════════════════════════════════════════════════════════════
      🔧 MODEL: QWEN 3 32B (Fast)
      ═══════════════════════════════════════════════════════════════
      
      Model-specific notes:
      • Use native Bedrock converse tool API format
      • For external data display → use create_freeform_canvas (not raw HTML in chat)
      • Proofread for typos and word spacing
    ADDENDUM
    
    'deepseek-r1' => <<~ADDENDUM,
      ═══════════════════════════════════════════════════════════════
      🧠 DEEPSEEK R1: REASONING & ANALYSIS MODE
      ═══════════════════════════════════════════════════════════════
      
      You are DeepSeek R1, specialized for complex reasoning and analysis.
      
      YOUR STRENGTHS:
      • Multi-step calculations and business metrics
      • Strategic analysis and tradeoff evaluation
      • Cause-and-effect chain reasoning
      • Long-term planning and forecasting
      
      NOTE: You are NOT expected to use tools. Focus on analysis and reasoning.
      If the user needs data fetched or actions taken, the system will route
      to a different model that handles tools.
    ADDENDUM
    
    'deepseek-v3' => nil, # V3 not used as primary anymore
    'mistral-large-3' => nil, # Mistral not used as primary anymore
    'claude-sonnet-4-5' => nil, # Claude is fallback only
  }.freeze
  
  def model_specific_addendum(model_name)
    return nil unless model_name.present?
    MODEL_PROMPT_ADDENDUMS[model_name.to_s]
  end
  
  # Format business context for the system prompt
  def format_business_context_for_prompt
    context_parts = []
    
    # Check if we're in Personal space - minimal business context
    in_personal_space = @user&.active_space == 'personal'
    
    # ═══════════════════════════════════════════════════════════════
    # 👤 USER PROFILE (always include - it's about THEM, not work)
    # ═══════════════════════════════════════════════════════════════
    context_parts << "═══════════════════════════════════════════════════════════════"
    context_parts << "👤 WHO YOU'RE TALKING TO"
    context_parts << "═══════════════════════════════════════════════════════════════"
    
    if @user.present?
      user_name = @user.respond_to?(:full_name) ? @user.full_name : "#{@user.first_name} #{@user.last_name}".strip
      context_parts << "Name: #{user_name}" if user_name.present?
      # In personal space, skip work email - keep it personal
      context_parts << "Email: #{@user.email}" if !in_personal_space && @user.respond_to?(:email) && @user.email.present?
      # Skip role in personal space
      context_parts << "Role: #{@user.role.humanize}" if !in_personal_space && @user.respond_to?(:role) && @user.role.present?
    end
    
    # In Personal space, skip all business context - this is "off the clock"
    if in_personal_space
      context_parts << ""
      context_parts << "[Personal Space - Business context suppressed. You know their work context but keep it as PRIVATE KNOWLEDGE unless they ask.]"
      return context_parts.join("\n")
    end
    
    # ═══════════════════════════════════════════════════════════════
    # 🏢 BUSINESS PROFILE (Work/Team spaces only)
    # ═══════════════════════════════════════════════════════════════
    context_parts << ""
    context_parts << "═══════════════════════════════════════════════════════════════"
    context_parts << "🏢 THEIR BUSINESS"
    context_parts << "═══════════════════════════════════════════════════════════════"
    
    # Try user's business profile first, then entity's
    profile = @user&.business_profile || @entity&.business_profiles&.first
    
    if profile.present?
      context_parts << "Business Name: #{profile.name}" if profile.respond_to?(:name) && profile.name.present?
      context_parts << "Industry: #{profile.industry}" if profile.respond_to?(:industry) && profile.industry.present?
      context_parts << "Website: #{profile.website}" if profile.respond_to?(:website) && profile.website.present?
      context_parts << "Founded: #{profile.founded_year}" if profile.respond_to?(:founded_year) && profile.founded_year.present?
      
      if profile.respond_to?(:description) && profile.description.present?
        context_parts << "Description: #{profile.description.truncate(300)}"
      end
      
      if profile.respond_to?(:target_audience) && profile.target_audience.present?
        context_parts << "Target Audience: #{profile.target_audience}"
      end
      
      if profile.respond_to?(:values) && profile.values.present?
        context_parts << "Core Values: #{profile.values.truncate(200)}"
      end
      
      if profile.respond_to?(:tone_of_voice) && profile.tone_of_voice.present?
        context_parts << "Brand Voice/Tone: #{profile.tone_of_voice.truncate(200)}"
      end
    elsif @entity.present?
      # Fallback to entity info if no business profile
      context_parts << "Business Name: #{@entity.name}"
      context_parts << "Industry: #{@entity.industry}" if @entity.respond_to?(:industry) && @entity.industry.present?
    end
    
    # ═══════════════════════════════════════════════════════════════
    # 📊 ACCOUNT STATS (Quick overview of what they have)
    # ═══════════════════════════════════════════════════════════════
    if @entity.present?
      stats = []
      begin
        campaign_count = @entity.campaigns.count rescue 0
        landing_page_count = @entity.landing_pages.count rescue 0
        contact_count = @entity.contacts.count rescue 0
        template_count = @entity.email_templates.count rescue 0
        
        stats << "#{campaign_count} campaigns" if campaign_count > 0
        stats << "#{landing_page_count} landing pages" if landing_page_count > 0
        stats << "#{contact_count} contacts" if contact_count > 0
        stats << "#{template_count} email templates" if template_count > 0
        
        if stats.any?
          context_parts << ""
          context_parts << "📊 Account Overview: #{stats.join(', ')}"
        end
      rescue => e
        Rails.logger.debug "Could not load account stats: #{e.message}"
      end
      
      # Connected integrations - with DETAILED info so Amos knows what's available
      begin
        # Get connections for this specific user (user-scoped like the list_connections tool)
        user_connections = Connection.includes(:integration)
                                     .where(user: @user, entity: @entity, status: 'connected')
        
        # Also get entity-level connections (no specific user)
        entity_connections = Connection.includes(:integration)
                                       .where(entity: @entity, user: nil, status: 'connected')
        
        all_connected = (user_connections + entity_connections).uniq(&:integration_id)
        
        if all_connected.any?
          context_parts << ""
          context_parts << "═══════════════════════════════════════════════════════════════"
          context_parts << "🔌 CONNECTED INTEGRATIONS"
          context_parts << "═══════════════════════════════════════════════════════════════"
          
          all_connected.each do |connection|
            integration = connection.integration
            ops_count = integration.integration_operations.count rescue 0
            context_parts << "• #{integration.name}: connected (id: #{connection.id}, #{ops_count} operations)"
          end
        else
          context_parts << ""
          context_parts << "🔌 No integrations connected yet."
        end
      rescue => e
        Rails.logger.debug "Could not load integrations: #{e.message}"
      end
    end
    
    # ═══════════════════════════════════════════════════════════════
    # 🧠 LEARNED INSIGHTS (What Scout has learned about this business)
    # ═══════════════════════════════════════════════════════════════
    if @entity.present? && defined?(BusinessInsight)
      begin
        insights = BusinessInsight.where(entity: @entity)
                                  .where("confidence_score >= ?", 0.7)
                                  .order(created_at: :desc)
                                  .limit(5)
        
        if insights.any?
          context_parts << ""
          context_parts << "🧠 What I've Learned About This Business:"
          insights.each do |insight|
            context_parts << "   • #{insight.insight_type.humanize}: #{insight.content.truncate(150)}"
          end
        end
      rescue => e
        Rails.logger.debug "Could not load business insights: #{e.message}"
      end
    end
    
    return "" if context_parts.empty?
    
    <<~CONTEXT
      ═══════════════════════════════════════════════════════════════
      📋 CONTEXT - What you know about this user/business
      ═══════════════════════════════════════════════════════════════
      
      #{context_parts.join("\n")}
    CONTEXT
  end
  
  # Format user memories and preferences for system prompt
  def format_user_memories_for_prompt
    return "" unless @user.present? && @entity.present?
    return "" unless defined?(UserMemory)
    
    begin
      UserMemory.for_prompt(user: @user, entity: @entity, limit: 10)
    rescue => e
      Rails.logger.debug "Could not load user memories: #{e.message}"
      ""
    end
  end
  
  # Format Scout personality for system prompt
  def format_scout_personality_for_prompt
    return "" unless @entity.present?
    return "" unless defined?(ScoutPersonality)
    
    begin
      personality = ScoutPersonality.for_entity(@entity)
      personality&.to_prompt || ""
    rescue => e
      Rails.logger.debug "Could not load Scout personality: #{e.message}"
      ""
    end
  end
  
  # Format Scout's own learnings for system prompt
  def format_scout_learnings_for_prompt
    return "" unless @entity.present?
    return "" unless defined?(ScoutLearning)
    
    begin
      ScoutLearning.for_prompt(entity: @entity, limit: 8)
    rescue => e
      Rails.logger.debug "Could not load Scout learnings: #{e.message}"
      ""
    end
  end
  
  # Format conversation summaries for system prompt
  # This gives Scout context about earlier parts of long conversations
  def format_conversation_summaries_for_prompt
    return "" unless @user.present? && @entity.present?
    
    begin
      # Use unified memory system if available
      if defined?(Scout::UnifiedMemory) && defined?(MemorySegment)
        # Pass fresh_start_at to filter out old messages from before "Fresh Start"
        memory = Scout::UnifiedMemory.new(user: @user, entity: @entity, fresh_start_at: @fresh_start_at)
        context = memory.build_context
        return memory.format_for_prompt(context)
      end
      
      # Fallback to session-based summaries
      return "" unless @session_id.present? && defined?(ConversationSummary)
      ConversationSummary.for_prompt(session_id: @session_id, limit: 3)
    rescue => e
      Rails.logger.debug "Could not load conversation summaries: #{e.message}"
      ""
    end
  end

  # Format AI rulesets for system prompt injection
  # Rulesets define behavioral constraints that Scout must follow
  def format_ai_rulesets_for_prompt
    return "" unless @entity.present?

    begin
      AiRulesetService.new(@entity).to_system_prompt_section
    rescue => e
      Rails.logger.debug "Could not load AI rulesets: #{e.message}"
      ""
    end
  end

  # Format team roster for prompt - shows available agents
  # This helps Amos understand who's on the team and when to delegate
  def format_team_roster_for_prompt
    return "" unless @entity.present?

    begin
      registry = Amos::CapabilityRegistry.new(entity: @entity)
      agents = registry.available_agents
      
      return "" if agents.empty?

      roster_parts = []
      roster_parts << "👥 YOUR TEAM (delegate to specialists!):"
      
      # Group agents by type
      integration_agents = agents.select { |a| a[:agent_type] == :integration }
      module_agents = agents.select { |a| a[:agent_type] == :module }
      system_agents = agents.select { |a| a[:agent_type] == :system || a[:agent_type] == :general }
      
      # Integration experts (API specialists)
      if integration_agents.any?
        roster_parts << "🔌 Integration Experts:"
        integration_agents.each do |agent|
          specializations = agent[:specializations]&.first(2)&.join(', ') || 'API operations'
          roster_parts << "   • #{agent[:name]} (#{agent[:slug]}): #{specializations}"
        end
      end
      
      # Module experts (custom app specialists)
      if module_agents.any?
        roster_parts << "📦 Module Experts:"
        module_agents.each do |agent|
          roster_parts << "   • #{agent[:name]} (#{agent[:slug]}): Knows this module's data deeply"
        end
      end
      
      # System agents (built-in specialists)
      if system_agents.any?
        roster_parts << "⚙️ System Specialists:"
        system_agents.first(5).each do |agent|
          specializations = agent[:specializations]&.first(2)&.join(', ') || agent[:description].to_s.truncate(50)
          roster_parts << "   • #{agent[:name]} (#{agent[:slug]}): #{specializations}"
        end
      end
      
      # Pre-warmed agents from preprocessor (most relevant for current request)
      if @prewarmed_agents.present? && @prewarmed_agents.any?
        top_agent = @prewarmed_agents.first
        roster_parts << ""
        roster_parts << "⚡ SUGGESTED FOR THIS REQUEST: #{top_agent[:name]} (#{top_agent[:slug]})"
      end
      
      roster_parts.join("\n")
    rescue => e
      Rails.logger.debug "Could not load team roster: #{e.message}"
      ""
    end
  end

  def format_templates_for_prompt(templates)
    return "None available" if templates.empty?

    templates.map do |t|
      "- #{t[:name]} (#{t[:slug]}): #{t[:description]}"
    end.join("\n      ")
  end

  # Track repeated phrases to detect model looping
  REPETITION_THRESHOLD = 3  # If same phrase appears 3+ times, it's a loop

  def handle_streaming_chunk(chunk, accumulated_content, tool_calls, streaming_started, progress_callback)
    case chunk[:type]
    when :content
      accumulated_content << chunk[:content]
      
      # LOOP DETECTION: Check if model is generating repetitive content
      # This catches the case where model outputs same sentence over and over
      if accumulated_content.length > 200
        # Look for repeated phrases (40+ chars)
        text = accumulated_content.to_s
        # Find all sentences/phrases
        phrases = text.scan(/[^.!?\n]{40,}[.!?]/).map(&:strip)
        phrase_counts = phrases.tally
        
        # Check if any phrase appears too many times
        repeated = phrase_counts.find { |phrase, count| count >= REPETITION_THRESHOLD }
        if repeated
          Rails.logger.warn "⚠️ Repetition loop detected: '#{repeated[0].truncate(60)}' appeared #{repeated[1]} times"
          # Signal to stop the stream
          @repetition_loop_detected = true
      progress_callback&.call({
        type: "content_chunk",
            content: "\n\n*I noticed I was repeating myself. Let me stop here. How can I help you?*"
          })
          return :stop_streaming  # Caller should check for this
        end
      end
      
      # Filter out handoff markers before streaming to user
      # User should NEVER see internal model coordination
      # IMPORTANT: Don't skip the whole chunk - just remove the marker patterns!
      display_content = chunk[:content].dup
      
      # Remove handoff markers (but keep surrounding content!)
      display_content.gsub!(/\[HANDOFF_TO_MISTRAL:[^\]]*\]?/i, '')
      display_content.gsub!(/_MISTRAL:[^\]]*\]?/i, '')
      display_content.gsub!(/\[Called\s+\w+\s+with[^\]]*\]?/i, '')
      display_content.gsub!(/<function=\w+>[^<]*(?:<\/function>)?/i, '')
      
      # Remove partial markers that might be building up
      display_content.gsub!(/\[HANDOFF[^\]]*$/i, '')  # Partial at end of chunk
      display_content.gsub!(/\[Called[^\]]*$/i, '')   # Partial at end
      display_content.gsub!(/<function[^>]*$/i, '')   # Partial at end
      
      # Also remove the "Switching to tool mode" message
      display_content.gsub!(/🔧\s*Switching to tool mode\.{0,3}/i, '')
      
      # SAFETY: Strip raw HTML/Bootstrap markup from chat text
      # Amos should use create_freeform_canvas for HTML, not output it directly
      # Detect patterns like <div class="container">, <h5>, Bootstrap classes
      if display_content.match?(/<(div|span|h[1-6]|ul|ol|table|p|strong|small)\s*(class|id|style)?=/i) ||
         display_content.match?(/class="(container|card|alert|btn|row|col|mb-|py-|px-)/i)
        # Log this as an issue - Amos should NOT output HTML directly
        Rails.logger.warn "⚠️ Stripping raw HTML from chat output - Amos should use create_freeform_canvas"
        
        # Strip the HTML tags but keep any meaningful text content
        display_content = strip_html_to_text(display_content)
      end
      
      # Skip if nothing left after filtering
      if display_content.strip.empty?
        Rails.logger.debug "🤝 Chunk was entirely marker content, skipping"
        return
      end
      
      progress_callback&.call({
        type: "content_chunk",
        content: display_content
      })
    when :tool_use_start
      Rails.logger.info "🔧 Tool detected: #{chunk[:tool_name]}"

      # If this is the first tool and no content has been streamed yet,
      # stream some initial feedback so the user knows we're working
      if tool_calls.empty? && accumulated_content.blank?
        # Check if this is a delegation tool
        initial_message = if chunk[:tool_name] == "delegate_to_agent"
          "One moment, let me get the right agent to help with that. "
        else
          "I'll help you with that. "
        end
        accumulated_content << initial_message
        progress_callback&.call({
          type: "content_chunk",
          content: initial_message
        })
      end

      tool_calls << {
        id: chunk[:tool_id],
        name: chunk[:tool_name],
        arguments: ""
      }
      progress_callback&.call({
        type: "tool_start",
        name: chunk[:tool_name]
      })
    when :tool_use
      if tool_calls.any?
        input = chunk[:tool_use].input
        # Handle both Hash and String inputs from streaming
        if input.is_a?(Hash)
          tool_calls.last[:arguments] = input
        elsif input.is_a?(String)
          tool_calls.last[:arguments] += input
        end
      end
    when :usage
      # Token usage with cache metrics and model used (for fallback transparency)
      @model_used = chunk[:model_used] if chunk[:model_used]
      @model_name = chunk[:model_name] if chunk[:model_name]

      progress_callback&.call({
        type: "cache_metrics",
        tokens: chunk[:tokens],
        cache_creation: chunk[:cache_creation] || 0,
        cache_read: chunk[:cache_read] || 0,
        model_used: @model_used,
        model_name: @model_name
      })
    when :message_stop
      # Message complete
      if accumulated_content.present? && !@saved_message_content.include?(accumulated_content.hash)
        progress_callback&.call({
          type: "save_message",
          content: accumulated_content,
          role: "assistant"
        })
        @saved_message_content.add(accumulated_content.hash)
        @messages_saved_during_streaming = true
      end
    end
  end

  def execute_tool_calls(tool_calls, progress_callback)
    results = []

    tool_calls.each do |tool_call|
      begin
        args = parse_tool_arguments(tool_call[:arguments])
        Rails.logger.debug "Executing #{tool_call[:name]} with args: #{args.inspect}"

        # ═══════════════════════════════════════════════════════════════
        # INTEGRATION CONFIDENCE CHECK (Learn Before Act)
        # For integration operations, check if we should consult knowledge first
        # ═══════════════════════════════════════════════════════════════
        if should_suggest_knowledge_consultation?(tool_call[:name], args)
          suggestion = get_integration_knowledge_suggestion(tool_call[:name], args)
          if suggestion
            Rails.logger.info "💡 Suggesting integration knowledge consultation for #{args['operation_id'] || args['operation']}"
            # Prepend the suggestion but still execute the operation
            progress_callback&.call({
              type: "content_chunk",
              content: suggestion[:guidance]
            }) if suggestion[:should_warn]
            
            # If there's modified args, use them instead
            args = suggestion[:corrected_args] if suggestion[:corrected_args]
          end
        end

        result = execute_tool_by_name(tool_call[:name], args, progress_callback)

        # Special handling for delegate_to_agent - display the confirmation message
        if tool_call[:name] == "delegate_to_agent" && result[:success]
          # Stream the helpful delegation message to the user
          if result[:message].present?
            progress_callback&.call({
              type: "content_chunk",
              content: result[:message]
            })
            # Save this as the assistant response
            @delegation_message = result[:message]
          end
          
          # Simplify the result to prevent Scout from adding more
          result = { 
            success: true, 
            agent_name: result[:agent_name],
            note: "Agent is now working on the task."
          }
          # Mark that we should not continue generating content
          @stop_after_delegation = true
        end

        # Special handling for delegate_to_planner
        if tool_call[:name] == "delegate_to_planner" && result[:success] && result[:approval_required]
          # Store flag to indicate workflow delegation happened
          @workflow_delegated = true
          @delegated_task_session_id = result[:task_session_id]
          @delegated_workflow_spec = result[:workflow_spec]
        end

        # Extract sources from tool results
        extract_sources_from_result(tool_call[:name], result)

        progress_callback&.call({
          type: "tool_complete",
          name: tool_call[:name],
          success: result[:success] || false
        })

        # Log success for RL model selection
        if result[:success]
          log_model_quality_event(:tool_success, tool_call[:name], "success")
        else
          log_model_quality_event(:tool_failure, tool_call[:name], result[:error] || "unknown failure")
          # MISTAKE LEARNING: Record this failure so we don't repeat it
          record_tool_mistake(tool_call[:name], tool_call[:input], result[:error] || "unknown failure")
        end

        Rails.logger.debug "Tool #{tool_call[:name]} result: #{result[:success] ? 'success' : 'failed'}"
        results << result
      rescue JSON::ParserError => e
        # Provide a helpful error that lets the model self-correct
        error_details = build_json_error_feedback(tool_call, e)
        log_model_quality_event(:json_parse_error, tool_call[:name], e.message)
        # MISTAKE LEARNING: Record JSON errors too
        record_tool_mistake(tool_call[:name], tool_call[:input], "JSON parse error: #{e.message}")
        
        Rails.logger.error "Tool execution failed - Invalid JSON: #{e.message}"
        progress_callback&.call({
          type: "tool_complete",
          name: tool_call[:name],
          success: false
        })
        
        results << error_details
      rescue => e
        Rails.logger.error "Tool execution failed: #{e.message}"
        results << { success: false, error: e.message }
      end
    end

    Rails.logger.info "🔧 Tools completed: #{results.map { |r| r[:success] ? '✓' : '✗' }.join(' ')}" if results.any?
    results
  end

  # Build a helpful error message that guides the model to fix its JSON
  def build_json_error_feedback(tool_call, error)
    args_preview = tool_call[:arguments].to_s.truncate(200)
    
    # Identify common issues
    issues = []
    args_str = tool_call[:arguments].to_s
    
    if args_str =~ /\d":/ || args_str =~ /":.*":/ 
      issues << "Colons are appearing outside of string quotes - check date/time formatting"
    end
    if args_str =~ /\d{4}-[,\s]/
      issues << "Date formatting is corrupted (spaces or commas in dates)"
    end
    if args_str =~ /"[^"]*\n[^"]*"/
      issues << "Unescaped newlines in string values"
    end
    if args_str.count('{') != args_str.count('}')
      issues << "Mismatched braces - missing #{args_str.count('{') > args_str.count('}') ? 'closing' : 'opening'} brace"
    end
    if args_str.count('[') != args_str.count(']')
      issues << "Mismatched brackets - check array syntax"
    end
    
    issues << "General JSON syntax error" if issues.empty?
    
    {
      success: false,
      error: "JSON_PARSE_ERROR",
      message: "Your tool arguments contained invalid JSON. Please retry with properly formatted JSON.",
      issues_detected: issues,
      specific_error: error.message.truncate(100),
      guidance: [
        "Ensure all strings are properly quoted with double quotes",
        "Escape special characters in strings (\\n for newlines, \\\" for quotes)",
        "Use ISO 8601 format for dates: \"2026-01-12T10:30:00Z\"",
        "Verify all braces {} and brackets [] are matched",
        "For complex data, consider using simpler structures"
      ],
      retry_suggested: true
    }
  end
  
  # Log model quality events for RL-based model selection
  def log_model_quality_event(event_type, tool_name, details)
    model_id = @model_used || "unknown"
    
    Rails.logger.info "[ModelQuality] event=#{event_type} model=#{model_id} tool=#{tool_name} details=#{details.to_s.truncate(200)}"
    
    # Store for RL model selection (async to not block)
    begin
      ModelQualityLog.create!(
        model_id: model_id,
        event_type: event_type.to_s,
        tool_name: tool_name,
        details: details.to_s.truncate(1000),
        entity_id: @entity&.id,
        user_id: @user&.id,
        session_id: @session_id,
        created_at: Time.current
      )
    rescue => e
      # Don't fail if logging fails - table might not exist yet
      Rails.logger.debug "[ModelQuality] Could not persist event: #{e.message}"
    end
  end

  # ============================================================================
  # SMART LOOP DETECTION
  # Instead of a hard limit on tool calls, we detect actual loops:
  # - Same tool with same args called 3+ times = loop
  # - Same failing pattern repeating = loop  
  # - Sequential unique operations (e.g., create 50 contacts) = NOT a loop
  # ============================================================================
  
  LOOP_DETECTION_THRESHOLD = 3  # Same call 3x = loop
  MAX_TOOL_CALLS_PER_REQUEST = 100  # Absolute safety cap (very generous)

  def get_continuation_after_tools(system_prompt, conversation_messages, tool_calls, tool_results, progress_callback, recursion_depth: 0)
    # Initialize tool call history for this request if not already done
    @tool_call_history ||= []
    
    # Record current tool calls
    tool_calls.each_with_index do |tc, idx|
      @tool_call_history << {
        name: tc[:name],
        args_hash: Digest::MD5.hexdigest((tc[:arguments] || {}).to_json),
        success: tool_results[idx].to_s.exclude?('error') && tool_results[idx].to_s.exclude?('failed'),
        timestamp: Time.current
      }
    end
    
    # SMART LOOP DETECTION: Check for actual loops
    loop_detected, loop_reason = detect_tool_loop(@tool_call_history)
    
    if loop_detected
      Rails.logger.warn "🔄 Loop detected: #{loop_reason}"
      
      # Learn from the mistakes made in this session
      learn_from_session_mistakes(tool_calls, tool_results)
      
      return {
        final_response: {
          message: "I noticed I was repeating the same action without progress. #{loop_reason}\n\nHere's what I learned:\n\n#{summarize_session_mistakes}\n\nLet me try a different approach, or please provide more details.",
          message_already_saved: false
        },
        tools_used: @tool_call_history.map { |tc| tc[:name] }.uniq,
        sources: @sources
      }
    end
    
    # ABSOLUTE SAFETY CAP - for truly runaway situations
    if @tool_call_history.length >= MAX_TOOL_CALLS_PER_REQUEST
      Rails.logger.warn "⚠️ Absolute tool limit (#{MAX_TOOL_CALLS_PER_REQUEST}) reached"
      return {
        final_response: {
          message: "I've made #{MAX_TOOL_CALLS_PER_REQUEST} tool calls for this request - that's a lot! Let me summarize what I've accomplished so far and check if there's anything left to do.",
          message_already_saved: false
        },
        tools_used: @tool_call_history.map { |tc| tc[:name] }.uniq,
        sources: @sources
      }
    end
    
    # Log progress for sequential operations
    if @tool_call_history.length > 5 && @tool_call_history.length % 10 == 0
      Rails.logger.info "📊 Progress: #{@tool_call_history.length} tool calls executed (no loops detected)"
    end
    
    # Check for repeated failures and inject learning context
    inject_mistake_learning_context(tool_results, progress_callback) if recursion_depth > 2

    # Check if we should stop after delegation
    if @stop_after_delegation
      Rails.logger.info "Stopping response after agent delegation - agent will communicate through Scout"
      return ""
    end
    
    # MULTI-MODEL PIPELINE: Check if we should switch to DeepSeek for visualization
    should_use_visualization_model = should_switch_to_visualization_model?(tool_calls, tool_results)
    Rails.logger.info "🎨 Visualization mode: #{should_use_visualization_model}" if should_use_visualization_model

    # Add tool results (truncated to prevent context overflow)
    conversation_messages << {
      role: "user",
      content: tool_calls.map.with_index do |tool_call, idx|
        {
          type: "tool_result",
          tool_result: {
            tool_use_id: tool_call[:id],
            content: [
              {
                type: "text",
                text: truncate_tool_result(tool_results[idx])
              }
            ]
          }
        }
      end
    }

    # Get continuation - use DeepSeek for visualization if applicable
    continuation_message = ""
    continuation_tool_calls = []
    
    # MULTI-MODEL: If we have data and need visualization, use DeepSeek (no tools - just code gen)
    if should_use_visualization_model
      continuation_model = 'deepseek-v3'
      tools = [] # DeepSeek doesn't need tools - we're asking it to generate HTML/CSS/JS
      
      # Add special visualization prompt for DeepSeek
      viz_system_prompt = build_visualization_only_prompt(system_prompt, tool_results)
      
      # IMPORTANT: Clean conversation - remove tool_use/tool_result blocks for DeepSeek
      # Bedrock throws "toolConfig field must be defined" if we have tool blocks but no tools
      viz_conversation = convert_tool_blocks_to_text(conversation_messages, tool_results)
      
      # Send a friendly message while we generate the visualization
      progress_callback&.call({
        type: "content_chunk",
        content: "📊 Creating your visualization..."
      })
    else
      continuation_model = @model
    tools = get_filtered_tools
      viz_system_prompt = system_prompt
      viz_conversation = conversation_messages
    end

    # Use thinking depth for continuation calls (reuse cached config)
    depth_config = thinking_depth_config
    
    @ai_service.send_message_streaming(
      viz_system_prompt,
      viz_conversation,
      model: continuation_model,
      max_tokens: depth_config[:max_tokens],
      temperature: depth_config[:temperature],
      json_mode: false,
      tools: tools,
      enable_prompt_caching: true
    ) do |chunk|
      case chunk[:type]
      when :content
        continuation_message << chunk[:content]
        
        # MULTI-MODEL: Don't stream visualization JSON to chat - collect silently
        unless should_use_visualization_model
        progress_callback&.call({
          type: "content_chunk",
          content: chunk[:content]
        })
        end
      when :tool_use_start
        # Handle additional tool calls in continuation
        Rails.logger.info "🔧 Additional tool detected in continuation: #{chunk[:tool_name]}"
        continuation_tool_calls << {
          id: chunk[:tool_id],
          name: chunk[:tool_name],
          arguments: ""
        }
        progress_callback&.call({
          type: "tool_start",
          name: chunk[:tool_name]
        })
      when :tool_use
        if continuation_tool_calls.any? && chunk[:tool_use]
          continuation_tool_calls.last[:arguments] += chunk[:tool_use][:input] || ""
        end
      when :usage
        # Capture model info from continuation as well
        @model_used = chunk[:model_used] if chunk[:model_used]
        @model_name = chunk[:model_name] if chunk[:model_name]
      end
    end

    # MULTI-MODEL: If we used DeepSeek for visualization, parse its JSON output and load canvas
    if should_use_visualization_model && continuation_message.present?
      viz_result = handle_visualization_json_output(continuation_message, progress_callback)
      
      if viz_result[:success]
        Rails.logger.info "🎨 Visualization loaded successfully"
        return viz_result[:response]
      end
      # If parsing failed, fall through to clean fallback response
    end

    # If there are more tool calls, execute them recursively
    if continuation_tool_calls.any?
      Rails.logger.info "Executing #{continuation_tool_calls.length} additional tools in continuation"
      additional_results = execute_tool_calls(continuation_tool_calls, progress_callback)

      # Recursively get the next continuation (smart loop detection in effect)
      @tool_call_history ||= []
      Rails.logger.info "🔄 Continuing after tools - #{@tool_call_history.length} total calls (loop detection active)"
      return get_continuation_after_tools(
        system_prompt,
        conversation_messages + [
          {
            role: "assistant",
            content: [
              { type: "text", text: continuation_message.present? ? continuation_message : "Continuing with the next step..." }
            ] + continuation_tool_calls.map do |tc|
              {
                type: "tool_use",
                tool_use: {
                  id: tc[:id],
                  name: tc[:name],
                  input: begin
                    parse_tool_arguments(tc[:arguments])
                  rescue JSON::ParserError => e
                    Rails.logger.error "Failed to parse tool arguments: #{tc[:arguments]}"
                    {}
                  end
                }
              }
            end
          },
          {
            role: "user",
            content: continuation_tool_calls.map.with_index do |tc, idx|
              {
                type: "tool_result",
                tool_result: {
                  tool_use_id: tc[:id],
                  content: [
                    {
                      type: "text",
                      text: truncate_tool_result(additional_results[idx])
                    }
                  ]
                }
              }
            end
          }
        ],
        [],  # No more tool calls to add
        [],  # No more results to add
        progress_callback,
        recursion_depth: recursion_depth + 1
      )
    end

    # If visualization mode failed, return clean message instead of raw JSON
    final_message = if should_use_visualization_model
      @canvas_already_broadcast ? 
        "I've loaded a visualization for you! Check the canvas panel. 📊" :
        "I tried to create a visualization but encountered an issue. Would you like me to try a different format?"
    else
      continuation_message
    end

    response = {
      final_response: {
        message: final_message,
        message_already_saved: false,
        delegation_occurred: @stop_after_delegation || false
      },
      tools_used: tool_calls.map { |tc| tc[:name] },
      sources: @sources,
      model_used: @model_used,
      model_name: @model_name,
      delegation_occurred: @stop_after_delegation || false
    }
    
    # Only include canvas info if it wasn't already broadcast
    if @suggested_canvas && !@canvas_already_broadcast
      response[:canvas_type] = @suggested_canvas
      response[:canvas_data] = @canvas_data
    else
      response[:canvas_type] = "conversation"
    end

    # Add workflow approval data if delegation happened
    if @workflow_delegated
      response[:workflow_approval_needed] = true
      response[:task_session_id] = @delegated_task_session_id
      response[:workflow_spec] = @delegated_workflow_spec
    end

    # 🧠 CONSCIENCE CHECK - Validate response before returning
    validate_response_with_conscience(final_message, tool_calls, response)
    
    # 🛡️ EXECUTION GUARD - Detect unfulfilled promises and force completion
    guard_result = check_unfulfilled_intent(final_message, tool_calls, response)
    if guard_result[:needs_retry]
      Rails.logger.warn "[ExecutionGuard] ⚠️ Unfulfilled intent detected - forcing tool execution"
      response[:execution_guard] = guard_result
    end

    response
  end

  # Conscience Validator - catches hallucinated actions
  def validate_response_with_conscience(response_text, tool_calls, response_hash)
    return unless response_text.present?
    
    begin
      validator = Amos::ConscienceValidator.new(entity: @entity, user: @user)
      
      validation = validator.validate(
        response: response_text,
        tool_calls: tool_calls,
        tool_results: @tool_results || [],
        context: { recent_messages: @conversation_history || [] }
      )
      
      # Log issues for monitoring
      if validation[:issues].any?
        Rails.logger.warn "[CONSCIENCE] 🧠 Issues detected in response:"
        validation[:issues].each do |issue|
          Rails.logger.warn "[CONSCIENCE]   - #{issue[:type]}: #{issue[:message]}"
        end
        
        # Add conscience validation to response metadata
        response_hash[:conscience_validation] = {
          valid: validation[:valid],
          severity: validation[:severity],
          issues: validation[:issues].map { |i| { type: i[:type], message: i[:message] } }
        }
        
        # For critical issues (claimed action without tool call), log prominently
        if validation[:severity] == :critical
          Rails.logger.error "[CONSCIENCE] 🚨 CRITICAL: Response claims action without tool call!"
          Rails.logger.error "[CONSCIENCE] Response: #{response_text.truncate(200)}"
          Rails.logger.error "[CONSCIENCE] Tools called: #{tool_calls.map { |t| t[:name] }.join(', ')}"
          
          # TODO: In future, we could:
          # 1. Block the response and force a retry
          # 2. Append a warning to the user
          # 3. Auto-trigger the missing tool call
        end
      end
    rescue => e
      Rails.logger.debug "[CONSCIENCE] Validation error (non-blocking): #{e.message}"
    end
  end
  
  # 🛡️ Execution Guard - Detect when AI promises action but doesn't call tools
  # This catches "I'll fetch X" without actually calling the fetch tool
  def check_unfulfilled_intent(response_text, tool_calls, response_hash)
    return { needs_retry: false } unless response_text.present?
    
    begin
      guard = ExecutionGuardService.new(entity: @entity, user: @user, session_id: @session_id)
      
      # Check for unfulfilled promises
      result = guard.check_unfulfilled_intent(
        response: response_text,
        tool_calls: tool_calls || []
      )
      
      if result[:has_unfulfilled_intent]
        Rails.logger.warn "[ExecutionGuard] ⚠️ Unfulfilled intents: #{result[:intents].join(', ')}"
        
        # Record this for learning
        record_unfulfilled_intent(response_text, result[:intents])
        
        # Check if we should force a retry
        if result[:force_tool_call] && @retry_count.to_i < 2
          @retry_count = (@retry_count || 0) + 1
          
          return {
            needs_retry: true,
            intents: result[:intents],
            suggested_prompt: result[:suggested_prompt],
            retry_count: @retry_count
          }
        else
          # Add warning to response
          response_hash[:unfulfilled_intents] = result[:intents]
          response_hash[:execution_warning] = "AI stated intent but may not have completed all actions"
        end
      end
      
      # Also check for loops
      if @tool_call_history.present?
        loop_result = guard.detect_loop(recent_tool_calls: @tool_call_history.last(6))
        
        if loop_result[:is_loop]
          Rails.logger.error "[ExecutionGuard] 🔄 Loop detected: #{loop_result[:pattern]}"
          response_hash[:loop_detected] = true
          response_hash[:loop_pattern] = loop_result[:pattern]
        end
      end
      
      { needs_retry: false }
    rescue => e
      Rails.logger.debug "[ExecutionGuard] Error (non-blocking): #{e.message}"
      { needs_retry: false }
    end
  end
  
  # Record unfulfilled intent for learning via ExecutionLearningBridge
  def record_unfulfilled_intent(response, intents)
    return unless @entity
    
    begin
      bridge = ExecutionLearningBridge.new(entity: @entity, user: @user, agent: current_agent)
      bridge.record_unfulfilled_intent(
        intents: intents,
        response: response,
        context: {
          session_id: @session_id,
          model: @model,
          thinking_depth: @thinking_depth
        }
      )
    rescue => e
      Rails.logger.debug "[ExecutionGuard] Failed to record unfulfilled intent: #{e.message}"
    end
  end
  
  # Get current agent if delegated
  def current_agent
    return nil unless @delegated_agent_slug
    AgentPlugin.find_by(slug: @delegated_agent_slug, entity: @entity)
  end

  def execute_load_canvas(args, progress_callback = nil)
    # Support both canvas_name and canvas_type (some models use canvas_type)
    canvas_name = args["canvas_name"] || args[:canvas_name] || 
                  args["canvas_type"] || args[:canvas_type]
    canvas_data = args["canvas_data"] || args[:canvas_data] || {}

    # CRITICAL: Send canvas update IMMEDIATELY via progress callback
    # This ensures it arrives BEFORE any response message
    if progress_callback
      # Send the canvas update FIRST - no intermediate message
      progress_callback.call({
        type: "canvas_update",
        canvas_type: canvas_name,
        canvas_data: canvas_data
      })
      
      # Small delay to ensure canvas broadcast completes first
      sleep(0.1)
    end

    # Always set the canvas so it's included in the final response as backup
    safe_load_canvas(canvas_name, canvas_data)
    
    # Mark that we already broadcast this canvas to prevent double broadcast
    @canvas_already_broadcast = true
    
    # Return success
    { success: true, message: nil }
  end

  def safe_load_canvas(canvas_name, data = {})
    if @agent_loadout && !@agent_loadout.canvas_allowed?(canvas_name)
      Rails.logger.warn "Canvas #{canvas_name} not allowed by agent loadout"
      return false
    end

    @suggested_canvas = canvas_name
    @canvas_data = data
    true
  end

  # Broadcast auto-loaded canvas to frontend (before Amos responds)
  def broadcast_auto_canvas(canvas_type, progress_callback)
    return if @canvas_already_broadcast
    return if canvas_type.nil? || canvas_type == :keep_current

    Rails.logger.info "[Scout] Auto-loading canvas: #{canvas_type}"
    
    # Broadcast via progress callback
    progress_callback&.call({
      type: "auto_canvas",
      canvas: canvas_type.to_s,
      message: "Loading #{canvas_type.to_s.humanize}..."
    })

    # Also broadcast via ActionCable for immediate UI update
    if @session_id
      ScoutChannel.broadcast_to(@session_id, {
        type: 'auto_canvas_load',
        canvas: canvas_type.to_s,
        timestamp: Time.current.iso8601
      })
    end

    @canvas_already_broadcast = true
  rescue => e
    Rails.logger.warn "[Scout] Auto-canvas broadcast failed: #{e.message}"
  end

  # Inject canvas context into system prompt (compact, ~30-50 tokens)
  def inject_canvas_context(system_prompt, context_inject)
    return system_prompt if context_inject.blank?

    # Insert at the very beginning for visibility
    <<~PROMPT
      #{context_inject.strip}

      #{system_prompt}
    PROMPT
  end

  def enhance_message_with_canvas_context(message, canvas)
    # Add user context to message (not in cached system prompt for better cache sharing)
    user_name = @user.respond_to?(:first_name) ? "#{@user.first_name} #{@user.last_name}" : @user.to_s
    
    # Use BusinessProfile name if available, otherwise fall back to Entity name
    business_profile = @user&.business_profile || @entity&.business_profiles&.first
    business_name = business_profile&.name.presence || (@entity.respond_to?(:name) ? @entity.name : @entity.to_s)
    
    user_context_prefix = "[User Context: #{user_name} from #{business_name}]\n\n"
    
    # Check for attached files in the context
    enhanced_message = message
    if @context[:attached_files] && @context[:attached_files].any?
      Rails.logger.info "🔍 Found attached files in context: #{@context[:attached_files].inspect}"
      
      file_info = @context[:attached_files].map do |file|
        "📎 #{file['filename'] || file[:filename]} (asset_id: #{file['asset_id'] || file[:asset_id]})"
      end.join("\n")
      
      enhanced_message = "#{message}\n\n[ATTACHED FILES]:\n#{file_info}\n\nIMPORTANT: Use the read_document tool with the asset_id to access these files!"
    end

    # If no canvas, just add user context
    return user_context_prefix + enhanced_message unless canvas.present?

    # Convert ActionController::Parameters to hash if needed
    if canvas.respond_to?(:to_unsafe_h)
      canvas = canvas.to_unsafe_h
    elsif canvas.respond_to?(:to_h) && !canvas.is_a?(String) && !canvas.is_a?(Hash)
      canvas = canvas.to_h
    end

    # Handle both old format (string) and new format (hash with type and data)
    if canvas.is_a?(Hash)
      canvas_type = canvas["type"] || canvas[:type]
      canvas_data = canvas["data"] || canvas[:data] || {}

      # Also convert canvas_data if it's ActionController::Parameters
      if canvas_data.respond_to?(:to_unsafe_h)
        canvas_data = canvas_data.to_unsafe_h
      elsif canvas_data.respond_to?(:to_h) && !canvas_data.is_a?(Hash)
        canvas_data = canvas_data.to_h
      end
    else
      canvas_type = canvas
      canvas_data = {}
    end

    Rails.logger.debug "Canvas context: #{canvas_type}" if canvas_type

    context_hints = {
      "landing_page_viewer" => "\n[Context: User is viewing landing pages]",
      "landing_page_editor" => lambda { |data|
        landing_page_id = data["landing_page_id"] || data[:landing_page_id]
        Rails.logger.info "📄 Landing page editor - ID: #{landing_page_id}"
        if landing_page_id
          "\n[Context: User is editing landing page ID #{landing_page_id}. Use update_landing_page_content tool to modify this page, not generate_ai_landing_page.]"
        else
          "\n[Context: User is in landing page editor]"
        end
      },
      "document_viewer" => lambda { |data|
        asset_id = data["asset_id"] || data[:asset_id]
        filename = data["filename"] || data[:filename]
        if asset_id
          "\n[Context: User is viewing document '#{filename}' (asset_id: #{asset_id}). When user says 'this' or 'this document', they mean THIS specific document. Use read_document tool with asset_id #{asset_id} to access its content.]"
        else
          "\n[Context: User is viewing a document]"
        end
      },
      "document_search_results" => lambda { |data|
        query = data["query"] || data[:query]
        total = data["total_results"] || data[:total_results]
        "\n[Context: User is viewing document search results for '#{query}' (#{total} results found)]"
      },
      "campaign_viewer" => "\n[Context: User is viewing email campaigns]",
      "email_campaign_viewer" => "\n[Context: User is viewing email campaigns]",
      "contact_viewer" => "\n[Context: User is viewing contacts]",
      "analytics_dashboard" => "\n[Context: User is viewing analytics]",
      "parallel_tasks" => "\n[Context: User is viewing the task monitor]",
      "dynamic_canvas" => lambda { |data|
        title = data["title"] || data[:title] || "dynamic data"
        "\n[Context: User is viewing #{title}]"
      }
    }

    hint = context_hints[canvas_type]
    hint_text = hint.is_a?(Proc) ? hint.call(canvas_data) : hint

    # Add user context prefix + enhanced message (with attached files) + canvas hint
    enhanced = user_context_prefix + enhanced_message + (hint_text || "")
    Rails.logger.info "✅ Enhanced message with user context: #{enhanced}"

    enhanced
  end

  def format_conversation_for_ai(history, current_message)
    Rails.logger.info "🔍 format_conversation_for_ai called with #{history.length} history messages"

    messages = []
    
    # OPTION 1: Extract important IDs/references BEFORE truncation
    working_context = extract_working_context(history)
    
    # OPTION 3: Also retrieve any previously stored context from memory
    # This helps when conversation continues after a gap
    stored_context = retrieve_working_context_from_memory
    if stored_context.any?
      # Merge stored context with current extraction
      stored_context.each do |key, values|
        working_context[key] ||= []
        working_context[key] = (working_context[key] + values).uniq.first(10)
      end
    end
    
    # OPTION 2: Increased from 6 to 12 messages (6 exchanges) for better context retention
    max_messages = 12
    truncated_history = history.last(max_messages)

    if history.length > max_messages
      Rails.logger.info "⚡ Truncated conversation: #{history.length} → #{max_messages} messages"
    end
    
    # Store updated working context in memory for persistence
    store_working_context_in_memory(working_context) if working_context.any?

    # Add working context as first message if we have references from truncated messages
    # OR if we have stored context from a previous session
    needs_context_injection = (working_context.any? && history.length > max_messages) || 
                              (stored_context.any? && history.length < 4)
    
    if needs_context_injection && working_context.any?
      context_text = format_working_context(working_context)
      messages << {
        role: "user",
        content: [{ type: "text", text: "[Working Context - Recent References]\n#{context_text}" }]
      }
      messages << {
        role: "assistant", 
        content: [{ type: "text", text: "I'll keep those references in mind." }]
      }
      Rails.logger.info "📎 Injected working context: #{working_context.keys.join(', ')}"
    end

    # Add recent history, filtering out messages with nil content
    truncated_history.each do |msg|
      content = msg["content"] || msg[:content]
      role = msg["role"] || msg[:role]

      # Skip messages with nil or empty content
      next if content.nil? || content.to_s.strip.empty?

      # CRITICAL: Clean internal coordination markers from history
      # These should NEVER be seen by models as they cause confusion/repetition
      content = clean_internal_markers(content.to_s)
      
      # Skip messages that became empty after cleaning
      next if content.strip.empty?

      # Compress long tool-related messages to save tokens, but preserve IDs
      if content.length > 1000
        content_preview = compress_message_preserve_ids(content)
        Rails.logger.debug "⚡ Compressed message: #{content.length} → #{content_preview.length} chars"
      else
        content_preview = content
      end

      formatted_message = {
        role: role == "user" ? "user" : "assistant",
        content: [{ type: "text", text: content_preview }]
      }

      messages << formatted_message
    end

    # Add current message only if it's not already in the history
    last_user_message = messages.reverse.find { |m| m[:role] == "user" }
    if !last_user_message || last_user_message[:content].first[:text] != current_message
      messages << {
        role: "user",
        content: [{ type: "text", text: current_message }]
      }
    end

    # Log final token estimate
    estimated_tokens = messages.sum { |m| m[:content].first[:text].length / 4 }
    Rails.logger.info "📊 Conversation: #{messages.length} messages, ~#{estimated_tokens} tokens"

    messages
  end

  # OPTION 1: Extract important IDs and references from conversation history before truncation
  def extract_working_context(history)
    context = {
      documents: [],
      campaigns: [],
      landing_pages: [],
      contacts: [],
      agents: []
    }
    
    history.each do |msg|
      content = (msg["content"] || msg[:content]).to_s
      
      # Extract document references (asset_id, rag_document_id, document_id)
      content.scan(/(?:asset_id|rag_document_id|document_id)[:\s]*(\d+)/i).each do |match|
        context[:documents] << match[0].to_i
      end
      
      # Extract document names with IDs from formatted results
      content.scan(/["']([^"']+)["']\s*\((?:id|asset_id)[:\s]*(\d+)/i).each do |name, id|
        context[:documents] << { id: id.to_i, name: name.strip }
      end
      
      # Extract campaign IDs
      content.scan(/campaign[_\s]?id[:\s]*(\d+)/i).each do |match|
        context[:campaigns] << match[0].to_i
      end
      
      # Extract landing page IDs
      content.scan(/landing[_\s]?page[_\s]?id[:\s]*(\d+)/i).each do |match|
        context[:landing_pages] << match[0].to_i
      end
      
      # Extract contact IDs
      content.scan(/contact[_\s]?id[:\s]*(\d+)/i).each do |match|
        context[:contacts] << match[0].to_i
      end
      
      # Extract agent references
      content.scan(/agent[_\s]?(?:type|name)[:\s]*["']?(\w+)["']?/i).each do |match|
        context[:agents] << match[0]
      end
    end
    
    # Deduplicate and clean up
    context.transform_values! do |values|
      values.uniq.first(10) # Keep max 10 of each type
    end
    
    # Remove empty categories
    context.reject! { |_, v| v.empty? }
    
    context
  end
  
  # Format working context for injection into conversation
  def format_working_context(context)
    lines = []
    
    if context[:documents]&.any?
      doc_refs = context[:documents].map do |doc|
        doc.is_a?(Hash) ? "#{doc[:name]} (asset_id: #{doc[:id]})" : "asset_id: #{doc}"
      end
      lines << "📄 Documents: #{doc_refs.join(', ')}"
    end
    
    if context[:campaigns]&.any?
      lines << "📧 Campaigns: #{context[:campaigns].map { |id| "id: #{id}" }.join(', ')}"
    end
    
    if context[:landing_pages]&.any?
      lines << "🌐 Landing Pages: #{context[:landing_pages].map { |id| "id: #{id}" }.join(', ')}"
    end
    
    if context[:contacts]&.any?
      lines << "👤 Contacts: #{context[:contacts].map { |id| "id: #{id}" }.join(', ')}"
    end
    
    if context[:agents]&.any?
      lines << "🤖 Agents: #{context[:agents].join(', ')}"
    end
    
    lines.join("\n")
  end
  
  # OPTION 3: Store working context in unified memory for persistence across truncation
  def store_working_context_in_memory(context)
    return unless @user && @entity && @session_id
    
    begin
      # Store in Redis with session scope for quick access
      redis_key = "scout:working_context:#{@session_id}"
      
      # Merge with existing context (don't overwrite)
      existing = $redis.get(redis_key)
      if existing
        existing_context = JSON.parse(existing, symbolize_names: true) rescue {}
        context.each do |key, values|
          existing_context[key] ||= []
          existing_context[key] = (existing_context[key] + values).uniq.first(10)
        end
        context = existing_context
      end
      
      $redis.setex(redis_key, 1.hour.to_i, context.to_json)
      Rails.logger.debug "📎 Stored working context in memory"
    rescue => e
      Rails.logger.warn "Failed to store working context: #{e.message}"
    end
  end
  
  # Retrieve working context from memory (for use when history is very short)
  def retrieve_working_context_from_memory
    return {} unless @session_id
    
    begin
      redis_key = "scout:working_context:#{@session_id}"
      stored = $redis.get(redis_key)
      return {} unless stored
      
      JSON.parse(stored, symbolize_names: true)
    rescue => e
      Rails.logger.warn "Failed to retrieve working context: #{e.message}"
      {}
    end
  end
  
  # Compress message content while preserving important IDs and references
  def compress_message_preserve_ids(content)
    # Extract all IDs and references first
    preserved_refs = []
    
    # Preserve document references
    content.scan(/(?:asset_id|rag_document_id|document_id)[:\s]*\d+/i).each do |ref|
      preserved_refs << ref
    end
    
    # Preserve named entities with IDs
    content.scan(/["'][^"']+["']\s*\([^)]*id[^)]*\)/i).each do |ref|
      preserved_refs << ref
    end
    
    # Preserve campaign/landing page/contact IDs
    content.scan(/(?:campaign|landing_page|contact)[_\s]?id[:\s]*\d+/i).each do |ref|
      preserved_refs << ref
    end
    
    # Build compressed version
    # Take first 400 chars of content
    compressed = content.first(400)
    
    # If we have preserved refs that aren't in the first 400 chars, append them
    missing_refs = preserved_refs.reject { |ref| compressed.include?(ref) }
    if missing_refs.any?
      compressed += "... [IDs: #{missing_refs.uniq.join(', ')}]"
    else
      compressed += "... [truncated]" unless content.length <= 400
    end
    
    compressed
  end

  # Extract source information from tool results
  def extract_sources_from_result(tool_name, result)
    return unless result[:success]

    case tool_name
    when "query_document_content"
      # Unified document query - handles both session and RAG sources
      source_type = result[:source] # 'session', 'rag', or 'none'

      if result[:results].is_a?(Array) && result[:results].any?
        result[:results].each do |chunk|
          source_data = {
            tool: "query_document_content"
          }

          # Determine source type from result
          if source_type == 'session'
            source_data[:type] = "session_document"
            source_data[:filename] = chunk[:filename] || chunk.dig(:metadata, :filename)
            source_data[:asset_id] = chunk.dig(:metadata, :asset_id)
          elsif source_type == 'rag'
            source_data[:type] = "rag_document"
            source_data[:filename] = chunk[:filename] || chunk.dig(:metadata, :filename)
            source_data[:page] = chunk.dig(:metadata, :page)
            source_data[:section] = chunk.dig(:metadata, :section)
            source_data[:similarity_score] = chunk[:similarity_score]
          end

          add_source(source_data) if source_data[:filename]
        end
      end

    when "query_rag_store"
      # RAG query tool returns sources array
      if result[:sources].present?
        result[:sources].each do |filename|
          add_source({
            type: "rag_document",
            filename: filename,
            tool: "query_rag_store"
          })
        end
      end

      # Also extract chunk-level details if available
      if result[:results].is_a?(Array)
        result[:results].each do |chunk|
          if chunk[:metadata] && chunk[:metadata][:filename]
            add_source({
              type: "rag_document",
              filename: chunk[:metadata][:filename],
              page: chunk[:metadata][:page],
              section: chunk[:metadata][:section],
              similarity_score: chunk[:similarity_score],
              tool: "query_rag_store"
            })
          end
        end
      end

    when "read_document"
      # Document read tool
      if result[:filename].present?
        add_source({
          type: "document",
          filename: result[:filename],
          asset_id: result[:asset_id],
          content_type: result[:content_type],
          tool: "read_document"
        })
      end

    when "get_data"
      # Data retrieval tool - track what data was fetched
      if result[:records].present?
        add_source({
          type: "database",
          object_type: result[:object_type],
          record_count: result[:record_count],
          tool: "get_data"
        })
      end

    when "web_search_tool"
      # Web search results - track URLs and titles
      if result[:results].is_a?(Array) && result[:results].any?
        result[:results].each do |search_result|
          add_source({
            type: "web_search",
            url: search_result[:url] || search_result["url"],
            title: search_result[:title] || search_result["title"],
            snippet: search_result[:snippet] || search_result["snippet"],
            tool: "web_search_tool"
          })
        end
      end

    when "execute_integration", "invoke_operation"
      # Integration API calls - track which services were used
      add_source({
        type: "integration",
        integration_name: result[:integration_name] || result[:service_name],
        operation: result[:operation] || result[:operation_name],
        record_count: result[:record_count] || result[:results]&.length,
        tool: tool_name
      })

    when "retrieve_history", "search_history"
      # Conversation history - track how many messages were referenced
      if result[:messages].is_a?(Array) && result[:messages].any?
        add_source({
          type: "conversation",
          message_count: result[:messages].length,
          time_range: result[:time_range],
          tool: tool_name
        })
      end

    when "query_metric", "aggregate_artifact_data"
      # Analytics and metrics - track what data was analyzed
      add_source({
        type: "analytics",
        metric_name: result[:metric_name] || result[:artifact_type],
        data_points: result[:data_points]&.length || result[:record_count],
        time_range: result[:time_range],
        tool: tool_name
      })

    when "get_billing_info", "view_invoices"
      # Billing and subscription data
      add_source({
        type: "billing",
        data_type: tool_name == "get_billing_info" ? "Subscription Info" : "Invoices",
        record_count: result[:invoices]&.length || 1,
        tool: tool_name
      })

    when "get_workflow_context"
      # Workflow context - files and data from current workflow
      if result[:files].present? || result[:context_data].present?
        add_source({
          type: "workflow",
          file_count: result[:files]&.length || 0,
          context_keys: result[:context_data]&.keys&.length || 0,
          tool: "get_workflow_context"
        })
      end
    end
  rescue => e
    Rails.logger.error "Error extracting sources: #{e.message}"
  end

  # Add a source to the accumulated sources list
  def add_source(source_data)
    # Deduplicate based on source type
    case source_data[:type]
    when "rag_document", "session_document", "document"
      # For documents, deduplicate by filename
      key = source_data[:filename]
      existing = @sources.find { |s| s[:filename] == key }

      if existing
        # Merge additional details (like page numbers)
        if source_data[:page] && !existing[:pages]&.include?(source_data[:page])
          existing[:pages] ||= []
          existing[:pages] << source_data[:page]
        end
      else
        @sources << source_data
      end

    when "database"
      # For database, deduplicate by object_type
      key = source_data[:object_type]
      existing = @sources.find { |s| s[:type] == "database" && s[:object_type] == key }

      if existing
        # Update record count if new data has more records
        existing[:record_count] = [existing[:record_count], source_data[:record_count]].max
      else
        @sources << source_data
      end

    when "web_search"
      # For web search, deduplicate by URL
      key = source_data[:url]
      existing = @sources.find { |s| s[:type] == "web_search" && s[:url] == key }
      @sources << source_data unless existing

    when "integration"
      # For integrations, deduplicate by integration name + operation
      key = "#{source_data[:integration_name]}_#{source_data[:operation]}"
      existing = @sources.find { |s|
        s[:type] == "integration" &&
        "#{s[:integration_name]}_#{s[:operation]}" == key
      }

      if existing
        # Update record count if available
        existing[:record_count] = [existing[:record_count] || 0, source_data[:record_count] || 0].max
      else
        @sources << source_data
      end

    when "conversation", "analytics", "billing", "workflow"
      # For these types, only add once per type (deduplicate by type)
      existing = @sources.find { |s| s[:type] == source_data[:type] }

      if existing
        # Merge counts and update with latest data
        existing[:message_count] = [existing[:message_count] || 0, source_data[:message_count] || 0].max
        existing[:data_points] = [existing[:data_points] || 0, source_data[:data_points] || 0].max
        existing[:record_count] = [existing[:record_count] || 0, source_data[:record_count] || 0].max
        existing[:file_count] = [existing[:file_count] || 0, source_data[:file_count] || 0].max
      else
        @sources << source_data
      end

    else
      # Unknown type, just add without deduplication
      @sources << source_data
    end
  end

  # ═══════════════════════════════════════════════════════════════
  # INTEGRATION CONFIDENCE HELPERS (Learn Before Act)
  # ═══════════════════════════════════════════════════════════════

  # Check if this tool call should trigger a knowledge consultation suggestion
  def should_suggest_knowledge_consultation?(tool_name, args)
    return false unless tool_name.in?(['execute_integration', 'invoke_operation'])
    
    operation_id = args['operation_id'] || args['operation'] || ''
    
    # These integrations have complex query patterns that often cause issues
    complex_integrations = ['quickbooks', 'hubspot', 'salesforce']
    integration_match = complex_integrations.find { |i| operation_id.downcase.include?(i) }
    
    return false unless integration_match
    
    # Check if using potentially problematic parameters
    params = args['params'] || args['parameters'] || {}
    
    # QuickBooks-specific: Check if using wrong parameter format
    if integration_match == 'quickbooks'
      # QuickBooks requires 'query' parameter with SQL-like syntax
      # Common mistake: passing status, limit as direct params
      if params['status'].present? || params['limit'].present?
        return true unless params['query'].present?
      end
    end
    
    false
  end

  # Get guidance and potentially correct parameters for integration operations
  def get_integration_knowledge_suggestion(tool_name, args)
    operation_id = args['operation_id'] || args['operation'] || ''
    params = args['params'] || args['parameters'] || {}
    
    # QuickBooks parameter correction
    if operation_id.downcase.include?('quickbooks')
      return quickbooks_parameter_guidance(operation_id, params, args)
    end
    
    nil
  end

  # Provide QuickBooks-specific guidance and parameter correction
  def quickbooks_parameter_guidance(operation_id, params, original_args)
    # Check for common mistakes
    if params['status'].present? && !params['query'].present?
      status = params['status'].to_s.downcase
      
      # Build corrected query
      if operation_id.include?('invoice')
        entity = 'Invoice'
        case status
        when 'open', 'unpaid'
          where_clause = "Balance > '0'"
        when 'paid', 'closed'
          where_clause = "Balance = '0'"
        when 'overdue'
          where_clause = "Balance > '0' AND DueDate < '#{Date.today}'"
        else
          where_clause = nil
        end
        
        if where_clause
          # Correct the parameters
          corrected_params = { 'query' => "SELECT * FROM #{entity} WHERE #{where_clause}" }
          corrected_params['query'] += " MAXRESULTS #{params['limit']}" if params['limit'].present?
          
          corrected_args = original_args.deep_dup
          corrected_args['params'] = corrected_params
          
          return {
            should_warn: false, # Silent correction
            corrected_args: corrected_args,
            guidance: nil
          }
        end
      elsif operation_id.include?('customer')
        corrected_params = { 'query' => "SELECT * FROM Customer" }
        if params['status']&.downcase == 'active'
          corrected_params['query'] += " WHERE Active = true"
        end
        corrected_params['query'] += " MAXRESULTS #{params['limit']}" if params['limit'].present?
        
        corrected_args = original_args.deep_dup
        corrected_args['params'] = corrected_params
        
        return {
          should_warn: false,
          corrected_args: corrected_args,
          guidance: nil
        }
      end
    end
    
    # No correction needed
    nil
  end

  # ============================================================================
  # MISTAKE LEARNING SYSTEM
  # Prevents Amos from repeating the same errors within a session
  # ============================================================================
  
  def initialize_mistake_tracking
    @session_mistakes ||= []
    @tool_failure_patterns ||= {}
  end

  def record_tool_mistake(tool_name, args, error_message)
    initialize_mistake_tracking
    
    # Generate actionable suggested fix based on error pattern
    suggested_fix = generate_suggested_fix(tool_name, args, error_message)
    
    mistake = {
      tool: tool_name,
      args: args.to_json.truncate(200),
      error: error_message.to_s.truncate(200),
      suggested_fix: suggested_fix,
      timestamp: Time.current
    }
    
    @session_mistakes << mistake
    
    # Track failure patterns
    pattern_key = "#{tool_name}:#{extract_error_pattern(error_message)}"
    @tool_failure_patterns[pattern_key] ||= 0
    @tool_failure_patterns[pattern_key] += 1
    
    Rails.logger.info "📝 Recorded mistake: #{tool_name} - #{error_message.to_s.truncate(60)}"
    Rails.logger.info "💡 Suggested fix: #{suggested_fix}" if suggested_fix.present?
  end
  
  # Generate actionable fix suggestions based on error patterns
  # The goal is to tell Amos WHAT TO DO, not just what went wrong
  def generate_suggested_fix(tool_name, args, error_message)
    error = error_message.to_s.downcase
    args_hash = args.is_a?(Hash) ? args : (JSON.parse(args.to_s) rescue {})
    
    # Pattern: Missing required field
    if error.match?(/missing required fields?:\s*(\w+)/i)
      missing_field = $1
      return "Add the '#{missing_field}' parameter to your call. Example: #{missing_field}: \"value\""
    end
    
    # Pattern: Invalid field value
    if error.match?(/invalid (value|type) for (field )?['"]?(\w+)['"]?/i)
      field = $3
      return "Check the type/format for '#{field}'. Use list_operations to see expected types."
    end
    
    # Pattern: Connection/Integration not found
    if error.match?(/connection not found|integration not found/i)
      return "Use list_connections to find valid connection IDs. The integration may not be connected."
    end
    
    # Tool-specific patterns
    case tool_name
    when 'execute_integration'
      if error.include?('missing') && error.include?('integration')
        return "Use: execute_integration(integration: \"slug\", operation: \"op_name\", params: {...}). The 'integration' field requires the lowercase slug like 'stripe', not 'Stripe' or an ID."
      elsif error.include?('operation') && error.include?('not found')
        return "Use list_operations(integration_slug: \"slug\") to see available operations."
      elsif error.include?('status') || error.include?('query')
        return "This API may use different field names. Use query_integration_knowledge or ask an integration expert."
      end
    when 'create_object', 'update_object'
      if error.include?('unknown attribute') || error.include?('no column')
        return "Use get_schema(object_type: \"type\") to see valid field names."
      end
    when 'load_canvas'
      if error.include?('not found') || error.include?('invalid')
        return "Check available canvases. For module canvases use format: module_{slug}_list or module_{slug}_form"
      end
    end
    
    # Generic fallback: If same tool has failed multiple times, suggest asking for help
    if @tool_failure_patterns["#{tool_name}:#{extract_error_pattern(error_message)}"].to_i >= 2
      return "This tool has failed multiple times. Consider: 1) Use query_integration_knowledge to understand the API, or 2) Delegate to a specialist agent."
    end
    
    nil
  end

  def extract_error_pattern(error_message)
    msg = error_message.to_s.downcase
    
    case msg
    when /status.*not.*valid|invalid.*status/i
      'invalid_status_field'
    when /query.*error|syntax.*error/i
      'query_syntax'
    when /not.*found|404/i
      'resource_not_found'
    when /unauthorized|401/i
      'auth_error'
    when /rate.*limit|429/i
      'rate_limited'
    when /bad.*request|400/i
      'bad_request'
    else
      'unknown'
    end
  end

  def inject_mistake_learning_context(tool_results, progress_callback)
    initialize_mistake_tracking
    return if @session_mistakes.empty?
    
    # Find recent failures
    recent_failures = @session_mistakes.last(3)
    return if recent_failures.empty?
    
    # Build learning context with ACTIONABLE fixes
    learning_hints = recent_failures.map do |m|
      hint = "❌ #{m[:tool]} failed: #{m[:error]}"
      
      # Add the suggested fix if we have one - THIS IS THE KEY
      if m[:suggested_fix].present?
        hint += "\n💡 FIX: #{m[:suggested_fix]}"
      end
      
      hint
    end.compact.uniq
    
    return if learning_hints.empty?
    
    # Log for debugging
    Rails.logger.info "💡 Injecting learning context: #{learning_hints.join('; ')}"
  end

  def learn_from_session_mistakes(tool_calls, tool_results)
    initialize_mistake_tracking
    return if @session_mistakes.empty?
    
    # Store mistakes in user's session memory for future reference
    begin
      if @user && @entity
        mistake_summary = @session_mistakes.map do |m|
          "#{m[:tool]}: #{m[:error]}"
        end.join("; ")
        
        # Store in a lightweight way - could be enhanced to use RAG later
        Rails.logger.info "📚 Session learning: #{mistake_summary.truncate(200)}"
        
        # Persist to integration-specific knowledge if it's an integration error
        integration_mistakes = @session_mistakes.select { |m| m[:tool] == 'execute_integration' }
        if integration_mistakes.any?
          persist_integration_learning(integration_mistakes)
        end
      end
    rescue => e
      Rails.logger.warn "Could not persist session learning: #{e.message}"
    end
  end

  def persist_integration_learning(mistakes)
    return if mistakes.empty?
    
    # Group by integration
    mistakes.each do |mistake|
      begin
        args = JSON.parse(mistake[:args]) rescue {}
        integration_slug = args['integration']
        next unless integration_slug
        
        # Find or create an integration learning record
        # This could be enhanced to store in RAG or a dedicated table
        learning_content = <<~LEARNING
          ## Integration Mistake - #{Time.current.strftime('%Y-%m-%d %H:%M')}
          
          **Integration**: #{integration_slug}
          **Operation**: #{args['operation']}
          **Error**: #{mistake[:error]}
          
          **Lesson Learned**: Avoid this parameter combination in future calls.
        LEARNING
        
        Rails.logger.info "📖 Persisting integration learning for #{integration_slug}"
        
        # Could store this in the integration agent's knowledge base
        # For now, just log it
      rescue => e
        Rails.logger.debug "Could not persist integration learning: #{e.message}"
      end
    end
  end

  def summarize_session_mistakes
    initialize_mistake_tracking
    return "No specific errors recorded." if @session_mistakes.empty?
    
    # Group mistakes by type
    grouped = @session_mistakes.group_by { |m| m[:tool] }
    
    summary = grouped.map do |tool, mistakes|
      unique_errors = mistakes.map { |m| m[:error] }.uniq.first(2)
      "• **#{tool}**: #{unique_errors.join(', ')}"
    end.join("\n")
    
    summary
  end

  # ============================================================================
  # SMART LOOP DETECTION
  # Analyzes tool call history to detect actual loops vs legitimate sequences
  # ============================================================================
  
  def detect_tool_loop(history)
    return [false, nil] if history.length < LOOP_DETECTION_THRESHOLD
    
    # -------------------------------------------------------------------------
    # CHECK 1: Same exact call (tool + args) repeated 3+ times
    # This catches: "create_object with EXACT same data" being called repeatedly
    # -------------------------------------------------------------------------
    call_signatures = history.map { |h| "#{h[:name]}:#{h[:args_hash]}" }
    signature_counts = call_signatures.tally
    
    repeated_call = signature_counts.find { |sig, count| count >= LOOP_DETECTION_THRESHOLD }
    if repeated_call
      tool_name = repeated_call[0].split(':').first
      return [true, "I called `#{tool_name}` with the same parameters #{repeated_call[1]} times."]
    end
    
    # -------------------------------------------------------------------------
    # CHECK 2: Same tool failing repeatedly (3+ failures in a row)
    # This catches: trying the same approach and failing each time
    # -------------------------------------------------------------------------
    recent = history.last(6)
    if recent.length >= 3
      failed_calls = recent.select { |h| !h[:success] }
      if failed_calls.length >= 3
        # Check if it's the same tool failing
        failing_tools = failed_calls.map { |h| h[:name] }
        most_common_failure = failing_tools.tally.max_by { |_, count| count }
        
        if most_common_failure && most_common_failure[1] >= 3
          return [true, "`#{most_common_failure[0]}` failed #{most_common_failure[1]} times in a row."]
        end
      end
    end
    
    # -------------------------------------------------------------------------
    # CHECK 3: Cyclical pattern detection (A→B→A→B→A→B)
    # This catches: oscillating between two tools without progress
    # -------------------------------------------------------------------------
    if history.length >= 6
      recent_tools = history.last(6).map { |h| h[:name] }
      
      # Check for 2-cycle: A,B,A,B,A,B
      if recent_tools[0] == recent_tools[2] && recent_tools[2] == recent_tools[4] &&
         recent_tools[1] == recent_tools[3] && recent_tools[3] == recent_tools[5] &&
         recent_tools[0] != recent_tools[1]
        return [true, "I was alternating between `#{recent_tools[0]}` and `#{recent_tools[1]}` without progress."]
      end
      
      # Check for 3-cycle: A,B,C,A,B,C
      if recent_tools[0] == recent_tools[3] && 
         recent_tools[1] == recent_tools[4] && 
         recent_tools[2] == recent_tools[5]
        return [true, "I was cycling through `#{recent_tools[0..2].join(' → ')}` without progress."]
      end
    end
    
    # -------------------------------------------------------------------------
    # NO LOOP DETECTED
    # This is likely a legitimate sequential operation (e.g., creating 50 contacts)
    # -------------------------------------------------------------------------
    [false, nil]
  end
end
