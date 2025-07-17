class ScoutGenericToolsService
  def initialize(user, entity)
    @user = user
    @entity = entity
    @claude_service = ClaudeService.new
  end

  # Generic function calling tools for Claude
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

  def process_message_with_tools(user_message)
    begin
      # Build system prompt with dynamic schema information
      system_prompt = build_system_prompt_with_dynamic_schema
      
      # Prepare conversation messages
      conversation_messages = [
        { role: 'user', content: user_message }
      ]
      
      # Send to Claude with function calling
      response = @claude_service.send_message(
        system_prompt,
        conversation_messages,
        model: 'claude-3-5-sonnet-20241022',
        max_tokens: 4000,
        temperature: 0.7
      )
      
      # Parse response for JSON structure with message and tool calls
      if tool_calls = parse_function_calls_from_response(response)
        Rails.logger.info "Detected function calls: #{tool_calls.map { |t| t[:name] }}"
        
        # Execute the tools
        tool_results = execute_tools(tool_calls)
        
        # Send the real tool results back to Claude for an updated response
        final_message = generate_response_with_tool_results(user_message, @parsed_user_message, tool_results)
        
        return {
          message: final_message,
          tool_calls_made: true,
          tools_used: tool_calls.map { |t| t[:name] },
          success_count: tool_results.count { |r| r[:success] },
          error_count: tool_results.count { |r| !r[:success] },
          tool_results: tool_results
        }
      else
        # Regular response without tools (use parsed message if available)
        return {
          message: @parsed_user_message || response,
          tool_calls_made: false
        }
      end
      
    rescue => e
      Rails.logger.error "Scout generic tools error: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      
      {
        message: "I apologize, but I'm experiencing some technical difficulties. Please try again.",
        tool_calls_made: false,
        error: e.message
      }
    end
  end

  def process_message_with_tools_streaming(user_message, progress_callback = nil)
    begin
      progress_callback&.call("🧠 Building context with available data models...")
      
      # Build system prompt with dynamic schema information
      system_prompt = build_system_prompt_with_dynamic_schema
      
      # Prepare conversation messages
      conversation_messages = [
        { role: 'user', content: user_message }
      ]
      
      progress_callback&.call("🤖 Sending request to Claude...")
      
      # Send to Claude with function calling
      response = @claude_service.send_message(
        system_prompt,
        conversation_messages,
        model: 'claude-3-5-sonnet-20241022',
        max_tokens: 4000,
        temperature: 0.7
      )
      
      progress_callback&.call("📝 Parsing Claude's response...")
      
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
        
        # Send the real tool results back to Claude for an updated response
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
    
    <<~PROMPT
      You are Scout, the AI marketing assistant. You have access to a simple, powerful toolset for accessing and creating marketing data.

      USER CONTEXT:
      - User: #{@user.first_name} #{@user.last_name}
      - Entity: #{@entity.name}

      AVAILABLE TOOLS:
      1. get_data(object_type, filters, options) - Query any data model
      2. create_object(object_type, data) - Create new objects  
      3. get_schema(object_type) - Get REAL database schema and field information

      AVAILABLE DATA MODELS:
      #{available_models.join(', ')}

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
        ]
      }

      OR if no tools are needed:

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
    begin
      # Parse the entire response as JSON
      parsed_response = JSON.parse(response.strip)
      
      # Extract message and tool calls
      user_message = parsed_response['message'] || ""
      tool_calls_data = parsed_response['tool_calls'] || []
      
      # Convert tool calls to our expected format
      tool_calls = []
      tool_calls_data.each do |tool_call|
        if tool_call['name'] && tool_call['arguments']
          tool_calls << {
            name: tool_call['name'],
            arguments: tool_call['arguments']
          }
        end
      end
      
      Rails.logger.info "Successfully parsed JSON response: message=#{user_message.length} chars, tools=#{tool_calls.length}"
      
      # Store the user message for later use
      @parsed_user_message = user_message
      
      # Return tool calls (or nil if none)
      tool_calls.empty? ? nil : tool_calls
      
    rescue JSON::ParserError => e
      Rails.logger.error "Failed to parse response as JSON: #{e.message}"
      Rails.logger.error "Response was: #{response}"
      
      # Fallback: treat as regular conversational response
      @parsed_user_message = response
      nil
    end
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
    # Format tool results for Claude
    results_summary = format_tool_results_for_claude(tool_results)
    
    # Check if we have any successful results
    successful_results = tool_results.select { |r| r[:success] }
    failed_results = tool_results.select { |r| !r[:success] }
    
    # If all tools failed, return a simplified error message
    if successful_results.empty?
      error_summary = failed_results.map { |r| r[:result][:error] }.join(', ')
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

      Provide your updated response as plain text (not JSON):
    PROMPT
    
    # Ensure we're not sending empty content
    if final_prompt.strip.empty?
      return "I'm having trouble processing that request right now. Please try again."
    end
    
    # Send to Claude with a fallback message
    begin
      response = @claude_service.send_message(final_prompt, "Please provide your response.")
      response.present? ? response : "I was able to process your request but had trouble generating a response. Please try again."
    rescue => e
      Rails.logger.error "Error generating final response: #{e.message}"
      "I found your data but had trouble generating a detailed response. Please try asking again or be more specific about what you'd like to know."
    end
  end

  def format_tool_results_for_claude(tool_results)
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
    
    summary = []
    result[:data].each do |object_type, data|
      records = data[:records] || []
      if records.any?
        summary << "Found #{records.length} #{object_type}:"
        records.first(3).each do |record|
          case object_type
          when 'campaigns'
            summary << "- #{record[:name] || record[:subject] || "Campaign ##{record[:id]}"}"
          when 'contacts'
            name = [record[:first_name], record[:last_name]].compact.join(' ')
            summary << "- #{name} (#{record[:email]})"
          else
            summary << "- #{record[:name] || record[:title] || "Item ##{record[:id]}"}"
          end
        end
        summary << "... and #{records.length - 3} more" if records.length > 3
      else
        summary << "No #{object_type} found"
      end
    end
    
    summary.join("\n")
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
end 