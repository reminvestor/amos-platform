# frozen_string_literal: true

# PluginInjectionService - Injects agent plugin capabilities directly into Amos
#
# Instead of delegating to separate agents, this service merges an agent's
# system prompt and tools directly into Amos's context, allowing him to
# handle specialized tasks in a single LLM call.
#
# Benefits:
# - 50% faster responses (one LLM call instead of two)
# - Full conversation context preserved
# - Unified user experience (always Amos)
# - Lower cost per interaction
#
# Usage:
#   service = PluginInjectionService.new(user: user, entity: entity)
#   injection = service.select_plugin(
#     canvas_context: { type: 'landing_page_editor', landing_page_id: 123 },
#     message: "Change the hero background color",
#     intent: :operate
#   )
#
#   # Returns:
#   # {
#   #   plugin: AgentPlugin,
#   #   prompt_block: "## CURRENT SPECIALIZATION: Landing Page Manager\n...",
#   #   tools: ["edit_landing_page_section", "read_landing_page_sections", ...],
#   #   injection_reason: "Canvas context: landing_page_editor"
#   # }
#
class PluginInjectionService
  # Canvas type → Plugin slug mapping
  # When user is viewing a specific canvas, inject that plugin's capabilities
  CANVAS_PLUGIN_MAP = {
    'landing_page_editor' => 'landing_page_manager',
    'website_editor' => 'website_manager',
    'workflow_designer' => 'workflow_architect',
    'app_designer' => 'app_architect',
    'crm_dashboard' => 'crm_agent',
    'integrations_manager' => nil, # Amos handles integrations directly
    'document_viewer' => nil,
    'freeform' => nil
  }.freeze

  # Alias for backward compatibility with other services
  CANVAS_TO_PLUGIN_MAP = CANVAS_PLUGIN_MAP

  # Intent → Plugin suggestions (used when no canvas match)
  INTENT_PLUGIN_MAP = {
    crm: 'crm_agent',
    landing_page: 'landing_page_manager',
    website: 'website_manager',
    workflow: 'workflow_architect',
    analytics: 'analytics_agent',
    email: 'email_agent'
  }.freeze

  # Keywords that suggest specific plugins
  KEYWORD_PLUGIN_MAP = {
    /landing\s*page|hero\s*section|cta\s*button/i => 'landing_page_manager',
    /workflow|automation|trigger/i => 'workflow_architect',
    /crm|contact|lead|opportunity|pipeline/i => 'crm_agent',
    /website|web\s*page|site\s*page/i => 'website_manager',
    /email|newsletter|campaign/i => 'email_agent'
  }.freeze

  attr_reader :user, :entity

  def initialize(user:, entity:)
    @user = user
    @entity = entity
    @plugin_cache = {}
    @optimization_service = nil # Lazy loaded
  end

  # ═══════════════════════════════════════════════════════════════
  # METRIC RECORDING (call after interaction completes)
  # ═══════════════════════════════════════════════════════════════

  def record_success(plugin_slug:, canvas:, quality: nil, response_time_ms: nil, session_id: nil, details: {})
    optimization_service.record_success(
      loadout_slug: plugin_slug,
      user: user,
      canvas: canvas,
      quality: quality,
      response_time_ms: response_time_ms,
      session_id: session_id,
      details: details
    )
  end

  def record_failure(plugin_slug:, canvas:, error: nil, session_id: nil, details: {})
    optimization_service.record_failure(
      loadout_slug: plugin_slug,
      user: user,
      canvas: canvas,
      session_id: session_id,
      details: details.merge(error: error)
    )
  end

  def record_hallucination(plugin_slug:, canvas:, response: nil, session_id: nil, details: {})
    optimization_service.record_hallucination(
      loadout_slug: plugin_slug,
      user: user,
      canvas: canvas,
      session_id: session_id,
      details: details.merge(response_preview: response.to_s.truncate(500))
    )
  end

  def record_tool_call(plugin_slug:, tool_name:, success:, canvas: nil, session_id: nil, details: {})
    optimization_service.record_tool_call(
      loadout_slug: plugin_slug,
      tool_name: tool_name,
      success: success,
      user: user,
      canvas: canvas,
      session_id: session_id,
      details: details
    )
  end

  def optimization_service
    @optimization_service ||= LoadoutOptimizationService.new(entity: entity)
  end

  # Main entry point: Select and prepare a plugin for injection
  def select_plugin(canvas_context: nil, message: nil, intent: nil, classification: nil)
    # Priority order:
    # 1. Canvas context (highest priority - user is viewing something specific)
    # 2. Explicit mention in message
    # 3. Keyword matching
    # 4. Intent-based suggestion
    
    plugin = nil
    injection_reason = nil

    # 1. Canvas-based selection (highest priority)
    if canvas_context.present?
      canvas_type = canvas_context[:type] || canvas_context['type']
      plugin_slug = CANVAS_PLUGIN_MAP[canvas_type]
      
      if plugin_slug.present?
        plugin = find_plugin(plugin_slug)
        injection_reason = "Canvas context: #{canvas_type}" if plugin
      end
    end

    # 2. Explicit mention in message
    if plugin.nil? && message.present?
      plugin, injection_reason = detect_explicit_plugin_mention(message)
    end

    # 3. Keyword matching
    if plugin.nil? && message.present?
      plugin, injection_reason = detect_keyword_plugin(message)
    end

    # 4. Intent-based (lowest priority)
    if plugin.nil? && intent.present?
      plugin_slug = INTENT_PLUGIN_MAP[intent.to_sym]
      if plugin_slug.present?
        plugin = find_plugin(plugin_slug)
        injection_reason = "Intent: #{intent}" if plugin
      end
    end

    # No plugin needed
    return nil if plugin.nil?

    # Build the injection payload
    build_injection(plugin, injection_reason, canvas_context)
  end

  # Build the injection payload for a plugin
  def build_injection(plugin, reason, canvas_context = nil)
    return nil unless plugin

    # Get the plugin's system prompt
    prompt_text = extract_prompt_text(plugin)
    
    # Build the specialization block
    prompt_block = build_prompt_block(plugin, prompt_text, canvas_context)
    
    # Get the plugin's tools
    tools = get_plugin_tools(plugin)
    
    {
      plugin: plugin,
      plugin_slug: plugin.slug,
      plugin_name: plugin.name,
      prompt_block: prompt_block,
      tools: tools,
      tool_names: tools.map { |t| t[:name] },
      injection_reason: reason,
      canvas_context: canvas_context
    }
  end

  private

  def find_plugin(slug)
    return @plugin_cache[slug] if @plugin_cache.key?(slug)
    
    plugin = AgentPlugin.active.for_entity(@entity).find_by(slug: slug)
    @plugin_cache[slug] = plugin
    plugin
  end

  def detect_explicit_plugin_mention(message)
    msg_lower = message.downcase
    
    # Check for explicit agent mentions
    explicit_patterns = [
      [/\b(use|ask|with)\s+(the\s+)?landing\s*page\s*(manager|agent)/i, 'landing_page_manager'],
      [/\b(use|ask|with)\s+(the\s+)?crm\s*(agent)?/i, 'crm_agent'],
      [/\b(use|ask|with)\s+(the\s+)?workflow\s*(architect|agent)?/i, 'workflow_architect'],
      [/\b(use|ask|with)\s+(the\s+)?website\s*(manager|agent)?/i, 'website_manager']
    ]
    
    explicit_patterns.each do |pattern, slug|
      if msg_lower.match?(pattern)
        plugin = find_plugin(slug)
        return [plugin, "Explicit mention: #{slug}"] if plugin
      end
    end
    
    [nil, nil]
  end

  def detect_keyword_plugin(message)
    KEYWORD_PLUGIN_MAP.each do |pattern, slug|
      if message.match?(pattern)
        plugin = find_plugin(slug)
        return [plugin, "Keyword match: #{pattern.source}"] if plugin
      end
    end
    
    [nil, nil]
  end

  def extract_prompt_text(plugin)
    prompt = plugin.system_prompt
    
    if prompt.is_a?(Hash)
      prompt['prompt'] || prompt[:prompt] || prompt.values.first.to_s
    else
      prompt.to_s
    end
  end

  def build_prompt_block(plugin, prompt_text, canvas_context = nil)
    block = <<~PROMPT
      ## 🎯 CURRENT SPECIALIZATION: #{plugin.name}
      
      You are currently operating with specialized capabilities for this task.
      
      #{prompt_text}
    PROMPT

    # Add canvas context if available
    if canvas_context.present?
      block += <<~CONTEXT
        
        ## 📍 CURRENT CONTEXT
        #{format_canvas_context(canvas_context)}
      CONTEXT
    end

    block
  end

  def format_canvas_context(canvas_context)
    context_parts = []
    
    canvas_type = canvas_context[:type] || canvas_context['type']
    context_parts << "- Canvas: #{canvas_type}" if canvas_type
    
    if canvas_context[:landing_page_id] || canvas_context['landing_page_id']
      lp_id = canvas_context[:landing_page_id] || canvas_context['landing_page_id']
      context_parts << "- Landing Page ID: #{lp_id}"
      
      # Try to get landing page title
      lp = LandingPage.find_by(id: lp_id)
      context_parts << "- Landing Page Title: #{lp.title}" if lp
    end
    
    if canvas_context[:workflow_id] || canvas_context['workflow_id']
      context_parts << "- Workflow ID: #{canvas_context[:workflow_id] || canvas_context['workflow_id']}"
    end
    
    context_parts.join("\n")
  end

  def get_plugin_tools(plugin)
    catalog = Tools::ToolCatalog.instance
    
    # Get explicitly assigned tools
    assigned_tool_names = plugin.agent_tools.pluck(:tool_name)
    
    # Load tool definitions
    tools = assigned_tool_names.filter_map do |name|
      catalog.get_tool_definition(name)
    end
    
    Rails.logger.info "🔌 [PluginInjection] #{plugin.name}: #{tools.size} tools loaded"
    
    tools
  end
end
