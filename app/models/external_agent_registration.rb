# frozen_string_literal: true

# ExternalAgentRegistration - Tracks AI agents from external platforms
#
# Enables agents running on OpenClaw, custom builds, or other platforms
# to register with Amos Labs, discover bounties, and earn tokens.
#
# Key concepts:
# - operator: The human user responsible for this agent
# - capabilities: What the agent claims it can do (maps to bounty types)
# - trust_level: Unlocks more capabilities as agent proves itself
# - reputation_score: Quality metric based on work approval rate
#
class ExternalAgentRegistration < ApplicationRecord
  # Associations
  belongs_to :entity
  belongs_to :operator, class_name: 'User'
  
  has_many :external_agent_executions, dependent: :destroy
  has_many :external_agent_tool_calls, dependent: :destroy
  has_many :external_agent_daily_stats, dependent: :destroy
  has_many :external_agent_notifications, dependent: :destroy
  has_many :bounties, through: :external_agent_executions

  # Platform types
  PLATFORMS = %w[openclaw custom mcp langchain autogen crewai other].freeze

  # Status progression
  STATUSES = %w[pending active suspended revoked].freeze

  # Trust levels unlock capabilities
  TRUST_LEVELS = {
    1 => { bounty_types: %w[documentation content], max_points: 100, tools: %w[web_search get_data list_documents] },
    2 => { bounty_types: %w[documentation content support translation], max_points: 200, tools: %w[web_search get_data list_documents read_document] },
    3 => { bounty_types: %w[documentation content support translation bug testing], max_points: 500, tools: %w[web_search get_data list_documents read_document create_object] },
    4 => { bounty_types: %w[documentation content support translation bug testing feature design], max_points: 1000, tools: %w[web_search get_data list_documents read_document create_object update_object] },
    5 => { bounty_types: Bounty::BOUNTY_TYPES, max_points: nil, tools: :all }
  }.freeze

  # Validations
  validates :agent_identifier, presence: true, uniqueness: true
  validates :agent_name, presence: true
  validates :agent_platform, presence: true, inclusion: { in: PLATFORMS }
  validates :api_key, presence: true, uniqueness: true
  validates :api_key_prefix, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :reputation_score, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }
  validates :trust_level, numericality: { greater_than_or_equal_to: 1, less_than_or_equal_to: 5 }
  validates :daily_bounty_limit, numericality: { greater_than: 0, less_than_or_equal_to: 50 }
  
  # Operator can have max 5 active agents
  validate :operator_agent_limit, on: :create

  # Scopes
  scope :active, -> { where(status: 'active') }
  scope :pending, -> { where(status: 'pending') }
  scope :suspended, -> { where(status: 'suspended') }
  scope :by_platform, ->(platform) { where(agent_platform: platform) }
  scope :for_operator, ->(user) { where(operator: user) }
  scope :for_entity, ->(entity) { where(entity: entity) }
  scope :recently_active, -> { where('last_active_at > ?', 24.hours.ago) }
  scope :top_performers, -> { active.order(reputation_score: :desc) }

  # Callbacks
  before_validation :generate_api_key, on: :create
  before_validation :set_initial_permissions, on: :create
  after_create :schedule_activation

  # ═══════════════════════════════════════════════════════════════════════════
  # AUTHENTICATION
  # ═══════════════════════════════════════════════════════════════════════════

  # Find agent by API key (used in authentication)
  def self.authenticate(api_key)
    return nil if api_key.blank?
    
    prefix = api_key[0..7]
    agent = find_by(api_key_prefix: prefix, status: 'active')
    return nil unless agent
    
    # Secure comparison to prevent timing attacks
    ActiveSupport::SecurityUtils.secure_compare(agent.api_key, api_key) ? agent : nil
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # STATUS MANAGEMENT
  # ═══════════════════════════════════════════════════════════════════════════

  def activate!
    return false unless pending?
    
    update!(
      status: 'active',
      last_active_at: Time.current
    )
  end

  def suspend!(reason:)
    update!(
      status: 'suspended',
      suspended_at: Time.current,
      suspension_reason: reason
    )
  end

  def revoke!
    update!(status: 'revoked')
  end

  def reactivate!
    return false unless suspended?
    
    update!(
      status: 'active',
      suspended_at: nil,
      suspension_reason: nil
    )
  end

  def active?
    status == 'active'
  end

  def pending?
    status == 'pending'
  end

  def suspended?
    status == 'suspended'
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # CAPABILITY & PERMISSION CHECKS
  # ═══════════════════════════════════════════════════════════════════════════

  def can_claim_bounty?(bounty)
    return false unless active?
    return false unless within_daily_limit?
    return false unless within_concurrent_limit?
    return false unless can_work_bounty_type?(bounty.bounty_type)
    return false unless can_earn_points?(bounty.points)
    
    true
  end

  def can_work_bounty_type?(bounty_type)
    allowed_bounty_types.include?(bounty_type)
  end

  def can_use_tool?(tool_name)
    return true if allowed_tools.include?('*')  # Wildcard access
    
    allowed_tools.include?(tool_name)
  end

  def can_earn_points?(points)
    max_points = trust_config[:max_points]
    return true if max_points.nil?  # No limit
    
    points <= max_points
  end

  def within_daily_limit?
    today_stats.bounties_claimed < daily_bounty_limit
  end

  def within_concurrent_limit?
    external_agent_executions.where(status: 'in_progress').count < max_concurrent_bounties
  end

  def daily_remaining
    [daily_bounty_limit - today_stats.bounties_claimed, 0].max
  end

  def trust_config
    TRUST_LEVELS[trust_level] || TRUST_LEVELS[1]
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # REPUTATION & PROGRESSION
  # ═══════════════════════════════════════════════════════════════════════════

  def update_reputation!
    return if total_bounties_completed.zero? && total_bounties_rejected.zero?
    
    total = total_bounties_completed + total_bounties_rejected
    approval_rate = total_bounties_completed.to_f / total
    
    # Weighted score: 60% approval rate, 40% quality average
    avg_quality = external_agent_executions.approved.average(:quality_score) || 50.0
    new_score = (approval_rate * 60) + (avg_quality * 0.4)
    
    update!(reputation_score: new_score.round(2))
    
    # Check for trust level upgrade
    check_trust_level_upgrade!
  end

  def check_trust_level_upgrade!
    return if trust_level >= 5
    
    thresholds = {
      2 => { min_completed: 3, min_reputation: 55 },
      3 => { min_completed: 10, min_reputation: 65 },
      4 => { min_completed: 25, min_reputation: 75 },
      5 => { min_completed: 50, min_reputation: 85 }
    }
    
    next_level = trust_level + 1
    threshold = thresholds[next_level]
    
    if total_bounties_completed >= threshold[:min_completed] && reputation_score >= threshold[:min_reputation]
      upgrade_trust_level!(next_level)
    end
  end

  def upgrade_trust_level!(new_level)
    config = TRUST_LEVELS[new_level]
    
    update!(
      trust_level: new_level,
      allowed_bounty_types: config[:bounty_types],
      allowed_tools: config[:tools] == :all ? ['*'] : config[:tools],
      daily_bounty_limit: calculate_daily_limit(new_level),
      max_concurrent_bounties: [new_level, 3].min
    )
    
    # Notify operator of upgrade
    notify_operator(:trust_level_upgraded, level: new_level)
  end

  def approval_rate
    total = total_bounties_completed + total_bounties_rejected
    return 0.0 if total.zero?
    
    (total_bounties_completed.to_f / total * 100).round(1)
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # STATISTICS
  # ═══════════════════════════════════════════════════════════════════════════

  def today_stats
    external_agent_daily_stats.find_or_create_by!(stat_date: Date.current)
  end

  def record_bounty_claimed!
    today_stats.increment!(:bounties_claimed)
    increment!(:total_bounties_claimed)
    touch(:last_active_at)
  end

  def record_bounty_completed!(tokens_earned)
    today_stats.increment!(:bounties_completed)
    today_stats.increment!(:tokens_earned, tokens_earned)
    
    increment!(:total_bounties_completed)
    self.total_tokens_earned += tokens_earned
    save!
    
    update_reputation!
  end

  def record_bounty_rejected!
    today_stats.increment!(:bounties_rejected)
    increment!(:total_bounties_rejected)
    
    update_reputation!
  end

  # Calculate available bounty slots (for matching service)
  def available_bounty_slots
    active = external_agent_executions.where(status: 'in_progress').count
    [max_concurrent_bounties - active, 0].max
  end

  # Calculate success rate (completions / total attempts)
  def success_rate
    return 100.0 if total_bounties_completed.zero? && total_bounties_rejected.zero?
    
    total_attempts = total_bounties_completed + total_bounties_rejected
    return 100.0 if total_attempts.zero?
    
    (total_bounties_completed.to_f / total_attempts * 100).round(1)
    
    # Auto-suspend if too many rejections
    check_for_auto_suspension!
  end

  def record_tool_call!
    today_stats.increment!(:tool_calls)
    touch(:last_active_at)
  end

  def check_for_auto_suspension!
    # Suspend if 3+ rejections in a row or approval rate drops below 30%
    recent_executions = external_agent_executions.order(created_at: :desc).limit(5)
    recent_rejections = recent_executions.rejected.count
    
    if recent_rejections >= 3 || (total_bounties_completed > 5 && approval_rate < 30)
      suspend!(reason: "Automatic suspension: high rejection rate (#{approval_rate}%)")
      notify_operator(:agent_suspended, reason: suspension_reason)
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # API RESPONSES
  # ═══════════════════════════════════════════════════════════════════════════

  def to_api_response(include_key: false)
    response = {
      id: id,
      agent_identifier: agent_identifier,
      agent_name: agent_name,
      agent_platform: agent_platform,
      status: status,
      trust_level: trust_level,
      reputation_score: reputation_score,
      approval_rate: approval_rate,
      total_bounties_completed: total_bounties_completed,
      total_tokens_earned: total_tokens_earned.to_f,
      daily_bounty_limit: daily_bounty_limit,
      daily_remaining: daily_remaining,
      allowed_bounty_types: allowed_bounty_types,
      allowed_tools: allowed_tools,
      last_active_at: last_active_at&.iso8601,
      created_at: created_at.iso8601
    }
    
    response[:api_key] = api_key if include_key
    response
  end

  def status_summary
    {
      agent: to_api_response,
      current_executions: external_agent_executions.in_progress.map(&:to_summary),
      recent_completions: external_agent_executions.completed_recently.limit(5).map(&:to_summary)
    }
  end

  private

  def generate_api_key
    return if api_key.present?
    
    self.api_key = "ext_#{SecureRandom.hex(32)}"
    self.api_key_prefix = api_key[0..7]
  end

  def set_initial_permissions
    config = TRUST_LEVELS[1]
    
    self.trust_level ||= 1
    self.allowed_bounty_types ||= config[:bounty_types]
    self.allowed_tools ||= config[:tools]
    self.daily_bounty_limit ||= 3
    self.max_concurrent_bounties ||= 1
    self.reputation_score ||= 50.0
  end

  def schedule_activation
    # New agents have 24h cooldown before activation
    # For launch, we can auto-activate
    activate! if Rails.env.development? || metadata['auto_activate']
  end

  def operator_agent_limit
    if operator.present? && operator.external_agent_registrations.active.count >= 5
      errors.add(:operator, 'has reached maximum of 5 active agents')
    end
  end

  def calculate_daily_limit(level)
    case level
    when 1 then 3
    when 2 then 5
    when 3 then 10
    when 4 then 15
    when 5 then 25
    else 3
    end
  end

  def notify_operator(event, **data)
    # Create notification for operator
    return unless operator.present?
    
    UserNotification.create(
      user: operator,
      entity: entity,
      notification_type: "external_agent_#{event}",
      title: notification_title(event),
      message: notification_message(event, data),
      metadata: { agent_id: id, agent_name: agent_name, **data }
    )
  rescue => e
    Rails.logger.warn "[ExternalAgent] Failed to notify operator: #{e.message}"
  end

  def notification_title(event)
    case event
    when :trust_level_upgraded then "Agent Upgraded: #{agent_name}"
    when :agent_suspended then "Agent Suspended: #{agent_name}"
    else "External Agent Update"
    end
  end

  def notification_message(event, data)
    case event
    when :trust_level_upgraded
      "Your agent #{agent_name} has been upgraded to trust level #{data[:level]}!"
    when :agent_suspended
      "Your agent #{agent_name} has been suspended: #{data[:reason]}"
    else
      "Update for agent #{agent_name}"
    end
  end
end
