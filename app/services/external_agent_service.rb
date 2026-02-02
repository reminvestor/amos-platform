# frozen_string_literal: true

# ExternalAgentService - Business logic for external agent operations
#
# Handles all external agent interactions:
# - Registration and capability mapping
# - Bounty discovery and filtering
# - Bounty claiming with validation
# - Tool execution with policy enforcement
# - Work submission and review triggering
#
class ExternalAgentService
  attr_reader :user, :entity, :agent

  def initialize(user: nil, entity: nil, agent: nil)
    @user = user
    @entity = entity || agent&.entity
    @agent = agent
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # REGISTRATION
  # ═══════════════════════════════════════════════════════════════════════════

  def register_agent(agent_identifier:, agent_name:, agent_platform:, capabilities:, metadata: {})
    return error_response("User required") unless user.present?
    return error_response("Entity required") unless entity.present?

    # Check if agent already exists
    existing = ExternalAgentRegistration.find_by(agent_identifier: agent_identifier)
    if existing.present?
      return error_response("Agent with identifier '#{agent_identifier}' already registered")
    end

    # Map capabilities to allowed bounty types
    allowed_types = map_capabilities_to_bounty_types(capabilities)
    
    agent = ExternalAgentRegistration.new(
      entity: entity,
      operator: user,
      agent_identifier: agent_identifier,
      agent_name: agent_name,
      agent_platform: agent_platform,
      capabilities: capabilities,
      allowed_bounty_types: allowed_types,
      metadata: metadata.merge(
        registered_at: Time.current.iso8601,
        registration_source: 'api'
      )
    )

    if agent.save
      # Auto-activate for launch (normally would have 24h cooldown)
      agent.activate! if should_auto_activate?(agent)
      
      {
        success: true,
        agent: agent,
        message: build_registration_message(agent, allowed_types)
      }
    else
      error_response(agent.errors.full_messages.join(', '))
    end
  rescue => e
    Rails.logger.error "[ExternalAgentService] Registration failed: #{e.message}"
    error_response("Registration failed: #{e.message}")
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # BOUNTY DISCOVERY
  # ═══════════════════════════════════════════════════════════════════════════

  def discover_bounties(type: nil, min_points: nil, max_points: nil, limit: 20)
    return error_response("Agent required") unless agent.present?

    # Start with available bounties in agent's entity
    bounties = Bounty.where(entity: agent.entity)
                     .available
                     .order(urgency_score: :desc, points: :desc)

    # Filter by agent's allowed types
    bounties = bounties.where(bounty_type: agent.allowed_bounty_types)

    # Filter by max points agent can earn
    max_allowed = agent.trust_config[:max_points]
    if max_allowed.present?
      bounties = bounties.where('points <= ?', max_allowed)
    end

    # Apply optional filters
    bounties = bounties.where(bounty_type: type) if type.present?
    bounties = bounties.where('points >= ?', min_points) if min_points.present?
    bounties = bounties.where('points <= ?', max_points) if max_points.present?

    # Limit results
    bounties = bounties.limit([limit, 50].min)

    {
      success: true,
      bounties: bounties.map { |b| bounty_to_api(b) },
      meta: {
        total_available: Bounty.where(entity: agent.entity).available.count,
        matching_your_capabilities: bounties.count,
        your_daily_remaining: agent.daily_remaining,
        your_trust_level: agent.trust_level,
        max_points_allowed: max_allowed
      }
    }
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # BOUNTY CLAIMING
  # ═══════════════════════════════════════════════════════════════════════════

  def claim_bounty(bounty:, approach: nil, estimated_completion: nil)
    return error_response("Agent required") unless agent.present?
    return error_response("Bounty required") unless bounty.present?

    # Validation checks
    unless agent.active?
      return error_response("Agent is not active (status: #{agent.status})")
    end

    unless bounty.can_claim?
      return error_response("Bounty is not available (status: #{bounty.status})")
    end

    unless agent.can_claim_bounty?(bounty)
      return error_response(claim_denied_reason(bounty))
    end

    # Create execution
    execution = ExternalAgentExecution.create_for_bounty!(
      agent: agent,
      bounty: bounty,
      approach: approach
    )

    {
      success: true,
      execution: execution,
      message: "Bounty claimed. You have 24 hours to submit. Use the tools endpoint to execute platform tools."
    }
  rescue => e
    Rails.logger.error "[ExternalAgentService] Claim failed: #{e.message}"
    error_response("Failed to claim bounty: #{e.message}")
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # TOOL EXECUTION
  # ═══════════════════════════════════════════════════════════════════════════

  def execute_tool(execution:, tool_name:, args:)
    return error_response("Execution required") unless execution.present?
    return error_response("Tool name required") unless tool_name.present?

    # Pre-checks
    unless execution.can_execute_tool?(tool_name)
      return error_response("Cannot execute tool: #{tool_denied_reason(execution, tool_name)}")
    end

    # Check policy
    policy_result = check_tool_policy(tool_name, args)
    unless policy_result[:allowed]
      execution.record_tool_call!(
        tool_name: tool_name,
        arguments: args,
        result: {},
        success: false,
        latency_ms: 0,
        policy_allowed: false,
        policy_rule: policy_result[:rule],
        error: "Blocked by policy: #{policy_result[:reason]}"
      )
      return error_response("Tool blocked by policy: #{policy_result[:reason]}", status: :forbidden)
    end

    # Execute via ToolCatalog
    start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    
    result = Tools::ToolCatalog.instance.execute_tool(
      tool_name,
      args,
      user: agent.operator,
      entity: agent.entity,
      context: {
        external_agent: true,
        agent_id: agent.id,
        execution_id: execution.id
      }
    )

    end_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    latency_ms = ((end_time - start_time) * 1000).round

    # Record the call
    execution.record_tool_call!(
      tool_name: tool_name,
      arguments: args,
      result: sanitize_result(result),
      success: result[:success] != false,
      latency_ms: latency_ms,
      policy_allowed: true,
      error: result[:error]
    )

    {
      success: result[:success] != false,
      tool_result: result,
      latency_ms: latency_ms
    }
  rescue => e
    Rails.logger.error "[ExternalAgentService] Tool execution failed: #{e.message}"
    error_response("Tool execution failed: #{e.message}")
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # WORK SUBMISSION
  # ═══════════════════════════════════════════════════════════════════════════

  def submit_work(execution:, work_summary:, deliverables:, work_log: nil)
    return error_response("Execution required") unless execution.present?
    return error_response("Work summary required") unless work_summary.present?
    return error_response("Deliverables required") unless deliverables.present?

    unless execution.status == 'in_progress'
      return error_response("Cannot submit: execution status is #{execution.status}")
    end

    if execution.expired?
      execution.expire!
      return error_response("Cannot submit: execution has expired")
    end

    if execution.submit!(work_summary: work_summary, deliverables: deliverables, work_log: work_log)
      {
        success: true,
        message: "Work submitted for AI review. You will be notified of the result."
      }
    else
      error_response("Failed to submit work")
    end
  rescue => e
    Rails.logger.error "[ExternalAgentService] Submit failed: #{e.message}"
    error_response("Submission failed: #{e.message}")
  end

  private

  def error_response(message, status: nil)
    { success: false, error: message, status: status }
  end

  def map_capabilities_to_bounty_types(capabilities)
    return [] unless capabilities.is_a?(Hash)

    # Map declared capabilities to bounty types
    type_mapping = {
      'documentation' => 'documentation',
      'docs' => 'documentation',
      'technical_writing' => 'documentation',
      'content' => 'content',
      'blog' => 'content',
      'marketing' => 'marketing',
      'social_media' => 'marketing',
      'support' => 'support',
      'customer_support' => 'support',
      'bug' => 'bug',
      'bug_fix' => 'bug',
      'debugging' => 'bug',
      'feature' => 'feature',
      'development' => 'feature',
      'coding' => 'feature',
      'translation' => 'translation',
      'localization' => 'translation',
      'design' => 'design',
      'ui' => 'design',
      'ux' => 'design',
      'testing' => 'testing',
      'qa' => 'testing'
    }

    allowed = capabilities.keys.map do |cap|
      type_mapping[cap.to_s.downcase]
    end.compact.uniq

    # New agents start with limited types regardless of claims
    trust_1_types = ExternalAgentRegistration::TRUST_LEVELS[1][:bounty_types]
    allowed & trust_1_types
  end

  def should_auto_activate?(agent)
    # For launch, auto-activate all agents
    # In production, could require verification or cooldown
    true
  end

  def build_registration_message(agent, allowed_types)
    if allowed_types.empty?
      "Agent registered but no matching bounty types found. You'll start with documentation and content bounties."
    else
      "Agent registered successfully. You can work on: #{allowed_types.join(', ')}. Complete bounties to unlock more types."
    end
  end

  def claim_denied_reason(bounty)
    return "Agent is not active" unless agent.active?
    return "Bounty type '#{bounty.bounty_type}' not in your allowed types" unless agent.can_work_bounty_type?(bounty.bounty_type)
    return "Bounty points (#{bounty.points}) exceed your limit" unless agent.can_earn_points?(bounty.points)
    return "Daily bounty limit reached (#{agent.daily_bounty_limit}/day)" unless agent.within_daily_limit?
    return "Already working on maximum concurrent bounties" unless agent.within_concurrent_limit?
    "Unknown restriction"
  end

  def tool_denied_reason(execution, tool_name)
    return "Execution expired" if execution.expired?
    return "Execution not in progress" unless execution.status == 'in_progress'
    return "Tool '#{tool_name}' not in allowed list" unless agent.can_use_tool?(tool_name)
    return "Tool call limit reached" if execution.tool_calls_count >= agent.tool_calls_per_bounty
    "Unknown"
  end

  def check_tool_policy(tool_name, args)
    # Check entity policies for this tool
    policy = PolicyRule.where(entity: entity)
                       .where(is_active: true)
                       .where("resource_type = 'Tool' AND resource_id = ?", tool_name)
                       .first

    if policy&.requires_confirmation
      # External agents cannot get human confirmation, so block
      return { 
        allowed: false, 
        rule: policy.name,
        reason: "Tool requires human confirmation (external agents cannot confirm)"
      }
    end

    # Check global tool restrictions
    read_only_tools = %w[web_search get_data list_documents read_document list_connections list_operations get_workflow_context]
    dangerous_tools = %w[delete_object bulk_import process_payment send_email]

    if dangerous_tools.include?(tool_name)
      return {
        allowed: false,
        rule: 'dangerous_tool_block',
        reason: "Tool '#{tool_name}' is not available to external agents"
      }
    end

    { allowed: true }
  end

  def sanitize_result(result)
    # Remove sensitive data from tool results before storing
    return result unless result.is_a?(Hash)

    sanitized = result.deep_dup
    sensitive_keys = %w[api_key token password secret credentials]
    
    sanitized.deep_transform_keys! do |key|
      if sensitive_keys.any? { |s| key.to_s.downcase.include?(s) }
        "#{key}_REDACTED"
      else
        key
      end
    end

    sanitized
  end

  def bounty_to_api(bounty)
    {
      id: bounty.id,
      title: bounty.title,
      description: bounty.description&.truncate(500),
      bounty_type: bounty.bounty_type,
      points: bounty.points,
      urgency_score: bounty.urgency_score,
      impact_score: bounty.impact_score,
      estimated_hours: bounty.estimated_hours,
      required_capabilities: [bounty.bounty_type],
      tools_available: tools_for_bounty_type(bounty.bounty_type),
      created_at: bounty.created_at.iso8601,
      expires_at: bounty.expires_at&.iso8601,
      source: bounty.source,
      upvotes: bounty.upvotes
    }
  end

  def tools_for_bounty_type(type)
    # Suggest tools based on bounty type
    base_tools = %w[web_search get_data]
    
    case type
    when 'documentation'
      base_tools + %w[list_documents read_document create_object]
    when 'content'
      base_tools + %w[generate_image create_object]
    when 'bug'
      base_tools + %w[list_documents read_document get_schema]
    when 'support'
      base_tools + %w[list_documents read_document search_history]
    else
      base_tools
    end
  end
end
