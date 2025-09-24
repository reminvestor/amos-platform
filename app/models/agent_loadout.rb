# Agent Loadout - Defines the bounded capabilities for an agent in a specific step
class AgentLoadout
  include ActiveModel::Model
  
  attr_accessor :step_id, :agent_role, :tool_allowlist, :canvas_allowlist,
                :data_scopes, :budgets, :confirmations, :prompts
  
  AGENT_ROLES = %w[planner executor analyst verifier].freeze
  
  # Default loadouts by agent role
  ROLE_DEFAULTS = {
    'planner' => {
      tool_allowlist: ['get_schema', 'list_connections'],
      canvas_allowlist: ['task_progress'],
      data_scopes: { read: ['workflow_templates'], write: ['task_sessions'] },
      budgets: { max_tokens: 5000, max_tool_calls: 5, timeout_seconds: 30 }
    },
    'executor' => {
      tool_allowlist: ['get_data', 'create_object', 'invoke_operation', 'generate_ai_landing_page'],
      canvas_allowlist: ['dynamic_canvas', 'integrations_manager'],
      data_scopes: { read: ['*'], write: ['*'] }, # Scoped by entity
      budgets: { max_tokens: 10000, max_tool_calls: 20, timeout_seconds: 120 }
    },
    'analyst' => {
      tool_allowlist: ['aggregate_artifact_data', 'fetch_next_page', 'create_dynamic_visualization'],
      canvas_allowlist: ['dynamic_canvas', 'analytics_dashboard'],
      data_scopes: { read: ['artifacts'], write: ['artifacts'] },
      budgets: { max_tokens: 8000, max_tool_calls: 15, timeout_seconds: 60 }
    },
    'verifier' => {
      tool_allowlist: ['get_data'],
      canvas_allowlist: ['task_progress'],
      data_scopes: { read: ['*'], write: [] }, # Read-only
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
    tool_allowlist.include?(tool_name) || tool_allowlist.include?('*')
  end
  
  # Check if a canvas is allowed for this loadout
  def canvas_allowed?(canvas_name)
    return false if canvas_allowlist.blank?
    canvas_allowlist.include?(canvas_name) || canvas_allowlist.include?('*')
  end
  
  # Check if data access is allowed
  def data_access_allowed?(artifact_id, access_type = :read)
    return false unless data_scopes[access_type.to_s]
    
    allowed_artifacts = data_scopes[access_type.to_s]
    allowed_artifacts.include?('*') || allowed_artifacts.include?(artifact_id.to_s)
  end
  
  # Check if budget allows another tool call
  def within_budget?(current_usage)
    return true unless budgets
    
    if budgets['max_tool_calls'] && current_usage[:tool_calls]
      return false if current_usage[:tool_calls] >= budgets['max_tool_calls']
    end
    
    if budgets['max_tokens'] && current_usage[:tokens]
      return false if current_usage[:tokens] >= budgets['max_tokens']
    end
    
    true
  end
  
  # Generate a minimal prompt for this loadout
  def generate_prompt(context = {})
    base_prompt = prompts['base'] || default_prompt_for_role
    
    # Add tool-specific instructions
    if tool_allowlist.present? && tool_allowlist != ['*']
      base_prompt += "\n\nYou may only use these tools: #{tool_allowlist.join(', ')}"
    end
    
    # Add data scope instructions
    if data_scopes['read'].present? && data_scopes['read'] != ['*']
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
  end
  
  def default_prompt_for_role
    case agent_role
    when 'planner'
      "You are a planning agent. Analyze the request and create a structured plan."
    when 'executor'
      "You are an execution agent. Execute the assigned task using available tools."
    when 'analyst'
      "You are an analysis agent. Perform data analysis and generate insights."
    when 'verifier'
      "You are a verification agent. Validate results and ensure quality."
    else
      "You are an AI agent. Complete the assigned task."
    end
  end
end
