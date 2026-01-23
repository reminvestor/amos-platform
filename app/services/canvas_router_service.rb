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
      /\b(schedule|scheduled|task)s?\b/i,
      /\b(show|view|list).*(task|schedule)/i
    ],
    'work_items' => [
      /\b(work item|inbox)s?\b/i,
      /\b(what.*(working on|pending)|show.*inbox)/i
    ],
    'operations_dashboard' => [
      /\b(operation|system|health)s?\s*(center|dashboard|status)?\b/i,
      /\b(notification|alert|warning|error)s?\s*(center|dashboard)?\b/i,
      /\b(show|view|check).*(notification|alert|system|health)/i,
      /\b(what.*(fail|error|wrong|broken))/i,
      /\b(any.*(issue|problem|error|failure))/i
    ],
    'integrations_manager' => [
      /\b(integration|connect)s?\s*(manager|settings?|config)?\b/i,
      /\b(manage|configure).*(integration|connection)/i,
      /\b(show|view|list|see).*(my\s+)?(integration|connection)s?\b/i,
      /\bmy\s+integrations?\b/i
    ],
    
    # Automation & Workflow canvases
    'automation_dashboard' => [
      /\b(automation|workflow|trigger)s?\s*(dashboard|overview|monitor)?\b/i,
      /\b(show|view|list).*(automation|workflow)s?\b/i,
      /\b(automation|workflow)\s+(stats?|metrics?|execution)/i
    ],
    'workflow_designer' => [
      /\b(edit|create|build|design).*(automation|workflow)/i,
      /\b(workflow|automation)\s+(editor|builder|designer)/i
    ],
    
    # Design Space canvases
    'design_preview' => [
      /\b(preview|show).*(web app|website|design|app)/i,
      /\b(web app|website|design)\s+preview\b/i,
      /\blive\s+preview\b/i
    ],
    'component_gallery' => [
      /\b(component|bootstrap)\s+(gallery|library|picker)/i,
      /\b(show|browse).*(component|ui element)s?\b/i
    ],
    'application_plan_preview' => [
      /\b(application|app)\s+plan\b/i,
      /\b(show|view).*(plan|blueprint)\b/i
    ],
    'landing_page_editor' => [
      /\b(edit|modify|change).*(landing page)/i,
      /\blanding page\s+editor\b/i
    ],
    
    # Keep these as hints - never auto-load, but signals intent
    '_freeform_hint' => [],
    '_visualization_hint' => []
  }.freeze
  
  # Context keywords to infer canvas from conversation history
  # When user says "show it" or "show me that", check recent messages for these
  CONTEXT_CANVAS_MAPPING = {
    # Automation/Workflow context
    %w[automation workflow trigger execution recipe] => 'automation_dashboard',
    # Integration context - now properly routes to integrations_manager
    %w[integration connection api stripe connected] => 'integrations_manager',
    # Design context
    %w[design preview component bootstrap layout] => 'design_preview',
    %w[landing page hero section testimonial] => 'landing_page_editor',
    %w[web app website module] => 'design_preview',
    # Planning context
    %w[plan blueprint application build] => 'application_plan_preview',
    # Data context
    %w[campaign email sequence] => 'campaign_viewer',
    %w[contact lead subscriber] => 'contact_viewer',
    %w[analytics performance report] => 'analytics',
    %w[dashboard overview summary] => 'dashboard'
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

  attr_reader :entity, :current_canvas, :conversation_history
  attr_accessor :llm_thinking_depth, :llm_context_topic

  def initialize(entity:, current_canvas: nil, conversation_history: nil)
    @entity = entity
    @current_canvas = current_canvas
    @conversation_history = conversation_history || []
    @llm_thinking_depth = nil
    @llm_context_topic = nil
  end

  # Main entry: Route message to appropriate canvas
  # Returns result in ~10ms for rule-based, ~150ms for LLM fallback
  def route(message:, use_llm_fallback: true)
    # Step 0: Check for bare "show" or "show it" - use context from history
    if bare_show_request?(message)
      context_canvas = infer_canvas_from_history
      if context_canvas
        Rails.logger.info "[CanvasRouter] Inferred '#{context_canvas}' from conversation context"
        return build_result(context_canvas.to_sym, message, source: :context)
      end
    end
    
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
  
  # Check if user is making a bare "show" request without specifying what
  def bare_show_request?(message)
    normalized = message.to_s.strip.downcase
    # Match: "show", "show it", "show me", "show that", "show me that", "display it", etc.
    normalized.match?(/^(show|display|view|see)\s*(it|that|this|me|me that|me this)?\.?!?$/i) ||
    normalized.match?(/^(can you |please )?(show|display|view)\s*(it|that|this)?\.?!?$/i)
  end
  
  # Infer canvas from recent conversation context
  def infer_canvas_from_history
    return nil if conversation_history.blank?
    
    # Get last 5 messages (both user and assistant)
    recent_messages = conversation_history.last(10).map do |msg|
      content = msg[:content] || msg['content'] || ''
      content.to_s.downcase
    end.join(' ')
    
    # Score each context mapping
    best_match = nil
    best_score = 0
    
    CONTEXT_CANVAS_MAPPING.each do |keywords, canvas|
      score = keywords.count { |kw| recent_messages.include?(kw) }
      if score > best_score
        best_score = score
        best_match = canvas
      end
    end
    
    # Only return if we have at least 2 keyword matches
    best_score >= 2 ? best_match : nil
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
    when 'automation_dashboard'
      summarize_automations(data)
    when 'workflow_designer'
      summarize_workflow(data)
    when 'design_preview'
      summarize_design_preview(data)
    when 'application_plan_preview'
      summarize_application_plan(data)
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
    # Use IntentClassifierService for unified LLM classification
    # Falls back to quick 4k token call - fast and cheap
    # NOW INCLUDES: design_intent - does user want to CREATE something?
    begin
      classifier = IntentClassifierService.new(entity: @entity)
      result = classifier.classify(
        message: message,
        conversation_history: @conversation_history,
        needs: [:canvas, :thinking_depth, :context_topic, :design_intent]  # All classifications in ONE call!
      )

      canvas = result[:canvas]&.to_sym || :keep_current
      
      # Store classifications for use by other services
      @llm_thinking_depth = result[:thinking_depth]&.to_sym
      @llm_context_topic = result[:context_topic]
      @llm_design_intent = result[:design_intent]  # :module, :app, :landing_page, :email, :workflow, :integration, :agent, or nil
      
      Rails.logger.info "[CanvasRouter] LLM classified: canvas=#{canvas}, depth=#{@llm_thinking_depth}, topic=#{@llm_context_topic}, design_intent=#{@llm_design_intent}"
      
      { 
        canvas: canvas, 
        source: :llm, 
        thinking_depth: @llm_thinking_depth, 
        context_topic: @llm_context_topic,
        design_intent: @llm_design_intent  # NEW: Design mode routing hint
      }
    rescue => e
      Rails.logger.warn "[CanvasRouter] LLM fallback failed: #{e.message}"
      { canvas: :keep_current, source: :error }
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
      thinking_depth: @llm_thinking_depth,  # LLM-suggested thinking depth (from fallback)
      context_topic: @llm_context_topic,    # LLM-inferred topic
      design_intent: @llm_design_intent,    # LLM-detected design intent (:module, :app, etc.)
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
  
  def summarize_automations(data)
    return "Automation dashboard: Loading..." unless data
    
    if data.is_a?(Hash)
      active = data[:active_count] || 0
      recent = data[:recent_executions] || 0
      "Automation dashboard: #{active} active automations, #{recent} recent executions"
    else
      "Automation dashboard"
    end
  end
  
  def summarize_workflow(data)
    return "Workflow editor: Loading..." unless data
    
    if data.is_a?(Hash) && data[:workflow_name]
      "Editing workflow: #{data[:workflow_name]}"
    else
      "Workflow editor"
    end
  end
  
  def summarize_design_preview(data)
    return "Design preview: Loading..." unless data
    
    if data.is_a?(Hash)
      type = data[:preview_type] || 'content'
      title = data[:title] || 'Preview'
      "Design preview: #{title} (#{type})"
    else
      "Design preview"
    end
  end
  
  def summarize_application_plan(data)
    return "Application plan: Loading..." unless data
    
    if data.is_a?(Hash)
      name = data[:name] || 'Untitled'
      status = data[:status] || 'draft'
      "Application plan: #{name} (#{status})"
    else
      "Application plan preview"
    end
  end
end



