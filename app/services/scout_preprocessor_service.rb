# frozen_string_literal: true

# ScoutPreprocessorService - Parallel preprocessing for Scout requests
#
# Runs model selection and canvas routing in parallel to minimize latency.
# Provides context injection for Amos without bloating the prompt.
#
# Usage:
#   preprocessor = ScoutPreprocessorService.new(entity: entity, current_canvas: 'dashboard')
#   result = preprocessor.preprocess(message: "Show me my landing pages", mode: :auto)
#   
#   result[:model]          # Selected model
#   result[:canvas]         # Canvas to load (or :keep_current)
#   result[:context_inject] # Context string to inject into prompt
#   result[:latency_ms]     # Processing time
#
class ScoutPreprocessorService
  attr_reader :entity, :current_canvas, :user

  def initialize(entity:, current_canvas: nil, user: nil)
    @entity = entity
    @current_canvas = current_canvas
    @user = user
  end

  # Main entry point - runs preprocessing in parallel
  # Target: <50ms for rule-based, <200ms with LLM fallback
  def preprocess(message:, mode: :auto, use_canvas_llm: false)
    start_time = Time.current

    # Run model selection and canvas routing in parallel
    model_thread = Thread.new { select_model(message, mode) }
    canvas_thread = Thread.new { route_canvas(message, use_canvas_llm) }

    # Wait for both to complete
    model_result = model_thread.value
    canvas_result = canvas_thread.value

    # Generate context injection (very fast, no I/O)
    context_inject = build_context_injection(canvas_result, message)

    latency_ms = ((Time.current - start_time) * 1000).round

    {
      model: model_result[:model],
      model_tier: model_result[:tier],
      model_reasoning: model_result[:reasoning],
      canvas: canvas_result[:canvas],
      canvas_delegate: canvas_result[:delegate_to_amos],
      canvas_source: canvas_result[:source],
      context_inject: context_inject,
      latency_ms: latency_ms,
      timestamp: Time.current
    }
  end

  # Synchronous version for simpler use cases
  def preprocess_sync(message:, mode: :auto)
    start_time = Time.current

    model_result = select_model(message, mode)
    canvas_result = route_canvas(message, false) # Skip LLM for sync
    context_inject = build_context_injection(canvas_result, message)

    latency_ms = ((Time.current - start_time) * 1000).round

    {
      model: model_result[:model],
      model_tier: model_result[:tier],
      canvas: canvas_result[:canvas],
      canvas_delegate: canvas_result[:delegate_to_amos],
      context_inject: context_inject,
      latency_ms: latency_ms
    }
  end

  private

  def select_model(message, mode)
    selector = ModelSelectionService.new(provider: :anthropic)
    selector.select_model(message: message, mode: mode)
  end

  def route_canvas(message, use_llm)
    router = CanvasRouterService.new(entity: entity, current_canvas: current_canvas)
    router.route(message: message, use_llm_fallback: use_llm)
  end

  def build_context_injection(canvas_result, message)
    canvas = canvas_result[:canvas]
    
    # Special cases that Amos must handle
    # Note: freeform and visualization no longer auto-route - they are handled by tools
    if canvas_result[:delegate_to_amos]
      case canvas
      when :freeform, :_freeform_hint
        return <<~CONTEXT
          [CANVAS: User needs custom freeform content. Use create_freeform_canvas tool with HTML content.]
        CONTEXT
      when :visualization, :_visualization_hint
        return <<~CONTEXT
          [CANVAS: User wants a chart/visualization. Use create_freeform_canvas tool with chart HTML/JS.]
        CONTEXT
      end
    end

    # Keep current - minimal injection
    if canvas == :keep_current || canvas.nil?
      if current_canvas.present?
        return "[CURRENT VIEW: #{current_canvas}]"
      else
        return "" # No injection needed
      end
    end

    # Canvas will be loaded - tell Amos what's showing
    summary = generate_canvas_summary(canvas)
    
    <<~CONTEXT
      [AUTO-LOADED: #{canvas} canvas is now visible to user. #{summary}]
    CONTEXT
  end

  def generate_canvas_summary(canvas)
    case canvas.to_s
    when 'dashboard'
      stats = fetch_dashboard_stats
      "Shows overview: #{stats[:campaigns]} campaigns, #{stats[:contacts]} contacts, #{stats[:landing_pages]} landing pages."
    when 'landing_page_viewer'
      count = entity.landing_pages.count
      "Shows #{count} landing pages."
    when 'campaign_viewer'
      active = entity.campaigns.where(status: 'active').count
      total = entity.campaigns.count
      "Shows #{total} campaigns (#{active} active)."
    when 'contact_viewer'
      count = entity.contacts.count
      "Shows #{count} contacts."
    when 'analytics'
      "Shows performance analytics and metrics."
    when 'module_manager'
      count = entity.app_modules.count
      "Shows #{count} custom modules."
    when 'scheduled_tasks'
      "Shows scheduled tasks and automations."
    when 'work_items'
      "Shows work inbox with pending items."
    else
      "Shows #{canvas} view."
    end
  end

  def fetch_dashboard_stats
    {
      campaigns: entity.campaigns.count,
      contacts: entity.contacts.count,
      landing_pages: entity.landing_pages.count
    }
  rescue
    { campaigns: 0, contacts: 0, landing_pages: 0 }
  end
end



