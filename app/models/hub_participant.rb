# frozen_string_literal: true

# HubParticipant
#
# Tracks who is in a Hub thread - both humans AND agents.
# This is the core of the privacy model: agents can only see threads they're in.
#
class HubParticipant < ApplicationRecord
  # Associations
  belongs_to :hub_thread
  belongs_to :participant, polymorphic: true  # User or AgentPlugin

  # Roles
  OWNER = 'owner'.freeze      # Created the thread
  MEMBER = 'member'.freeze    # Full participant
  OBSERVER = 'observer'.freeze # Can read but not write
  MENTIONED = 'mentioned'.freeze # Added via @mention

  ROLES = [OWNER, MEMBER, OBSERVER, MENTIONED].freeze

  # Validations
  validates :role, presence: true, inclusion: { in: ROLES }
  validates :joined_at, presence: true
  validates :participant_id, uniqueness: { 
    scope: [:hub_thread_id, :participant_type],
    message: 'is already a participant in this thread'
  }

  # Scopes
  scope :active, -> { where(left_at: nil) }
  scope :left, -> { where.not(left_at: nil) }
  scope :users, -> { where(participant_type: 'User') }
  scope :agents, -> { where(participant_type: 'AgentPlugin') }
  scope :with_unread, -> { where('unread_count > 0') }
  scope :owners, -> { where(role: OWNER) }
  scope :members, -> { where(role: [OWNER, MEMBER]) }
  scope :by_role, ->(role) { where(role: role) }
  scope :unmuted, -> { where(muted: false).or(where('muted_until < ?', Time.current)) }

  # Callbacks
  before_validation :set_defaults, on: :create
  after_create :update_thread_dm_cache, if: -> { hub_thread.dm? }

  # ============================================
  # TYPE HELPERS
  # ============================================

  def user?
    participant_type == 'User'
  end

  def agent?
    participant_type == 'AgentPlugin'
  end

  def active?
    left_at.nil?
  end

  def left?
    left_at.present?
  end

  # ============================================
  # READ TRACKING
  # ============================================

  def mark_read!
    update!(
      last_read_at: Time.current,
      unread_count: 0
    )
  end

  def mark_read_up_to!(message)
    return if message.created_at <= (last_read_at || Time.at(0))

    unread = hub_thread.hub_messages
                       .where('created_at > ?', message.created_at)
                       .where(deleted: false)
                       .count

    update!(
      last_read_at: message.created_at,
      unread_count: unread
    )
  end

  def has_unread?
    unread_count.positive?
  end

  # ============================================
  # NOTIFICATIONS
  # ============================================

  def muted?
    return false unless muted
    return true if muted_until.nil?
    
    muted_until > Time.current
  end

  def mute!(duration: nil)
    update!(
      muted: true,
      muted_until: duration ? Time.current + duration : nil
    )
  end

  def unmute!
    update!(muted: false, muted_until: nil)
  end

  def should_notify?
    active? && notifications_enabled && !muted?
  end

  # ============================================
  # CONTEXT ACCESS (for agents)
  # ============================================

  def accessible_messages
    hub_thread.hub_messages
              .where('created_at >= ?', context_access_from || joined_at)
              .where(deleted: false)
              .order(created_at: :asc)
  end

  def can_access_message?(message)
    return false unless active? || message.created_at <= left_at
    
    message.created_at >= (context_access_from || joined_at)
  end

  def has_permission?(permission)
    (permissions || {})[permission.to_s] == true
  end

  def grant_permission!(permission)
    update!(permissions: (permissions || {}).merge(permission.to_s => true))
  end

  def revoke_permission!(permission)
    update!(permissions: (permissions || {}).merge(permission.to_s => false))
  end

  # ============================================
  # SERIALIZATION
  # ============================================

  def as_json_for_list
    {
      id: id,
      participant: {
        id: participant_id,
        type: participant_type,
        name: participant.respond_to?(:name) ? participant.name : participant.to_s,
        avatar: participant.respond_to?(:avatar_url) ? participant.avatar_url : nil,
        icon: participant.respond_to?(:icon) ? participant.icon : (agent? ? '🤖' : nil)
      },
      role: role,
      joined_at: joined_at.iso8601,
      unread_count: unread_count,
      muted: muted?
    }
  end

  private

  def set_defaults
    self.joined_at ||= Time.current
    self.context_access_from ||= Time.current if agent?
  end

  def update_thread_dm_cache
    # Update the DM participant cache on the thread for fast lookups
    current = hub_thread.dm_participant_ids || []
    new_entry = { 'type' => participant_type, 'id' => participant_id }
    
    # Check if this participant is already in the cache (avoid duplicates)
    already_exists = current.any? do |entry|
      entry['type'] == participant_type && entry['id'] == participant_id
    end
    
    unless already_exists
      current << new_entry
      hub_thread.update_column(:dm_participant_ids, current)
    end
  end
end
