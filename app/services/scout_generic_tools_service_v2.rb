class ScoutGenericToolsServiceV2
  attr_reader :user, :entity, :session_id, :agent_loadout
  attr_accessor :suggested_canvas, :canvas_data
  
  def initialize(user, entity, session_id, agent_loadout: nil)
    @user = user
    @entity = entity
    @session_id = session_id
    @agent_loadout = agent_loadout
    @ai_service = BedrockService.new
    @ai_provider_name = Rails.application.config.ai_service.to_s.capitalize
    @tool_catalog = Tools::ToolCatalog.instance
    @suggested_canvas = nil
    @canvas_data = {}
    @saved_message_content = Set.new
    @messages_saved_during_streaming = false
  end
  
  def process_message_with_tools_streaming(user_message, progress_callback, conversation_history = [], current_canvas = nil)
    begin
      # Build system prompt
      system_prompt = build_system_prompt(current_canvas)
      
      # Enhance user message with context
      enhanced_message = enhance_message_with_canvas_context(user_message, current_canvas)
      
      # Format conversation
      conversation_messages = format_conversation_for_ai(conversation_history, enhanced_message)
      
      Rails.logger.info "Sending #{conversation_messages.length} messages to #{@ai_provider_name}"
      progress_callback&.call("🤖 Processing request...")
      
      # Get filtered tools based on agent loadout
      tools = get_filtered_tools
      Rails.logger.info "Using #{tools.length} tools (filtered by agent loadout)"
      
      # Stream the response
      accumulated_content = ""
      tool_calls = []
      streaming_started = false
      
      @ai_service.send_message_streaming(
        system_prompt,
        conversation_messages,
        max_tokens: 25000,
        temperature: 0.7,
        json_mode: false,
        tools: tools
      ) do |chunk|
        handle_streaming_chunk(chunk, accumulated_content, tool_calls, streaming_started, progress_callback)
        streaming_started = true if chunk[:type] == :content
      end
      
      # Execute any tool calls
      if tool_calls.any?
        tool_results = execute_tool_calls(tool_calls, progress_callback)
        
        # Get final response after tools
        final_response = get_continuation_after_tools(
          system_prompt, 
          conversation_messages, 
          tool_calls, 
          tool_results, 
          progress_callback
        )
        
        return final_response
      else
        # No tools used, return the accumulated content
        {
          final_response: {
            message: accumulated_content,
            message_already_saved: @messages_saved_during_streaming
          },
          canvas_type: @suggested_canvas || 'conversation',
          canvas_data: @canvas_data,
          tools_used: []
        }
      end
    rescue => e
      Rails.logger.error "ScoutGenericToolsServiceV2 error: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      
      {
        final_response: {
          message: "I encountered an error: #{e.message}",
          error: true
        },
        canvas_type: 'conversation',
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
    if tool_name == 'load_canvas'
      return execute_load_canvas(args)
    end
    
    # Create context that will be shared with the tool
    tool_context = { 
      session_id: @session_id,
      canvas_suggestion: nil,
      canvas_data: {}
    }
    
    # Execute through tool catalog
    result = @tool_catalog.execute_tool(
      tool_name, 
      args,
      user: @user,
      entity: @entity,
      context: tool_context
    )
    
    # Handle any canvas suggestions from tools
    if tool_context[:canvas_suggestion]
      safe_load_canvas(tool_context[:canvas_suggestion], tool_context[:canvas_data] || {})
    end
    
    result
  end
  
  private
  
  def get_filtered_tools
    # Get tools filtered by agent loadout
    @tool_catalog.get_bedrock_tools(agent_loadout: @agent_loadout)
  end
  
  def build_system_prompt(current_canvas = nil)
    ai_identity = case Rails.application.config.ai_service
    when :bedrock
      "You are Amos, the AI business automation assistant powered by AWS Bedrock."
    else
      "You are Amos, the AI business automation assistant."
    end
    
    available_models = ScoutDataRegistry.available_object_types
    
    prompt = <<~PROMPT
      #{ai_identity}
      
      You have access to a comprehensive toolset for managing and automating business operations.
      
      USER CONTEXT:
      - User: #{@user.first_name} #{@user.last_name}
      - Entity: #{@entity.name}
      
      AVAILABLE DATA MODELS: #{available_models.join(', ')}
      
      INTELLIGENT CANVAS:
      You can load data viewers and interactive canvases to display information visually.
      
      CRITICAL: Be concise and helpful. Use tools when needed to accomplish tasks.
      
      For multi-step operations:
      1. Use manage_task_list to create and track your plan
      2. Use get_schema to discover available fields before creating objects
      3. Complete all requested steps - don't stop after gathering data
    PROMPT
    
    # Add agent-specific instructions if using loadout
    if @agent_loadout
      prompt += "\n\n#{@agent_loadout.generate_prompt}"
    end
    
    prompt
  end
  
  def handle_streaming_chunk(chunk, accumulated_content, tool_calls, streaming_started, progress_callback)
    case chunk[:type]
    when :content
      accumulated_content << chunk[:content]
      progress_callback&.call({
        type: 'content_chunk',
        content: chunk[:content]
      })
    when :tool_use_start
      Rails.logger.info "🔧 Tool detected: #{chunk[:tool_name]}"
      tool_calls << {
        id: chunk[:tool_id],
        name: chunk[:tool_name],
        arguments: ""
      }
      progress_callback&.call({
        type: 'tool_start',
        name: chunk[:tool_name]
      })
    when :tool_use
      if tool_calls.any?
        tool_calls.last[:arguments] += chunk[:tool_use].input || ""
      end
    when :message_stop
      # Message complete
      if accumulated_content.present? && !@saved_message_content.include?(accumulated_content.hash)
        progress_callback&.call({
          type: 'save_message',
          content: accumulated_content,
          role: 'assistant'
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
        args = JSON.parse(tool_call[:arguments])
        Rails.logger.info "Executing #{tool_call[:name]} with args: #{args.inspect}"
        
        result = execute_tool_by_name(tool_call[:name], args, progress_callback)
        
        progress_callback&.call({
          type: 'tool_complete',
          name: tool_call[:name],
          success: result[:success] || false
        })
        
        results << result
      rescue => e
        Rails.logger.error "Tool execution failed: #{e.message}"
        results << { success: false, error: e.message }
      end
    end
    
    results
  end
  
  def get_continuation_after_tools(system_prompt, conversation_messages, tool_calls, tool_results, progress_callback)
    # Add tool results to conversation
    conversation_messages << {
      role: 'assistant',
      content: [
        { type: 'text', text: "I'll help you with that." },
        *tool_calls.map.with_index do |tool_call, idx|
          {
            type: 'tool_use',
            tool_use: {
              id: tool_call[:id],
              name: tool_call[:name],
              input: JSON.parse(tool_call[:arguments])
            }
          }
        end
      ]
    }
    
    # Add tool results
    conversation_messages << {
      role: 'user',
      content: tool_calls.map.with_index do |tool_call, idx|
        {
          type: 'tool_result',
          tool_result: {
            tool_use_id: tool_call[:id],
            content: [
              {
                type: 'text',
                text: tool_results[idx].to_json
              }
            ]
          }
        }
      end
    }
    
    # Get continuation
    continuation_message = ""
    continuation_tool_calls = []
    tools = get_filtered_tools
    
    @ai_service.send_message_streaming(
      system_prompt,
      conversation_messages,
      max_tokens: 25000,
      temperature: 0.7,
      json_mode: false,
      tools: tools
    ) do |chunk|
      case chunk[:type]
      when :content
        continuation_message << chunk[:content]
        progress_callback&.call({
          type: 'content_chunk',
          content: chunk[:content]
        })
      when :tool_use_start
        # Handle additional tool calls in continuation
        Rails.logger.info "🔧 Additional tool detected in continuation: #{chunk[:tool_name]}"
        continuation_tool_calls << {
          id: chunk[:tool_id],
          name: chunk[:tool_name],
          arguments: ""
        }
        progress_callback&.call({
          type: 'tool_start',
          name: chunk[:tool_name]
        })
      when :tool_use
        if continuation_tool_calls.any?
          continuation_tool_calls.last[:arguments] += chunk[:tool_use].input || ""
        end
      end
    end
    
    # If there are more tool calls, execute them recursively
    if continuation_tool_calls.any?
      Rails.logger.info "Executing #{continuation_tool_calls.length} additional tools in continuation"
      additional_results = execute_tool_calls(continuation_tool_calls, progress_callback)
      
      # Recursively get the next continuation
      return get_continuation_after_tools(
        system_prompt,
        conversation_messages + [
          {
            role: 'assistant',
            content: continuation_tool_calls.map do |tc|
              {
                type: 'tool_use',
                tool_use: {
                  id: tc[:id],
                  name: tc[:name],
                  input: JSON.parse(tc[:arguments])
                }
              }
            end
          },
          {
            role: 'user',
            content: continuation_tool_calls.map.with_index do |tc, idx|
              {
                type: 'tool_result',
                tool_result: {
                  tool_use_id: tc[:id],
                  content: [
                    {
                      type: 'text',
                      text: additional_results[idx].to_json
                    }
                  ]
                }
              }
            end
          }
        ],
        [],  # No more tool calls to add
        [],  # No more results to add
        progress_callback
      )
    end
    
    {
      final_response: {
        message: continuation_message,
        message_already_saved: false
      },
      canvas_type: @suggested_canvas || 'conversation',
      canvas_data: @canvas_data,
      tools_used: tool_calls.map { |tc| tc[:name] }
    }
  end
  
  def execute_load_canvas(args)
    canvas_name = args['canvas_name'] || args[:canvas_name]
    safe_load_canvas(canvas_name)
    { success: true, message: "Loading #{canvas_name}" }
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
  
  def enhance_message_with_canvas_context(message, canvas_type)
    return message unless canvas_type.present?
    
    context_hints = {
      'landing_page_viewer' => "\n[Context: User is viewing landing pages]",
      'campaign_viewer' => "\n[Context: User is viewing email campaigns]",
      'contact_viewer' => "\n[Context: User is viewing contacts]",
      'analytics_dashboard' => "\n[Context: User is viewing analytics]"
    }
    
    message + (context_hints[canvas_type] || "")
  end
  
  def format_conversation_for_ai(history, current_message)
    Rails.logger.info "🔍 format_conversation_for_ai called with history: #{history.inspect}"
    Rails.logger.info "🔍 Current message: #{current_message}"
    
    messages = []
    
    # Add recent history, filtering out messages with nil content
    history.last(10).each do |msg|
      content = msg['content'] || msg[:content]
      role = msg['role'] || msg[:role]
      
      # Skip messages with nil or empty content
      next if content.nil? || content.to_s.strip.empty?
      
      # Log suspicious messages for debugging
      if role == 'assistant' && content.to_s.downcase == 'hello'
        Rails.logger.warn "🚨 Found suspicious assistant message saying 'hello' - this might be incorrectly saved"
      end
      
      formatted_message = {
        role: role == 'user' ? 'user' : 'assistant',
        content: [{ type: 'text', text: content.to_s }]
      }
      
      Rails.logger.info "🔍 Adding history message: role=#{role}, formatted_role=#{formatted_message[:role]}, content=#{content.to_s.first(50)}"
      
      messages << formatted_message
    end
    
    # Add current message only if it's not already in the history
    # (This can happen when the controller adds the message to history before calling this service)
    last_user_message = messages.reverse.find { |m| m[:role] == 'user' }
    if !last_user_message || last_user_message[:content].first[:text] != current_message
      Rails.logger.info "🔍 Adding current message as it's not in history"
      messages << {
        role: 'user',
        content: [{ type: 'text', text: current_message }]
      }
    else
      Rails.logger.info "🔍 Current message already in history, not adding again"
    end
    
    Rails.logger.info "🔍 Final messages array: #{messages.map { |m| "#{m[:role]}: #{m[:content].first[:text].to_s.first(30)}..." }}"
    
    messages
  end
end
