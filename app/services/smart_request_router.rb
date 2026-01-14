# frozen_string_literal: true

# SmartRequestRouter - Simplified Qwen-first routing
#
# SIMPLIFIED STRATEGY (based on benchmarks):
#
# Qwen3-Next-80B is the DEFAULT for complex tasks because:
#   - Best overall: 9.2/10 (vs 8.2/10 for Qwen 3 32B)
#   - 100% tool success
#   - 131K context window (4x larger)
#
# Qwen 3 32B for FAST tasks (canvas loading, simple queries):
#   - 2x faster: 352ms vs 770ms
#   - Same 100% tool success
#   - Perfect for simple view/load operations
#
# DeepSeek R1 ONLY for complex reasoning:
#   - 22% better at reasoning (7.3 vs Qwen's 6.0)
#   - No tools needed for reasoning anyway
#
# NO HANDOFF LOGIC NEEDED - Qwen handles tools natively!
#
class SmartRequestRouter
  # Simple canvas loading patterns - use FAST Qwen 3 32B (352ms vs 770ms)
  SIMPLE_CANVAS_PATTERNS = [
    /^\s*(show|view|display|list|open)\s+(my\s+)?(contacts?|campaigns?|landing\s*pages?|documents?|modules?|tasks?|inbox|dashboard|analytics?)\s*$/i,
    /^\s*(show|view|display)\s+(me\s+)?(my\s+)?(contacts?|campaigns?|landing\s*pages?|documents?|modules?|tasks?)\s*$/i,
    /^\s*go\s+to\s+(contacts?|campaigns?|landing\s*pages?|documents?|modules?|tasks?|inbox|dashboard)\s*$/i,
    /^\s*(what's|show)\s+(in\s+)?(my\s+)?(inbox|dashboard)\s*\??\s*$/i,
  ].freeze

  # Patterns that need DeepSeek R1's advanced reasoning
  REASONING_PATTERNS = [
    /\b(analyze|analysis|evaluate|assessment)\b.*\b(strategy|business|market|data)\b/i,
    /\b(compare|contrast|pros\s+and\s+cons|tradeoffs?)\b/i,
    /\b(plan|planning|roadmap)\s+(for|to|the)\b/i,
    /\bwhy\s+(did|does|is|are|should|would)\b/i,
    /\b(calculate|compute)\b.*\b(ltv|cac|mrr|arr|roi|churn)\b/i,
    /\b(second|third)[\s-]order\s+effects?\b/i,
    /\bcausal\s+(chain|analysis|reasoning)\b/i,
    /\b(strategic|long[\s-]term)\s+(thinking|planning|analysis)\b/i,
  ].freeze

  # Tool categories for when we do need tools
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

  # Keyword to category mapping
  KEYWORD_TO_CATEGORY = {
    'email' => :communication,
    'contact' => :contacts,
    'task' => :tasks,
    'landing' => :content,
    'campaign' => :campaigns,
    'stripe' => :integrations,
    'module' => :modules,
    'browse' => :web_browsing,
    'website' => :web_browsing,
  }.freeze

  attr_reader :entity, :user

  def initialize(entity: nil, user: nil)
    @entity = entity
    @user = user
  end

  # Patterns that always need tools (creation/action requests)
  ACTION_PATTERNS = [
    /\b(create|make|build|generate|add)\s+(a\s+)?(new\s+)?(one|it|that|this)\b/i,  # "create a new one", "make one"
    /\b(create|make|build|generate|add)\s+(a\s+)?new\b/i,  # "create a new"
    /\b(send|save|import|export|fetch|update|delete|remove)\b/i,  # Action verbs
    /\bcan you\s+(create|make|build|send|save|get|fetch|import|export|show)/i,  # "can you create..."
    /\b(assign|delegate|hand\s*off)\s+(it|this|that|the\s+task)\b/i,  # "assign it", "delegate this"
    /\bjust\s+(do|assign|delegate|start|build)\s+it\b/i,  # "just do it", "just assign it"
  ].freeze

  # Canvas type to category mapping
  CANVAS_TO_CATEGORY = {
    'landing_page_viewer' => :content,
    'landing_page_editor' => :content,
    'contact_viewer' => :contacts,
    'campaign_viewer' => :campaigns,
    'module_viewer' => :modules,
    'document_viewer' => :documents,
  }.freeze

  # Main entry point - SIMPLIFIED Qwen-first routing
  # Returns: { needs_tools: bool, tool_categories: [], suggested_model: string }
  def analyze(message:, context: {})
    start_time = Time.current

    # Check for follow-up confirmations first (context-aware)
    followup_result = detect_followup_confirmation(message, context)
    if followup_result[:confident]
      return followup_result.merge(
        latency_ms: ((Time.current - start_time) * 1000).round,
        detection_method: :followup
      )
    end

    # Check for SIMPLE CANVAS LOADING → Qwen 3 32B (2x faster!)
    # Perfect for simple "show my contacts" type requests
    if SIMPLE_CANVAS_PATTERNS.any? { |p| message.match?(p) }
      return {
        needs_tools: true,
        confident: true,
        tool_categories: [:visualization],
        suggested_model: 'qwen-3-32b',  # 2x faster: 352ms vs 770ms
        reasoning: "Simple canvas loading - using faster Qwen 3 32B",
        latency_ms: ((Time.current - start_time) * 1000).round,
        detection_method: :simple_canvas
      }
    end

    # Check for COMPLEX REASONING patterns → DeepSeek R1
    # R1 is 22% better at reasoning (7.3 vs Qwen's 6.0)
    if REASONING_PATTERNS.any? { |p| message.match?(p) }
      return {
        needs_tools: false,  # R1 doesn't use tools well anyway
        confident: true,
        tool_categories: [],
        suggested_model: 'deepseek-r1',  # Benchmarked: 7.3/10 reasoning
        reasoning: "Complex reasoning detected - using DeepSeek R1",
        latency_ms: ((Time.current - start_time) * 1000).round,
        detection_method: :reasoning
      }
    end

    # Detect categories from message keywords
    categories = detect_tool_categories(message)
    
    # Also consider current canvas context
    if context[:canvas].present?
      canvas_type = context[:canvas]['type'] || context[:canvas][:type]
      if canvas_type && CANVAS_TO_CATEGORY[canvas_type]
        categories.add(CANVAS_TO_CATEGORY[canvas_type])
        Rails.logger.info "[SmartRouter] Added category #{CANVAS_TO_CATEGORY[canvas_type]} from canvas #{canvas_type}"
      end
    end
    
    # Check for action patterns that need tools
    needs_tools = categories.length > 1 || ACTION_PATTERNS.any? { |p| message.match?(p) }
    
    {
      needs_tools: needs_tools,
      confident: true,
      tool_categories: categories.to_a,
      suggested_model: 'qwen3-next-80b',  # Benchmarked: 9.2/10 overall, 100% tools, 131K context
      reasoning: 'Qwen3-Next-80B - best overall, handles tools natively',
      latency_ms: ((Time.current - start_time) * 1000).round,
      detection_method: :default
    }
  end

  # Detect tool categories from message keywords
  # Returns a Set (not Array) so caller can add more categories
  def detect_tool_categories(message)
    message_lower = message.downcase
    categories = Set.new([:general])

    KEYWORD_TO_CATEGORY.each do |keyword, category|
      categories.add(category) if message_lower.include?(keyword)
    end

    categories  # Return Set, not Array
  end

  # Get tool names for categories
  def tools_for_categories(categories)
    tools = []
    categories.each do |category|
      tools.concat(TOOL_CATEGORIES[category] || [])
    end
    tools.uniq
  end

  private

  # Detect if this is a follow-up confirmation to a tool-based action
  def detect_followup_confirmation(message, context)
    return { confident: false } unless context[:recent_messages].present?

    # Check if message is a short confirmation
    confirmation_patterns = [
      /^yes\b/i,
      /^yeah\b/i,
      /^yep\b/i,
      /^sure\b/i,
      /^do it\b/i,
      /^go ahead\b/i,
      /^ok\b/i,
      /^please\b/i,
      /^all\s+\d+/i,  # "all 10"
      /\bjust\s+(do|assign|delegate|start|build)\s+it\b/i,  # "just do it", "just assign it"
      /\b(assign|delegate)\s+it\b/i,  # "assign it", "delegate it"
      /^nah.*\b(do|assign|delegate|just)\b/i,  # "nah...just assign it"
      # Agent-related confirmations when AI just mentioned an agent
      /^agent\b/i,  # User saying "agent" after we mentioned one = YES, USE THAT AGENT
      /^that\s*(one|agent)?\b/i,  # "that one", "that"
      /^the\s*(first|second|one|agent)\b/i,  # "the first one"
      /^proceed\b/i,
      /^let'?s?\s+(do|go|start)\b/i,  # "let's do it", "lets go"
      /^(sounds?\s+good|perfect|great)\b/i,  # "sounds good", "perfect"
    ]

    is_short_confirmation = message.strip.split.length <= 10 &&
                            confirmation_patterns.any? { |p| message.strip.match?(p) }
    
    return { confident: false } unless is_short_confirmation

    # Check if last assistant message offered a tool-based action
    last_assistant = context[:recent_messages].reverse.find { |m| m[:role] == 'assistant' }
    return { confident: false } unless last_assistant

    assistant_content = last_assistant[:content].to_s.downcase

    # Patterns that indicate AI was offering to do something
    offer_patterns = [
      /would you like me to/,
      /should i/,
      /do you want me to/,
      /shall i/,
      /want me to/,
      /i can (create|save|send|import|export|fetch|update|delete)/,
      # Agent-related offers
      /the\s+(best|right|recommended)\s+agent/,
      /delegate\s+(this\s+)?to/,
      /hand\s+(this\s+)?(off\s+)?to/,
      /landing\s+page\s+manager/i,  # Specific agent mentions
      /i'?ve?\s+identified/,
      /proceed\s+with\s+delegating/,
    ]

    if offer_patterns.any? { |p| assistant_content.match?(p) }
      Rails.logger.info "[SmartRouter] Follow-up confirmation detected"
      return {
        confident: true,
        needs_tools: true,
        tool_categories: [:general, :contacts, :integrations],
        suggested_model: 'qwen3-next-80b',  # Default: handles tools natively
        reasoning: 'Follow-up confirmation to tool action offer'
      }
    end

    { confident: false }
  end
end
