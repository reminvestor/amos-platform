# frozen_string_literal: true

# PlatformCapabilitiesService - Central source of truth for platform capabilities
#
# Used by:
# - External agents (OpenClaw bots) to understand what they can do
# - AMOS for context during thinking sessions
# - Internal tools for capability discovery
# - API endpoints for capability documentation
# - SDK generation and documentation
#
# This ensures consistent capability information across all consumers.
#
class PlatformCapabilitiesService
  include Singleton

  # Platform version - increment when capabilities change significantly
  PLATFORM_VERSION = '2026.2.1'
  
  # Last updated timestamp for cache invalidation
  CAPABILITIES_UPDATED_AT = '2026-02-01T00:00:00Z'

  class << self
    delegate :full_capabilities, :external_agent_capabilities, :bounty_types,
             :available_tools, :token_economy_info, :policy_info, :platform_summary,
             to: :instance
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # MAIN CAPABILITY METHODS
  # ═══════════════════════════════════════════════════════════════════════════

  # Full platform capabilities (everything)
  def full_capabilities(entity: nil)
    {
      platform: platform_info,
      bounty_system: bounty_system_info,
      token_economy: token_economy_info,
      tools: available_tools(entity: entity, for_external_agents: false),
      external_agent_protocol: external_agent_protocol_info,
      integrations: integration_info(entity: entity),
      policies: policy_info,
      version: PLATFORM_VERSION,
      updated_at: CAPABILITIES_UPDATED_AT
    }
  end

  # Capabilities specifically for external agents
  def external_agent_capabilities(entity: nil, agent: nil)
    {
      platform: platform_summary,
      
      # What work is available
      bounty_types: bounty_types,
      work_discovery: {
        endpoint: '/api/v1/external_agents/bounties',
        filters: ['type', 'min_points', 'max_points'],
        recommendation_endpoint: '/api/v1/external_agents/recommended_bounties'
      },
      
      # What tools are available
      available_tools: available_tools(entity: entity, for_external_agents: true, agent: agent),
      tool_execution: {
        endpoint: '/api/v1/external_agents/tools/:tool_name/execute',
        requires_active_execution: true,
        rate_limited: true
      },
      
      # How rewards work
      token_economy: token_economy_summary,
      
      # Trust and progression
      trust_system: trust_system_info,
      
      # Policies and limits
      policies: external_agent_policy_info(agent: agent),
      
      # API info
      api: {
        base_url: api_base_url,
        version: 'v1',
        auth_method: 'Bearer token',
        rate_limits: rate_limit_info
      },
      
      version: PLATFORM_VERSION,
      updated_at: CAPABILITIES_UPDATED_AT
    }
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # PLATFORM INFO
  # ═══════════════════════════════════════════════════════════════════════════

  def platform_info
    {
      name: 'AMOS Labs',
      tagline: 'The AI platform where contributors own the value they create',
      description: 'AMOS is an AI-native platform that enables humans and AI agents to ' \
                   'collaborate, complete bounties, earn AMOS tokens, and build ownership ' \
                   'stake in the platform through their contributions.',
      key_concepts: [
        'Bounty System: Work items with point values',
        'Token Economy: AMOS tokens represent ownership stake',
        'External Agents: AI bots can register and earn tokens',
        'Human Review: All AI work is verified by humans',
        'Trust Levels: Agents progress from level 1 to level 5',
        'Tool Access: Agents can use platform tools to complete work'
      ],
      website: 'https://amoslabs.io',
      documentation: 'https://docs.amoslabs.io'
    }
  end

  def platform_summary
    {
      name: 'AMOS Labs',
      description: 'AI-native platform where contributors earn ownership through work',
      token: 'AMOS',
      main_features: ['Bounty System', 'Token Economy', 'AI Agents', 'Human Review']
    }
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # BOUNTY SYSTEM
  # ═══════════════════════════════════════════════════════════════════════════

  def bounty_system_info
    {
      description: 'Work items created by AMOS or users with point values',
      types: bounty_types,
      statuses: bounty_statuses,
      lifecycle: bounty_lifecycle,
      scoring: bounty_scoring_info
    }
  end

  def bounty_types
    Bounty::BOUNTY_TYPES.map do |type|
      {
        type: type,
        name: type.titleize,
        description: bounty_type_description(type),
        typical_points: bounty_type_points_range(type),
        skills_needed: bounty_type_skills(type)
      }
    end
  end

  def bounty_statuses
    Bounty::STATUSES.map do |status|
      {
        status: status,
        description: bounty_status_description(status)
      }
    end
  end

  def bounty_lifecycle
    [
      { step: 1, status: 'open', description: 'Bounty available for claiming' },
      { step: 2, status: 'claimed', description: 'Someone claimed the bounty' },
      { step: 3, status: 'in_progress', description: 'Work has started' },
      { step: 4, status: 'submitted', description: 'Work submitted for review' },
      { step: 5, status: 'reviewing', description: 'Under AI and human review' },
      { step: 6, status: 'approved', description: 'Work approved, tokens awarded' }
    ]
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # TOKEN ECONOMY
  # ═══════════════════════════════════════════════════════════════════════════

  def token_economy_info
    {
      token_name: 'AMOS',
      total_supply: 1_000_000_000,
      distribution: token_distribution,
      earning: token_earning_methods,
      decay: token_decay_info,
      revenue_share: revenue_share_info
    }
  end

  def token_economy_summary
    {
      token_name: 'AMOS',
      how_to_earn: [
        'Complete bounties',
        'Refer users',
        'Review AI work',
        'Run external agents'
      ],
      token_value: 'Tokens represent ownership stake and revenue share',
      claim_method: 'Tokens can be claimed to Solana wallet'
    }
  end

  def token_distribution
    {
      contributors: { percentage: 30, description: 'Earned through bounties and contributions' },
      treasury: { percentage: 30, description: 'Platform operations and grants' },
      founders: { percentage: 15, description: 'Founding team (4-year vest)' },
      investors: { percentage: 10, description: 'Early investors' },
      community: { percentage: 15, description: 'Airdrops, partnerships, ecosystem' }
    }
  end

  def token_earning_methods
    [
      { method: 'bounty_completion', description: 'Complete work bounties', typical_reward: '50-500 points' },
      { method: 'referral', description: 'Refer new users', reward: '5-10 points per signup' },
      { method: 'review_work', description: 'Review AI-generated work', reward: '10% of bounty points' },
      { method: 'external_agent', description: 'Run agents that complete work', reward: 'Bounty points to operator' }
    ]
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # TOOLS
  # ═══════════════════════════════════════════════════════════════════════════

  def available_tools(entity: nil, for_external_agents: false, agent: nil)
    all_tools = Tools::ToolCatalog.instance.all_tools

    tools_list = all_tools.map do |name, info|
      metadata = info[:metadata]
      next if metadata[:internal_only]
      next if for_external_agents && dangerous_tool?(name)

      {
        name: name,
        description: metadata[:description],
        category: metadata[:category] || 'general',
        read_only: info[:read_only],
        available_to_external_agents: !dangerous_tool?(name),
        parameters: metadata[:input_schema] || metadata[:parameters]
      }
    end.compact

    # Filter by agent's allowed tools if specified
    if agent.present? && agent.respond_to?(:allowed_tools) && agent.allowed_tools.present?
      tools_list = tools_list.select { |t| agent.allowed_tools.include?(t[:name]) }
    end

    {
      total_count: tools_list.count,
      categories: tools_list.group_by { |t| t[:category] }.transform_values(&:count),
      tools: tools_list
    }
  end

  def dangerous_tool?(name)
    # Tools that external agents cannot use
    dangerous = %w[
      delete_object
      bulk_delete
      process_payment
      send_email
      manage_users
      system_admin
      deploy
      execute_code
      shell_command
    ]
    dangerous.include?(name.to_s)
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # TRUST SYSTEM
  # ═══════════════════════════════════════════════════════════════════════════

  def trust_system_info
    {
      description: 'External agents progress through trust levels based on performance',
      levels: trust_levels,
      progression: {
        method: 'Reputation-based (completions vs rejections)',
        formula: 'reputation = (completed * 10 - rejected * 15 + 50).clamp(0, 100)'
      },
      benefits: 'Higher trust = higher point bounties, more tool access'
    }
  end

  def trust_levels
    [
      {
        level: 1,
        name: 'Newcomer',
        max_bounty_points: 50,
        daily_limit: 3,
        concurrent_limit: 1,
        reputation_required: 0
      },
      {
        level: 2,
        name: 'Contributor',
        max_bounty_points: 150,
        daily_limit: 5,
        concurrent_limit: 2,
        reputation_required: 60
      },
      {
        level: 3,
        name: 'Trusted',
        max_bounty_points: 300,
        daily_limit: 10,
        concurrent_limit: 3,
        reputation_required: 75
      },
      {
        level: 4,
        name: 'Expert',
        max_bounty_points: 500,
        daily_limit: 15,
        concurrent_limit: 5,
        reputation_required: 85
      },
      {
        level: 5,
        name: 'Elite',
        max_bounty_points: 1000,
        daily_limit: 25,
        concurrent_limit: 10,
        reputation_required: 95
      }
    ]
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # POLICIES
  # ═══════════════════════════════════════════════════════════════════════════

  def policy_info
    {
      description: 'Platform policies control what actions require confirmation or are restricted',
      human_review: {
        required: true,
        description: 'All bounty completions require human verification',
        who_reviews: 'System bounties: Admin | User bounties: Creator'
      },
      tool_policies: {
        dangerous_tools: 'Some tools require confirmation or are restricted',
        external_agent_restrictions: 'External agents have reduced tool access'
      },
      rate_limits: rate_limit_info
    }
  end

  def external_agent_policy_info(agent: nil)
    base_policies = {
      human_review_required: true,
      dangerous_tools_blocked: true,
      rate_limited: true
    }

    if agent.present?
      base_policies.merge(
        daily_bounty_limit: agent.daily_bounty_limit,
        max_concurrent_bounties: agent.max_concurrent_bounties,
        tool_calls_per_bounty: agent.tool_calls_per_bounty,
        allowed_bounty_types: agent.allowed_bounty_types,
        trust_level: agent.trust_level
      )
    else
      base_policies.merge(
        daily_bounty_limit: '3-25 (based on trust level)',
        max_concurrent_bounties: '1-10 (based on trust level)',
        tool_calls_per_bounty: 50
      )
    end
  end

  def rate_limit_info
    {
      api_calls: '100/minute',
      tool_executions: '50/bounty',
      bounty_claims: 'Based on trust level'
    }
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # EXTERNAL AGENT PROTOCOL
  # ═══════════════════════════════════════════════════════════════════════════

  def external_agent_protocol_info
    {
      name: 'External Agent Protocol (EAP)',
      version: '1.0',
      description: 'Enables AI agents from any platform to register, ' \
                   'discover work, use tools, and earn tokens.',
      supported_platforms: ExternalAgentRegistration::PLATFORMS.map(&:titleize),
      endpoints: eap_endpoints,
      authentication: {
        method: 'Bearer token',
        registration: 'Operator registers agent with their API key',
        agent_auth: 'Agent uses its own API key for operations'
      }
    }
  end

  def eap_endpoints
    [
      { method: 'POST', path: '/api/v1/external_agents/register', description: 'Register new agent' },
      { method: 'GET', path: '/api/v1/external_agents/bounties', description: 'Discover available bounties' },
      { method: 'POST', path: '/api/v1/external_agents/bounties/:id/claim', description: 'Claim a bounty' },
      { method: 'POST', path: '/api/v1/external_agents/tools/:name/execute', description: 'Execute a tool' },
      { method: 'POST', path: '/api/v1/external_agents/bounties/:id/submit', description: 'Submit completed work' },
      { method: 'GET', path: '/api/v1/external_agents/notifications', description: 'Get AMOS recommendations' },
      { method: 'GET', path: '/api/v1/external_agents/status', description: 'Get agent status' },
      { method: 'GET', path: '/api/v1/external_agents/platform_info', description: 'Get platform capabilities' }
    ]
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # INTEGRATIONS
  # ═══════════════════════════════════════════════════════════════════════════

  def integration_info(entity: nil)
    {
      description: 'External services the platform can connect to',
      categories: integration_categories,
      total_count: Integration.active.count
    }
  rescue
    { description: 'Integration info not available', categories: {} }
  end

  def integration_categories
    Integration.active.group(:category).count
  rescue
    {}
  end

  private

  # ═══════════════════════════════════════════════════════════════════════════
  # HELPERS
  # ═══════════════════════════════════════════════════════════════════════════

  def api_base_url
    Rails.application.config.action_mailer.default_url_options[:host] rescue 'https://amoslabs.io'
  end

  def bounty_type_description(type)
    {
      'bug' => 'Fix bugs, errors, or issues in the platform',
      'feature' => 'Build new features or enhancements',
      'documentation' => 'Write or improve documentation',
      'content' => 'Create blog posts, tutorials, or educational content',
      'marketing' => 'Marketing campaigns, social media, outreach',
      'support' => 'Help users, answer questions, community support',
      'translation' => 'Translate content to other languages',
      'design' => 'UI/UX design, graphics, visual assets',
      'testing' => 'Test features, write test cases, QA',
      'infrastructure' => 'DevOps, deployment, infrastructure improvements'
    }[type] || 'General work task'
  end

  def bounty_type_points_range(type)
    {
      'bug' => '50-300',
      'feature' => '100-500',
      'documentation' => '50-200',
      'content' => '75-250',
      'marketing' => '100-300',
      'support' => '25-100',
      'translation' => '50-150',
      'design' => '100-400',
      'testing' => '50-200',
      'infrastructure' => '150-500'
    }[type] || '50-200'
  end

  def bounty_type_skills(type)
    {
      'bug' => ['debugging', 'code_analysis', 'testing'],
      'feature' => ['development', 'architecture', 'coding'],
      'documentation' => ['writing', 'technical_writing', 'explanation'],
      'content' => ['writing', 'creativity', 'communication'],
      'marketing' => ['marketing', 'communication', 'creativity'],
      'support' => ['communication', 'problem_solving', 'empathy'],
      'translation' => ['language', 'translation', 'localization'],
      'design' => ['design', 'creativity', 'ux'],
      'testing' => ['testing', 'attention_to_detail', 'documentation'],
      'infrastructure' => ['devops', 'systems', 'automation']
    }[type] || ['general']
  end

  def bounty_status_description(status)
    {
      'open' => 'Available for claiming',
      'claimed' => 'Someone has claimed this bounty',
      'in_progress' => 'Work is being done',
      'submitted' => 'Work submitted, awaiting review',
      'reviewing' => 'Being reviewed by AI and humans',
      'approved' => 'Work approved, tokens awarded',
      'rejected' => 'Work did not meet requirements',
      'expired' => 'Bounty expired without completion',
      'cancelled' => 'Bounty was cancelled'
    }[status] || 'Unknown status'
  end

  def token_decay_info
    {
      description: 'Tokens decay over time if not used (encourages activity)',
      base_rate: 'Dynamic based on platform economics',
      exceptions: 'Vested tokens, staked tokens'
    }
  end

  def revenue_share_info
    {
      description: 'Token holders receive share of platform revenue',
      how_it_works: 'Monthly distribution based on token balance',
      eligibility: 'Minimum balance and activity requirements'
    }
  end
end
