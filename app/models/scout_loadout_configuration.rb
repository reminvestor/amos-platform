# ScoutLoadoutConfiguration
#
# Stores the configurable tool allowlist for Scout (main_chat agent) per entity.
# This allows each organization to customize which tools Scout has direct access to.
#
# By default, Scout uses a standard set of tools. Entity admins can:
# - Add tools to Scout's allowlist
# - Remove tools from Scout's allowlist
# - Enable tiered discovery (RAG-based tool selection)
# - Set budget limits
#
class ScoutLoadoutConfiguration < ApplicationRecord
  belongs_to :entity

  # Default tools that Scout should have access to (baseline)
  # These match the current hardcoded main_chat loadout in AgentLoadout
  # Users can customize this per entity
  DEFAULT_TOOL_ALLOWLIST = %w[
    get_schema
    get_data
    create_object
    update_object
    update_landing_page_content
    execute_integration
    integration_analytics
    list_operations
    list_connections
    explain_query
    read_document
    query_document_content
    query_rag_store
    load_canvas
    create_dynamic_visualization
    get_workflow_context
    retrieve_history
    get_message_count
    search_history
    list_available_agents
    delegate_to_agent
    invoke_agent_plugin
    update_agent
    ask_agent_for_help
    web_search
    create_scheduled_task
    list_scheduled_tasks
    manage_scheduled_task
    save_visualization
    get_work_inbox
    respond_to_agent
  ].freeze

  # Tools that should NEVER be given to Scout (always delegate)
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

  # Get the effective tool allowlist (merging defaults with customizations)
  def effective_tool_allowlist
    return DEFAULT_TOOL_ALLOWLIST.dup if tool_allowlist.blank?
    
    # Start with the stored allowlist
    tools = tool_allowlist.dup
    
    # Never include excluded tools
    tools - EXCLUDED_TOOLS
  end

  # Add a tool to the allowlist
  def add_tool(tool_name)
    return false if EXCLUDED_TOOLS.include?(tool_name)
    
    self.tool_allowlist ||= DEFAULT_TOOL_ALLOWLIST.dup
    self.tool_allowlist << tool_name unless tool_allowlist.include?(tool_name)
    save
  end

  # Remove a tool from the allowlist
  def remove_tool(tool_name)
    return false if tool_allowlist.blank?
    
    self.tool_allowlist.delete(tool_name)
    save
  end

  # Reset to defaults
  def reset_to_defaults!
    update!(
      tool_allowlist: DEFAULT_TOOL_ALLOWLIST.dup,
      canvas_allowlist: ["*"],
      budgets: DEFAULT_BUDGETS.dup,
      use_tiered_discovery: false,
      max_discovered_tools: 0
    )
  end

  # Check if a specific tool is allowed
  def tool_allowed?(tool_name)
    effective_tool_allowlist.include?(tool_name)
  end

  # Get effective budgets
  def effective_budgets
    DEFAULT_BUDGETS.merge(budgets&.symbolize_keys || {})
  end

  # Class method to get or create config for an entity
  def self.for_entity(entity)
    find_or_create_by(entity: entity)
  end

  private

  def set_defaults
    self.tool_allowlist ||= DEFAULT_TOOL_ALLOWLIST.dup
    self.canvas_allowlist ||= ["*"]
    self.budgets ||= DEFAULT_BUDGETS.dup
    self.use_tiered_discovery ||= false
    self.max_discovered_tools ||= 0
  end
end

