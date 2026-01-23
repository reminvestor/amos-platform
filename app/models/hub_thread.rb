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
      
      # Broadcast unread count update to each participant
      if hp.participant_type == 'User'
        total_unread = hp.participant.hub_participations
                                     .joins(:hub_thread)
                                     .where(hub_threads: { entity: entity, status: 'active' })
                                     .sum(:unread_count)
        
        HubChannel.broadcast_unread_count(hp.participant_id, total_unread)
      end
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
      
      # Check if there's a pending input request for this agent in this thread
      # This means the agent asked a question and is waiting for the user's response
      pending_input = find_pending_input_request(agent, message.sender)
      
      if pending_input
        Rails.logger.info "[Hub] Found pending input request #{pending_input.id} - answering instead of new execution"
        answer_pending_input_request(pending_input, message)
        next
      end
      
      # Extract attachments/file URLs from the message
      # Attachment structure: [{"type": "file", "url": {"url": "http://...", "filename": "..."}}]
      attachments = message.attachments || []
      file_urls = attachments.map do |a|
        url_data = a['url'] || a[:url]
        if url_data.is_a?(Hash)
          url_data['url'] || url_data[:url]
        else
          url_data
        end
      end.compact
      
      Rails.logger.info "[Hub] Message has #{file_urls.length} attachments: #{file_urls}" if file_urls.any?
      
      # Build conversation context from recent messages
      recent_messages = hub_messages.where(deleted: false)
                                    .order(created_at: :desc)
                                    .limit(20)
                                    .reverse
      
      conversation_context = recent_messages.map do |msg|
        role = msg.sender_type == 'AgentPlugin' ? 'assistant' : 'user'
        { role: role, content: msg.content }
      end
      
      # Build the task prompt with conversation context and attachments
      attachment_info = if file_urls.any?
        "\n\n[Attached files: #{file_urls.join(', ')}]\nPlease analyze and use these files as needed."
      else
        ""
      end
      
      task_prompt = if conversation_context.length > 1
        # This is a follow-up message in an ongoing conversation
        <<~PROMPT
          [Continuing conversation]
          
          Previous messages in this conversation:
          #{conversation_context[0..-2].map { |m| "#{m[:role].upcase}: #{m[:content]}" }.join("\n\n")}
          
          ---
          
          User's latest message: #{message.content}#{attachment_info}
          
          Respond appropriately. If the user is asking for changes or improvements to your previous work, acknowledge what they want changed and provide an updated response.
        PROMPT
      else
        # First message in conversation
        "#{message.content}#{attachment_info}"
      end
      
      # Use the existing agent execution system
      # Note: AgentPluginExecution doesn't have entity_id - entity comes from agent_plugin
      execution = AgentPluginExecution.create!(
        agent_plugin: agent,
        user_id: message.sender_id,
        status: 'running',
        started_at: Time.current,
        input_context: {
          task: message.content,
          hub_thread_id: id,
          hub_message_id: message.id,
          entity_id: entity_id,
          source: 'hub_dm',
          is_followup: conversation_context.length > 1,
          file_urls: file_urls,
          attachments: attachments
        }
      )
      
      # Queue the existing agent execution job
      # Get the entity for the job context
      job_entity = Entity.find_by(id: entity_id)
      
      AgentPluginExecutionJob.perform_later(
        execution.id,
        task_prompt,
        {
          entity: job_entity,
          user_id: message.sender_id,
          hub_thread_id: id,
          hub_message_id: message.id,
          respond_in_hub: true,
          conversation_context: conversation_context,
          file_urls: file_urls
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
    
    Rails.logger.info "[Hub] Looking for DM with participants: #{participant_key.join(', ')}"

    # Check for existing DM with same participants
    # Use a more reliable query - find all DMs for this entity, then check participants
    dm_threads = where(entity: entity, thread_type: DM).includes(:hub_participants)
    
    dm_threads.each do |thread|
      # Get unique participant keys (avoid duplicates)
      thread_key = thread.hub_participants
                         .where(left_at: nil)
                         .map { |hp| "#{hp.participant_type}:#{hp.participant_id}" }
                         .uniq
                         .sort
      
      if thread_key == participant_key
        Rails.logger.info "[Hub] Found existing DM thread #{thread.id}"
        return thread
      end
    end

    Rails.logger.info "[Hub] Creating new DM thread"
    
    # Create new DM
    thread = create!(
      entity: entity,
      thread_type: DM,
      started_by: participants.first,
      dm_participant_ids: participants.map { |p| { type: p.class.name, id: p.id } }
    )

    # Add participants (with duplicate check)
    participants.each do |p|
      unless thread.hub_participants.exists?(participant: p)
        thread.add_participant(p, role: p == participants.first ? 'owner' : 'member')
      end
    end
    
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
      others.map { |p| participant_display_name(p) }.join(', ')
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

  # Get display name for a participant (handles User vs AgentPlugin)
  def participant_display_name(participant)
    return 'Unknown' if participant.nil?

    # User has full_name, AgentPlugin has name
    if participant.respond_to?(:full_name)
      participant.full_name
    elsif participant.respond_to?(:name)
      participant.name
    else
      participant.to_s
    end
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
  
  # Find pending input request for an agent in this Hub thread
  def find_pending_input_request(agent, user)
    # Look for executions for this agent that are waiting for input
    # and were triggered from this Hub thread
    executions = AgentPluginExecution.where(
      agent_plugin: agent,
      user: user,
      status: 'waiting_for_input'
    ).where("input_context->>'hub_thread_id' = ?", id.to_s)
    
    return nil if executions.empty?
    
    # Find the most recent pending input request
    executions.each do |execution|
      input_request = execution.agent_input_requests.pending.order(created_at: :desc).first
      return input_request if input_request
    end
    
    nil
  end
  
  # Answer a pending input request with the user's message
  def answer_pending_input_request(input_request, message)
    # Answer the input request - this will trigger ResumeAgentExecutionJob
    input_request.answer!(message.content, hub_context: {
      hub_thread_id: id,
      hub_message_id: message.id,
      respond_in_hub: true
    })
    
    Rails.logger.info "[Hub] Answered input request #{input_request.id} with message #{message.id}"
  rescue => e
    Rails.logger.error "[Hub] Error answering input request: #{e.message}"
    Rails.logger.error e.backtrace.first(3).join("\n")
  end
end
