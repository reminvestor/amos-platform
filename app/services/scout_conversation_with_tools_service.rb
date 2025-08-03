class ScoutConversationWithToolsService
  def initialize(user, entity, conversation_context = [])
    @user = user
    @entity = entity
    @conversation_context = conversation_context
    @claude_service = ClaudeService.new
    @universal_tools = ScoutUniversalTools.new(user, entity)
  end
  
  def process_message_with_tools(user_message)
    begin
      # Build the system prompt with tool awareness
      system_prompt = build_system_prompt_with_tools
      
      # Prepare conversation messages
      conversation_messages = build_conversation_messages(@conversation_context, user_message)
      
      # Send to Claude with function calling capabilities
      response = send_to_claude_with_tools(system_prompt, conversation_messages)
      
      # Check if Claude wants to use tools
      if response[:function_calls].present?
        # Execute the requested tools
        tool_results = execute_tool_calls(response[:function_calls])
        
        # Send tool results back to Claude for final response
        final_response = send_tool_results_to_claude(response, tool_results)
        
        return format_final_response(final_response, tool_results)
      else
        # Regular conversation response without tools
        return {
          message: response[:message] || response,
          tool_calls_made: false,
          raw_response: response
        }
      end
      
    rescue => e
      Rails.logger.error "Scout conversation with tools error: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      
      # Fallback to regular conversation
      fallback_response = @claude_service.send_message(
        build_fallback_prompt,
        conversation_messages
      )
      
      {
        message: fallback_response,
        tool_calls_made: false,
        error: "Tool system temporarily unavailable, using fallback response"
      }
    end
  end
  
  private
  
  def build_system_prompt_with_tools
    data_objects_info = ScoutUniversalTools.available_data_objects
    
    <<~PROMPT
      You are Scout, the AI marketing agent for Crux Marketing. You have access to powerful tools that let you autonomously query, analyze, and create marketing data.

      IMPORTANT: You can now ACCESS REAL DATA from the user's account instead of asking them to provide information manually.

      AVAILABLE TOOLS:
      1. get_data - Query any data objects (campaigns, landing_pages, contacts, contact_groups, email_templates, email_deliveries)
      2. get_schema - Get database schema and field information for any object type
      3. create_object - Create basic objects like campaigns, contacts, or groups (for simple data entry)
      4. generate_ai_landing_page - Create sophisticated AI-powered landing pages using multi-agent system (PREFERRED for landing pages)

      AVAILABLE DATA OBJECTS:
      #{data_objects_info[:available_objects]}

      USER CONTEXT:
      - User: #{@user.first_name} #{@user.last_name}
      - Entity: #{@entity.name}
      - Business Profile: #{get_business_context}

      TOOL USAGE GUIDELINES:
      
      When users ask about their data:
      1. ALWAYS use get_data first to retrieve real information
      2. Use get_schema when you need to understand data structure
      3. Never ask users to provide data that you can retrieve yourself
      
      LANDING PAGE CREATION - CRITICAL:
      - For landing pages: ALWAYS use generate_ai_landing_page (triggers sophisticated multi-agent system)
      - Never use create_object for landing pages - it only creates empty records
      - The AI system includes: web research, planning, content generation, HTML creation, and optimization
      
      Example flows:
      - "How are my campaigns performing?" → get_data(campaigns) 
      - "Show me my best contacts" → get_data(contacts, filters: high engagement)
      - "Create a landing page" → generate_ai_landing_page(title, description, page_type)
      - "Create a contact" → create_object(contacts, data)
      - "Create a campaign" → create_object(campaigns, data)

      CONVERSATION STYLE:
      - Be proactive: "Let me check your recent campaigns..."
      - Show confidence: "I can see your July campaign had a 24% open rate..."
      - Provide actionable insights: "Your Tuesday sends perform 30% better than Fridays"
      - Ask intelligent follow-ups: "Want me to create a campaign targeting your most engaged segment?"
      
      CRITICAL RULES:
      1. If users ask for data analysis, marketing performance, or want to create campaigns - USE TOOLS
      2. Don't ask for information you can get with tools
      3. Always explain what you're doing: "Let me pull up your campaign data..."
      4. Provide specific insights from real data, not generic advice
      5. Be concise but comprehensive - users want actionable insights

      Remember: You're not just a chatbot - you're a data-powered marketing intelligence agent!
    PROMPT
  end
  
  def build_conversation_messages(conversation_context, user_message)
    messages = []
    
    # Add recent conversation history (keep it manageable)
    recent_history = conversation_context.last(6)
    recent_history.each do |msg|
      # Only add messages with non-empty content
      content = msg[:content]&.to_s&.strip
      if content.present?
        messages << { role: msg[:role], content: content }
      end
    end
    
    # Add current user message (ensure it's not empty)
    user_content = user_message&.to_s&.strip
    if user_content.present?
      messages << { role: 'user', content: user_content }
    end
    
    # Log the messages being sent for debugging
    Rails.logger.info "Sending #{messages.length} messages to Claude"
    messages.each_with_index do |msg, i|
      Rails.logger.info "Message #{i}: role=#{msg[:role]}, content_length=#{msg[:content]&.length || 0}"
    end
    
    messages
  end
  
  def send_to_claude_with_tools(system_prompt, messages)
    # Safety check: ensure we have at least one valid message
    if messages.empty?
      Rails.logger.warn "No valid messages to send to Claude, creating default message"
      messages = [{ role: 'user', content: 'Hello' }]
    end
    
    # Validate all messages have content
    invalid_messages = messages.select { |msg| msg[:content].blank? }
    if invalid_messages.any?
      Rails.logger.error "Found #{invalid_messages.length} messages with empty content, filtering them out"
      messages = messages.reject { |msg| msg[:content].blank? }
    end
    
    # Final safety check
    if messages.empty?
      Rails.logger.warn "All messages filtered out, using fallback"
      messages = [{ role: 'user', content: 'Hello, I need help with my marketing.' }]
    end
    
    # For now, we'll simulate function calling since Claude API integration
    # would need to be enhanced for actual function calling
    # This is where we'd integrate with Claude's function calling API
    
    # Create enhanced system prompt with tool instructions
    enhanced_system_prompt = build_enhanced_system_prompt(system_prompt)
    
    # Send messages directly to Claude
    response = @claude_service.send_message(enhanced_system_prompt, messages)
    
    # Parse response to see if Claude indicates tool usage
    parsed_response = parse_claude_response_for_tools(response)
    
    parsed_response
  rescue => e
    Rails.logger.error "Error in send_to_claude_with_tools: #{e.message}"
    Rails.logger.error "Messages being sent: #{messages.inspect}"
    raise e
  end
  
  def build_enhanced_system_prompt(system_prompt)
    <<~PROMPT
      #{system_prompt}

      INTELLIGENT TOOL USAGE:
      You are an intelligent agent who can access real marketing data. When users ask questions that would benefit from actual data, you should use your tools to provide specific, contextual insights.

      EXAMPLES OF WHEN TO USE TOOLS:

      User: "How are my campaigns performing?"
      You should: Use get_data to retrieve recent campaigns with metrics, then analyze_data to provide insights about performance trends, best/worst performers, and actionable recommendations.

      User: "Can you pull all that data from my campaigns?"  
      You should: Use get_data for campaigns, then analyze_data to interpret what the data means for their business goals.

      User: "Show me my contact engagement"
      You should: Use get_data for contacts with engagement metrics, then analyze_data to identify segments and patterns.

      TOOL DECISION FRAMEWORK:
      - If user asks about performance, metrics, or wants to see data → Use get_data + analyze_data
      - If user wants insights, recommendations, or analysis → Use analyze_data (may need get_data first)
      - If user wants to create campaigns, contacts, etc. → Use create_object
      - If user is just chatting or asking general questions → No tools needed

      RESPONSE FORMAT:
      If you determine tools are needed, respond with: "I'll analyze your [specific data type] to give you detailed insights. TOOL_USE_NEEDED"
      
      If no tools needed, respond normally and conversationally.

      Your goal: Be a marketing intelligence agent who proactively accesses real data to provide specific, actionable insights rather than generic advice.
    PROMPT
  end
  
  def parse_claude_response_for_tools(response)
    # Look for Claude indicating that tools are needed
    if response.include?("TOOL_USE_NEEDED")
      # Claude has indicated tools are needed - determine what tools to use based on the response context
      tool_calls = determine_intelligent_tool_calls(response)
      
      {
        message: response,
        function_calls: tool_calls,
        requires_tools: true
      }
    else
      {
        message: response,
        function_calls: [],
        requires_tools: false
      }
    end
  end
  
  def determine_intelligent_tool_calls(response)
    # Use Claude's response context to intelligently determine what tools are needed
    # This is more contextual than pattern matching
    
    tool_calls = []
    user_question = extract_user_question_from_context
    
    # Analyze Claude's response to understand what data is needed
    needs_campaign_data = response.match?(/campaign|email.*performance|marketing.*data/i) || user_question.match?(/campaign|email|marketing/i)
    needs_contact_data = response.match?(/contact|audience|engagement/i) || user_question.match?(/contact|audience|subscriber/i)
    needs_landing_data = response.match?(/landing.*page|conversion/i) || user_question.match?(/landing|page|conversion/i)
    needs_analysis = response.match?(/analyz|insight|trend|performance|recommend/i) || user_question.match?(/analyz|insight|how.*doing|recommend/i)
    
    # Determine what objects to fetch
    objects = []
    objects << 'campaigns' if needs_campaign_data
    objects << 'contacts' if needs_contact_data  
    objects << 'landing_pages' if needs_landing_data
    objects << 'contact_groups' if user_question.match?(/group|segment/i)
    
    # Default to campaigns if Claude mentioned tools but no specific object detected
    objects = ['campaigns'] if objects.empty? && response.include?("TOOL_USE_NEEDED")
    
    # Add get_data tool if we identified objects to fetch
    if objects.any?
      tool_calls << {
        name: 'get_data',
        parameters: {
          objects: objects.uniq,
          filters: determine_appropriate_filters(user_question),
          include_metrics: true,
          limit: 20
        }
      }
    end
    
    # Add analysis if Claude's response suggests analytical work is needed
    if needs_analysis || tool_calls.any?
      analysis_type = determine_analysis_type_from_context(user_question, response)
      
      tool_calls << {
        name: 'analyze_data',
        parameters: {
          data_context: build_analysis_context(user_question, objects),
          analysis_type: analysis_type,
          user_question: user_question
        }
      }
    end
    
    # Creation patterns (if Claude mentions creating something)
    if response.match?(/create|new|build/i) || user_question.match?(/create|new|make|build/i)
      if user_question.match?(/campaign|email/i)
        tool_calls << {
          name: 'create_object',
          parameters: {
            object_type: 'campaigns',
            object_data: { name: extract_campaign_name_from_question(user_question) },
            auto_populate: true
          }
        }
      end
    end
    
    Rails.logger.info "Intelligent tool detection: needs_campaign=#{needs_campaign_data}, needs_contact=#{needs_contact_data}, needs_analysis=#{needs_analysis}, tools=#{tool_calls.map { |t| t[:name] }}"
    
    tool_calls
  end
  
  def determine_appropriate_filters(user_question)
    # Intelligently determine filters based on user question context
    filters = {}
    
    if user_question.match?(/recent|latest|new/i)
      filters[:created_at] = 'last_30_days'
    elsif user_question.match?(/this.*month/i)
      filters[:created_at] = 'this_month'
    elsif user_question.match?(/last.*month/i)
      filters[:created_at] = 'last_month'
    elsif user_question.match?(/this.*week/i)
      filters[:created_at] = 'last_7_days'
    else
      # Default to recent data
      filters[:created_at] = 'last_30_days'
    end
    
    # Add status filters if mentioned
    if user_question.match?(/sent|completed/i)
      filters[:status] = 'sent'
    elsif user_question.match?(/draft/i)
      filters[:status] = 'draft'
    end
    
    filters
  end
  
  def determine_analysis_type_from_context(user_question, claude_response)
    # Intelligently determine what type of analysis is needed
    
    if user_question.match?(/trend|over.*time|growing|declining/i)
      'trends'
    elsif user_question.match?(/compare|vs|versus|best|top|worst/i)
      'comparison'
    elsif user_question.match?(/improve|optimize|better|increase|boost/i)
      'optimization'
    elsif user_question.match?(/performance|how.*doing|metrics/i)
      'performance'
    elsif claude_response.match?(/insight|recommend/i)
      'summary'
    else
      'performance' # Default to performance analysis
    end
  end
  
  def build_analysis_context(user_question, objects)
    # Build contextual description for analysis
    object_types = objects.join(' and ')
    "User asked about #{object_types} data: '#{user_question}'"
  end
  
  def execute_tool_calls(function_calls)
    results = []
    
    function_calls.each do |function_call|
      tool_name = function_call[:name]
      parameters = function_call[:parameters] || {}
      
      Rails.logger.info "Executing tool: #{tool_name} with params: #{parameters}"
      
      result = @universal_tools.execute_tool(tool_name, parameters)
      
      results << {
        tool_name: tool_name,
        parameters: parameters,
        result: result,
        success: !result.key?(:error)
      }
    end
    
    results
  end
  
  def send_tool_results_to_claude(initial_response, tool_results)
    # Build a prompt with tool results for Claude to generate final response
    results_summary = format_tool_results_for_claude(tool_results)
    
    final_prompt = <<~PROMPT
      Based on the tool results below, provide a comprehensive response to the user's question.

      TOOL RESULTS:
      #{results_summary}

      INSTRUCTIONS:
      1. Use the actual data from the tool results
      2. Provide specific insights and metrics
      3. Be conversational and helpful
      4. Suggest next steps or ask follow-up questions
      5. Don't mention "tools" - just present the information naturally

      Provide a helpful response based on this real data:
    PROMPT
    
    @claude_service.send_message(final_prompt, "")
  end
  
  def format_tool_results_for_claude(tool_results)
    formatted_results = []
    
    tool_results.each do |result|
      if result[:success]
        case result[:tool_name]
        when 'get_data'
          formatted_results << format_get_data_results(result[:result])
        when 'analyze_data'
          formatted_results << format_analysis_results(result[:result])
        when 'create_object'
          formatted_results << format_creation_results(result[:result])
        end
      else
        formatted_results << "Error in #{result[:tool_name]}: #{result[:result][:error]}"
      end
    end
    
    formatted_results.join("\n\n")
  end
  
  def format_get_data_results(result)
    return "No data retrieved" unless result[:data]
    
    summary_parts = []
    
    result[:data].each do |object_type, data|
      records = data[:records] || []
      next if records.empty?
      
      summary_parts << "#{object_type.humanize}: #{records.length} records"
      
      # Add key metrics if available
      if records.first&.dig(:metrics)
        sample_metrics = records.first[:metrics]
        key_metrics = sample_metrics.select { |k, v| k.match?(/rate|score/) && v.is_a?(Numeric) }
        if key_metrics.any?
          avg_metrics = calculate_average_metrics(records)
          summary_parts << "  Average metrics: #{avg_metrics.map { |k, v| "#{k}: #{v}%" }.join(', ')}"
        end
      end
    end
    
    "Data Retrieved:\n#{summary_parts.join("\n")}"
  end
  
  def format_analysis_results(result)
    return "Analysis failed" unless result[:insights]
    
    "Analysis Results:\n#{result[:insights][:summary] || 'Analysis completed'}"
  end
  
  def format_creation_results(result)
    return "Creation failed" unless result[:success]
    
    "Created: #{result[:message]}"
  end
  
  def format_final_response(claude_response, tool_results)
    {
      message: claude_response,
      tool_calls_made: true,
      tool_results: tool_results,
      tools_used: tool_results.map { |r| r[:tool_name] }.uniq,
      success_count: tool_results.count { |r| r[:success] },
      error_count: tool_results.count { |r| !r[:success] }
    }
  end
  
  def build_fallback_prompt
    "You are Scout, a helpful AI marketing assistant. The user has asked a question about their marketing data. Provide a helpful response and explain that you're working on accessing their data directly."
  end
  
  def get_business_context
    profile = @user.business_profile
    return "No business profile available" unless profile
    
    "#{profile.industry} business targeting #{profile.target_audience}"
  end
  
  def extract_user_question_from_context
    @conversation_context.last&.dig(:content) || "General performance analysis"
  end
  
  def calculate_average_metrics(records)
    all_metrics = records.map { |r| r[:metrics] }.compact
    return {} if all_metrics.empty?
    
    avg_metrics = {}
    all_metrics.first.keys.each do |metric|
      values = all_metrics.map { |m| m[metric] }.compact.select { |v| v.is_a?(Numeric) }
      avg_metrics[metric] = (values.sum.to_f / values.length).round(2) if values.any?
    end
    
    avg_metrics.select { |k, v| k.match?(/rate|score/) }
  end
  
  def extract_campaign_name_from_question(question)
    # Try to extract a campaign name from the user's question
    if match = question.match(/create.*campaign.*for\s+([^.?!]+)/i)
      match[1].strip.titleize
    elsif match = question.match(/new.*campaign.*called\s+([^.?!]+)/i)
      match[1].strip.titleize  
    elsif match = question.match(/campaign.*named\s+([^.?!]+)/i)
      match[1].strip.titleize
    else
      "New Campaign #{Time.current.strftime('%m/%d')}"
    end
  end
  
  def extract_group_name_from_question(question)
    # Try to extract a group name from the user's question
    if match = question.match(/create.*group.*for\s+([^.?!]+)/i)
      match[1].strip.titleize
    elsif match = question.match(/new.*group.*called\s+([^.?!]+)/i)
      match[1].strip.titleize
    elsif match = question.match(/segment.*named\s+([^.?!]+)/i)
      match[1].strip.titleize
    else
      "New Segment #{Time.current.strftime('%m/%d')}"
    end
  end
  
  def extract_page_title_from_question(question)
    # Try to extract a page title from the user's question
    if match = question.match(/create.*page.*for\s+([^.?!]+)/i)
      match[1].strip.titleize
    elsif match = question.match(/new.*page.*called\s+([^.?!]+)/i)
      match[1].strip.titleize
    elsif match = question.match(/landing.*page.*about\s+([^.?!]+)/i)
      match[1].strip.titleize
    else
      "New Landing Page #{Time.current.strftime('%m/%d')}"
    end
  end
end 