# frozen_string_literal: true

# CanvasRouterService - Offloads canvas selection from Amos
#
# Runs IN PARALLEL with Amos prompt building for zero added latency.
# Uses Haiku 3.5 for fast classification (~100-150ms).
#
# Returns:
#   - canvas_type: Which canvas to load
#   - context_summary: Token-efficient context for Amos
#   - delegate_to_amos: true if Amos should handle (freeform, visualization)
#
class CanvasRouterService
  # Canvas patterns for rule-based matching (zero latency, covers 70% of cases)
  CANVAS_PATTERNS = {
    # Data viewing - BUILT-IN canvases
    'dashboard' => [
      /\b(dashboard|overview|summary|home)\b/i,
      /^(show me |what's |how are ).*(stats?|metrics?|numbers?)/i
    ],
    'campaign_viewer' => [
      /\b(campaign|email campaign)s?\b/i,
      /\b(show|view|list|check).*(campaign)/i
    ],
    'contact_viewer' => [
      /\b(contact|lead|subscriber)s?\b/i,
      /\b(show|view|list).*(contact|lead|people)/i
    ],
    'landing_page_viewer' => [
      /\b(landing page|lp)s?\b/i,
      /\b(show|view|list).*(landing|page)/i
    ],
    'document_viewer' => [
      /\b(document|file|upload|pdf)s?\b/i,
      /\b(show|view|read).*(document|file)/i
    ],
    'analytics' => [
      /\b(analytics?|performance|metrics?|report)\b/i,
      /\b(how.*(perform|doing)|what.*(results?|numbers?))/i
    ],
    
    # Management canvases
    'module_manager' => [
      /\b(module|app|custom app)s?\b/i,
      /\b(create|build|manage).*(module|app)/i
    ],
    'scheduled_tasks' => [
      /\b(schedule|scheduled|task|automation)s?\b/i,
      /\b(show|view|list).*(task|schedule)/i
    ],
    'work_items' => [
      /\b(work item|inbox|notification)s?\b/i,
      /\b(what.*(working on|pending)|show.*inbox)/i
    ],
    'integrations_manager' => [
      /\b(integration|connect)s?\s*(manager|settings?|config)?\b/i,
      /\b(manage|configure).*(integration|connection)/i
    ],
    
    # Keep these as hints - never auto-load, but signals intent
    '_freeform_hint' => [],
    '_visualization_hint' => []
  }.freeze

  # Integration patterns - trigger freeform canvas preparation
  # These don't have built-in canvases, so Amos needs create_freeform_canvas
  INTEGRATION_PATTERNS = [
    /\b(stripe|quickbooks|shopify|hubspot|salesforce|mailgun|twilio)\b/i,
    /\b(show|get|list|view).*(customer|invoice|payment|transaction|order|product)s?\b/i,
    /\b(integration|api)\s+(data|records?|results?)\b/i
  ].freeze

  # Intents that don't need canvas changes
  NO_CANVAS_PATTERNS = [
    /^(hi|hello|hey|thanks|ok|yes|no|sure)\b/i,
    /\?$/,  # Pure questions often don't need canvas change
    /\b(what do you think|help me understand|explain)\b/i,
    /\b(how does|why does|what is)\b/i
  ].freeze

  attr_reader :entity, :current_canvas

  def initialize(entity:, current_canvas: nil)
    @entity = entity
    @current_canvas = current_canvas
  end

  # Main entry: Route message to appropriate canvas
  # Returns result in ~10ms for rule-based, ~150ms for LLM fallback
  def route(message:, use_llm_fallback: true)
    # Step 1: Quick rule-based check (zero latency)
    rule_result = match_by_rules(message)
    
    if rule_result[:confident]
      return build_result(rule_result[:canvas], message, source: :rules)
    end

    # Step 2: Check if no canvas change needed
    if should_keep_current?(message)
      return build_result(:keep_current, message, source: :rules)
    end

    # Step 3: LLM fallback for ambiguous cases (only if enabled)
    if use_llm_fallback && rule_result[:canvas].nil?
      llm_result = classify_with_llm(message)
      return build_result(llm_result[:canvas], message, source: :llm)
    end

    # Step 4: Default to keeping current canvas
    build_result(rule_result[:canvas] || :keep_current, message, source: :rules)
  end

  # Parallel-safe: Can be called in thread while Amos prompt builds
  def route_async(message:)
    Thread.new do
      route(message: message)
    end
  end

  # Generate context summary for Amos (token-efficient)
  def generate_context_summary(canvas_type:, data: nil)
    case canvas_type.to_s
    when 'dashboard'
      summarize_dashboard(data)
    when 'landing_page_viewer'
      summarize_landing_pages(data)
    when 'campaign_viewer'
      summarize_campaigns(data)
    when 'contact_viewer'
      summarize_contacts(data)
    when 'analytics'
      summarize_analytics(data)
    when 'module_manager'
      summarize_modules(data)
    when 'keep_current'
      "Keeping current view: #{current_canvas || 'none'}"
    else
      "Showing: #{canvas_type}"
    end
  end

  private

  def match_by_rules(message)
    matched = nil
    confidence = 0

    # First check for built-in canvas patterns
    CANVAS_PATTERNS.each do |canvas, patterns|
      patterns.each do |pattern|
        if message.match?(pattern)
          matched = canvas
          confidence += 1
        end
      end
    end

    # If no built-in canvas matched, check for integration patterns
    # These need freeform canvas (no built-in viewer for Stripe, QuickBooks, etc.)
    if matched.nil?
      is_integration_query = INTEGRATION_PATTERNS.any? { |p| message.match?(p) }
      if is_integration_query
        matched = '_freeform_hint'
        confidence = 1
        Rails.logger.info "[CanvasRouter] Integration query detected - will need create_freeform_canvas"
      end
    end

    {
      canvas: matched&.to_sym,
      confident: confidence >= 1,
      confidence_score: confidence,
      needs_freeform: matched == '_freeform_hint'
    }
  end

  def should_keep_current?(message)
    NO_CANVAS_PATTERNS.any? { |p| message.match?(p) }
  end

  def classify_with_llm(message)
    # Use Nemotron Nano 2 for fast, cheap classification (OPEN SOURCE)
    # $0.06/$0.23 per 1M tokens - cheapest model available
    prompt = build_classification_prompt(message)
    
    begin
      bedrock_service = BedrockService.new(@entity)
      response = bedrock_service.send_message_converse(
        prompt,
        model: 'nemotron-nano',
        max_tokens: 50,
        temperature: 0.1
      )

      result = response.to_s.strip.downcase
      
      # Parse response
      canvas = parse_llm_response(result)
      { canvas: canvas, source: :llm }
    rescue => e
      Rails.logger.warn "[CanvasRouter] LLM fallback failed: #{e.message}"
      { canvas: :keep_current, source: :error }
    end
  end

  def build_classification_prompt(message)
    available = CANVAS_PATTERNS.keys.join(', ')
    
    <<~PROMPT
      Classify this user message to a canvas type. Reply with ONLY the canvas name.
      
      Available: #{available}, keep_current
      
      Message: "#{message.truncate(200)}"
      
      Canvas:
    PROMPT
  end

  def parse_llm_response(response)
    return :keep_current if response.blank?
    
    # Clean and match
    clean = response.gsub(/[^a-z_]/, '')
    
    if CANVAS_PATTERNS.keys.include?(clean)
      clean.to_sym
    elsif clean.include?('keep') || clean.include?('current') || clean.include?('none')
      :keep_current
    else
      :keep_current
    end
  end

  def build_result(canvas, message, source:)
    # Determine if Amos should handle this
    # Note: freeform and visualization are now handled ONLY via tools, not auto-loading
    # They won't match any patterns, so this check is mainly for future safety
    delegate = %i[freeform visualization _freeform_hint _visualization_hint].include?(canvas&.to_sym)
    
    # If it's a freeform hint, provide guidance to Amos
    needs_freeform = canvas&.to_sym == :_freeform_hint

    {
      canvas: needs_freeform ? :keep_current : canvas,  # Don't auto-load freeform
      delegate_to_amos: delegate,
      needs_freeform: needs_freeform,  # Signal that create_freeform_canvas will be needed
      source: source,
      context_summary: nil, # Will be filled by caller after data load
      timestamp: Time.current
    }
  end

  # Context summarizers - keep these SHORT (target: <50 tokens each)
  
  def summarize_dashboard(data)
    return "Dashboard: Loading..." unless data
    
    stats = [
      data[:campaigns_count] && "#{data[:campaigns_count]} campaigns",
      data[:contacts_count] && "#{data[:contacts_count]} contacts",
      data[:landing_pages_count] && "#{data[:landing_pages_count]} landing pages"
    ].compact.join(', ')
    
    "Dashboard showing: #{stats}"
  end

  def summarize_landing_pages(data)
    return "Landing pages: Loading..." unless data
    
    if data.is_a?(Array)
      count = data.length
      best = data.max_by { |lp| lp[:conversion_rate] || 0 }
      best_info = best ? " (best: '#{best[:name]&.truncate(20)}' #{best[:conversion_rate]}% CVR)" : ""
      "Showing #{count} landing pages#{best_info}"
    else
      "Landing pages viewer"
    end
  end

  def summarize_campaigns(data)
    return "Campaigns: Loading..." unless data
    
    if data.is_a?(Array)
      active = data.count { |c| c[:status] == 'active' }
      "Showing #{data.length} campaigns (#{active} active)"
    else
      "Campaigns viewer"
    end
  end

  def summarize_contacts(data)
    return "Contacts: Loading..." unless data
    
    count = data.is_a?(Array) ? data.length : data[:total_count]
    "Showing #{count || 'many'} contacts"
  end

  def summarize_analytics(data)
    return "Analytics: Loading..." unless data
    
    "Analytics showing performance metrics"
  end

  def summarize_modules(data)
    return "Module manager: Loading..." unless data
    
    if data.is_a?(Array)
      "Module manager with #{data.length} custom modules"
    else
      "Module manager"
    end
  end
end



