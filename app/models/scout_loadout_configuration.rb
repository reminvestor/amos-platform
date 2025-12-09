# ScoutLoadoutConfiguration
#
# Stores the configurable tool allowlist for Scout (main_chat agent) per entity.
# This allows each organization to customize which tools Scout has direct access to.
#
# TOOL TIERS:
# - CORE_TOOLS: Always available, cannot be removed (Scout's native abilities)
# - CONFIGURABLE_TOOLS: User can enable/disable based on preference
# - EXCLUDED_TOOLS: Never given to Scout (always delegate to agents)
#
# Scout's identity: Orchestrator/Concierge - SHOWS and ROUTES, doesn't CREATE or BUILD
#
class ScoutLoadoutConfiguration < ApplicationRecord
  belongs_to :entity

  # ═══════════════════════════════════════════════════════════════
  # TIER 1: CORE TOOLS - Scout's native abilities (always available)
  # These define WHAT SCOUT IS - cannot be removed
  # ═══════════════════════════════════════════════════════════════
  CORE_TOOLS = %w[
    get_data
    get_schema
    query_document_content
    read_document
    load_canvas
    create_dynamic_visualization
    list_available_agents
    delegate_to_agent
    respond_to_agent
    web_search
    list_connections
    retrieve_history
    search_history
    remember_this
    bookmark_this
    recall_context
    list_saved
    search_memory
  ].freeze

  # ═══════════════════════════════════════════════════════════════
  # TIER 2: CONFIGURABLE TOOLS - User chooses which to enable
  # These extend Scout's capabilities based on user preference
  # ═══════════════════════════════════════════════════════════════
  CONFIGURABLE_TOOLS = %w[
    create_object
    update_object
    execute_integration
    analyze_dataset
    create_scheduled_task
    list_scheduled_tasks
    manage_scheduled_task
    update_landing_page_content
    get_work_inbox
    save_visualization
    list_operations
    explain_query
  ].freeze

  # Default configurable tools for new users (conservative set)
  DEFAULT_CONFIGURABLE = %w[
    create_object
    update_object
    save_visualization
  ].freeze

  # Default tool allowlist (CORE + DEFAULT_CONFIGURABLE) - for UI reference
  DEFAULT_TOOL_ALLOWLIST = (CORE_TOOLS + DEFAULT_CONFIGURABLE).freeze

  # ═══════════════════════════════════════════════════════════════
  # TIER 3: EXCLUDED TOOLS - Never given to Scout (delegate only)
  # These are specialist work - always route to agents
  # ═══════════════════════════════════════════════════════════════
  EXCLUDED_TOOLS = %w[
    generate_ai_landing_page
    process_landing_page_images
    analyze_landing_page_request
    generate_integration_scaffold
    generate_integration_code
    add_integration_endpoint
    test_integration_endpoint
    register_integration_operation
    manage_task_list
    create_agent
    create_tool
    update_tool
    create_integration
    create_integration_foundation
    configure_integration_auth
    test_integration_auth
    add_integration_operations
    invoke_agent_plugin
    ask_agent_for_help
    update_agent
    get_message_count
    query_rag_store
    get_workflow_context
  ].freeze

  DEFAULT_BUDGETS = {
    max_tokens: 8000,
    max_tool_calls: 15,
    timeout_seconds: 90
  }.freeze

  # Validations
  validates :entity_id, uniqueness: true

  # Callbacks
  after_initialize :set_defaults, if: :new_record?

  # Get the effective tool allowlist
  # CORE_TOOLS are always included, plus user-configured tools
  def effective_tool_allowlist
    tools = CORE_TOOLS.dup
    
    # Add user-configured tools (only valid configurable ones)
    if configured_tools.present?
      valid_configured = configured_tools & CONFIGURABLE_TOOLS
      tools += valid_configured
    else
      # Use defaults for new/unconfigured entities
      tools += DEFAULT_CONFIGURABLE
    end
    
    tools.uniq
  end

  # Get user's configured tools (stored in tool_allowlist column)
  def configured_tools
    return [] if tool_allowlist.blank?
    tool_allowlist & CONFIGURABLE_TOOLS
  end

  # Set user's configured tools
  def configured_tools=(tools)
    valid_tools = Array(tools) & CONFIGURABLE_TOOLS
    self.tool_allowlist = valid_tools
  end

  # Enable a configurable tool
  def enable_tool(tool_name)
    return false unless CONFIGURABLE_TOOLS.include?(tool_name)
    
    current = configured_tools
    return true if current.include?(tool_name)
    
    self.tool_allowlist = (current + [tool_name]).uniq
    save
  end

  # Disable a configurable tool
  def disable_tool(tool_name)
    return false unless CONFIGURABLE_TOOLS.include?(tool_name)
    return false if configured_tools.blank?
    
    self.tool_allowlist = configured_tools - [tool_name]
    save
  end

  # Check if a tool is enabled
  def tool_enabled?(tool_name)
    effective_tool_allowlist.include?(tool_name)
  end

  # Check if a tool is a core tool (always enabled)
  def core_tool?(tool_name)
    CORE_TOOLS.include?(tool_name)
  end

  # Check if a tool is configurable
  def configurable_tool?(tool_name)
    CONFIGURABLE_TOOLS.include?(tool_name)
  end

  # Legacy compatibility - maps to tool_enabled?
  def tool_allowed?(tool_name)
    tool_enabled?(tool_name)
  end

  # Reset to defaults
  def reset_to_defaults!
    update!(
      tool_allowlist: DEFAULT_CONFIGURABLE.dup,
      canvas_allowlist: ["*"],
      budgets: DEFAULT_BUDGETS.dup,
      use_tiered_discovery: false,
      max_discovered_tools: 0
    )
  end

  # Get effective budgets
  def effective_budgets
    DEFAULT_BUDGETS.merge(budgets&.symbolize_keys || {})
  end

  # Class method to get or create config for an entity
  def self.for_entity(entity)
    find_or_create_by(entity: entity)
  end

  # Get tool statistics for display
  def tool_stats
    {
      core_count: CORE_TOOLS.length,
      configured_count: configured_tools.length,
      total_enabled: effective_tool_allowlist.length,
      available_configurable: CONFIGURABLE_TOOLS.length
    }
  end

  private

  def set_defaults
    self.tool_allowlist ||= DEFAULT_CONFIGURABLE.dup
    self.canvas_allowlist ||= ["*"]
    self.budgets ||= DEFAULT_BUDGETS.dup
    self.use_tiered_discovery ||= false
    self.max_discovered_tools ||= 0
  end
end

