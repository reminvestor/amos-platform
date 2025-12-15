# TeamChannel
#
# Represents a shared channel in Team Space for entity-wide collaboration.
# Part of the Collaborative Intelligence Hub where humans and agents communicate.
#
class TeamChannel < ApplicationRecord
  belongs_to :entity

  # Hub associations
  has_many :hub_threads, dependent: :destroy
  has_many :hub_messages, through: :hub_threads

  # Validations
  validates :name, presence: true, uniqueness: { scope: :entity_id }
  validates :channel_type, inclusion: { in: %w[general project integration agent] }

  # Scopes
  scope :active, -> { where(archived: false) }
  scope :archived, -> { where(archived: true) }
  scope :default_channels, -> { where(is_default: true) }
  scope :by_type, ->(type) { where(channel_type: type) }
  scope :ordered, -> { order(is_default: :desc, name: :asc) }
  scope :public_channels, -> { where(is_private: false) }
  scope :private_channels, -> { where(is_private: true) }
  scope :recent, -> { order(last_activity_at: :desc) }

  # Channel types
  GENERAL = 'general'.freeze
  PROJECT = 'project'.freeze
  INTEGRATION = 'integration'.freeze
  AGENT = 'agent'.freeze  # Agent-focused channels

  TYPES = [GENERAL, PROJECT, INTEGRATION, AGENT].freeze

  # Callbacks
  after_create :create_default_thread
  after_create :invite_default_agents, if: :auto_invite_agents?

  # Archive the channel
  def archive!
    update!(archived: true)
  end

  # Unarchive the channel
  def unarchive!
    update!(archived: false)
  end

  # Get channel icon based on type
  def icon
    case channel_type
    when GENERAL then 'hash'
    when PROJECT then 'folder'
    when INTEGRATION then 'plug'
    when AGENT then 'cpu'
    else 'message-circle'
    end
  end

  # ============================================
  # AGENT ROSTER MANAGEMENT
  # ============================================

  def agents
    return AgentPlugin.none if agent_roster.blank?
    
    AgentPlugin.where(id: agent_roster)
  end

  def add_agent(agent)
    return if agent_roster&.include?(agent.id)
    
    new_roster = (agent_roster || []) + [agent.id]
    update!(agent_roster: new_roster)
    
    # Add agent to all active threads in this channel
    hub_threads.active.find_each do |thread|
      thread.add_participant(agent, role: 'member')
    end
  end

  def remove_agent(agent)
    return unless agent_roster&.include?(agent.id)
    
    update!(agent_roster: agent_roster - [agent.id])
  end

  def has_agent?(agent)
    agent_roster&.include?(agent.id)
  end

  # ============================================
  # THREAD MANAGEMENT
  # ============================================

  def main_thread
    hub_threads.find_by(subject: nil) || create_default_thread
  end

  def create_thread(started_by:, subject: nil)
    thread = hub_threads.create!(
      entity: entity,
      started_by: started_by,
      subject: subject,
      thread_type: HubThread::CHANNEL
    )

    # Add channel agents to the thread
    agents.find_each do |agent|
      thread.add_participant(agent, role: 'member')
    end

    thread
  end

  def touch_activity!
    update_column(:last_activity_at, Time.current)
  end

  # ============================================
  # CLASS METHODS
  # ============================================

  # Class method to create default channels for a new entity
  def self.create_defaults_for(entity)
    channels = []
    
    channels << create!(
      entity: entity,
      name: 'General',
      description: 'General team discussions and updates',
      channel_type: GENERAL,
      is_default: true,
      purpose: 'Company-wide announcements and team discussions',
      auto_invite_agents: true
    )

    channels << create!(
      entity: entity,
      name: 'Agent Activity',
      description: 'See what AI agents are working on',
      channel_type: AGENT,
      is_default: false,
      purpose: 'Live feed of agent work and status updates',
      auto_invite_agents: true,
      allow_agent_initiation: true
    )

    channels
  end

  # Class method to get or create default channel for entity
  def self.default_for(entity)
    find_by(entity: entity, is_default: true) || 
      create_defaults_for(entity).first
  end

  private

  def create_default_thread
    return if hub_threads.exists?(subject: nil)
    
    hub_threads.create!(
      entity: entity,
      started_by: entity.owner || entity.users.first,
      thread_type: HubThread::CHANNEL
    )
  rescue => e
    Rails.logger.warn "Could not create default thread for channel #{id}: #{e.message}"
  end

  def invite_default_agents
    return unless auto_invite_agents?
    
    # Invite all active entity agents to this channel
    AgentPlugin.active.for_entity(entity).find_each do |agent|
      add_agent(agent)
    end
  end
end
