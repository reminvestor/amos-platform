# frozen_string_literal: true

# HubPresence
#
# Real-time presence tracking for humans AND agents in the Hub.
# Shows who's online, what agents are working on, etc.
#
class HubPresence < ApplicationRecord
  # Associations
  belongs_to :entity
  belongs_to :participant, polymorphic: true  # User or AgentPlugin
  belongs_to :active_execution, class_name: 'AgentPluginExecution', optional: true

  # User statuses
  USER_ONLINE = 'online'.freeze
  USER_AWAY = 'away'.freeze
  USER_BUSY = 'busy'.freeze
  USER_OFFLINE = 'offline'.freeze

  USER_STATUSES = [USER_ONLINE, USER_AWAY, USER_BUSY, USER_OFFLINE].freeze

  # Agent statuses
  AGENT_ONLINE = 'online'.freeze      # Available, not doing anything
  AGENT_WORKING = 'working'.freeze    # Actively processing a task
  AGENT_THINKING = 'thinking'.freeze  # Making decisions, analyzing
  AGENT_WAITING = 'waiting'.freeze    # Waiting for human input
  AGENT_OFFLINE = 'offline'.freeze    # Not available

  AGENT_STATUSES = [AGENT_ONLINE, AGENT_WORKING, AGENT_THINKING, AGENT_WAITING, AGENT_OFFLINE].freeze

  ALL_STATUSES = (USER_STATUSES + AGENT_STATUSES).uniq.freeze

  # Validations
  validates :status, presence: true, inclusion: { in: ALL_STATUSES }

  # Scopes
  scope :online, -> { where.not(status: 'offline') }
  scope :offline, -> { where(status: 'offline') }
  scope :users, -> { where(participant_type: 'User') }
  scope :agents, -> { where(participant_type: 'AgentPlugin') }
  scope :working, -> { where(status: [AGENT_WORKING, AGENT_THINKING]) }
  scope :waiting_on_human, -> { where(status: AGENT_WAITING) }
  scope :expired, -> { where('expires_at < ?', Time.current) }
  scope :for_entity, ->(entity) { where(entity: entity) }

  # Callbacks
  after_save :broadcast_presence_change, if: :saved_change_to_status?
  after_save :broadcast_activity_change, if: :saved_change_to_current_activity?

  # ============================================
  # TYPE HELPERS
  # ============================================

  def user?
    participant_type == 'User'
  end

  def agent?
    participant_type == 'AgentPlugin'
  end

  def online?
    status != 'offline'
  end

  def available?
    status.in?([USER_ONLINE, AGENT_ONLINE])
  end

  def busy?
    status.in?([USER_BUSY, AGENT_WORKING, AGENT_THINKING, AGENT_WAITING])
  end

  # ============================================
  # STATUS MANAGEMENT
  # ============================================

  def go_online!(custom_status: nil, emoji: nil)
    update!(
      status: user? ? USER_ONLINE : AGENT_ONLINE,
      status_message: custom_status,
      status_emoji: emoji,
      last_seen_at: Time.current,
      status_changed_at: Time.current,
      expires_at: 5.minutes.from_now
    )
  end

  def go_offline!
    update!(
      status: 'offline',
      current_activity: nil,
      active_execution: nil,
      activity_progress: nil,
      status_changed_at: Time.current,
      expires_at: nil
    )
  end

  def go_away!
    return unless user?
    
    update!(
      status: USER_AWAY,
      status_changed_at: Time.current
    )
  end

  def heartbeat!
    touch(:last_seen_at)
    update_column(:expires_at, 5.minutes.from_now)
  end

  # ============================================
  # AGENT ACTIVITY TRACKING
  # ============================================

  def start_working!(activity:, execution: nil, progress: 0.0)
    return unless agent?

    update!(
      status: AGENT_WORKING,
      current_activity: activity,
      active_execution: execution,
      activity_progress: progress,
      status_changed_at: Time.current
    )
  end

  def start_thinking!(activity: nil)
    return unless agent?

    update!(
      status: AGENT_THINKING,
      current_activity: activity || 'Analyzing...',
      status_changed_at: Time.current
    )
  end

  def waiting_for_human!(reason: nil)
    return unless agent?

    update!(
      status: AGENT_WAITING,
      current_activity: reason || 'Waiting for your input',
      status_changed_at: Time.current
    )
  end

  def update_progress!(progress, activity: nil)
    return unless agent?

    updates = { activity_progress: progress.clamp(0.0, 1.0) }
    updates[:current_activity] = activity if activity.present?
    update!(updates)
  end

  def finish_work!
    return unless agent?

    update!(
      status: AGENT_ONLINE,
      current_activity: nil,
      active_execution: nil,
      activity_progress: nil,
      status_changed_at: Time.current
    )
  end

  # ============================================
  # CLASS METHODS
  # ============================================

  def self.for_participant(participant)
    find_or_create_by!(
      entity: participant.respond_to?(:entity) ? participant.entity : participant.entities.first,
      participant: participant
    ) do |presence|
      presence.status = 'offline'
    end
  end

  def self.cleanup_expired!
    expired.find_each do |presence|
      presence.go_offline!
    end
  end

  def self.entity_summary(entity)
    presences = for_entity(entity).includes(:participant, :active_execution)

    {
      users: {
        online: presences.users.online.count,
        away: presences.users.where(status: USER_AWAY).count,
        busy: presences.users.where(status: USER_BUSY).count,
        total: presences.users.count
      },
      agents: {
        online: presences.agents.where(status: AGENT_ONLINE).count,
        working: presences.agents.working.count,
        waiting: presences.agents.waiting_on_human.count,
        total: presences.agents.count
      },
      active_work: presences.agents.working.map do |p|
        {
          agent_id: p.participant_id,
          agent_name: p.participant.name,
          activity: p.current_activity,
          progress: p.activity_progress
        }
      end
    }
  end

  # ============================================
  # SERIALIZATION
  # ============================================

  def as_broadcast_json
    {
      participant_id: participant_id,
      participant_type: participant_type,
      participant_name: participant.respond_to?(:name) ? participant.name : nil,
      status: status,
      status_message: status_message,
      status_emoji: status_emoji,
      current_activity: current_activity,
      activity_progress: activity_progress,
      last_seen_at: last_seen_at&.iso8601
    }
  end

  def status_display
    case status
    when USER_ONLINE, AGENT_ONLINE then '🟢'
    when USER_AWAY then '🟡'
    when USER_BUSY, AGENT_WORKING, AGENT_THINKING then '🔴'
    when AGENT_WAITING then '🟠'
    else '⚫'
    end
  end

  private

  def broadcast_presence_change
    HubChannel.broadcast_presence(entity_id, as_broadcast_json)
  end

  def broadcast_activity_change
    return unless agent? && current_activity.present?

    HubChannel.broadcast_agent_activity(entity_id, {
      agent_id: participant_id,
      agent_name: participant.name,
      activity: current_activity,
      progress: activity_progress,
      status: status
    })
  end
end
