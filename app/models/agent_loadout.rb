# Agent Loadout - Defines the bounded capabilities for an agent in a specific step
class AgentLoadout
  include ActiveModel::Model

  attr_accessor :step_id, :agent_role, :tool_allowlist, :canvas_allowlist,
                :data_scopes, :budgets, :confirmations, :prompts

  AGENT_ROLES = %w[planner executor analyst verifier].freeze

  # Default loadouts by agent role
  ROLE_DEFAULTS = {
    # Main chat agent (AMOS) - Reduced tool set for better decision making
    "main_chat" => {
      tool_allowlist: [
        'delegate_to_planner',        # Complex multi-step tasks
        'get_schema',                 # Check field structure before creating
        'get_data',                   # Simple data queries
        'create_object',              # Simple object creation
        'update_object',              # Simple updates
        'update_landing_page_content', # Update existing landing pages
        'execute_integration',        # Simple integration calls
        'list_operations',            # Discover integration capabilities
        'list_connections',           # See available integrations
        'query_metric',               # Analytics queries
        'list_metrics',               # Discover metrics
        'explain_query',              # Explain analytics queries
        'read_document',              # Read uploaded PDFs/docs
        'load_canvas',                # UI interactions
        'aggregate_artifact_data',    # Simple aggregations
        'create_dynamic_visualization', # Quick visualizations
        'get_workflow_context',       # Access uploaded files
        'get_my_ai_usage'            # Usage tracking
      ],
      canvas_allowlist: [ "*" ],
      data_scopes: { read: [ "*" ], write: [ "*" ] },
      budgets: { max_tokens: 8000, max_tool_calls: 15, timeout_seconds: 90 }
    },

    # Planner agent - Workflow planning
    "planner" => {
      tool_allowlist: [ "get_schema", "list_connections", "list_operations", "get_template_details" ],
      canvas_allowlist: [ "task_progress" ],
      data_scopes: { read: [ "workflow_templates" ], write: [ "task_sessions" ] },
      budgets: { max_tokens: 5000, max_tool_calls: 5, timeout_seconds: 30 }
    },

    # Phase executors in workflows - Need full tool access for their allowed_tools
    "executor" => {
      tool_allowlist: [ "*" ],  # Workflows define allowed_tools per phase
      canvas_allowlist: [ "*" ],
      data_scopes: { read: [ "*" ], write: [ "*" ] },
      budgets: { max_tokens: 15000, max_tool_calls: 30, timeout_seconds: 300 }
    },
    'analyst' => {
      tool_allowlist: ['aggregate_artifact_data', 'fetch_next_page', 'create_dynamic_visualization', 'query_metric', 'list_metrics', 'explain_query'],
      canvas_allowlist: ['dynamic_canvas', 'analytics_dashboard'],
      data_scopes: { read: ['artifacts'], write: ['artifacts'] },
      budgets: { max_tokens: 8000, max_tool_calls: 15, timeout_seconds: 60 }
    },
    "verifier" => {
      tool_allowlist: [ "get_data" ],
      canvas_allowlist: [ "task_progress" ],
      data_scopes: { read: [ "*" ], write: [] }, # Read-only
      budgets: { max_tokens: 3000, max_tool_calls: 5, timeout_seconds: 30 }
    }
  }.freeze

  def initialize(attributes = {})
    super
    apply_role_defaults if agent_role.present?
  end

  # Check if a tool is allowed for this loadout
  def tool_allowed?(tool_name)
    return false if tool_allowlist.blank?
    tool_allowlist.include?(tool_name) || tool_allowlist.include?("*")
  end

  # Check if a canvas is allowed for this loadout
  def canvas_allowed?(canvas_name)
    return false if canvas_allowlist.blank?
    canvas_allowlist.include?(canvas_name) || canvas_allowlist.include?("*")
  end

  # Check if data access is allowed
  def data_access_allowed?(artifact_id, access_type = :read)
    return false unless data_scopes[access_type.to_s]

    allowed_artifacts = data_scopes[access_type.to_s]
    allowed_artifacts.include?("*") || allowed_artifacts.include?(artifact_id.to_s)
  end

  # Check if budget allows another tool call
  def within_budget?(current_usage)
    return true unless budgets

    if budgets["max_tool_calls"] && current_usage[:tool_calls]
      return false if current_usage[:tool_calls] >= budgets["max_tool_calls"]
    end

    if budgets["max_tokens"] && current_usage[:tokens]
      return false if current_usage[:tokens] >= budgets["max_tokens"]
    end

    true
  end

  # Generate a minimal prompt for this loadout
  def generate_prompt(context = {})
    base_prompt = (prompts && prompts["base"]) || default_prompt_for_role

    # Add tool-specific instructions
    if tool_allowlist.present? && tool_allowlist != [ "*" ]
      base_prompt += "\n\nYou may only use these tools: #{tool_allowlist.join(', ')}"
    end

    # Add data scope instructions
    if data_scopes && data_scopes["read"].present? && data_scopes["read"] != [ "*" ]
      base_prompt += "\n\nYou may only access these data types: #{data_scopes['read'].join(', ')}"
    end

    base_prompt
  end

  private

  def apply_role_defaults
    defaults = ROLE_DEFAULTS[agent_role] || {}

    self.tool_allowlist ||= defaults[:tool_allowlist]
    self.canvas_allowlist ||= defaults[:canvas_allowlist]
    self.data_scopes ||= defaults[:data_scopes]
    self.budgets ||= defaults[:budgets]
    self.prompts ||= {}  # Initialize prompts to empty hash if not set
  end

  def default_prompt_for_role
    case agent_role
    when "main_chat"
      "You are AMOS, the main business advisor. Orchestrate tasks by delegating complex requests to specialized workflows."
    when "planner"
      "You are a planning agent. Analyze the request and create a structured plan."
    when "executor"
      "You are an execution agent. Execute the assigned task using available tools."
    when "analyst"
      "You are an analysis agent. Perform data analysis and generate insights."
    when "verifier"
      "You are a verification agent. Validate results and ensure quality."
    else
      "You are an AI agent. Complete the assigned task."
    end
  end
end
