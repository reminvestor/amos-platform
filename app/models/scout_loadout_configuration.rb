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
    ask_user
    get_data
    get_schema
    query_document_content
    read_document
    load_canvas
    create_dynamic_visualization
    create_freeform_canvas
    list_available_agents
    propose_task_to_agent
    delegate_to_agent
    respond_to_agent
    web_search
    view_web_page
    discover_tools
    list_connections
    list_integrations
    list_operations
    retrieve_history
    search_history
    remember_this
    bookmark_this
    recall_context
    list_saved
    search_memory
    create_scheduled_task
    list_scheduled_tasks
    manage_scheduled_task
    get_work_inbox
    create_object
    update_object
    update_landing_page_content
    edit_landing_page_section
    read_landing_page_sections
    start_module_design
    propose_module_schema
    refine_module_schema
    approve_module_design
    customize_template
    extend_module_schema
    start_app_design
    generate_app_blueprint
    build_app
    preview_app
    publish_app
    list_apps
    install_app_template
    update_module
    diagnose_module
    get_platform_capabilities
    find_best_agent
    analyze_agent_performance
    repair_agent_failures
    delegate_to_planner
    create_execution_plan
    execute_plan_step
    get_plan_status
    modify_plan
    create_support_ticket
    check_ticket_status
    generate_image
  ].freeze

  # ═══════════════════════════════════════════════════════════════
  # TIER 2: CONFIGURABLE TOOLS - User chooses which to enable
  # Now dynamically computed: any tool not in CORE_TOOLS or EXCLUDED_TOOLS
  # Users can toggle these based on their needs
  # ═══════════════════════════════════════════════════════════════
  
  # Default configurable tools for new users (commonly useful extras)
  DEFAULT_CONFIGURABLE = %w[
    save_visualization
    execute_integration
    analyze_dataset
    computer_use
  ].freeze

  # Default tool allowlist (CORE + DEFAULT_CONFIGURABLE) - for UI reference
  DEFAULT_TOOL_ALLOWLIST = (CORE_TOOLS + DEFAULT_CONFIGURABLE).freeze

  # Get all configurable tools dynamically from the tool catalog
  # Any tool not in CORE_TOOLS or EXCLUDED_TOOLS is configurable
  def self.configurable_tools
    return @configurable_tools if @configurable_tools.present?
    
    all_tool_names = Tools::ToolCatalog.instance.all_tools.keys.map(&:to_s)
    @configurable_tools = all_tool_names - CORE_TOOLS - EXCLUDED_TOOLS
    @configurable_tools
  rescue => e
    Rails.logger.warn "Could not load configurable tools: #{e.message}"
    DEFAULT_CONFIGURABLE
  end

  # Clear cached configurable tools (useful after adding new tools)
  def self.clear_configurable_tools_cache!
    @configurable_tools = nil
  end

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
    design_module_schema
    generate_model_code
    generate_canvas_code
    generate_tool_definition
    register_module_canvas
    validate_module
    request_module
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
      valid_configured = configured_tools & self.class.configurable_tools
      tools += valid_configured
    else
      # Use defaults for new/unconfigured entities
      tools += DEFAULT_CONFIGURABLE
    end
    
    tools.uniq
  end

  # Get effective tool allowlist for a specific space
  # Space tools are layered: Space defaults + Entity customizations
  def effective_tool_allowlist_for_space(space_slug)
    space = SpaceDefinition.find_by(slug: space_slug)
    return effective_tool_allowlist unless space
    
    # Start with space-specific tool loadout
    space_tools = space.tool_loadout
    
    # If no space-specific loadout, fall back to default
    return effective_tool_allowlist if space_tools.blank?
    
    # Add any user-configured tools that are also in configurable_tools
    if configured_tools.present?
      valid_configured = configured_tools & self.class.configurable_tools & space_tools
      space_tools = (space_tools + valid_configured).uniq
    end
    
    space_tools
  end

  # Check if tool is allowed in a specific space
  def tool_allowed_in_space?(tool_name, space_slug)
    effective_tool_allowlist_for_space(space_slug).include?(tool_name)
  end

  # Get user's configured tools (stored in tool_allowlist column)
  def configured_tools
    return [] if tool_allowlist.blank?
    tool_allowlist & self.class.configurable_tools
  end

  # Set user's configured tools
  def configured_tools=(tools)
    valid_tools = Array(tools) & self.class.configurable_tools
    self.tool_allowlist = valid_tools
  end

  # Enable a configurable tool
  def enable_tool(tool_name)
    return false unless self.class.configurable_tools.include?(tool_name)
    
    current = configured_tools
    return true if current.include?(tool_name)
    
    self.tool_allowlist = (current + [tool_name]).uniq
    save
  end

  # Disable a configurable tool
  def disable_tool(tool_name)
    return false unless self.class.configurable_tools.include?(tool_name)
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
    self.class.configurable_tools.include?(tool_name)
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
      available_configurable: self.class.configurable_tools.length
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

