# Scout AI Service with configurable AI providers
#
# CONFIGURATION:
# To use Grok 4 (default): export AI_PROVIDER=grok && export XAI_API_KEY=your_key
# To use Claude:           export AI_PROVIDER=claude && export ANTHROPIC_API_KEY=your_key
#
# Easy switching:
# - Development: Add to .env file
# - Production: Set environment variables
# - Runtime: ScoutGenericToolsService::AI_PROVIDER = 'claude'

class ScoutGenericToolsService
  # AI Provider Configuration - Easy to switch between providers
  AI_PROVIDER = ENV['AI_PROVIDER'] || 'grok' # Options: 'grok', 'claude'
  
  def initialize(user, entity)
    @user = user
    @entity = entity
    @ai_service = case AI_PROVIDER.downcase
    when 'grok'
      GrokService.new
    when 'claude'
      ClaudeService.new
    else
      raise "Unknown AI provider: #{AI_PROVIDER}. Use 'grok' or 'claude'"
    end
    @ai_provider_name = AI_PROVIDER.downcase == 'grok' ? 'Grok' : 'Claude'
    Rails.logger.info "🤖 Scout using AI provider: #{AI_PROVIDER}"
  end

  # Generic function calling tools for AI providers
  TOOLS = [
    {
      name: "get_data",
      description: "Query any data model with filters and options",
      input_schema: {
        type: "object",
        properties: {
          object_type: {
            type: "string",
            description: "The type of object to query (e.g., 'campaign', 'contact', 'landing_page')"
          },
          filters: {
            type: "object",
            description: "Filters to apply (e.g., {status: 'sent', date_range: 'last_30_days'})"
          },
          options: {
            type: "object",
            description: "Query options (e.g., {limit: 20, order_by: 'created_at desc', include_metrics: true})"
          }
        },
        required: ["object_type"]
      }
    },
    {
      name: "create_object",
      description: "Create a new object of any type",
      input_schema: {
        type: "object",
        properties: {
          object_type: {
            type: "string",
            description: "The type of object to create (e.g., 'campaign', 'contact', 'landing_page')"
          },
          data: {
            type: "object",
            description: "The data for the new object"
          }
        },
        required: ["object_type", "data"]
      }
    },
    {
      name: "get_schema",
      description: "Get the schema and field information for any data model",
      input_schema: {
        type: "object",
        properties: {
          object_type: {
            type: "string",
            description: "The type of object to get schema for (e.g., 'campaign', 'contact')"
          }
        },
        required: ["object_type"]
      }
    }
  ]

  def process_message_with_tools(user_message, conversation_history = [])
    begin
      # Build system prompt with dynamic schema information
      system_prompt = build_system_prompt_with_dynamic_schema
      
      # Prepare conversation messages with history
      conversation_messages = format_conversation_for_ai(conversation_history, user_message)
      
      Rails.logger.info "Sending #{conversation_messages.length} messages to #{@ai_provider_name} (including history)"
      
      # Send to AI service with function calling
      response = @ai_service.send_message(
        system_prompt,
        conversation_messages,
        
        max_tokens: 4000,
        temperature: 0.7
      )
      
      # Parse response for JSON structure with message and tool calls
      if tool_calls = parse_function_calls_from_response(response)
        Rails.logger.info "Detected function calls: #{tool_calls.map { |t| t[:name] }}"
        
        # Execute the tools
        tool_results = execute_tools(tool_calls)
        
        # Send the real tool results back to AI service for an updated response
        final_message = generate_response_with_tool_results(user_message, @parsed_user_message, tool_results)
        
        return {
          message: final_message,
          tools_used: true,
          tools_list: tool_calls.map { |t| t[:name] }.uniq,
          success_count: tool_results.count { |r| r[:success] },
          error_count: tool_results.count { |r| !r[:success] },
          canvas: @suggested_canvas
        }
      else
        # No tools needed, return original response
        return {
          message: @parsed_user_message || response,
          tools_used: false,
          canvas: @suggested_canvas
        }
      end
      
    rescue JSON::ParserError => e
      Rails.logger.error "Scout JSON parsing error: #{e.message}"
      Rails.logger.error "Response that failed to parse: #{response}"
      
      return {
        message: "I understand your request, but I'm having trouble processing it right now. Could you try rephrasing your question?",
        tools_used: false,
        error: 'JSON parsing failed'
      }
    rescue => e
      Rails.logger.error "Scout generic tools error: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      
      return {
        message: "I'm experiencing some technical difficulties. Please try again or let me know if you need help with something else.",
        tools_used: false,
        error: e.message
      }
    end
  end

  def process_message_with_tools_streaming(user_message, progress_callback = nil, conversation_history = [])
    begin
      progress_callback&.call("🧠 Building context with available data models...")
      
      # Build system prompt with dynamic schema information
      system_prompt = build_system_prompt_with_dynamic_schema
      
      # Prepare conversation messages with history
      conversation_messages = format_conversation_for_ai(conversation_history, user_message)
      
      Rails.logger.info "Sending #{conversation_messages.length} messages to #{@ai_provider_name} (including history)"
      progress_callback&.call("🤖 Sending request to #{@ai_provider_name} with conversation context...")
      
      # Send to AI service with function calling
      response = @ai_service.send_message(
        system_prompt,
        conversation_messages,
        
        max_tokens: 4000,
        temperature: 0.7
      )
      
      progress_callback&.call("📝 Parsing #{@ai_provider_name}'s response...")
      
      # Parse response for JSON structure with message and tool calls
      if tool_calls = parse_function_calls_from_response(response)
        Rails.logger.info "Detected function calls: #{tool_calls.map { |t| t[:name] }}"
        
        # Show what tools will be executed
        tool_names = tool_calls.map { |t| t[:name] }.uniq
        if tool_names.include?('get_schema')
          progress_callback&.call("🔍 Discovering database schema...")
        end
        if tool_names.include?('get_data')
          progress_callback&.call("📊 Querying your marketing data...")
        end
        if tool_names.include?('create_object')
          progress_callback&.call("✨ Creating new marketing object...")
        end
        
        # Execute the tools with individual progress updates
        tool_results = execute_tools_with_progress(tool_calls, progress_callback)
        
        progress_callback&.call("🎯 Generating personalized response...")
        
        # Send the real tool results back to AI service for an updated response
        final_message = generate_response_with_tool_results(user_message, @parsed_user_message, tool_results)
        
        return {
          message: final_message,
          tools_used: true,
          tools_list: tool_names,
          success_count: tool_results.count { |r| r[:success] },
          error_count: tool_results.count { |r| !r[:success] }
        }
      else
        # No tools needed, return original response
        return {
          message: @parsed_user_message || response,
          tools_used: false
        }
      end
      
    rescue JSON::ParserError => e
      Rails.logger.error "Scout JSON parsing error: #{e.message}"
      Rails.logger.error "Response that failed to parse: #{response}"
      
      return {
        message: "I understand your request, but I'm having trouble processing it right now. Could you try rephrasing your question?",
        tools_used: false,
        error: 'JSON parsing failed'
      }
    rescue => e
      Rails.logger.error "Scout generic tools error: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      
      return {
        message: "I'm experiencing some technical difficulties. Please try again or let me know if you need help with something else.",
        tools_used: false,
        error: e.message
      }
    end
  end

  private

  def build_system_prompt_with_dynamic_schema
    available_models = ScoutDataRegistry.available_object_types
    
    # Dynamic AI identity based on provider
    ai_identity = case AI_PROVIDER.downcase
    when 'grok'
      "You are Scout, the AI marketing assistant powered by Grok. You have access to a simple, powerful toolset for accessing and creating marketing data."
    when 'claude'
      "You are Scout, the AI marketing assistant powered by Claude. You have access to a simple, powerful toolset for accessing and creating marketing data."
    else
      "You are Scout, the AI marketing assistant. You have access to a simple, powerful toolset for accessing and creating marketing data."
    end
    
    <<~PROMPT
      #{ai_identity}

      USER CONTEXT:
      - User: #{@user.first_name} #{@user.last_name}
      - Entity: #{@entity.name}

      AVAILABLE TOOLS:
      1. get_data(object_type, filters, options) - Query any data model
      2. create_object(object_type, data) - Create new objects  
      3. get_schema(object_type) - Get REAL database schema and field information

      AVAILABLE DATA MODELS:
      #{available_models.join(', ')}

      **ADDITIONAL SERVICES AVAILABLE:**
      
      INTELLIGENT CANVAS:
      You can load data viewers and interactive canvases to display information visually.
      Available canvases: landing_page_viewer, landing_page_generator, contact_viewer, contact_generator,
      campaign_viewer, analytics_dashboard
      
      When users ask to "show", "view", or "see" data, suggest loading the appropriate canvas.
      Example responses with canvas suggestions:
      - "Let me show you your landing pages" → suggest loading landing_page_viewer canvas
      - "Here are your contacts" → suggest loading contact_viewer canvas  
      - "I'll create a landing page for you" → suggest loading landing_page_generator canvas
      
      LANDING PAGE FORM TEMPLATES:
      You can reference predefined form templates when creating landing pages with html_content.
      Available templates: contact_form, newsletter_signup, lead_magnet, demo_request, event_registration, 
      free_trial, quote_request, consultation_booking
      
      Each template provides Bootstrap-styled HTML forms that submit to /api/v1/contacts with proper field names.
      When generating landing page HTML, you can include these forms or create custom forms following the same pattern.
      
      MODEL METADATA:
      All business models have comprehensive metadata including purpose, business context, relationships, 
      and usage examples. This helps you understand how models relate and what they're used for in marketing.

      **CRITICAL: WHEN TO USE TOOLS - BE AGGRESSIVE!**
      
      If the user mentions ANY of these, USE TOOLS IMMEDIATELY:
      - "create a contact" → use create_object("contacts", {email: ..., first_name: ..., last_name: ...})
      - "create a campaign" → use create_object("campaigns", {...})  
      - "show me campaigns" → use get_data("campaigns", ...)
      - "performance" or "metrics" → use get_data with include_metrics: true
      - "recent" → use get_data with date filters

      CONTACT CREATION EXAMPLES:
      - "create contact John Doe john@doe.com" → create_object("contacts", {email: "john@doe.com", first_name: "John", last_name: "Doe"})
      - "add contact for Jane Smith jane@smith.com" → create_object("contacts", {email: "jane@smith.com", first_name: "Jane", last_name: "Smith"})

      **SCHEMA DISCOVERY - CRITICAL FOR SUCCESS:**
      
      ALWAYS use get_schema(object_type) FIRST when:
      - You need to query data but aren't sure what fields exist
      - You encounter database column errors
      - You're creating objects and need to know required fields
      - The user asks about data structure or available fields

      The get_schema tool shows you ACTUAL database columns, not assumptions!

      **For Data Queries:**
      - Use get_schema("campaigns") to see real available fields
      - Then use get_data("campaigns", filters, options) with correct field names
      - Example workflow: get_schema("campaigns") → see actual columns → get_data("campaigns", {status: "sent"}, {limit: 10})

      **For Creating Objects:**
      - Use get_schema(object_type) first to understand required fields
      - Then use create_object(object_type, data)
      - Example: get_schema("contacts") → see required fields → create_object("contacts", {email: "john@doe.com"})

      **QUERY OPTIONS:**
      - limit: number (default 10, max 100)
      - include_metrics: boolean (includes performance data)
      - order_by: "field_name desc/asc" (use ONLY fields that exist!)
      - filters: object with field names that actually exist

      **AVAILABLE CANVASES (optional):**
      When appropriate, you can suggest loading a visual canvas:
      - "analytics_dashboard" - for performance metrics and analytics
      - "landing_page_viewer" - to show existing landing pages
      - "landing_page_generator" - to create new landing pages
      - "campaign_viewer" - to show email campaigns
      - "contact_viewer" - to show contacts
      - "contact_generator" - to create new contacts

      **CRITICAL RESPONSE FORMAT:**
      You MUST respond with valid JSON in this exact format:

      {
        "message": "Your conversational response to the user",
        "tool_calls": [
          {
            "name": "get_schema", 
            "arguments": {"object_type": "campaigns"}
          },
          {
            "name": "get_data",
            "arguments": {"object_type": "campaigns", "filters": {"status": "sent"}, "options": {"limit": 20}}
          }
        ],
        "canvas": "analytics_dashboard"
      }

      OR if no tools are needed:

      {
        "message": "Your conversational response to the user",
        "tool_calls": [],
        "canvas": "contact_viewer"
      }

      OR for simple conversation (no canvas needed):

      {
        "message": "Your conversational response to the user",
        "tool_calls": []
      }

      **Key Rules:**
      1. Always respond with valid JSON
      2. The "message" field is what the user will see
      3. Use get_schema proactively to avoid database errors
      4. Only reference fields that actually exist in the database
      5. When in doubt, check the schema first!
      6. Be transparent: tell users when you're discovering their data structure
      7. **BE AGGRESSIVE WITH TOOLS** - If user wants to create/query anything, USE TOOLS!

      Be conversational in your message but use tools intelligently behind the scenes.
    PROMPT
  end

  def format_available_models(models)
    models.map do |model|
      status = []
      status << "Query" if model[:can_query]
      status << "Create" if model[:can_create]
      "- #{model[:model_name]}: #{model[:description]} (#{status.join(', ')})"
    end.join("\n")
  end

  def format_query_options(options)
    lines = []
    lines << "Filters:"
    lines << "  - date_range: #{options[:filters][:date_ranges].join(', ')}"
    lines << "  - status: #{options[:filters][:status_values].join(', ')}"
    lines << "Options:"
    lines << "  - limit: #{options[:options][:limit]}"
    lines << "  - order_by: #{options[:options][:order_by]}"
    lines << "  - include_metrics: #{options[:options][:include_metrics]}"
    lines.join("\n")
  end

  def parse_function_calls_from_response(response)
    Rails.logger.info "Raw #{@ai_provider_name} response: #{response}"
    
    begin
      # Try to parse the response as JSON
      parsed = JSON.parse(response)
      Rails.logger.info "Successfully parsed JSON response: #{parsed.keys}"
      
      @parsed_user_message = parsed['message']
      @suggested_canvas = parsed['canvas']
      tool_calls = parsed['tool_calls']
      
      if tool_calls && tool_calls.is_a?(Array) && tool_calls.any?
        Rails.logger.info "Found #{tool_calls.length} tool calls: #{tool_calls.map { |t| t['name'] }}"
        return tool_calls.map do |call|
          {
            name: call['name'],
            arguments: call['arguments'] || {}
          }
        end
      else
        Rails.logger.warn "No tool calls found in response. Tool_calls field: #{tool_calls.inspect}"
        return nil
      end
      
    rescue JSON::ParserError => e
      Rails.logger.error "Failed to parse #{@ai_provider_name} response as JSON: #{e.message}"
      Rails.logger.error "This suggests #{@ai_provider_name} returned plain text instead of JSON format"
      
      # Try to extract message from malformed JSON
      extracted_message = extract_message_from_malformed_json(response)
      @parsed_user_message = extracted_message || "I apologize, but I'm having trouble processing that request. Could you please try rephrasing it?"
      
      return nil
    end
  end

  private

  def extract_message_from_malformed_json(response)
    # Try different patterns to extract the message content from malformed JSON
    
    # Pattern 1: Look for "message": "content" in the string
    if match = response.match(/"message"\s*:\s*"([^"]*)"/)
      return match[1]
    end
    
    # Pattern 2: Look for message content after a JSON structure
    if match = response.match(/\}\s*(.+)$/)
      cleaned = match[1].strip
      return cleaned unless cleaned.empty?
    end
    
    # Pattern 3: If it's just plain text with no JSON structure
    if !response.include?('"tool_calls"') && !response.include?('{')
      return response.strip
    end
    
    # Pattern 4: Extract content before "tool_calls": []
    if match = response.match(/^(.*?)\s*,?\s*"tool_calls"\s*:\s*\[\]?\s*\}?\s*$/m)
      content = match[1].strip
      # Remove leading JSON structure if present
      content = content.gsub(/^\{\s*"message"\s*:\s*"/, '').gsub(/"$/, '')
      return content unless content.empty?
    end
    
    # Pattern 5: Try to find any text that looks like a message
    if match = response.match(/([A-Z][^{}\[\]]*[.!?])/)
      return match[1].strip
    end
    
    Rails.logger.warn "Could not extract message from malformed response: #{response}"
    return nil
  end

  def execute_tools(tool_calls)
    results = []
    
    tool_calls.each do |tool_call|
      result = case tool_call[:name]
      when 'get_data'
        execute_get_data(tool_call[:arguments])
      when 'create_object'
        execute_create_object(tool_call[:arguments])
      when 'get_schema'
        execute_get_schema(tool_call[:arguments])
      else
        { success: false, error: "Unknown tool: #{tool_call[:name]}" }
      end
      
      results << {
        tool_name: tool_call[:name],
        arguments: tool_call[:arguments],
        result: result,
        success: !result.key?(:error)
      }
    end
    
    results
  end

  def execute_tools_with_progress(tool_calls, progress_callback = nil)
    results = []
    
    tool_calls.each_with_index do |tool_call, index|
      # Show progress for each tool
      case tool_call[:name]
      when 'get_schema'
        object_type = tool_call[:arguments]['object_type']
        progress_callback&.call("🔍 Checking #{object_type} database schema...")
      when 'get_data'
        object_type = tool_call[:arguments]['object_type']
        progress_callback&.call("📊 Fetching #{object_type} data...")
      when 'create_object'
        object_type = tool_call[:arguments]['object_type']
        progress_callback&.call("✨ Creating new #{object_type}...")
      end
      
      result = case tool_call[:name]
      when 'get_data'
        execute_get_data(tool_call[:arguments])
      when 'create_object'
        execute_create_object(tool_call[:arguments])
      when 'get_schema'
        execute_get_schema(tool_call[:arguments])
      else
        { success: false, error: "Unknown tool: #{tool_call[:name]}" }
      end
      
      results << {
        tool_name: tool_call[:name],
        arguments: tool_call[:arguments],
        result: result,
        success: !result.key?(:error)
      }
      
      # Show completion for each tool
      if result[:success]
        case tool_call[:name]
        when 'get_schema'
          progress_callback&.call("✅ Schema discovered for #{tool_call[:arguments]['object_type']}")
        when 'get_data'
          count = result.dig(:data, :count) || 0
          progress_callback&.call("✅ Found #{count} records")
        when 'create_object'
          progress_callback&.call("✅ Successfully created #{tool_call[:arguments]['object_type']}")
        end
      else
        progress_callback&.call("❌ Tool execution failed: #{result[:error]}")
      end
    end
    
    results
  end

  def execute_get_data(args)
    object_type = normalize_object_type(args['object_type'])
    filters = args['filters'] || {}
    options = args['options'] || {}
    
    Rails.logger.info "Executing get_data: object_type=#{object_type}, filters=#{filters}, options=#{options}"
    
    begin
      # Use existing UniversalQueryEngine
      query_engine = UniversalQueryEngine.new(@user, @entity)
      
      # Convert to format expected by query engine
      # Fix common field name variations
      fixed_filters = fix_field_names(filters, object_type)
      fixed_order_by = fix_field_names_in_order_by(options['order_by'], object_type)
      
      query_params = {
        objects: [object_type],
        filters: fixed_filters,
        limit: options['limit'] || 20,
        order_by: fixed_order_by,
        include_metrics: options['include_metrics'] != false,
        include_relationships: options['include_relationships']
      }
      
      Rails.logger.info "Query params: #{query_params}"
      
      result = query_engine.execute_get_data(query_params)
      
      Rails.logger.info "Query result success: #{result[:success]}"
      if result[:success] && result[:data]
        result[:data].each do |obj_type, data|
          Rails.logger.info "Found #{data[:count] || 0} #{obj_type}"
        end
      end
      
      if result[:success]
        {
          success: true,
          data: result[:data],
          metadata: result[:metadata]
        }
      else
        Rails.logger.error "Query failed: #{result[:error]}"
        { error: result[:error] }
      end
    rescue => e
      Rails.logger.error "get_data error: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      { error: "Query failed: #{e.message}" }
    end
  end

  def execute_create_object(args)
    object_type = args['object_type']
    data = args['data']
    
    Rails.logger.info "Executing create_object: object_type=#{object_type}, data=#{data}"
    
    begin
      # Get the model class (use singular form for model lookup)
      singular_type = singularize_object_type(object_type)
      model_class = object_type_to_class(singular_type)
      return { error: "Unknown object type: #{object_type}" } unless model_class
      
      # Add automatic scoping
      scoped_data = data.dup
      scoped_data['entity_id'] = @entity.id if model_class.column_names.include?('entity_id')
      scoped_data['user_id'] = @user.id if model_class.column_names.include?('user_id')
      
      # Create the object
      new_object = model_class.create!(scoped_data)
      
      {
        success: true,
        object_id: new_object.id,
        object_type: object_type,
        data: format_created_object(new_object),
        message: "Successfully created #{object_type}"
      }
    rescue ActiveRecord::RecordInvalid => e
      { error: "Validation failed: #{e.record.errors.full_messages.join(', ')}" }
    rescue => e
      Rails.logger.error "create_object error: #{e.message}"
      { error: "Creation failed: #{e.message}" }
    end
  end

  def execute_get_schema(args)
    object_type = args['object_type']
    
    Rails.logger.info "Schema discovery requested for: #{object_type}"
    
    # Normalize object type (handle both singular and plural)
    normalized_type = object_type.to_s.downcase
    normalized_type = normalized_type.pluralize unless normalized_type.end_with?('s')
    
    # Use dynamic schema discovery
    schema = ScoutDataRegistry.get_actual_schema(normalized_type)
    
    if schema
      Rails.logger.info "Schema discovered for #{normalized_type}: #{schema[:actual_columns].length} columns, #{schema[:record_count]} records"
      
      { 
        success: true, 
        object_type: normalized_type,
        schema: schema,
        summary: "Found #{schema[:actual_columns].length} actual database columns for #{normalized_type}. #{schema[:record_count]} records exist."
      }
    else
      available_types = ScoutDataRegistry.available_object_types.join(', ')
      { 
        success: false,
        error: "Unknown object type: #{object_type}. Available types: #{available_types}" 
      }
    end
  end

  def object_type_to_class(object_type)
    case object_type.to_s.downcase
    when 'campaign'
      Campaign
    when 'contact'
      Contact
    when 'contact_group'
      ContactGroup
    when 'landing_page'
      LandingPage
    when 'email_template'
      EmailTemplate
    when 'business_profile'
      BusinessProfile
    else
      nil
    end
  end

  def format_created_object(object)
    # Return basic object information
    result = { id: object.id }
    
    # Add common display fields
    display_fields = %w[name title subject email first_name last_name]
    display_fields.each do |field|
      if object.respond_to?(field) && object.send(field).present?
        result[field] = object.send(field)
      end
    end
    
    result
  end

  def generate_response_with_tool_results(user_message, initial_message, tool_results)
    # Format tool results for AI
    results_summary = format_tool_results_for_ai(tool_results)
    
    Rails.logger.info "=== TOOL RESULTS SUMMARY FOR #{@ai_provider_name.upcase} ==="
    Rails.logger.info "Number of tool results: #{tool_results.length}"
    tool_results.each_with_index do |result, i|
      Rails.logger.info "Tool #{i+1}: #{result[:tool_name]} - Success: #{result[:success]}"
      if result[:success] && result[:result]
        case result[:tool_name]
        when 'get_data'
          if result[:result][:data]
            Rails.logger.info "  Data keys: #{result[:result][:data].keys}"
            result[:result][:data].each do |type, data|
              if data.is_a?(Hash) && data[:records]
                Rails.logger.info "    #{type}: #{data[:records]&.length || 0} records"
              else
                Rails.logger.info "    #{type}: #{data.inspect}"
              end
            end
          end
        when 'create_object'
          Rails.logger.info "  Created object: #{result[:result].inspect}"
        when 'get_schema'
          Rails.logger.info "  Schema result: #{result[:result][:object_type] || 'unknown'}"
        else
          Rails.logger.info "  Result: #{result[:result].inspect}"
        end
      end
    end
    Rails.logger.info "=== END TOOL RESULTS SUMMARY ==="
    
    # Check if we have any successful results
    successful_results = tool_results.select { |r| r[:success] }
    failed_results = tool_results.select { |r| !r[:success] }
    
    # If all tools failed, return a simplified error message
    if successful_results.empty?
      error_summary = failed_results.map { |r| r[:result][:error] }.join(', ')
      Rails.logger.error "All tools failed: #{error_summary}"
      return "I tried to access your marketing data but ran into some technical issues: #{error_summary}. Please try again or let me know if you need help with something else."
    end
    
    final_prompt = <<~PROMPT
      You provided this initial response to the user: "#{initial_message}"

      You also requested tool execution, and here are the REAL results from those tools:

      TOOL RESULTS:
      #{results_summary}

      USER'S ORIGINAL REQUEST: #{user_message}

      Now provide an updated, conversational response that incorporates the actual data. You should:
      1. Use the REAL data from the tool results, not assumptions
      2. Be specific about what was found or created  
      3. Don't mention "tools" - just present the information naturally
      4. If any tools failed, explain it helpfully
      5. Suggest relevant next steps based on the actual results
      6. ANALYZE THE SPECIFIC METRICS provided in the data above
      7. Provide actionable insights based on the real performance numbers

      Provide your updated response as plain text (not JSON):
    PROMPT
    
    # Log the complete prompt being sent to Claude
    Rails.logger.info "=== COMPLETE PROMPT BEING SENT TO #{@ai_provider_name.upcase} ==="
    Rails.logger.info final_prompt
    Rails.logger.info "=== END #{@ai_provider_name.upcase} PROMPT ==="
    Rails.logger.info "Prompt length: #{final_prompt.length} characters"
    
    # Ensure we're not sending empty content
    if final_prompt.strip.empty?
      Rails.logger.error "Empty prompt generated!"
      return "I'm having trouble processing that request right now. Please try again."
    end
    
    # Send to Claude with a fallback message
    begin
      response = @ai_service.send_message(final_prompt, "Please provide your response.")
      response.present? ? response : "I was able to process your request but had trouble generating a response. Please try again."
    rescue => e
      Rails.logger.error "Error generating final response: #{e.message}"
      "I found your data but had trouble generating a detailed response. Please try asking again or be more specific about what you'd like to know."
    end
  end

  def format_tool_results_for_ai(tool_results)
    formatted = []
    
    tool_results.each do |result|
      if result[:success]
        case result[:tool_name]
        when 'get_data'
          formatted << format_data_results(result[:result])
        when 'create_object'
          formatted << format_creation_results(result[:result])
        when 'get_schema'
          formatted << format_schema_results(result[:result])
        end
      else
        formatted << "#{result[:tool_name]} failed: #{result[:result][:error]}"
      end
    end
    
    formatted.join("\n\n")
  end

  def format_data_results(result)
    return "No data found" unless result[:data]
    
    # Log what we're sending to Claude
    Rails.logger.info "=== FORMATTING DATA FOR #{@ai_provider_name.upcase} ==="
    Rails.logger.info "Result structure: #{result.keys}"
    Rails.logger.info "Data keys: #{result[:data].keys}"
    
    formatted_sections = []
    
    result[:data].each do |object_type, data|
      records = data[:records] || []
      
      if records.any?
        Rails.logger.info "Formatting #{records.length} #{object_type} records for #{@ai_provider_name}"
        
        section = []
        section << "=== #{object_type.upcase} DATA (#{records.length} records) ==="
        
        records.each_with_index do |record, index|
          section << "\n#{object_type.singularize.capitalize} ##{index + 1}:"
          
          # Include all relevant fields based on object type
          case object_type
                    when 'campaigns'
            section << format_campaign_for_ai(record)
          when 'contacts'
            section << format_contact_for_ai(record)
          when 'landing_pages'
            section << format_landing_page_for_ai(record)
          else
            section << format_generic_object_for_ai(record)
          end
        end
        
        formatted_sections << section.join("\n")
      else
        formatted_sections << "No #{object_type} found"
      end
    end
    
    final_result = formatted_sections.join("\n\n")
    
    # Log the final formatted result
    Rails.logger.info "=== FINAL FORMATTED DATA FOR #{@ai_provider_name.upcase} ==="
    Rails.logger.info final_result
    Rails.logger.info "=== END #{@ai_provider_name.upcase} DATA ==="
    
    final_result
  end

  def format_campaign_for_ai(record)
    Rails.logger.info "=== SENDING COMPLETE CAMPAIGN DATA TO #{@ai_provider_name.upcase} ==="
    
    # Convert the record to a readable format for AI
    if record.respond_to?(:to_json)
      data = JSON.parse(record.to_json)
    elsif record.is_a?(Hash)
      data = record
    else
      data = record.as_json rescue record.to_h rescue record.inspect
    end
    
    Rails.logger.info "Campaign data being sent: #{data.inspect}"
    
    # Format as clean, readable text for AI
    lines = []
    lines << "  COMPLETE CAMPAIGN DATA:"
    
    data.each do |key, value|
      if value.is_a?(Hash)
        lines << "    #{key}:"
        value.each do |sub_key, sub_value|
          lines << "      #{sub_key}: #{sub_value}"
        end
      else
        lines << "    #{key}: #{value}"
      end
    end
    
    lines.join("\n")
  end

  def format_contact_for_ai(record)
    Rails.logger.info "=== SENDING COMPLETE CONTACT DATA TO #{@ai_provider_name.upcase} ==="
    
    # Convert to readable format
    if record.respond_to?(:to_json)
      data = JSON.parse(record.to_json)
    else
      data = record.attributes rescue record.to_h
    end
    
    Rails.logger.info "Contact data being sent: #{data.inspect}"
    
    lines = []
    lines << "  CONTACT RECORD:"
    lines << "    - ID: #{data['id']}"
    lines << "    - Name: #{data['first_name']} #{data['last_name']}"
    lines << "    - Email: #{data['email']}"
    lines << "    - Created: #{data['created_at']}"
    lines << "    - Groups: #{data['contact_groups']&.map { |g| g['name'] }&.join(', ') || 'None'}"
    
    # Add engagement metrics if available
    if data['email_deliveries']
      lines << "    - Email Performance: #{data['email_deliveries'].length} emails sent"
    end
    
    lines.join("\n")
  end

  def format_landing_page_for_ai(record)
    Rails.logger.info "=== SENDING COMPLETE LANDING PAGE DATA TO #{@ai_provider_name.upcase} ==="
    
    # Convert to readable format
    if record.respond_to?(:to_json)
      data = JSON.parse(record.to_json)
    else
      data = record.attributes rescue record.to_h
    end
    
    Rails.logger.info "Landing page data being sent: #{data.inspect}"
    
    lines = []
    lines << "  LANDING PAGE RECORD:"
    lines << "    - ID: #{data['id']}"
    lines << "    - Title: #{data['title']}"
    lines << "    - Slug: #{data['slug']}"
    lines << "    - Status: #{data['status']}"
    lines << "    - Description: #{data['description']}"
    lines << "    - Created: #{data['created_at']}"
    
    # Add content preview if available
    if data['html_content']
      content_preview = data['html_content'].to_s.strip[0..100] + "..."
      lines << "    - Content Preview: #{content_preview}"
    end
    
    lines.join("\n")
  end

  def format_generic_object_for_ai(record)
    Rails.logger.info "=== SENDING COMPLETE GENERIC OBJECT DATA TO #{@ai_provider_name.upcase} ==="
    
    # Convert to readable format
    if record.respond_to?(:to_json)
      data = JSON.parse(record.to_json)
    else
      data = record.attributes rescue record.to_h
    end
    
    Rails.logger.info "Generic object data being sent: #{data.inspect}"
    
    lines = []
    lines << "  OBJECT RECORD:"
    data.each do |key, value|
      lines << "    - #{key.humanize}: #{value}"
    end
    
    lines.join("\n")
  end

  def format_creation_results(result)
    if result[:success]
      "Successfully created #{result[:object_type]}: #{result[:message]}"
    else
      "Failed to create object: #{result[:error]}"
    end
  end

  def format_schema_results(result)
    if result[:success]
      schema = result[:schema]
      available_columns = schema[:actual_columns] || []
      available_fields = schema[:available_fields] || []
      
      "Schema for #{schema[:model]} (#{schema[:object_type]}):\n" +
      "Database columns: #{available_columns.join(', ')}\n" +
      "Queryable fields: #{available_fields.join(', ')}\n" +
      "Record count: #{schema[:record_count]}\n" +
      "Relationships: #{(schema[:relationships] || []).join(', ')}"
    else
      "Failed to get schema: #{result[:error]}"
    end
  end

  def fix_field_names(filters, object_type)
    return filters unless filters.is_a?(Hash)
    
    fixed_filters = {}
    
    filters.each do |key, value|
      fixed_key = map_field_name(key.to_s, object_type)
      fixed_filters[fixed_key] = value
    end
    
    fixed_filters
  end

  def fix_field_names_in_order_by(order_by, object_type)
    return order_by unless order_by.is_a?(String)
    
    # Split field and direction
    parts = order_by.split(' ')
    field = parts[0]
    direction = parts[1] || 'desc'
    
    fixed_field = map_field_name(field, object_type)
    "#{fixed_field} #{direction}"
  end

  def map_field_name(field, object_type)
    # Common field mappings
    case object_type.to_s.downcase
    when 'campaign', 'campaigns'
      case field.to_s.downcase
      when 'send_date'
        'sent_at'
      when 'create_date'
        'created_at'
      when 'update_date'
        'updated_at'
      else
        field
      end
    when 'contact', 'contacts'
      case field.to_s.downcase
      when 'create_date'
        'created_at'
      when 'update_date'
        'updated_at'
      else
        field
      end
    else
      field
    end
  end

  def normalize_object_type(object_type)
    # Convert singular to plural forms expected by the query engine
    case object_type.to_s.downcase
    when 'campaign'
      'campaigns'
    when 'contact'
      'contacts'
    when 'contact_group'
      'contact_groups'
    when 'landing_page'
      'landing_pages'
    when 'email_template'
      'email_templates'
    when 'business_profile'
      'business_profiles'
    else
      # If already plural or unknown, return as-is
      object_type
    end
  end

  def singularize_object_type(object_type)
    # Convert plural to singular forms for model class lookup
    case object_type.to_s.downcase
    when 'campaigns'
      'campaign'
    when 'contacts'
      'contact'
    when 'contact_groups'
      'contact_group'
    when 'landing_pages'
      'landing_page'
    when 'email_templates'
      'email_template'
    when 'business_profiles'
      'business_profile'
    else
      # If already singular or unknown, return as-is
      object_type
    end
  end

  def format_conversation_for_ai(conversation_history, user_message)
    # Format conversation messages for AI consumption
    messages = []

    # Add conversation history (limit to recent messages to avoid token limits)
    recent_history = conversation_history.last(10) # Last 10 messages for context
    
    recent_history.each do |msg|
      role = msg[:role] == 'user' ? 'user' : 'assistant'
      content = msg[:content]
      
      if content.present?
        messages << { role: role, content: content }
      end
    end
    
    # Add current message
    messages << { role: 'user', content: user_message }
    
    Rails.logger.info "Formatted conversation: #{messages.length} messages total"
    Rails.logger.info "Messages: #{messages.map { |m| "#{m[:role]}: #{m[:content][0..50]}..." }.join(' | ')}"
    
    messages
  end
end 