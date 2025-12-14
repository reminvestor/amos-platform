# frozen_string_literal: true

# HubThread
#
# A conversation thread in the Collaborative Intelligence Hub.
# Threads can exist in channels, as DMs, or as work streams tied to agent tasks.
#
# Privacy: Agents can ONLY access threads where they are participants.
#
class HubThread < ApplicationRecord
  # Associations
  belongs_to :entity
  belongs_to :team_channel, optional: true
  belongs_to :started_by, polymorphic: true  # User or AgentPlugin
  belongs_to :agent_plugin_execution, optional: true
  belongs_to :agent_work_item, optional: true

  has_many :hub_messages, dependent: :destroy
  has_many :hub_participants, dependent: :destroy
  has_many :user_participants, through: :hub_participants, 
           source: :participant, source_type: 'User'
  has_many :agent_participants, through: :hub_participants,
           source: :participant, source_type: 'AgentPlugin'

  # Thread types
  CHANNEL = 'channel'.freeze        # In a team channel
  DM = 'dm'.freeze                  # Direct message between participants
  AGENT_HANDOFF = 'agent_handoff'.freeze  # Agent handing off to human
  WORK_STREAM = 'work_stream'.freeze      # Ongoing work collaboration

  TYPES = [CHANNEL, DM, AGENT_HANDOFF, WORK_STREAM].freeze
  STATUSES = %w[active archived resolved].freeze

  # Validations
  validates :thread_type, presence: true, inclusion: { in: TYPES }
  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :team_channel, presence: true, if: -> { thread_type == CHANNEL }

  # Scopes
  scope :active, -> { where(status: 'active') }
  scope :archived, -> { where(status: 'archived') }
  scope :channels, -> { where(thread_type: CHANNEL) }
  scope :dms, -> { where(thread_type: DM) }
  scope :work_streams, -> { where(thread_type: WORK_STREAM) }
  scope :handoffs, -> { where(thread_type: AGENT_HANDOFF) }
  scope :recent, -> { order(last_activity_at: :desc) }
  scope :with_unread_for, ->(participant) {
    joins(:hub_participants)
      .where(hub_participants: { participant: participant })
      .where('hub_participants.unread_count > 0')
  }

  # Callbacks
  before_create :set_last_activity
  after_create :add_starter_as_participant

  # ============================================
  # PARTICIPANT MANAGEMENT
  # ============================================

  def add_participant(participant, role: 'member')
    hub_participants.find_or_create_by!(participant: participant) do |hp|
      hp.role = role
      hp.joined_at = Time.current
      hp.context_access_from = Time.current
    end
  end

  def remove_participant(participant)
    hp = hub_participants.find_by(participant: participant)
    hp&.update!(left_at: Time.current)
  end

  def participant?(participant)
    hub_participants.active.exists?(participant: participant)
  end

  def participants
    hub_participants.active.includes(:participant).map(&:participant)
  end

  def user_count
    hub_participants.active.where(participant_type: 'User').count
  end

  def agent_count
    hub_participants.active.where(participant_type: 'AgentPlugin').count
  end

  # ============================================
  # MESSAGING
  # ============================================

  def add_message(sender:, content:, message_type: 'text', **options)
    raise "Sender not a participant" unless participant?(sender)

    message = hub_messages.create!(
      sender: sender,
      content: content,
      message_type: message_type,
      **options
    )

    # Update thread activity
    touch_activity!

    # Update unread counts for other participants
    hub_participants.active.where.not(participant: sender).find_each do |hp|
      hp.increment!(:unread_count)
    end

    # Broadcast the message
    broadcast_message(message)

    # Trigger agent response if this is a DM with an agent and sender is a user
    if thread_type == 'dm' && sender.is_a?(User)
      trigger_agent_response(message)
    end

    message
  end
  
  # Trigger agent to respond to a user message
  def trigger_agent_response(message)
    # Find agent participants in this thread
    agent_participants = hub_participants.active.where(participant_type: 'AgentPlugin')
    
    agent_participants.find_each do |hp|
      agent = hp.participant
      next unless agent
      
      Rails.logger.info "[Hub] Triggering response from #{agent.name} for message #{message.id}"
      
      # Build conversation context from recent messages
      recent_messages = hub_messages.where(deleted: false)
                                    .order(created_at: :desc)
                                    .limit(20)
                                    .reverse
      
      conversation_context = recent_messages.map do |msg|
        role = msg.sender_type == 'AgentPlugin' ? 'assistant' : 'user'
        { role: role, content: msg.content }
      end
      
      # Build the task prompt with conversation context
      task_prompt = if conversation_context.length > 1
        # This is a follow-up message in an ongoing conversation
        <<~PROMPT
          [Continuing conversation]
          
          Previous messages in this conversation:
          #{conversation_context[0..-2].map { |m| "#{m[:role].upcase}: #{m[:content]}" }.join("\n\n")}
          
          ---
          
          User's latest message: #{message.content}
          
          Respond appropriately. If the user is asking for changes or improvements to your previous work, acknowledge what they want changed and provide an updated response.
        PROMPT
      else
        # First message in conversation
        message.content
      end
      
      # Use the existing agent execution system
      execution = AgentPluginExecution.create!(
        agent_plugin: agent,
        entity_id: entity_id,
        user_id: message.sender_id,
        status: 'running',
        started_at: Time.current,
        model_id: 'claude-sonnet-4-5',
        input_context: {
          task: message.content,
          hub_thread_id: id,
          hub_message_id: message.id,
          source: 'hub_dm',
          is_followup: conversation_context.length > 1
        }
      )
      
      # Queue the existing agent execution job
      AgentPluginExecutionJob.perform_later(
        execution.id,
        task_prompt,
        {
          entity_id: entity_id,
          user_id: message.sender_id,
          hub_thread_id: id,
          hub_message_id: message.id,
          respond_in_hub: true,
          conversation_context: conversation_context
        }
      )
    end
  rescue => e
    Rails.logger.error "[Hub] Error triggering agent response: #{e.message}"
    Rails.logger.error e.backtrace.first(5).join("\n")
  end

  def messages_for_participant(participant)
    hp = hub_participants.find_by(participant: participant)
    return HubMessage.none unless hp

    # Participants can only see messages from when they joined
    hub_messages
      .where('created_at >= ?', hp.context_access_from || hp.joined_at)
      .where(deleted: false)
      .order(created_at: :asc)
  end

  # ============================================
  # DM HELPERS
  # ============================================

  def self.find_or_create_dm(entity:, participants:)
    # Sort participant IDs for consistent lookup
    participant_key = participants.map { |p| "#{p.class.name}:#{p.id}" }.sort

    # Check for existing DM with same participants
    existing = where(entity: entity, thread_type: DM)
                 .joins(:hub_participants)
                 .group('hub_threads.id')
                 .having('COUNT(*) = ?', participants.size)
                 .find_each do |thread|
      thread_key = thread.participants.map { |p| "#{p.class.name}:#{p.id}" }.sort
      return thread if thread_key == participant_key
    end

    # Create new DM
    thread = create!(
      entity: entity,
      thread_type: DM,
      started_by: participants.first,
      dm_participant_ids: participants.map { |p| { type: p.class.name, id: p.id } }
    )

    participants.each { |p| thread.add_participant(p, role: 'member') }
    thread
  end

  # ============================================
  # HANDOFF HELPERS
  # ============================================

  def create_handoff_request(from_agent:, to_user:, summary:, completed_items:, needed_items:, next_steps:)
    message = add_message(
      sender: from_agent,
      content: summary,
      message_type: 'handoff_request',
      is_handoff: true,
      handoff_status: 'pending',
      needs_response: true,
      metadata: {
        completed_items: completed_items,
        needed_items: needed_items,
        next_steps: next_steps
      },
      actions: [
        { id: 'approve', label: 'Approve All', style: 'primary' },
        { id: 'review', label: 'Review Details', style: 'secondary' },
        { id: 'discuss', label: 'Discuss', style: 'secondary' }
      ]
    )

    message
  end

  # ============================================
  # STATUS & ACTIVITY
  # ============================================

  def touch_activity!
    update_columns(
      last_activity_at: Time.current,
      message_count: hub_messages.count
    )
  end

  def archive!
    update!(status: 'archived')
  end

  def resolve!
    update!(status: 'resolved')
  end

  def dm?
    thread_type == DM
  end

  def channel?
    thread_type == CHANNEL
  end

  def work_stream?
    thread_type == WORK_STREAM
  end

  def handoff?
    thread_type == AGENT_HANDOFF
  end

  # Display name for the thread
  def display_name(for_participant: nil)
    return subject if subject.present?

    case thread_type
    when CHANNEL
      team_channel&.name || 'Channel'
    when DM
      # Show other participant's name
      others = participants.reject { |p| p == for_participant }
      others.map { |p| p.respond_to?(:name) ? p.name : p.to_s }.join(', ')
    when WORK_STREAM
      agent_plugin_execution&.agent_plugin&.name || 'Work Stream'
    when AGENT_HANDOFF
      "Handoff: #{started_by&.name}"
    end
  end

  private

  def set_last_activity
    self.last_activity_at = Time.current
  end

  def add_starter_as_participant
    add_participant(started_by, role: 'owner')
  end

  def broadcast_message(message)
    HubChannel.broadcast_to_thread(id, {
      type: 'new_message',
      thread_id: id,
      message: message.as_broadcast_json
    })
  end
end
