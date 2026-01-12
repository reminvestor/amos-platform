# frozen_string_literal: true

# Tracks task proposals between agents (handshake protocol)
# Enables agents to accept/reject tasks based on their capabilities
# and provides data for continuous improvement
class AgentTaskProposal < ApplicationRecord
  # Associations
  belongs_to :proposing_agent, class_name: 'AgentPlugin', optional: true # null = Amos/Scout
  belongs_to :receiving_agent, class_name: 'AgentPlugin'
  belongs_to :entity
  belongs_to :user, optional: true
  belongs_to :agent_work_item, optional: true
  belongs_to :agent_plugin_execution, optional: true

  # Statuses
  STATUSES = %w[proposed accepted rejected expired executing completed failed].freeze
  
  # Task types for categorization
  TASK_TYPES = %w[
    update_record create_record delete_record query_data
    fix_module update_schema fix_canvas add_field
    create_tool update_tool
    create_agent update_agent
    research web_search analyze
    generate_content create_visualization
    custom
  ].freeze

  # Validations
  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :task_description, presence: true
  validates :receiving_agent, presence: true
  validates :entity, presence: true

  # Scopes
  scope :pending, -> { where(status: 'proposed') }
  scope :accepted, -> { where(status: 'accepted') }
  scope :rejected, -> { where(status: 'rejected') }
  scope :completed, -> { where(status: 'completed') }
  scope :failed, -> { where(status: 'failed') }
  scope :recent, -> { order(created_at: :desc) }
  scope :for_agent, ->(agent) { where(receiving_agent: agent) }
  scope :from_agent, ->(agent) { where(proposing_agent: agent) }
  scope :successful, -> { where(task_succeeded: true) }
  scope :unsuccessful, -> { where(task_succeeded: false) }

  # Callbacks
  before_create :set_proposed_at
  before_create :set_expiration

  # ============================================
  # PROPOSAL LIFECYCLE
  # ============================================

  def propose!
    update!(status: 'proposed', proposed_at: Time.current)
  end

  def accept!(confidence: 1.0, details: {})
    update!(
      status: 'accepted',
      accepted: true,
      confidence: confidence,
      accepted_at: Time.current,
      evaluated_at: Time.current,
      evaluation_details: details
    )
  end

  def reject!(reason:, missing_tools: [], missing_capabilities: [], alternatives: [])
    update!(
      status: 'rejected',
      accepted: false,
      rejection_reason: reason,
      missing_tools: missing_tools,
      missing_capabilities: missing_capabilities,
      suggested_alternatives: alternatives,
      rejected_at: Time.current,
      evaluated_at: Time.current
    )
  end

  def start_execution!(work_item: nil, execution: nil)
    update!(
      status: 'executing',
      started_at: Time.current,
      agent_work_item: work_item,
      agent_plugin_execution: execution
    )
  end

  def complete!(success:, metrics: {}, failure_reason: nil)
    update!(
      status: success ? 'completed' : 'failed',
      completed_at: success ? Time.current : nil,
      failed_at: success ? nil : Time.current,
      task_succeeded: success,
      failure_reason: failure_reason,
      outcome_metrics: metrics
    )
  end

  def expire!
    update!(status: 'expired') if proposed?
  end

  # ============================================
  # STATUS CHECKS
  # ============================================

  def proposed?
    status == 'proposed'
  end

  def accepted?
    status == 'accepted' || accepted == true
  end

  def rejected?
    status == 'rejected'
  end

  def executing?
    status == 'executing'
  end

  def completed?
    status == 'completed'
  end

  def failed?
    status == 'failed'
  end

  def expired?
    status == 'expired' || (expires_at.present? && expires_at < Time.current)
  end

  def pending?
    proposed? && !expired?
  end

  # ============================================
  # CAPABILITY EVALUATION
  # ============================================

  # Evaluate if the receiving agent can handle this task
  def evaluate_capability
    agent = receiving_agent
    return rejection_result("Agent not found") unless agent

    # Get agent's tools
    agent_tools = agent.agent_tools.pluck(:tool_name)
    
    # FIRST: Check domain match - if agent clearly matches task domain, accept with high confidence
    # This prevents rejection when tools_needed was incorrectly inferred by the LLM
    domain_match = check_domain_match(agent, task_description)
    if domain_match[:strong_match]
      Rails.logger.info "[AgentTaskProposal] Strong domain match for #{agent.slug}: #{domain_match[:reason]}"
      return acceptance_result(domain_match[:confidence], {
        tools_available: agent_tools,
        domain_match: true,
        match_reason: domain_match[:reason],
        skipped_tool_check: true
      })
    end
    
    # Use intent-based tool matching (scalable, no hardcoded mappings)
    matcher = Tools::ToolIntentMatcher.new(
      agent_tools: agent_tools,
      task_description: task_description
    )
    match_result = matcher.can_satisfy?(tools_needed || [])
    missing = match_result[:missing]

    # Check capabilities
    agent_capabilities = agent.capabilities_definition&.dig('capabilities') || []
    missing_caps = (required_capabilities || []) - agent_capabilities

    # Check object types
    can_handle_objects = check_object_type_support(agent, object_types || [])

    # Calculate confidence
    confidence = calculate_confidence(
      tools_available: agent_tools,
      tools_needed: tools_needed || [],
      missing_tools: missing,
      capabilities_match: missing_caps.empty?,
      object_support: can_handle_objects
    )

    # Build evaluation result
    if missing.any? || missing_caps.any? || !can_handle_objects
      # Before rejecting, check if domain match suggests we should accept anyway
      if domain_match[:weak_match] && missing_caps.empty? && can_handle_objects
        Rails.logger.info "[AgentTaskProposal] Weak domain match overrides missing tools for #{agent.slug}"
        return acceptance_result(domain_match[:confidence], {
          tools_available: agent_tools,
          domain_match: true,
          ignored_missing_tools: missing,
          match_reason: domain_match[:reason]
        })
      end
      
      rejection_result(
        build_rejection_reason(missing, missing_caps, can_handle_objects),
        missing_tools: missing,
        missing_capabilities: missing_caps,
        alternatives: find_alternative_agents
      )
    else
      acceptance_result(confidence, {
        tools_available: agent_tools,
        capabilities_matched: required_capabilities,
        object_types_supported: object_types,
        tool_mappings: match_result[:mappings]
      })
    end
  end
  
  # Check if agent's specialty matches the task description
  # Returns { strong_match: bool, weak_match: bool, confidence: float, reason: string }
  def check_domain_match(agent, description)
    desc_lower = description.to_s.downcase
    agent_slug = agent.slug.to_s
    agent_desc = agent.description.to_s.downcase
    agent_tools = agent.agent_tools.pluck(:tool_name)
    
    # Domain patterns: agent_slug_pattern => [keywords in task description]
    domain_patterns = {
      'landing_page' => {
        keywords: %w[landing page website hero sales page marketing page],
        agents: %w[landing_page_manager ai_landing_page_creator],
        tools: %w[generate_ai_landing_page update_landing_page_content create_landing_page]
      },
      'integration' => {
        keywords: %w[integration api connect sync webhook rest external],
        agents: %w[integration_architect integration_specialist],
        tools: %w[create_integration create_integration_foundation test_integration]
      },
      'module' => {
        keywords: %w[module schema field model custom data structure],
        agents: %w[platform_factory module_architect],
        tools: %w[start_module_design propose_module_schema design_module_schema]
      },
      'email' => {
        keywords: %w[email sequence campaign nurture welcome],
        agents: %w[email_sequence_architect sales_email_generator],
        tools: %w[create_object get_data]
      },
      'analytics' => {
        keywords: %w[analytics chart graph dashboard metric report visualization],
        agents: %w[analytics_agent data_analyst],
        tools: %w[create_dynamic_visualization query_metric analyze_dataset]
      }
    }
    
    # Check each domain
    domain_patterns.each do |domain, config|
      # Check if agent matches this domain
      agent_matches = config[:agents].any? { |a| agent_slug.include?(a) || a.include?(agent_slug) }
      agent_has_domain_tools = (agent_tools & config[:tools]).any?
      
      next unless agent_matches || agent_has_domain_tools
      
      # Check if task matches this domain
      task_matches = config[:keywords].any? { |kw| desc_lower.include?(kw) }
      
      if task_matches
        # Strong match: agent is for this domain AND task is for this domain
        if agent_matches && agent_has_domain_tools
          return {
            strong_match: true,
            weak_match: false,
            confidence: 0.9,
            reason: "Agent '#{agent.name}' specializes in #{domain} and task mentions #{domain}-related keywords"
          }
        elsif agent_has_domain_tools
          return {
            strong_match: false,
            weak_match: true,
            confidence: 0.75,
            reason: "Agent has #{domain} tools and task mentions #{domain}-related keywords"
          }
        end
      end
    end
    
    { strong_match: false, weak_match: false, confidence: 0.0, reason: nil }
  end

  # ============================================
  # ANALYTICS & LEARNING
  # ============================================

  # Calculate success rate for this agent + task type combination
  def self.success_rate_for(agent:, task_type: nil)
    scope = where(receiving_agent: agent, status: %w[completed failed])
    scope = scope.where(task_type: task_type) if task_type.present?
    
    return 0.0 if scope.count.zero?
    
    scope.successful.count.to_f / scope.count
  end

  # Find patterns in failed tasks
  def self.failure_patterns_for(agent:, limit: 10)
    where(receiving_agent: agent, task_succeeded: false)
      .order(created_at: :desc)
      .limit(limit)
      .pluck(:task_type, :failure_reason, :missing_tools, :missing_capabilities)
  end

  # Identify capability gaps
  def self.capability_gaps_for(agent:)
    rejected = where(receiving_agent: agent, status: 'rejected')
    
    {
      missing_tools: rejected.pluck(:missing_tools).flatten.tally.sort_by { |_, v| -v },
      missing_capabilities: rejected.pluck(:missing_capabilities).flatten.tally.sort_by { |_, v| -v },
      rejection_reasons: rejected.pluck(:rejection_reason).tally.sort_by { |_, v| -v }
    }
  end

  # Find best agent for a task type
  def self.best_agent_for(entity:, task_type:, object_types: [])
    # Get agents with successful completions for this task type
    successful_agents = joins(:receiving_agent)
      .where(entity: entity, task_type: task_type, task_succeeded: true)
      .group(:receiving_agent_id)
      .select('receiving_agent_id, COUNT(*) as success_count, AVG(confidence) as avg_confidence')
      .order('success_count DESC, avg_confidence DESC')
      .limit(5)

    successful_agents.map do |result|
      agent = AgentPlugin.find(result.receiving_agent_id)
      {
        agent: agent,
        success_count: result.success_count,
        avg_confidence: result.avg_confidence,
        success_rate: success_rate_for(agent: agent, task_type: task_type)
      }
    end
  end

  private

  def set_proposed_at
    self.proposed_at ||= Time.current
  end

  def set_expiration
    self.expires_at ||= 5.minutes.from_now
  end

  def check_object_type_support(agent, object_types)
    return true if object_types.blank?
    
    # Check if agent has tools that can work with these object types
    agent_tools = agent.agent_tools.pluck(:tool_name)
    
    # If they have data tools, they can probably work with objects
    data_tools = %w[get_data get_schema update_object create_object]
    has_data_tools = (agent_tools & data_tools).any?
    
    # Module-specific tools
    module_tools = %w[update_module diagnose_module]
    has_module_tools = (agent_tools & module_tools).any?
    
    has_data_tools || has_module_tools
  end

  def calculate_confidence(tools_available:, tools_needed:, missing_tools:, capabilities_match:, object_support:)
    return 0.0 if missing_tools.any? || !capabilities_match || !object_support
    
    # Base confidence
    confidence = 0.5
    
    # Bonus for having all needed tools
    if tools_needed.present? && missing_tools.empty?
      tool_coverage = (tools_available & tools_needed).length.to_f / tools_needed.length
      confidence += 0.3 * tool_coverage
    else
      confidence += 0.2 # Default if no specific tools needed
    end
    
    # Bonus for capability match
    confidence += 0.2 if capabilities_match
    
    # Bonus for object support
    confidence += 0.1 if object_support
    
    confidence.clamp(0.0, 1.0)
  end

  def build_rejection_reason(missing_tools, missing_caps, object_support)
    reasons = []
    reasons << "Missing tools: #{missing_tools.join(', ')}" if missing_tools.any?
    reasons << "Missing capabilities: #{missing_caps.join(', ')}" if missing_caps.any?
    reasons << "Cannot work with specified object types" unless object_support
    reasons.join('. ')
  end

  def find_alternative_agents
    # Find other agents that might be able to help
    AgentPlugin.where(status: 'active')
      .where.not(id: receiving_agent_id)
      .limit(5)
      .map do |agent|
        tools = agent.agent_tools.pluck(:tool_name)
        has_needed = (tools & (tools_needed || [])).length
        {
          slug: agent.slug,
          name: agent.name,
          tools_match: has_needed,
          tools_needed: tools_needed&.length || 0
        }
      end
      .select { |a| a[:tools_match] > 0 }
      .sort_by { |a| -a[:tools_match] }
  end

  def acceptance_result(confidence, details)
    {
      accepted: true,
      confidence: confidence,
      details: details,
      message: "Agent can handle this task with #{(confidence * 100).round}% confidence"
    }
  end

  def rejection_result(reason, missing_tools: [], missing_capabilities: [], alternatives: [])
    {
      accepted: false,
      reason: reason,
      missing_tools: missing_tools,
      missing_capabilities: missing_capabilities,
      alternatives: alternatives,
      message: "Agent cannot handle this task: #{reason}"
    }
  end
end


