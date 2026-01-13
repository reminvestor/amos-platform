# frozen_string_literal: true

# SmartRequestRouter - Lightweight DeepSeek-first routing
#
# SIMPLIFIED ARCHITECTURE:
# 1. Minimal regex for OBVIOUS tool cases only (create, send, show my data)
# 2. Everything else defaults to DeepSeek
# 3. DeepSeek uses [HANDOFF_TO_MISTRAL] when it needs tools
#
# This avoids endless regex maintenance - DeepSeek is smart enough to know
# when it needs tools and will request a handoff to Mistral.
#
class SmartRequestRouter
  # Patterns that OBVIOUSLY need tools - keep this MINIMAL!
  # Only cases where we're 100% certain tools are required.
  # For anything ambiguous, let DeepSeek try first and handoff if needed.
  TOOL_REQUIRED_PATTERNS = [
    # Explicit CRUD on platform objects
    /\b(create|add|new)\s+(a\s+)?(contact|task|landing\s*page|campaign|module)\b/i,
    /\b(send|compose)\s+(an?\s+)?email\s+to\b/i,
    /\b(delete|remove)\s+(the\s+|my\s+)?(contact|task|campaign|landing\s*page)\b/i,
    
    # Explicit retrieval of MY platform data
    /\b(show|list|get)\s+(me\s+)?(my|all)\s+(contacts?|tasks?|campaigns?|customers?|modules?)\b/i,
    
    # Explicit integrations
    /\b(connect|sync)\s+(to|with)\s+(stripe|shopify|hubspot|slack)\b/i,
    /\bget\s+(my\s+)?stripe\s+(customers?|data)\b/i,
    
    # URLs = web browsing needed
    /\bhttps?:\/\/\S+/i,
    
    # Explicit real-time data
    /\b(current|live|today'?s?)\s+(weather|stock\s+price)\b/i,
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

  # Main entry point
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

    # Check for OBVIOUS tool patterns
    if TOOL_REQUIRED_PATTERNS.any? { |p| message.match?(p) }
      categories = detect_tool_categories(message)
      return {
        needs_tools: true,
        confident: true,
        tool_categories: categories,
        suggested_model: 'mistral-large-3',
        reasoning: "Obvious tool pattern: #{categories.join(', ')}",
        latency_ms: ((Time.current - start_time) * 1000).round,
        detection_method: :regex
      }
    end

    # DEFAULT: Send to DeepSeek (no tools)
    # DeepSeek will use [HANDOFF_TO_MISTRAL] if it needs tools
    {
      needs_tools: false,
      confident: true,
      tool_categories: [],
      suggested_model: 'deepseek-v3',
      reasoning: 'Default to DeepSeek - will handoff to Mistral if tools needed',
      latency_ms: ((Time.current - start_time) * 1000).round,
      detection_method: :default
    }
  end

  # Detect tool categories from message keywords
  def detect_tool_categories(message)
    message_lower = message.downcase
    categories = Set.new([:general])

    KEYWORD_TO_CATEGORY.each do |keyword, category|
      categories.add(category) if message_lower.include?(keyword)
    end

    categories.to_a
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
    ]

    if offer_patterns.any? { |p| assistant_content.match?(p) }
      Rails.logger.info "[SmartRouter] Follow-up confirmation detected"
      return {
        confident: true,
        needs_tools: true,
        tool_categories: [:general, :contacts, :integrations],
        suggested_model: 'mistral-large-3',
        reasoning: 'Follow-up confirmation to tool action offer'
      }
    end

    { confident: false }
  end
end
