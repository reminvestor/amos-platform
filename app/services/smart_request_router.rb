# frozen_string_literal: true

# SmartRequestRouter - Intelligent two-phase request routing
#
# ARCHITECTURE:
# 1. Zero-latency detection: Regex-based detection for obvious cases
# 2. Analysis phase: Use powerful model (no tools) to understand intent
# 3. Execution phase: Use tool-capable model with only relevant tools
#
# BENEFITS:
# - "Hello" skips 15K+ tool tokens → 90% cost reduction for simple chats
# - Can use Llama 3.2 90B for analysis (best reasoning, no tool streaming needed)
# - Selective tool loading (3-5 relevant tools instead of 50+)
# - Better model matching to task requirements
#
class SmartRequestRouter
  # Patterns that DEFINITELY need tools
  TOOL_REQUIRED_PATTERNS = [
    /\b(send|write|compose)\s+(an?\s+)?email/i,
    /\b(create|add|make)\s+(a\s+)?(contact|task|note|landing\s*page|campaign)/i,
    /\b(schedule|set\s+up|book)\s+(a\s+)?(meeting|call|appointment|task)/i,
    /\b(show|list|view|get|find|search)\s+(me\s+)?(my\s+)?(contacts?|tasks?|emails?|campaigns?|landing\s*pages?|modules?)/i,
    /\b(update|edit|modify|change|delete|remove)\s+(my\s+|the\s+|a\s+)?/i,
    /\b(analyze|report|dashboard|chart|graph|visuali[sz]e)\b/i,
    /\b(export|download|import|upload)\b/i,
    /\b(connect|integrate|sync)\s+(to|with)?\s*(stripe|shopify|hubspot|google|slack)/i,
    /\b(build|design|create)\s+(me\s+)?(a\s+)?(\w+\s+)?(module|app|workflow|automation|system)/i,
    /\b(browse|open|navigate|go\s+to)\s+(the\s+)?(website|url|page|site)/i,
    /\bespn\.com|cnn\.com|\.com\b/i,  # Web browsing hints (domain names)
    /\bhttps?:\/\//i,  # URLs
    
    # Real-time data queries - ALWAYS need tools
    /\b(current|today'?s?|right\s+now|latest)\s+(temperature|weather|price|stock|news)/i,
    /\b(weather|temperature|forecast)\s+(in|for|at)\b/i,
    /\bstock\s+price\b/i,
    /\b(what|how)\s+(is|are)\s+the\s+(weather|temperature|price)/i,
    
    # Knowledge lookups that need web search
    /\b(capital|population|president|founder|ceo|headquarters)\s+(of|in)\b/i,
    /\bwho\s+(is|was|founded|invented|created)\b/i,
    /\bwhen\s+(was|did|is)\s+\w+\s+(born|released|founded|invented)/i,
    /\bwhat\s+(year|country|city|currency)\b/i,
    /\bwhere\s+is\s+\w+\s+(located|headquartered|based)/i,
    
    # How many queries about data
    /\bhow\s+many\s+(contacts?|users?|customers?|leads?|tasks?|campaigns?)/i,
  ].freeze

  # Patterns that DEFINITELY don't need tools
  # IMPORTANT: Be VERY conservative here - only truly simple greetings/acknowledgments
  NO_TOOLS_PATTERNS = [
    /^(hi|hello|hey|yo|sup|howdy|greetings?)[\s!.,?]*$/i,  # ONLY exact greetings
    /^(hi|hello|hey)\s+(there|amos|buddy|friend)[\s!.,?]*$/i,  # "hi there" etc
    /^(thanks?|thank\s*you|thx|ty)[\s!.,?]*$/i,
    /^(ok|okay|alright|sure|got\s*it|sounds\s*good)[\s!.,?]*$/i,
    /^(yes|no|yeah|nope|yep|nah)[\s!.,?]*$/i,
    /^(bye|goodbye|later|see\s*ya|cya)[\s!.,?]*$/i,
    /^(good\s*(morning|afternoon|evening|night))[\s!.,?]*$/i,
    
    # REMOVED: The overly broad "what/who/how" pattern that was catching real queries
    # Instead, only match very specific explanatory patterns
    /^(explain|define)\s+(what\s+)?(a|an|the)?\s*\w+\s+(is|means)[\s!.,?]*$/i,  # "explain what X is"
    /^(what\s+does|what\s+is)\s+(the\s+)?(meaning|definition)\s+of\b/i,  # "what is the meaning of"
  ].freeze

  # Tool categories for selective loading
  TOOL_CATEGORIES = {
    communication: %w[send_email_tool compose_email search_contacts_tool],
    contacts: %w[search_contacts_tool create_contact_tool update_contact_tool list_contacts_tool],
    tasks: %w[create_task_tool list_tasks_tool update_task_tool],
    content: %w[create_landing_page_tool update_landing_page_tool list_landing_pages_tool],
    campaigns: %w[create_campaign_tool list_campaigns_tool campaign_analytics_tool],
    visualization: %w[create_freeform_canvas_tool load_canvas_tool save_visualization_tool],
    web_browsing: %w[browse_web_tool read_viewed_page_tool web_proxy_interact_tool],
    modules: %w[design_module_schema_tool approve_module_design_tool list_modules_tool],
    integrations: %w[execute_integration_tool list_integrations_tool],
    documents: %w[read_document_tool parse_csv_tool bulk_import_tool export_to_csv_tool],
    scheduling: %w[create_scheduled_task_tool list_scheduled_tasks_tool],
    general: %w[get_platform_capabilities_tool ask_user_tool]
  }.freeze

  # Keyword to category mapping for quick tool selection
  KEYWORD_TO_CATEGORY = {
    'email' => :communication,
    'contact' => :contacts,
    'task' => :tasks,
    'landing' => :content,
    'campaign' => :campaigns,
    'chart' => :visualization,
    'graph' => :visualization,
    'visualize' => :visualization,
    'dashboard' => :visualization,
    'freeform' => :visualization,
    'canvas' => :visualization,
    'display' => :visualization,
    'show data' => :visualization,
    'table' => :visualization,
    'browse' => :web_browsing,
    'website' => :web_browsing,
    'espn' => :web_browsing,
    'module' => :modules,
    'app' => :modules,
    'integrate' => :integrations,
    'sync' => :integrations,
    'csv' => :documents,
    'export' => :documents,
    'import' => :documents,
    'schedule' => :scheduling,
  }.freeze

  attr_reader :entity, :user

  def initialize(entity:, user:)
    @entity = entity
    @user = user
  end

  # Main entry point: Analyze request and determine routing
  # Returns: { needs_tools: bool, tool_categories: [], suggested_model: string, phase: :direct | :analysis | :execution }
  def analyze(message:, context: {})
    start_time = Time.current

    # Phase 1: Zero-latency regex detection
    zero_latency_result = zero_latency_detect(message)
    
    if zero_latency_result[:confident]
      latency_ms = ((Time.current - start_time) * 1000).round
      return zero_latency_result.merge(
        latency_ms: latency_ms,
        detection_method: :regex
      )
    end

    # Phase 2: Quick LLM analysis for ambiguous cases
    # Use a fast model to determine if tools are needed
    llm_result = llm_analyze(message, context)
    
    latency_ms = ((Time.current - start_time) * 1000).round
    llm_result.merge(
      latency_ms: latency_ms,
      detection_method: :llm
    )
  end

  # Zero-latency detection using regex patterns
  def zero_latency_detect(message)
    # Check for definite no-tools patterns
    if NO_TOOLS_PATTERNS.any? { |p| message.match?(p) }
      return {
        needs_tools: false,
        confident: true,
        phase: :direct,
        suggested_model: 'deepseek-v3',  # DeepSeek for direct responses
        reasoning: 'Simple greeting/acknowledgment - no tools needed'
      }
    end

    # Check for definite tools-required patterns
    if TOOL_REQUIRED_PATTERNS.any? { |p| message.match?(p) }
      categories = detect_tool_categories(message)
      
      return {
        needs_tools: true,
        confident: true,
        phase: :execution,
        tool_categories: categories,
        suggested_model: 'mistral-large-3',  # Mistral handles Bedrock tool format correctly
        reasoning: "Tool-required pattern detected: #{categories.join(', ')}"
      }
    end

    # Ambiguous - need LLM analysis
    {
      needs_tools: :unknown,
      confident: false,
      phase: :analysis,
      reasoning: 'Ambiguous request - needs LLM analysis'
    }
  end

  # Detect which tool categories are relevant based on keywords
  def detect_tool_categories(message)
    message_lower = message.downcase
    categories = Set.new([:general])  # Always include general

    KEYWORD_TO_CATEGORY.each do |keyword, category|
      if message_lower.include?(keyword)
        categories.add(category)
      end
    end

    categories.to_a
  end

  # Get the actual tool names for given categories
  def tools_for_categories(categories)
    tools = []
    categories.each do |category|
      tools.concat(TOOL_CATEGORIES[category] || [])
    end
    tools.uniq
  end

  private

  # LLM-based analysis for ambiguous cases
  def llm_analyze(message, context)
    # Use a fast model to quickly analyze intent
    analysis_prompt = build_analysis_prompt(message, context)
    
    begin
      bedrock = BedrockService.new(user: user, entity: entity)
      
      response = bedrock.send_message(
        analysis_prompt[:system],
        [{ role: 'user', content: [{ type: 'text', text: analysis_prompt[:user] }] }],
        model: 'mistral-small',  # Fast, cheap for classification
        max_tokens: 200,
        temperature: 0.1,
        json_mode: true
      )

      parse_analysis_response(response)
    rescue => e
      Rails.logger.error "[SmartRequestRouter] LLM analysis failed: #{e.message}"
      # Default to including tools if analysis fails
      {
        needs_tools: true,
        confident: false,
        phase: :execution,
        tool_categories: [:general],
        suggested_model: 'mistral-large-3',
        reasoning: "Analysis failed, defaulting to tool-enabled mode"
      }
    end
  end

  def build_analysis_prompt(message, context)
    {
      system: <<~SYSTEM,
        You are a request classifier. Analyze the user's message and determine:
        1. Does this request need tools/actions, or is it just a question/conversation?
        2. If tools needed, what categories? (communication, contacts, tasks, content, campaigns, visualization, web_browsing, modules, integrations, documents, scheduling)
        
        Respond in JSON format:
        {
          "needs_tools": true/false,
          "categories": ["category1", "category2"],
          "reasoning": "brief explanation"
        }
        
        Examples:
        - "Hello" → {"needs_tools": false, "categories": [], "reasoning": "greeting"}
        - "What is quantum physics?" → {"needs_tools": false, "categories": [], "reasoning": "general knowledge question"}
        - "Send an email to John" → {"needs_tools": true, "categories": ["communication", "contacts"], "reasoning": "email action required"}
        - "Show me my contacts" → {"needs_tools": true, "categories": ["contacts"], "reasoning": "data retrieval"}
      SYSTEM
      user: message
    }
  end

  def parse_analysis_response(response)
    content = response[:content].first[:text] rescue response.to_s
    
    # Try to parse JSON
    json = JSON.parse(content) rescue nil
    
    if json
      needs_tools = json['needs_tools'] == true
      categories = (json['categories'] || []).map(&:to_sym)
      
      {
        needs_tools: needs_tools,
        confident: true,
        phase: needs_tools ? :execution : :direct,
        tool_categories: categories.presence || [:general],
        suggested_model: needs_tools ? 'mistral-large-3' : 'deepseek-v3',  # Mistral for tools, DeepSeek for direct
        reasoning: json['reasoning'] || 'LLM classification'
      }
    else
      # Fallback if parsing fails
      {
        needs_tools: true,
        confident: false,
        phase: :execution,
        tool_categories: [:general],
        suggested_model: 'mistral-large-3',
        reasoning: 'Could not parse LLM response, defaulting to tools'
      }
    end
  end
end

